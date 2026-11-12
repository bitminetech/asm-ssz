# Merkleization

## Contents

### Functions

- [`ssz_hash_tree_root`](#function-ssz_hash_tree_root): computes the hash tree root of a value.
- [`ssz_l0_hash`](#function-ssz_l0_hash): hashes two tree nodes into their parent. Internal.
- [`ssz_l0_level`](#function-ssz_l0_level): describes the leaves of one value. Internal.
- [`ssz_l0_child`](#function-ssz_l0_child): describes the leaves of the value under one leaf. Internal.
- [`ssz_l0_leaf`](#function-ssz_l0_leaf): gives one leaf. Internal.
- [`ssz_l0_root`](#function-ssz_l0_root): gives the hash tree root of one value. Internal.
- [`ssz_l0_merkleize`](#function-ssz_l0_merkleize): gives the root of one subtree. Internal.

### Types

- [`Root`](#type-root): a Merkle root or tree node.
- [`Level`](#type-level): the leaves of one value. Internal.
- [`Range`](#type-range): one subtree of a level. Internal.
- [`Work`](#type-work): work area for one level. Internal.

## Spec

- Document: [ssz-specs v0.1.0](https://github.com/ethereum/ssz-specs/tree/7bce07ff7d51b1a3c66ff4e2bd3233ac248ede70/src/ssz), the version that consensus-specs v1.7.0-beta.4 pins.
- Section: `hash_tree_root` in `roots.py`, with `layout.py`, `merkleize` in `trees.py`, `mix_in_length` in `mixins.py`, and `chunks.py`.

## Function `ssz_hash_tree_root`

Computes the hash tree root of a value.

### Signature

```
ssz_hash_tree_root(type, value, scratch, root) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `type` | input | `TypeDescriptor` |
| `value` | input | `Value` |
| `scratch` | scratch | `Scratch` |
| `root` | output | `Root` |

`TypeDescriptor`, `Value` and `Scratch` are in [serialization.md](serialization.md).

### Returns

- `SSZ_OK`: `root` holds the hash tree root.
- `SSZ_BUFFER_TOO_SMALL`: `scratch` is too small.

### Caller must

- Pass a valid `TypeDescriptor` in `type`. It is not checked.
- Pass a valid `Value` of that type in `value`. It is not checked.
- Set the `size` field of `scratch` to its buffer size.
- Keep `root` and `scratch` apart from each other and from the inputs.

### Function does

- Computes `hash_tree_root` as v0.1.0 computes it.
- Packs basic values, byte strings and bit strings into 32 byte chunks.
- Uses the roots of elements and fields for composite values.
- Pads each tree to the next power of two of the type's chunk count.
- Mixes in the length of each list, byte list and bit list.
- Hashes with `crypto_sha256` from asm-crypto.
- Ignores what `root` held before.

### Function never

- Writes outside `root`, `scratch` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- `scratch`: the `scratch` bytes of the root `TypeNode`.
- Stack: at most 4256 bytes on x86-64, 4960 on ARM64 and 5024 on RISC-V, `crypto_sha256` included.

### ABI

- Symbol: `ssz_hash_tree_root` (`_ssz_hash_tree_root` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `type`, `value`, `scratch`, `root`.

## Function `ssz_l0_hash`

Hashes two tree nodes into their parent. Internal.

### Signature

```
ssz_l0_hash(ctx, left, right, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `ctx` | input | `Ctx` |
| `left` | input | `Root` |
| `right` | input | `Root` |
| `out` | output | `Root` |

`Ctx` is in [serialization.md](serialization.md).

### Returns

- `SSZ_OK`: always.

### Caller must

- Pass a `Ctx` that an L2 function filled from a valid `TypeDescriptor`.
- Keep `out` apart from `ctx` and the `sha` `ByteList`.

### Function does

- Writes SHA-256(`left` || `right`) to `out`.
- Copies `left` and `right` into the `sha` `ByteList` first, so `out` may be `left` or `right`.
- Hashes with `crypto_sha256` from asm-crypto.

### Function never

- Writes outside `out`, the `sha` `ByteList` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- Stack: 576 bytes on x86-64, 512 on ARM64 and 576 on RISC-V, `crypto_sha256` included.

### ABI

- Symbol: `ssz_l0_hash`, local to the library.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `ctx`, `left`, `right`, `out`.

## Function `ssz_l0_level`

Describes the leaves of one value at its own tree level. Internal.

### Signature

```
ssz_l0_level(ctx, node, slot, level) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `ctx` | input | `Ctx` |
| `node` | input | `TypeNode` |
| `slot` | input | `Slot` |
| `level` | output | `Level` |

`TypeNode` and `Slot` are in [serialization.md](serialization.md).

### Returns

- `SSZ_OK`: always.

### Caller must

- Pass a `Ctx` that an L2 function filled from a valid `TypeDescriptor`.
- Pass a `TypeNode` of that descriptor in `node`.
- Pass a valid `Value` of that type in `slot`.

### Function does

- Writes every field of `level` for the value in `slot`.
- Sets `depth` to ceil(log2(`chunks`)) of `node`.
- Sets `mixin` to 1 for a list, byte list or bit list, with its count in `length`.

### Function never

- Writes outside `level` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- Stack: 8 bytes on x86-64, the return address, and 0 bytes on ARM64 and RISC-V.

### ABI

- Symbol: `ssz_l0_level`, local to the library.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `ctx`, `node`, `slot`, `level`.

## Function `ssz_l0_child`

Describes the leaves of the value under one leaf of a level. Internal.

### Signature

```
ssz_l0_child(ctx, level, index, child) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `ctx` | input | `Ctx` |
| `level` | state | `Level` |
| `index` | input | u64 |
| `child` | output | `Level` |

### Returns

- `SSZ_OK`: always.

### Caller must

- Pass a `Ctx` that an L2 function filled from a valid `TypeDescriptor`.
- Pass a `level` whose mode is not `SSZ_MODE_PACKED`.
- Pass an `index` below `level.count`.
- Keep `child` apart from `level`.

### Function does

- Writes into `child` the `Level` of the element or field at `index`.
- For `SSZ_MODE_VARIABLE`, walks the nested values by their sizes. It starts at `walk_i` when `index` is not below it, else at the first value.
- Updates `walk_i` and `walk_v` of `level`.

### Function never

- Writes outside `child`, the walk fields of `level` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- Stack: 104 bytes on x86-64, return address included, and 128 bytes on ARM64 and RISC-V.

### ABI

- Symbol: `ssz_l0_child`, local to the library.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `ctx`, `level`, `index`, `child`.

## Function `ssz_l0_leaf`

Gives one leaf of a level. Internal.

### Signature

```
ssz_l0_leaf(ctx, level, index, work, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `ctx` | input | `Ctx` |
| `level` | state | `Level` |
| `index` | input | u64 |
| `work` | scratch | `Work` |
| `out` | output | `Root` |

### Returns

- `SSZ_OK`: always.

### Caller must

- Pass a `Ctx` that an L2 function filled from a valid `TypeDescriptor`.
- Pass an `index` below `level.count`.
- Give `work` the bytes that a leaf of this level needs (`Work` rules).
- Keep `work` and `out` apart from each other and from `level`.

### Function does

- `SSZ_MODE_PACKED`: writes the 32 data bytes at 32 × `index`, padded with zeros past the data.
- Other modes: writes the hash tree root of the value at `index`.
- Puts the child `Level` at byte 8 of `work`, then the child's `Work`.

### Function never

- Writes outside `out`, `work`, the walk fields of `level`, the `sha` `ByteList` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- Stack of its own frame: 64 bytes on x86-64, return address included, and 96 bytes on ARM64 and RISC-V.

### ABI

- Symbol: `ssz_l0_leaf`, local to the library.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `ctx`, `level`, `index`, `work`, `out`.

## Function `ssz_l0_root`

Gives the hash tree root of the value that a level describes. Internal.

### Signature

```
ssz_l0_root(ctx, level, work, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `ctx` | input | `Ctx` |
| `level` | state | `Level` |
| `work` | scratch | `Work` |
| `out` | output | `Root` |

### Returns

- `SSZ_OK`: always.

### Caller must

- Pass a `Ctx` that an L2 function filled from a valid `TypeDescriptor`.
- Pass a `level` that `ssz_l0_level` or `ssz_l0_child` wrote.
- Give `work` the bytes that this level needs (`Work` rules).
- Keep `work` and `out` apart from each other and from `level`.

### Function does

- Merkleizes the leaves of `level` into a tree of depth `level.depth`.
- Mixes in `level.length` when `level.mixin` is 1.

### Function never

- Writes outside `out`, `work`, the walk fields of `level`, the `sha` `ByteList` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- Stack of its own frame: 112 bytes on x86-64, return address included, and 144 bytes on ARM64 and RISC-V.
- Recursion depth: at most one call for each level of nested types, through `ssz_l0_merkleize` and `ssz_l0_leaf`.

### ABI

- Symbol: `ssz_l0_root`, local to the library.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `ctx`, `level`, `work`, `out`.

## Function `ssz_l0_merkleize`

Gives the root of one subtree of a level. Internal.

### Signature

```
ssz_l0_merkleize(ctx, level, range, work, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `ctx` | input | `Ctx` |
| `level` | state | `Level` |
| `range` | input | `Range` |
| `work` | scratch | `Work` |
| `out` | output | `Root` |

### Returns

- `SSZ_OK`: always.

### Caller must

- Pass a `Ctx` that an L2 function filled from a valid `TypeDescriptor`.
- Pass a `level` that `ssz_l0_level` or `ssz_l0_child` wrote.
- Pass a `range` within the tree of `level`.
- Give `work` the bytes that this level needs (`Work` rules).
- Keep `work` and `out` apart from each other and from `level`.

### Function does

- Writes the root of the subtree of depth `range.depth` whose first leaf is `range.lo`.
- Treats leaves at and after `level.count` as zero.
- Uses the zero root of each depth for subtrees with no data.
- Keeps one node for each depth, so the work does not grow with the leaf count.

### Function never

- Writes outside `out`, `work`, the walk fields of `level`, the `sha` `ByteList` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- Stack of its own frame: 128 bytes on every ISA. On x86-64 this includes the return address.

### ABI

- Symbol: `ssz_l0_merkleize`, local to the library.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `ctx`, `level`, `range`, `work`, `out`.

## Type `Root`

A Merkle root or tree node.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `bytes` | 32 bytes | The root |

### Rules

- 32 bytes.
- The buffer starts at a multiple of 8.

## Type `Level`

The leaves of one value at its own tree level. Internal.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `mode` | u64 | One of the `SSZ_MODE_*` constants |
| 8 | `count` | u64 | Leaves that hold data |
| 16 | `a` | u64 | Packed: address of the data. Fixed or variable: element `TypeNode`. Fields: container `TypeNode`. |
| 24 | `b` | u64 | Packed: data length in bytes. Fixed or variable: address of the first element. Fields: address of the container value. |
| 32 | `c` | u64 | Fixed: element stride |
| 40 | `depth` | u64 | Tree depth: ceil(log2(`chunks`)) |
| 48 | `mixin` | u64 | 1 when the root mixes in a length |
| 56 | `length` | u64 | The length that it mixes in |
| 64 | `walk_i` | u64 | Variable: index of the value at `walk_v` |
| 72 | `walk_v` | u64 | Variable: address of that value |

### Rules

- 96 bytes.
- `SSZ_MODE_PACKED`: the leaves are 32 byte chunks of the data.
- `SSZ_MODE_FIXED`: the leaves are the roots of fixed size elements.
- `SSZ_MODE_VARIABLE`: the leaves are the roots of nested values.
- `SSZ_MODE_FIELDS`: the leaves are the roots of the container fields.

## Type `Range`

One subtree of a level. Internal.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `lo` | u64 | Index of the first leaf |
| 8 | `depth` | u64 | Depth of the subtree |

### Rules

- 16 bytes.
- `lo` is a multiple of 2 to the power `depth`.
- `depth` is at most the depth of the level.

## Type `Work`

Work area for one level. Internal.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the work area, this field included |

### Rules

- Starts at a multiple of 8.
- `ssz_l0_merkleize` puts one node for each depth from 0 to `depth` at byte 8, then one more node.
- When the leaves are child values, the `Work` of a leaf follows.
- Needs 8 + 32 × (`depth` + 2) bytes.
- Needs 8 + 96 more bytes, plus the most that a child needs, when the leaves are child values.
- The descriptor builder adds this up into the `scratch` field of each `TypeNode`.

## Test vectors

- The roots of the `ssz_static` cases in [serialization.md](serialization.md#test-vectors).

## Results

<!-- CI generates the tick table for each function here. -->
