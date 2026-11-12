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

- Linux ISAs other than the host's run under QEMU user mode.
- [.github/workflows/ci.yml](../../.github/workflows/ci.yml) runs every file on all 7 targets.

## Checks

| Check | Fails when |
|---|---|
| Results | A status, encoding, size, root or branch differs from the case |
| Buffers | A function writes into the 64 guard bytes after any buffer |
| Stack | A call uses more than the README stack cap |

- Output and scratch buffers start filled with `0xA5`.
- The stack check fills the stack below the caller with a pattern before each call. After the call, it finds the lowest byte that changed.
- The runner prints the most stack each function used.
