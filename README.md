# asm-ssz

Assembly implementation of SimpleSerialize (SSZ), the serialization and Merkleization scheme used by Ethereum, as specified by [ethereum/ssz-specs](https://github.com/ethereum/ssz-specs). It holds only what a production Ethereum consensus client needs on the live mainnet forks, phase0 to fulu: serialize, deserialize, hash tree root, generalized indices and single proofs, for the SSZ kinds in [docs/reference/types.md](docs/reference/types.md).

Architecture: [asm-standard@561b8ae](https://github.com/bitminetech/asm-standard/blob/561b8aeaea69f98b4007e4e936f89596e3a1f225/ARCHITECTURE.md)

## Pins

| Dependency | Version |
|---|---|
| Original reference spec | [ethereum/ssz-specs@v0.1.0](https://github.com/ethereum/ssz-specs/tree/7bce07ff7d51b1a3c66ff4e2bd3233ac248ede70) (`7bce07f`), the version that [consensus-specs](https://github.com/ethereum/consensus-specs/blob/aa16bb4c156184e9548a997d53efaf2a228a6304/pyproject.toml) v1.7.0-beta.4 pins as `eth-ssz-specs==0.1.0`. |
| Vector generation | The consensus tests of [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/releases/tag/v1.7.0-beta.4): `mainnet.tar.gz` (SHA-256 `67762986572372a08d3b182535aa760433c86e174e14e0bbd756f350dd19398c`) and `minimal.tar.gz` (SHA-256 `26d09aea70c62ed235a120a95082d544ab1c2e6fe36bd35ea1bd5da62f3b7b68`), the `ssz_static`, `merkle_proof` and `light_client/single_merkle_proof` tests for phase0 to fulu. Generalized index cases come from the constant tables in the spec files at [consensus-specs@aa16bb4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304), which state each path with its index. The type of each case comes from the Python package of that commit, read by the descriptor builder. Python packages: [tests/generator/requirements.txt](tests/generator/requirements.txt). No seed or options. |
| Build tools | LLVM 23.1.5 (`clang` as the assembler, `llvm-ar`, `lld`), the official release build, for the library on every target. [llvm-mingw 20261104](https://github.com/mstorsjo/llvm-mingw/releases/tag/20261104) (LLVM 23.1.5) for the Windows test runner. Both are in the image from [platform/linux/Dockerfile](platform/linux/Dockerfile), on `debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2`. |
| Target profiles | Baseline instructions only, with no extensions and no feature selection: x86-64 (x86-64-v1), ARM64 (Armv8.0-A) and RISC-V (RV64GC). The library makes no OS calls, so it needs no OS or API version. Mach-O objects are marked for macOS 11.0 or later. |
| Stack limit | Each function uses at most 1024 bytes of stack, including `crypto_sha256` (at most 512 bytes). Walks over nested types keep their state in the scratch buffer, not on the stack. Less than one 4 KiB page, so no target needs stack probing. |

## Dependencies

- [asm-crypto@de79f5b](https://github.com/bitminetech/asm-crypto/tree/de79f5bc895ebca6c74ae6dfd86e409a234e07bf): `crypto_sha256` (L2, core ABI), called by `ssz_hash_tree_root` and `ssz_build_proof`.

## Integration

Callers use the common-ABI entry points listed in [include/ssz.inc](include/ssz.inc). Every function takes a `TypeDescriptor` that the descriptor builder ([tests/generator/descriptor.py](tests/generator/descriptor.py)) makes from an ssz-specs type; the consuming application supplies one for each type it uses. The functions are effect-free and have no resource context, startup, wakeup, actions, events or shutdown. The library provides no crash-recovery or persistence guarantees.
