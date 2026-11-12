# Generalized indices and proofs

Spec: [ssz-specs@v0.1.0](https://github.com/ethereum/ssz-specs/tree/7bce07ff7d51b1a3c66ff4e2bd3233ac248ede70/src/ssz), `paths.py` (`get_generalized_index`), `gindex.py` and `proofs.py` (`build_proof`, `node_root`). consensus-specs uses them as `get_generalized_index` and `compute_merkle_proof`.

Types: [types.md](types.md), [serialization.md](serialization.md) and [merkleization.md](merkleization.md). Every argument is public data.

### `Path`

A standalone list with one field, as ARCHITECTURE.md section 6 defines it, whose entries are unsigned 8-byte steps.

- `size` This unsigned 8-byte number gives the total buffer size in bytes.
- `offset` This unsigned 8-byte number gives the start of the step part, in bytes from the buffer start.
- `count` This unsigned 8-byte number gives the number of steps.

A step is a field index in a container, an element position in a vector or a list, or `0xffffffffffffffff` for the length that a list mixes in (`"__len__"` in the spec). The caller turns field names into field indices.

### `GeneralizedIndex`

- `index` This unsigned 8-byte number holds a generalized index, which is 1 for the root.

### `Branch`

A standalone list with one field, whose entries are `Root` values of 32 bytes.

- `size` This unsigned 8-byte number gives the total buffer size in bytes.
- `offset` This unsigned 8-byte number gives the start of the node part, in bytes from the buffer start.
- `count` This unsigned 8-byte number gives the number of nodes.

### `ssz_get_generalized_index(type, path, gindex)`

- `type` This input is a well-formed `TypeDescriptor`, and the function does not validate it.
- `path` This input is a well-formed `Path` whose steps are unvalidated.
- `gindex` This output is a `GeneralizedIndex` buffer of 8 bytes.

Requirements: The function walks `path` from the root of the described type as v0.1.0 `get_generalized_index` walks it, and writes the index of the node it names. It refuses a step as v0.1.0 refuses it, with the status of the first fault. It refuses an index that needs more than 64 bits with `SSZ_GINDEX_TOO_LARGE`.

ABI: The core ABI of ARCHITECTURE.md section 6. The symbol is `ssz_get_generalized_index` (`_ssz_get_generalized_index` in Mach-O). The pointer arguments are `type`, `path`, then `gindex`.

Effects and ownership: Effect-free.

Bounds: `gindex` is 8 bytes. The function needs no scratch.

Outputs: `gindex`, laid out as `GeneralizedIndex`.

Status: `0`, or `18` to `23` for a refused path.

### `ssz_build_proof(type, value, gindex, scratch, branch)`

- `type` This input is a well-formed `TypeDescriptor`, and the function does not validate it.
- `value` This input is a well-formed value of the described type, and the function does not validate it.
- `gindex` This input is a `GeneralizedIndex` whose index is unvalidated.
- `scratch` This scratch buffer holds at least `scratch` bytes of the root node.
- `branch` This output is a `Branch` whose `size` header gives its accessible extent.

Requirements: The function writes the branch for `gindex` as v0.1.0 `build_proof` builds it: the root of the sibling of each node on the path, from the node up to the root, read with `node_root`. For index 1 the branch is empty. It refuses an index as v0.1.0 `node_root` refuses it. It sets `offset` to 24 and `count` to the number of nodes, and it does not change `size`. It hashes with `crypto_sha256` from asm-crypto. `branch` and `scratch` do not overlap each other or the inputs.

ABI: As `ssz_get_generalized_index`, with the pointer arguments `type`, `value`, `gindex`, `scratch`, then `branch`.

Effects and ownership: Effect-free.

Bounds: For an index `i` of at least 1, `branch` needs `24 + 32 * floor(log2(i))` bytes. `scratch` needs the root node's `scratch` bytes.

Outputs: `branch`, laid out as `Branch`.

Status: `0`. `24` to `27` for a refused index, checked before capacity. `1` (`BUFFER_TOO_SMALL`) when `branch` or `scratch` is too small.

<!-- CI generates the tick table for each function here. -->
