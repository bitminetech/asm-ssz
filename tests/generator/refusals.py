"""Vectors for the refusal paths, with expected results from the reference implementation.

The official vectors test valid encodings, paths and proofs, and one decode
failure. These cases change valid inputs in set ways, and ssz-specs v0.1.0
decides each result: the Python spec's decode_bytes, get_generalized_index and
build_proof. The generator fails when a refusal code gets no case.
"""
import random
from typing import ClassVar

from ssz import (
    LENGTH_KEY,
    BaseUint,
    BitList,
    BitVector,
    Boolean,
    ByteList,
    ByteVector,
    Container,
    List,
    Uint8,
    Uint32,
    Uint64,
    Vector,
    build_proof,
    element_type,
    get_generalized_index,
)
from ssz.exceptions import SSZError

SEED = 20261112
# TRAILING_BYTES is left out: decode_bytes gives deserialize the whole input as
# its scope, and every type in scope reads its whole scope or raises first.
DECODE_FAULTS = (
    "SCOPE", "SCOPE_TOO_SMALL", "SCOPE_UNDIVIDED", "TRUNCATED",
    "FIRST_OFFSET", "OFFSET_UNORDERED", "OFFSET_PAST_SCOPE", "OFFSET_UNALIGNED",
    "OFFSET_BELOW_TABLE", "EMPTY_ENCODING", "NO_DELIMITER", "TRAILING_ZEROS",
    "PADDING_BITS", "NOT_A_BIT", "LIMIT", "COUNT",
)
PATH_FAULTS = ("NO_PARTS", "NO_MIXIN", "NO_PARTS_MIXIN", "NO_SUCH_FIELD", "NO_SUCH_POSITION",
               "GINDEX_TOO_LARGE")
PROOF_FAULTS = ("NOT_A_GINDEX", "PATH_INTO_MIXIN", "PATH_INTO_PACKED", "PATH_INTO_GAP")
STEP_LENGTH = (1 << 64) - 1
REJECTS_PER_FAULT = 3      # decode cases kept for each type and fault
ACCEPTED_PER_TYPE = 2      # changed encodings that the spec still accepts
WALKS_PER_TYPE = 16        # random paths for each type
DESCENTS_PER_VALUE = 32    # random generalized indices for each value
PROOFS_PER_OUTCOME = 5     # proof cases kept for each value and outcome


# Small types that reach each refusal in few bytes.
class Bytes4(ByteVector):
    LENGTH = 4


class ByteList8(ByteList):
    LIMIT = 8


class Bits1(BitVector):
    LENGTH: ClassVar[int] = 1


class Bits7(BitVector):
    LENGTH: ClassVar[int] = 7


class Bits9(BitVector):
    LENGTH: ClassVar[int] = 9


class BitList8(BitList):
    LIMIT: ClassVar[int] = 8


class BitList16(BitList):
    LIMIT: ClassVar[int] = 16


class Uint32List4(List[Uint32]):
    LIMIT: ClassVar[int] = 4
    ELEMENT_TYPE = Uint32


class Bytes4List3(List[Bytes4]):
    LIMIT: ClassVar[int] = 3
    ELEMENT_TYPE = Bytes4


class Uint64Vector2(Vector[Uint64]):
    LENGTH: ClassVar[int] = 2
    ELEMENT_TYPE = Uint64


class BooleanVector3(Vector[Boolean]):
    LENGTH: ClassVar[int] = 3
    ELEMENT_TYPE = Boolean


class FixedFields(Container):
    a: Uint8
    b: Boolean
    c: Uint32
    d: Bits7


class VariableFields(Container):
    a: Uint64
    b: Uint32List4
    c: BitList8
    d: ByteList8
    e: Boolean


class ByteList8List3(List[ByteList8]):
    LIMIT: ClassVar[int] = 3
    ELEMENT_TYPE = ByteList8


class ByteList8Vector2(Vector[ByteList8]):
    LENGTH: ClassVar[int] = 2
    ELEMENT_TYPE = ByteList8


class Nested(Container):
    x: VariableFields
    y: ByteList8List3
    z: FixedFields
    w: ByteList8Vector2


