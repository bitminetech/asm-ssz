# asm-ssz

SimpleSerialize (SSZ) for Ethereum, in assembly.

Standard: [asm-standard@185917b](https://github.com/bitminetech/asm-standard/blob/185917bedc54ff034e40069318add463c58f4db8/ARCHITECTURE.md)

<!-- CI generates the verification heatmap here. -->
<table><tr><td>

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/header-dark.svg"><img src="docs/heatmap/header-light.svg" alt="asm-ssz formal verification: 0 of 16 functions proved"></picture>

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/label-merkleization-dark.svg"><img src="docs/heatmap/label-merkleization-light.svg" alt="merkleization"></picture><a href="docs/reference/merkleization.md#function-ssz_hash_tree_root"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_hash_tree_root" title="ssz_hash_tree_root: Not proved"></picture></a><a href="docs/reference/merkleization.md#function-ssz_hash_pair"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_hash_pair" title="ssz_hash_pair: Not proved"></picture></a><a href="docs/reference/merkleization.md#function-ssz_value_level"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_value_level" title="ssz_value_level: Not proved"></picture></a><a href="docs/reference/merkleization.md#function-ssz_child_level"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_child_level" title="ssz_child_level: Not proved"></picture></a><a href="docs/reference/merkleization.md#function-ssz_level_leaf"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_level_leaf" title="ssz_level_leaf: Not proved"></picture></a><a href="docs/reference/merkleization.md#function-ssz_level_root"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_level_root" title="ssz_level_root: Not proved"></picture></a><a href="docs/reference/merkleization.md#function-ssz_subtree_root"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_subtree_root" title="ssz_subtree_root: Not proved"></picture></a><br>
<picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/label-proofs-dark.svg"><img src="docs/heatmap/label-proofs-light.svg" alt="proofs"></picture><a href="docs/reference/proofs.md#function-ssz_get_generalized_index"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_get_generalized_index" title="ssz_get_generalized_index: Not proved"></picture></a><a href="docs/reference/proofs.md#function-ssz_build_proof"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_build_proof" title="ssz_build_proof: Not proved"></picture></a><a href="docs/reference/proofs.md#function-ssz_verify_merkle_proof"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_verify_merkle_proof" title="ssz_verify_merkle_proof: Not proved"></picture></a><br>
<picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/label-serialization-dark.svg"><img src="docs/heatmap/label-serialization-light.svg" alt="serialization"></picture><a href="docs/reference/serialization.md#function-ssz_serialize"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_serialize" title="ssz_serialize: Not proved"></picture></a><a href="docs/reference/serialization.md#function-ssz_serialize_size"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_serialize_size" title="ssz_serialize_size: Not proved"></picture></a><a href="docs/reference/serialization.md#function-ssz_deserialize"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_deserialize" title="ssz_deserialize: Not proved"></picture></a><a href="docs/reference/serialization.md#function-ssz_deserialize_size"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_deserialize_size" title="ssz_deserialize_size: Not proved"></picture></a><a href="docs/reference/serialization.md#function-ssz_encode_value"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_encode_value" title="ssz_encode_value: Not proved"></picture></a><a href="docs/reference/serialization.md#function-ssz_decode_value"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_decode_value" title="ssz_decode_value: Not proved"></picture></a>

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/legend-dark.svg"><img src="docs/heatmap/legend-light.svg" alt="Legend"></picture>

</td></tr></table>
<!-- End of the verification heatmap. -->

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
| [asm-crypto](https://github.com/bitminetech/asm-crypto) | [`a364b8c`](https://github.com/bitminetech/asm-crypto/tree/a364b8c3c06b55607834f93cda7b7e315323b3b8) | `crypto_sha256` |

## Build tools

| Used for | Tool |
|---|---|
| Library | LLVM 23.1.5, official release (`clang`, `llvm-ar`, `lld`) |
| Windows test runner and bench | [llvm-mingw 20261104](https://github.com/mstorsjo/llvm-mingw/releases/tag/20261104) (LLVM 23.1.5) |
| macOS test runner and bench | The host Xcode clang, because it needs the macOS SDK |
| Build image | [platform/linux/Dockerfile](platform/linux/Dockerfile) on `debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2` |

## Tests

| Item | Location |
|---|---|
| Export and frame check | [platform/check.py](platform/check.py) |
| Vector generator | [tests/generator/](tests/generator/) |
| Test runner | [tests/runner/](tests/runner/) |
| Bench | [bench/](bench/) |

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

## Benchmark machines

| ISA | CPU |
|---|---|
| x86-64 | The CPU of the GitHub runners `ubuntu-24.04`, `windows-2025` and `macos-15-intel`. Each bench run prints it. |
| ARM64 | The CPU of the GitHub runners `ubuntu-24.04-arm`, `windows-11-arm` and `macos-15`, and Apple M series Macs. Each bench run prints it. |
| RISC-V | Run only, under QEMU on `ubuntu-24.04-arm`. Its times are not measurements. |
