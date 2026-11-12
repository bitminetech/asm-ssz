# Vector generator

## Run

```bash
tests/generator/run.sh ~/.cache/asm-ssz/vectors
```

- The output folder must be outside this repo.
- It runs in the image from [platform/linux/Dockerfile](../../platform/linux/Dockerfile).
- The output folder keeps the downloads, the consensus-specs clone and the Python environment. A second run downloads nothing.

## Files

| File | What it holds |
|---|---|
| `run.sh` | Runs the generator in Docker |
| `generate.py` | Fetches the archives, checks their pins, writes the case files |
| `descriptor.py` | The descriptor builder: turns an ssz-specs type into a `TypeDescriptor` |
| `requirements.txt` | Python packages, pinned |

## Output

| File | Cases |
|---|---|
| `<preset>-<fork>-static.bin` | A type, its encoding and its root |
| `<preset>-<fork>-proof.bin` | A type, an object, a generalized index, the leaf and the branch |
| `gindex.bin` | A type, a path of field indices and the generalized index |
| `manifest.txt` | Each file, its case count and its SHA-256 |

- `<preset>`: `mainnet` or `minimal`.
- `<fork>`: phase0, altair, bellatrix, capella, deneb, electra or fulu.

## File format

| Part | Content |
|---|---|
| Magic | The 8 bytes `SSZVEC01` |
| Kind | u64: 1 static, 2 proof, 3 generalized index |
| Descriptors | u64 count, then each `TypeDescriptor` as a blob |
| Cases | u64 count, then each case |

- u64 is 8 bytes, little endian.
- A blob is a u64 length, then that many bytes.
- Each case starts with its name as a blob, then the u64 index of its descriptor.

| Kind | Rest of a case |
|---|---|
| 1, static | The encoding as a blob, then the 32 byte root |
| 2, proof | The object's encoding as a blob, the u64 generalized index, the 32 byte leaf, a u64 node count, then the 32 byte nodes from the leaf up |
| 3, generalized index | A u64 step count, the u64 steps, then the u64 expected index |