class VariableFieldsList2(List[VariableFields]):
    LIMIT: ClassVar[int] = 2
    ELEMENT_TYPE = VariableFields


class Uint64List40(List[Uint64]):
    LIMIT: ClassVar[int] = 2**40
    ELEMENT_TYPE = Uint64


class DeepList(List[Uint64List40]):
    LIMIT: ClassVar[int] = 2**40
    ELEMENT_TYPE = Uint64List40


SMALL_TYPES = (Uint8, Uint32, Uint64, Boolean, Bytes4, ByteList8, Bits1, Bits7, Bits9, BitList8,
               BitList16, Uint32List4, Bytes4List3, Uint64Vector2, BooleanVector3, FixedFields,
               VariableFields, ByteList8List3, ByteList8Vector2, Nested, VariableFieldsList2)
PATH_ONLY_TYPES = (DeepList,)


def fields(t):
    return list(t._FIELD_TYPES)


def limit_of(t):
    if issubclass(t, (ByteVector, BitVector, Vector)):
        return t.declared_length()
    return t.declared_limit()


def random_value(t, rng, fill):
    """A value of t. fill picks list sizes: empty, one, full or random."""
    def count(limit):
        return {"empty": 0, "one": min(1, limit), "full": min(limit, 16)}.get(
            fill, rng.randint(0, min(limit, 4)))
    if issubclass(t, Boolean):
        return Boolean(rng.random() < 0.5)
    if issubclass(t, BaseUint):
        return t(rng.getrandbits(8 * t.BYTE_LENGTH))
    if issubclass(t, ByteVector):
        return t(rng.randbytes(t.declared_length()))
    if issubclass(t, ByteList):
        return t(data=rng.randbytes(count(t.declared_limit())))
    if issubclass(t, BitVector):
        return t(data=[Boolean(rng.random() < 0.5) for _ in range(t.declared_length())])
    if issubclass(t, BitList):
        return t(data=[Boolean(rng.random() < 0.5) for _ in range(count(t.declared_limit()))])
    if issubclass(t, Vector):
        return t(data=[random_value(t.ELEMENT_TYPE, rng, fill) for _ in range(t.declared_length())])
    if issubclass(t, List):
        return t(data=[random_value(t.ELEMENT_TYPE, rng, fill) for _ in range(count(t.declared_limit()))])
    return t(**{name: random_value(ft, rng, fill) for name, ft in fields(t)})


def decode(t, data):
    """(fault name, None) when the spec rejects data, else (None, value)."""
    try:
        return None, t.decode_bytes(data)
    except SSZError as e:
        return e.fault.name, None


