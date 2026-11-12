# Merkleization

## Contents

- Function [`ssz_hash_tree_root`](#function-ssz_hash_tree_root): computes the hash tree root of a value.
- Type [`Root`](#type-root): a Merkle root or tree node.

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

### ABI

- Symbol: `ssz_hash_tree_root` (`_ssz_hash_tree_root` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `type`, `value`, `scratch`, `root`.

## Type `Root`

A Merkle root or tree node.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `bytes` | 32 bytes | The root |

### Rules

- 32 bytes.
- The buffer starts at a multiple of 8.

## Test vectors

- The roots of the `ssz_static` cases in [serialization.md](serialization.md#test-vectors).

## Results

<!-- CI generates the tick table for each function here. -->
