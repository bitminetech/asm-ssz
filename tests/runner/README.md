# Test runner

`runner.c` reads the case files from [tests/generator/](../generator/), calls the library for every case and compares the results. It is test code in C. The library is assembly.

## Run

```bash
tests/runner/docker.sh ~/.cache/asm-ssz/vectors
```

```bash
tests/runner/macos.sh ~/.cache/asm-ssz/vectors
```

- Make the vectors first with [tests/generator/run.sh](../generator/run.sh).
- Add file names after the folder to run only those files.

## Files

| File | What it does |
|---|---|
| `runner.c` | Runs the cases: `runner VECTOR_DIR FILE ...` |
| `docker.sh` | Builds all 7 targets in Docker, then runs every file on Linux x86-64, ARM64 and RISC-V |
| `macos.sh` | Links the runner on a Mac against the library that `docker.sh` built, then runs every file |
| `tick_tables.py` | Writes the tick table of each function into its document, from the results of every target |

- Linux ISAs other than the host's run under QEMU user mode.
- [.github/workflows/ci.yml](../../.github/workflows/ci.yml) runs every file on all 7 targets.

## Checks

| Check | Fails when |
|---|---|
| Results | A status, encoding, size, root, branch or `valid` result differs from the case |
| Buffers | A function writes into the 64 guard bytes after any buffer |
| Stack | A call uses more than the README stack cap |

- Output and scratch buffers start filled with `0xA5`.
- The stack check fills the stack below the caller with a pattern before each call. After the call, it finds the lowest byte that changed.
- The runner prints the most stack each function used.

## Results

- The runner prints one line for each function: `FUNCTION <name> PASS` or `FUNCTION <name> FAIL`.
- `PASS`: every file with cases for the function passed, and the function stayed within the stack cap.

| File kind | Functions it tests |
|---|---|
| 1, static | `ssz_deserialize_size`, `ssz_deserialize`, `ssz_serialize_size`, `ssz_serialize`, `ssz_hash_tree_root` |
| 2, proof | `ssz_deserialize_size`, `ssz_deserialize`, `ssz_build_proof` |
| 3, generalized index | `ssz_get_generalized_index` |
| 4, verify | `ssz_verify_merkle_proof` |
| 5, reject | `ssz_deserialize_size`, `ssz_deserialize` |
| 6, proof outcome | `ssz_deserialize_size`, `ssz_deserialize`, `ssz_build_proof` |

## Tick tables

- CI runs `tick_tables.py` after the tests of all 7 targets.
- An OS cell gets ✅ when the runner of that target printed `PASS` for the function.
- An L0 function has no cases of its own. It gets ✅ when every L2 function that calls it, directly or through others, got ✅ on that target.
- The calls come from `build/linux-<ISA>/calls.txt`, which [platform/check.py](../../platform/check.py) writes.
- The `equal` cells stay empty: CI checks no proofs.
- On a push to `main`, CI commits the tables when they change.
