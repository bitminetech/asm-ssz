# asm-ssz

SimpleSerialize (SSZ) for Ethereum, in assembly.

Standard: [asm-standard@dc3b2a7](https://github.com/bitminetech/asm-standard/blob/dc3b2a75755f502828c0d6060ff655a9dcfea20a/ARCHITECTURE.md)

## Reference

| File | Covers |
|---|---|
| [docs/reference/serialization.md](docs/reference/serialization.md) | Types, serialize and deserialize |
| [docs/reference/merkleization.md](docs/reference/merkleization.md) | Hash tree root |
| [docs/reference/proofs.md](docs/reference/proofs.md) | Generalized indices and proofs |
| [include/ssz.inc](include/ssz.inc) | Constants |

## Targets

| OS | ISAs |
|---|---|
| Linux | x86-64, ARM64, RISC-V |
| Windows | x86-64, ARM64 |
| macOS | x86-64, ARM64 |

## Dependencies

| Repo | Commit | Functions used |
|---|---|---|
| [asm-crypto](https://github.com/bitminetech/asm-crypto) | [`de79f5b`](https://github.com/bitminetech/asm-crypto/tree/de79f5bc895ebca6c74ae6dfd86e409a234e07bf) | `crypto_sha256` |

## Build tools

| Used for | Tool |
|---|---|
| Library | LLVM 23.1.5, official release (`clang`, `llvm-ar`, `lld`) |
| Windows test runner | [llvm-mingw 20261104](https://github.com/mstorsjo/llvm-mingw/releases/tag/20261104) (LLVM 23.1.5) |
| macOS test runner | The host Xcode clang, because it needs the macOS SDK |
| Build image | [platform/linux/Dockerfile](platform/linux/Dockerfile) on `debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2` |

## Tests

| Item | Location |
|---|---|
| Vector generator | [tests/generator/](tests/generator/) |
| Test runner | [tests/runner/](tests/runner/) |

## Target profile

| ISA | Instructions |
|---|---|
| x86-64 | x86-64-v1 |
| ARM64 | Armv8.0-A |
| RISC-V | RV64GC |

| Item | Value |
|---|---|
| macOS objects | Marked for macOS 11.0 or later |

## Stack

| Item | Value |
|---|---|
| Stack per call | At most 6144 bytes, callees included |

## Integration

| Item | Value |
|---|---|
| Type descriptors | The caller supplies one for each SSZ type it uses, made by [tests/generator/descriptor.py](tests/generator/descriptor.py) |
