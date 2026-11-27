# asm-ssz

SimpleSerialize (SSZ) for Ethereum, in assembly.

Standard: [asm-standard@0db3e07](https://github.com/bitminetech/asm-standard/blob/0db3e07f58a9ba89c5b6a46925b179de265ee7e8/ARCHITECTURE.md)

<!-- CI generates the supported platforms panel here. -->
<table><tr><td>

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/readme/platforms-dark.svg"><img src="docs/readme/platforms-light.svg" alt="Supported platforms. Linux: x86-64, ARM64, RISC-V; Windows: x86-64, ARM64; macOS 11.0 or later: x86-64, ARM64"></picture>

</td></tr></table>
<!-- End of the supported platforms panel. -->

<!-- CI generates the verification heatmap here. -->
<table><tr><td>

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/header-dark.svg"><img src="docs/heatmap/header-light.svg" alt="asm-ssz formal verification: 0 of 16 functions proved"></picture>

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/label-merkleization-dark.svg"><img src="docs/heatmap/label-merkleization-light.svg" alt="merkleization"></picture><a href="docs/reference/merkleization.md#function-ssz_hash_tree_root"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_hash_tree_root" title="ssz_hash_tree_root: Not proved"></picture></a><a href="docs/reference/merkleization.md#function-ssz_hash_pair"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_hash_pair" title="ssz_hash_pair: Not proved"></picture></a><a href="docs/reference/merkleization.md#function-ssz_value_level"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_value_level" title="ssz_value_level: Not proved"></picture></a><a href="docs/reference/merkleization.md#function-ssz_child_level"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_child_level" title="ssz_child_level: Not proved"></picture></a><a href="docs/reference/merkleization.md#function-ssz_level_leaf"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_level_leaf" title="ssz_level_leaf: Not proved"></picture></a><a href="docs/reference/merkleization.md#function-ssz_level_root"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_level_root" title="ssz_level_root: Not proved"></picture></a><a href="docs/reference/merkleization.md#function-ssz_subtree_root"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_subtree_root" title="ssz_subtree_root: Not proved"></picture></a><br>
<picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/label-proofs-dark.svg"><img src="docs/heatmap/label-proofs-light.svg" alt="proofs"></picture><a href="docs/reference/proofs.md#function-ssz_get_generalized_index"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_get_generalized_index" title="ssz_get_generalized_index: Not proved"></picture></a><a href="docs/reference/proofs.md#function-ssz_build_proof"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_build_proof" title="ssz_build_proof: Not proved"></picture></a><a href="docs/reference/proofs.md#function-ssz_verify_merkle_proof"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_verify_merkle_proof" title="ssz_verify_merkle_proof: Not proved"></picture></a><br>
<picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/label-serialization-dark.svg"><img src="docs/heatmap/label-serialization-light.svg" alt="serialization"></picture><a href="docs/reference/serialization.md#function-ssz_serialize"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_serialize" title="ssz_serialize: Not proved"></picture></a><a href="docs/reference/serialization.md#function-ssz_serialize_size"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_serialize_size" title="ssz_serialize_size: Not proved"></picture></a><a href="docs/reference/serialization.md#function-ssz_deserialize"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_deserialize" title="ssz_deserialize: Not proved"></picture></a><a href="docs/reference/serialization.md#function-ssz_deserialize_size"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_deserialize_size" title="ssz_deserialize_size: Not proved"></picture></a><a href="docs/reference/serialization.md#function-ssz_encode_value"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_encode_value" title="ssz_encode_value: Not proved"></picture></a><a href="docs/reference/serialization.md#function-ssz_decode_value"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/cell-0-dark.svg"><img src="docs/heatmap/cell-0-light.svg" alt="ssz_decode_value" title="ssz_decode_value: Not proved"></picture></a>

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/heatmap/legend-dark.svg"><img src="docs/heatmap/legend-light.svg" alt="Legend"></picture>

</td></tr></table>
<!-- End of the verification heatmap. -->

<!-- CI generates the CI panel here. -->
<table><tr><td>

<a href="https://github.com/bitminetech/asm-ssz/actions/runs/45981665482"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/readme/ci-dark.svg"><img src="docs/readme/ci-light.svg" alt="Latest CI run passed: 8 of 8 jobs passed"></picture></a>

</td></tr></table>
<!-- End of the CI panel. -->

<!-- CI generates the docs panel here. -->
<table><tr><td>

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/readme/docs-header-dark.svg"><img src="docs/readme/docs-header-light.svg" alt="asm-ssz docs"></picture><br>
<picture><source media="(prefers-color-scheme: dark)" srcset="docs/readme/docs-docs-dark.svg"><img src="docs/readme/docs-docs-light.svg" alt="Function docs"></picture><br>
<a href="docs/reference/proofs.md"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/readme/docs-doc-proofs-dark.svg"><img src="docs/readme/docs-doc-proofs-light.svg" alt="Generalized indices and proofs: Merkle proofs of tree nodes"></picture></a><a href="docs/reference/merkleization.md"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/readme/docs-doc-merkleization-dark.svg"><img src="docs/readme/docs-doc-merkleization-light.svg" alt="Merkleization: Hash tree roots of SSZ values"></picture></a><br>
<a href="docs/reference/serialization.md"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/readme/docs-doc-serialization-dark.svg"><img src="docs/readme/docs-doc-serialization-light.svg" alt="Serialization: SSZ types, encode and decode"></picture></a>

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/readme/docs-footer-dark.svg"><img src="docs/readme/docs-footer-light.svg" alt="Select a card to open its doc."></picture>

</td></tr></table>
<!-- End of the docs panel. -->
