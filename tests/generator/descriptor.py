"""The descriptor builder: turn an ssz-specs v0.1.0 type into a binary TypeDescriptor.

The layout rules are in docs/reference/serialization.md; the field offsets are in
include/ssz.inc. The builder computes every in-memory position, so the assembly
only reads numbers. It refuses any kind outside the live-fork scope.
"""
import struct

from ssz.bitfields import BitList, BitVector
from ssz.boolean import Boolean
from ssz.byte_arrays import ByteList, ByteVector
from ssz.collections import List, Vector
from ssz.container import Container
from ssz.uint import BaseUint

KIND_UINT, KIND_BOOLEAN, KIND_BYTE_VECTOR, KIND_BYTE_LIST = 1, 2, 3, 4
KIND_BIT_VECTOR, KIND_BIT_LIST, KIND_VECTOR, KIND_LIST, KIND_CONTAINER = 5, 6, 7, 8, 9
DESC_FIXED = 48
NODE_STRIDE = 72
FIELD_STRIDE = 32
PART_REF = 16
LIST_VALUE_FIXED = 24
CHUNK = 32
UINT_WIDTHS = (1, 4, 8, 32)  # Uint8, Uint32, Uint64, Uint256: the widths the live forks use
LEVEL_SIZE = 96              # SSZ_LEVEL_SIZE
SCRATCH_WORK = 256           # SSZ_SCR_WORK: the root level's work area starts here
MAX_LEVELS = 12              # nested types; this bounds the stack (README)


