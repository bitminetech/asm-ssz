# Generalized indices and proofs

## Contents

- Function [`ssz_get_generalized_index`](#function-ssz_get_generalized_index): finds the tree node that a path names.
- Function [`ssz_build_proof`](#function-ssz_build_proof): builds the Merkle branch for one tree node.
- Type [`Path`](#type-path): a list of steps from the root of a type.
- Type [`GeneralizedIndex`](#type-generalizedindex): the position of one tree node.
- Type [`Branch`](#type-branch): a list of tree nodes.

## Spec

- Document: [ssz-specs v0.1.0](https://github.com/ethereum/ssz-specs/tree/7bce07ff7d51b1a3c66ff4e2bd3233ac248ede70/src/ssz), the version that consensus-specs v1.7.0-beta.4 pins.
- Section: `get_generalized_index` in `paths.py`, `gindex.py`, and `build_proof` and `node_root` in `proofs.py`.
- consensus-specs calls them `get_generalized_index` and `compute_merkle_proof`.

## Function `ssz_get_generalized_index`

Finds the generalized index of the tree node that a path names.

### Signature

```
ssz_get_generalized_index(type, path, gindex) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `type` | input | `TypeDescriptor` |
| `path` | input | `Path` |
| `gindex` | output | `GeneralizedIndex` |

`TypeDescriptor` is in [serialization.md](serialization.md).

### Returns

- `SSZ_OK`: `gindex` holds the index.
- A path refusal constant from [include/ssz.inc](../../include/ssz.inc): a step breaks a v0.1.0 rule. It names the first fault that v0.1.0 raises.
- `SSZ_GINDEX_TOO_LARGE`: the index needs more than 64 bits.

### Caller must

- Pass a valid `TypeDescriptor` in `type`. It is not checked.
- Pass a valid `Path` header in `path`. The steps in it can be anything.
- Keep `gindex` apart from the inputs.

### Function does

- Walks `path` from the root of the type, as v0.1.0 `get_generalized_index` walks it.
- Writes the index of the node it reaches.

### Function never

- Reads outside the `Path` header and its `count` steps.
- Writes outside `gindex` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- Stack: 80 bytes on x86-64, return address included, 0 bytes on ARM64 and 96 bytes on RISC-V.

### ABI

- Symbol: `ssz_get_generalized_index` (`_ssz_get_generalized_index` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `type`, `path`, `gindex`.

## Function `ssz_build_proof`

Builds the Merkle branch for one tree node of a value.

### Signature

```
ssz_build_proof(type, value, gindex, scratch, branch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `type` | input | `TypeDescriptor` |
| `value` | input | `Value` |
| `gindex` | input | `GeneralizedIndex` |
| `scratch` | scratch | `Scratch` |
| `branch` | output | `Branch` |

`TypeDescriptor`, `Value` and `Scratch` are in [serialization.md](serialization.md).

### Returns

- `SSZ_OK`: `branch` holds the branch.
- A proof refusal constant from [include/ssz.inc](../../include/ssz.inc): the value's tree does not reach `gindex`. It names the first fault that v0.1.0 raises.
- `SSZ_BUFFER_TOO_SMALL`: `branch` or `scratch` is too small. `branch` is then invalid.

### Caller must

- Pass a valid `TypeDescriptor` in `type`. It is not checked.
- Pass a valid `Value` of that type in `value`. It is not checked.
- Pass a `GeneralizedIndex` in `gindex`. Its index can be anything.
- Set the `size` field of `branch` and of `scratch` to their buffer sizes.
- Keep `branch` and `scratch` apart from each other and from the inputs.

### Function does

- Checks for index 0, then `scratch`, then the path, then `branch`.
- Builds the branch as v0.1.0 `build_proof` builds it.
- Writes the sibling of each node on the path, from the node up to the root.
- Reads each sibling with v0.1.0 `node_root`.
- Writes an empty branch for index 1.
- Sets `offset` of `branch` to 24 and `count` to the number of nodes.
- Keeps the `size` field of `branch`.
- Hashes with `crypto_sha256` from asm-crypto.

### Function never

- Writes outside `branch`, `scratch` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- `branch`: 24 + 32 × floor(log2(index)) bytes.
- `scratch`: the `scratch` bytes of the root `TypeNode`.
- Stack: at most 4240 bytes on x86-64, 4880 on ARM64 and 4944 on RISC-V, `crypto_sha256` included.

### ABI

- Symbol: `ssz_build_proof` (`_ssz_build_proof` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `type`, `value`, `gindex`, `scratch`, `branch`.

## Type `Path`

A list of steps from the root of a type.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Total buffer size in bytes |
| 8 | `offset` | u64 | Where the steps start, from the buffer start |
| 16 | `count` | u64 | Number of steps |

### Rules

- Each step is a u64.
- A step is a field index in a container, a position in a vector or list, or `SSZ_STEP_LENGTH` for the length that a list mixes in (`"__len__"` in the spec).
- The caller turns field names into field indices.
- The buffer starts at a multiple of 8.
- `offset` is at least 24 and a multiple of 8.
- `offset + 8 × count` is at most `size`.

## Type `GeneralizedIndex`

The position of one tree node.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `index` | u64 | The generalized index |

### Rules

- Index 1 is the root.
- The buffer starts at a multiple of 8.

## Type `Branch`

A list of tree nodes.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Total buffer size in bytes |
| 8 | `offset` | u64 | Where the nodes start, from the buffer start |
| 16 | `count` | u64 | Number of nodes |

### Rules

- Each node is a `Root` from [merkleization.md](merkleization.md).
- The buffer starts at a multiple of 8.
- `offset` is at least 24 and a multiple of 8.
- `offset + 32 × count` is at most `size`.

## Test vectors

- Proofs: consensus-specs v1.7.0-beta.4, `merkle_proof/single_merkle_proof` and `light_client/single_merkle_proof` tests, phase0 to fulu, mainnet and minimal presets, from the archives in [serialization.md](serialization.md#test-vectors).
  - Check: the Python spec's `compute_merkle_proof` gives the same branch.
- Generalized indices: the constant tables at [consensus-specs@aa16bb4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304). Each row states a path and its index.
  - Files: `specs/altair/light-client/sync-protocol.md`, `specs/capella/light-client/sync-protocol.md`, `specs/electra/light-client/sync-protocol.md`.
  - Check: the Python spec's `get_generalized_index` gives the stated index.

## Results

<!-- CI generates the tick table for each function here. -->
