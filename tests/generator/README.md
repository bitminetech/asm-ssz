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
| `refusals.py` | Changes valid inputs and records what the Python spec does with each one |
| `requirements.txt` | Python packages, pinned |

## Output

| File | Cases |
|---|---|
| `<preset>-<fork>-static.bin` | A type, its encoding and its root |
| `<preset>-<fork>-proof.bin` | A type, an object, a generalized index, the leaf and the branch |
| `<preset>-<fork>-verify.bin` | A leaf, a generalized index, a root, a branch and the expected result, for each proof case and changed copies of it |
| `gindex.bin` | A type, a path of field indices and the generalized index |
| `ssz-specs-static.bin` | A type, its encoding and its root, from the ssz-specs v0.1.0 vectors |
| `generated-static.bin` | Valid encodings of small types, and changed encodings that the spec still accepts (`refusals.py`) |
| `generated-reject.bin` | Changed encodings that the spec rejects, with the expected refusal (`refusals.py`) |
| `generated-gindex.bin` | Random paths, valid and not, with the expected status and index (`refusals.py`) |
| `generated-proof.bin` | Random generalized indices into proof objects, with the expected status and branch (`refusals.py`) |
| `ssz-specs-reject.bin` | A type, an encoding the spec rejects and the expected refusal, from the ssz-specs v0.1.0 vectors |
| `manifest.txt` | Each file, its case count and its SHA-256 |

- `<preset>`: `mainnet` or `minimal`.
- `<fork>`: phase0, altair, bellatrix, capella, deneb, electra or fulu.

## File format

| Part | Content |
|---|---|
| Magic | The 8 bytes `SSZVEC01` |
| Kind | u64: 1 static, 2 proof, 3 generalized index, 4 verify, 5 reject, 6 proof outcome |
| Descriptors | u64 count, then each `TypeDescriptor` as a blob |
| Cases | u64 count, then each case |

- u64 is 8 bytes, little endian.
- A blob is a u64 length, then that many bytes.
- Each case starts with its name as a blob.
- In every kind but 4, the u64 index of its descriptor follows the name.

| Kind | Rest of a case |
|---|---|
| 1, static | The encoding as a blob, then the 32 byte root |
| 2, proof | The object's encoding as a blob, the u64 generalized index, the 32 byte leaf, a u64 node count, then the 32 byte nodes from the leaf up |
| 3, generalized index | A u64 step count, the u64 steps, the u64 expected status, then the u64 expected index |
| 4, verify | The 32 byte leaf, the u64 generalized index, the 32 byte root, a u64 node count, the 32 byte nodes from the leaf up, the u64 expected status, then the u64 expected `valid` |
| 5, reject | The encoding as a blob, then the u64 expected status |
| 6, proof outcome | The object's encoding as a blob, the u64 generalized index, the u64 expected status, a u64 node count, then the 32 byte nodes from the leaf up |