def ceil_div(a, b):
    return -(-a // b)


def round_up(a, b):
    return ceil_div(a, b) * b


def children(t):
    """The types directly inside t, in declaration order."""
    if issubclass(t, Container):
        return [field_type for _, field_type in t._FIELD_TYPES]
    if issubclass(t, (Vector, List)):
        return [t.ELEMENT_TYPE]
    return []


def topological(root):
    """Every type reachable from root, each once, with a holder before what it holds."""
    seen, post = set(), []

    def visit(t):
        if t in seen:
            return
        seen.add(t)
        for c in children(t):
            visit(c)
        post.append(t)

    visit(root)
    return post[::-1]


class Node:
    pass


def is_basic(t):
    return issubclass(t, (BaseUint, Boolean))


def build_nodes(order):
    """Compute the node numbers for every type, children first."""
    nodes = {}
    for t in reversed(order):
        n = Node()
        n.fields = []
        if issubclass(t, Boolean):
            n.kind, n.length, n.ssz, n.mem, n.align, n.chunks = KIND_BOOLEAN, 1, 1, 1, 1, 1
        elif issubclass(t, BaseUint):
            w = t.BYTE_LENGTH
            if w not in UINT_WIDTHS:
                raise ValueError(f"{t.__name__}: uint of {w} bytes is outside the scope")
            n.kind, n.length, n.ssz, n.mem, n.align, n.chunks = KIND_UINT, w, w, w, min(w, 8), 1
        elif issubclass(t, ByteVector):
            length = t.declared_length()
            n.kind, n.length, n.ssz, n.mem, n.align = KIND_BYTE_VECTOR, length, length, length, 1
            n.chunks = ceil_div(length, CHUNK)
        elif issubclass(t, ByteList):
            limit = t.declared_limit()
            n.kind, n.length, n.ssz, n.mem, n.align = KIND_BYTE_LIST, limit, 0, PART_REF, 8
            n.chunks = ceil_div(limit, CHUNK)
        elif issubclass(t, BitVector):
            length = t.declared_length()
            width = ceil_div(length, 8)
            n.kind, n.length, n.ssz, n.mem, n.align = KIND_BIT_VECTOR, length, width, width, 1
            n.chunks = ceil_div(length, 256)
        elif issubclass(t, BitList):
            # ProgressiveBitList, ProgressiveList and ProgressiveContainer are not subclasses
            # of BitList, List and Container, so they fall through to the refusal below.
            limit = t.declared_limit()
            n.kind, n.length, n.ssz, n.mem, n.align = KIND_BIT_LIST, limit, 0, PART_REF, 8
            n.chunks = ceil_div(limit, 256)
        elif issubclass(t, (Vector, List)):
            e = nodes[t.ELEMENT_TYPE]
            is_vector = issubclass(t, Vector)
            count = t.declared_length() if is_vector else t.declared_limit()
            n.kind, n.length, n.element_type = (KIND_VECTOR if is_vector else KIND_LIST), count, t.ELEMENT_TYPE
            n.chunks = ceil_div(count * e.ssz, CHUNK) if is_basic(t.ELEMENT_TYPE) else count
            if is_vector and e.ssz:
                n.ssz, n.mem, n.align = count * e.ssz, count * e.mem, e.align
            else:
                n.ssz, n.mem, n.align = 0, PART_REF, 8
        elif issubclass(t, Container):
            fields = t._FIELD_TYPES
            if not fields:
                raise ValueError(f"{t.__name__} has no fields")
            variable = any(nodes[f].ssz == 0 for _, f in fields)
            at = 8 if variable else 0
            ssz_at, largest = 0, 1
            for _, f in fields:
                fn = nodes[f]
                at = round_up(at, fn.align)
                n.fields.append((f, at, ssz_at, 1 if fn.ssz == 0 else 0))
                at += fn.mem
                ssz_at += fn.ssz if fn.ssz else 4
                largest = max(largest, fn.align)
            n.kind, n.length, n.chunks = KIND_CONTAINER, len(fields), len(fields)
            if variable:
                n.ssz, n.mem, n.align, n.value_fixed = 0, PART_REF, 8, round_up(at, 8)
            else:
                n.ssz, n.align = ssz_at, largest
                n.mem = round_up(at, largest)
        else:
            raise ValueError(f"{t.__name__}: kind outside the scope")
        if not hasattr(n, "value_fixed"):
            n.value_fixed = n.mem if n.ssz else LIST_VALUE_FIXED
        if n.ssz and n.ssz != t.get_byte_length():
            raise AssertionError(f"{t.__name__}: SSZ size {n.ssz} != {t.get_byte_length()}")
        n.work = work_bytes(t, n, nodes)
        n.levels = 1 + max((nodes[c].levels for c in children(t)), default=0)
        if n.levels > MAX_LEVELS:
            raise ValueError(f"{t.__name__}: {n.levels} nested types, the limit is {MAX_LEVELS}")
        n.scratch = SCRATCH_WORK + n.work
        nodes[t] = n
    return nodes


def tree_depth(chunks):
    """ceil(log2(chunks)), the depth of the tree at a type's own level."""
    return (chunks - 1).bit_length() if chunks > 1 else 0


def work_bytes(t, n, nodes):
    """
    Work area that ssz_l0_root needs for a value of type t: its size header, a
    frontier of depth + 1 nodes and the node h; and, when leaves are child
    values, a size header, a child Level and the child's own work area.
    """
    work = 8 + 32 * (tree_depth(n.chunks) + 2)
    # Container fields are always child values; vector and list elements are,
    # unless they are basic, which pack into chunks.
    if issubclass(t, Container):
        leaves = children(t)
    else:
        leaves = [c for c in children(t) if not is_basic(c)]
    if leaves:
        work += 8 + LEVEL_SIZE + max(nodes[c].work for c in leaves)
    return work


def build(root):
    """Return (descriptor bytes, field index of each container type) for root."""
    order = topological(root)
    nodes = build_nodes(order)
    index = {t: i for i, t in enumerate(order)}
    field_records, first_field = [], {}
    for t in order:
        if nodes[t].fields:
            first_field[t] = len(field_records)
            field_records.extend(nodes[t].fields)
    nodes_offset = DESC_FIXED
    fields_offset = nodes_offset + NODE_STRIDE * len(order)
    size = fields_offset + FIELD_STRIDE * len(field_records)
    out = bytearray(struct.pack("<6Q", size, nodes_offset, len(order), fields_offset,
                                len(field_records), index[root]))
    for t in order:
        n = nodes[t]
        if n.kind == KIND_CONTAINER:
            element = first_field[t]
        elif n.kind in (KIND_VECTOR, KIND_LIST):
            element = index[n.element_type]
        else:
            element = 0
        out += struct.pack("<9Q", n.kind, n.length, element, n.ssz, n.mem, n.align,
                           n.value_fixed, n.chunks, n.scratch)
    for field_type, mem_offset, ssz_offset, flags in field_records:
        out += struct.pack("<4Q", index[field_type], mem_offset, ssz_offset, flags)
    assert len(out) == size
    return bytes(out)


def field_index(t, name):
    """Position of a field name in a container, as a path step."""
    names = [n for n, _ in t._FIELD_TYPES]
    return names.index(name)
