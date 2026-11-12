# Merkleization

Spec: [ssz-specs@v0.1.0](https://github.com/ethereum/ssz-specs/tree/7bce07ff7d51b1a3c66ff4e2bd3233ac248ede70/src/ssz), `roots.py` (`hash_tree_root`), `layout.py`, `trees.py` (`merkleize`), `mixins.py` (`mix_in_length`) and `chunks.py`.

Types: [types.md](types.md) and [serialization.md](serialization.md). Every argument is public data.

### `Root`

A fixed-size value of 32 bytes with no size header. The buffer starts at a multiple of 8.

- `bytes` These 32 bytes hold a Merkle root or a tree node.

### `ssz_hash_tree_root(type, value, scratch, root)`

- `type` This input is a well-formed `TypeDescriptor`, and the function does not validate it.
- `value` This input is a well-formed value of the described type, and the function does not validate it.
- `scratch` This scratch buffer holds at least `scratch` bytes of the root node.
- `root` This output is a `Root` buffer of 32 bytes that receives the hash tree root.

Requirements: The function computes `hash_tree_root` of `value` as v0.1.0 computes it: basic values and byte and bit sequences are packed into 32-byte chunks; composite values use the roots of their elements or fields; `merkleize` pads to the next power of two of the type's chunk count; lists, byte lists and bit lists mix in their length with `mix_in_length`. It hashes with `crypto_sha256` from asm-crypto. The previous contents of `root` do not change the result. `root` and `scratch` do not overlap each other or the inputs.

ABI: The core ABI of ARCHITECTURE.md section 6. The symbol is `ssz_hash_tree_root` (`_ssz_hash_tree_root` in Mach-O). The pointer arguments are `type`, `value`, `scratch`, then `root`.

Effects and ownership: Effect-free.

Bounds: `root` is 32 bytes. `scratch` needs the root node's `scratch` bytes. The stack bound is in the README, and it includes `crypto_sha256`.

Outputs: `root`, laid out as `Root`.

Status: `0`, or `1` (`BUFFER_TOO_SMALL`) when `scratch` is too small.

<!-- CI generates the tick table for each function here. -->
