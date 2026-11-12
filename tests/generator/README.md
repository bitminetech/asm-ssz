# Vector generation

```bash
tests/generator/run.sh ~/.cache/asm-ssz/vectors
```

`run.sh` runs `generate.py` in the image from [platform/linux/Dockerfile](../../platform/linux/Dockerfile), with the packages in `requirements.txt`. It downloads the pinned consensus test archives, checks their SHA-256 pins, and writes binary case files to the output folder, which must be outside this repo. The folder keeps the downloads and the Python environment, so a second run downloads nothing again. `manifest.txt` lists each file, its case count and its SHA-256.

`descriptor.py` is the descriptor builder: it turns an ssz-specs v0.1.0 type into a `TypeDescriptor` ([docs/reference/types.md](../../docs/reference/types.md)).

| File | Source | Cases |
|---|---|---|
| `<preset>-<fork>-static.bin` | `ssz_static` | Every consensus type: its encoding and its root |
| `<preset>-<fork>-proof.bin` | `merkle_proof/single_merkle_proof` and `light_client/single_merkle_proof` | An object, a generalized index, the leaf and the branch |
| `gindex.bin` | The constant tables of the spec files | A type, a path of field indices, and the generalized index |

`<preset>` is `mainnet` or `minimal`. `<fork>` is one of phase0 to fulu.

The generator also checks its own work: for the first case of each type, the pinned Python spec must decode the encoding and give the same root; for every proof case, the spec's `compute_merkle_proof` must give the same branch; and for every generalized index case, the spec's `get_generalized_index` must give the value that the table states.

## File format

All numbers are unsigned 8-byte little-endian integers. A blob is a length, then that many bytes.

Each file starts with the 8 bytes `SSZVEC01`, then `kind`, then the number of descriptors, then each descriptor as a blob, then the number of cases, then the cases. Every case starts with its name as a blob, then the index of its descriptor.

| `kind` | Rest of one case |
|---|---|
| 1, static | The SSZ encoding as a blob, then the 32-byte root. |
| 2, proof | The object's SSZ encoding as a blob, the generalized index, the 32-byte leaf, the number of branch nodes, then the 32-byte nodes from the leaf up. |
| 3, generalized index | The number of path steps, the steps (field indices), then the expected generalized index. |