def changed_copies(e, rng):
    """Encodings near e: cut, extended, and with one byte changed."""
    out = [b"", e[:-1], e[: len(e) // 2], e + b"\x00", e + b"\x01", e + bytes(4), e + e[-4:]]
    if len(e) <= 256:
        positions = range(len(e))
    else:
        positions = sorted(set(range(96)) | set(range(len(e) - 8, len(e)))
                           | set(rng.sample(range(len(e)), 32)))
    for i in positions:
        for b in ((e[i] + 1) & 255, (e[i] - 1) & 255, e[i] ^ 0x80, 0x00, 0xFF):
            if b != e[i]:
                out.append(e[:i] + bytes([b]) + e[i + 1:])
    return out


def decode_cases(seeds):
    """
    seeds: (label, type, [valid encodings]). Returns (static, reject, seen):
    static holds (label, type, encoding, root), reject holds (label, type,
    encoding, fault), and seen the fault names that came out.
    """
    rng = random.Random(SEED)
    static, reject, seen = [], [], set()
    for label, t, encodings in seeds:
        kept, accepted, done = {}, 0, set(encodings)
        for e in encodings:
            for m in changed_copies(e, rng):
                if m in done:
                    continue
                done.add(m)
                fault, value = decode(t, m)
                if fault is None:
                    if accepted < ACCEPTED_PER_TYPE:
                        accepted += 1
                        static.append((f"{label}/accepted-{accepted}", t, m, bytes(value.hash_tree_root())))
                    continue
                if kept.get(fault, 0) < REJECTS_PER_FAULT:
                    kept[fault] = kept.get(fault, 0) + 1
                    seen.add(fault)
                    reject.append((f"{label}/{fault.lower()}-{kept[fault]}", t, m, fault))
    return static, reject, seen


def small_seeds():
    """Valid values of the small types: empty, one, full and random sizes."""
    rng = random.Random(SEED + 1)
    seeds = []
    for t in SMALL_TYPES:
        encodings = []
        for fill in ("empty", "one", "full", "random", "random"):
            e = random_value(t, rng, fill).encode_bytes()
            if e not in encodings:
                encodings.append(e)
        seeds.append((f"small/{t.__name__}", t, encodings))
    return seeds


def path_step(t, rng):
    """One random step from type t: (spec step, our u64 step)."""
    r = rng.random()
    if issubclass(t, Container):
        names = [name for name, _ in fields(t)]
        if r < 0.12:
            return "no_such_field", len(names)
        if r < 0.2:
            return LENGTH_KEY, STEP_LENGTH
        i = rng.randrange(len(names))
        return names[i], i
    if issubclass(t, (ByteVector, ByteList, BitVector, BitList, Vector, List)):
        limit = limit_of(t)
        if r < 0.12:
            return limit, limit
        if r < 0.24:
            return LENGTH_KEY, STEP_LENGTH
        p = rng.choice((0, limit - 1, rng.randrange(limit)))
        return p, p
    return (LENGTH_KEY, STEP_LENGTH) if r < 0.3 else (0, 0)


def path_cases(types):
    """
    types: (label, type). Returns (cases, seen): cases hold (label, type, our
    steps, expected fault or None, expected index).
    """
    rng = random.Random(SEED + 2)
    cases, seen = [], set()
    for label, t in types:
        for walk in range(WALKS_PER_TYPE):
            spec_path, steps, current = [], [], t
            for _ in range(rng.randint(1, 6)):
                spec_step, step = path_step(current, rng) if current else (0, 0)
                spec_path.append(spec_step)
                steps.append(step)
                try:
                    current = None if spec_step == LENGTH_KEY else element_type(current, spec_step)
                except (SSZError, AttributeError, TypeError):
                    current = None
            try:
                index, fault = get_generalized_index(t, *spec_path), None
                if index >= 1 << 64:
                    index, fault = 0, "GINDEX_TOO_LARGE"
            except SSZError as e:
                index, fault = 0, e.fault.name
            if fault:
                seen.add(fault)
            cases.append((f"{label}/walk-{walk}", t, steps, fault, index))
    return cases, seen


def proof_cases(values):
    """
    values: (label, type, value). Returns (cases, seen): cases hold (label, type,
    encoding, generalized index, expected fault or None, branch).
    """
    rng = random.Random(SEED + 3)
    cases, seen = [], set()
    for label, t, value in values:
        encoding = value.encode_bytes()
        kept, done = {}, set()
        indices = [0, 1]
        for _ in range(DESCENTS_PER_VALUE):
            g = 1
            for _ in range(rng.randint(1, 48)):
                g = 2 * g + (rng.random() < 0.3)
            indices.append(g)
        for g in indices:
            if g in done or g >= 1 << 64:
                continue
            done.add(g)
            try:
                branch, fault = [bytes(n) for n in build_proof(value, g)], None
            except SSZError as e:
                branch, fault = [], e.fault.name
            key = fault or "OK"
            if kept.get(key, 0) >= PROOFS_PER_OUTCOME:
                continue
            kept[key] = kept.get(key, 0) + 1
            if fault:
                seen.add(fault)
            cases.append((f"{label}/{key.lower()}-{kept[key]}", t, encoding, g, fault, branch))
    return cases, seen


def small_values():
    """Values of the small types for proofs, with lists part full so gaps exist."""
    rng = random.Random(SEED + 4)
    return [(f"small/{t.__name__}", t, random_value(t, rng, "one"))
            for t in (Uint32List4, Bytes4List3, BitList16, ByteList8List3, VariableFieldsList2, Nested)]
