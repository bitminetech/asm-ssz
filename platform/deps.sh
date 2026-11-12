#!/bin/sh
# Fetch the dependencies that the README pins into build/deps/.
# Runs inside the image from platform/linux/Dockerfile, from the repo root.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
crypto=$root/build/deps/asm-crypto
commit=de79f5bc895ebca6c74ae6dfd86e409a234e07bf    # asm-crypto, README Dependencies
if [ "$(git -C "$crypto" rev-parse HEAD 2>/dev/null)" != "$commit" ]; then
    rm -rf "$crypto"
    git init -q "$crypto"
    git -C "$crypto" fetch -q --depth 1 https://github.com/bitminetech/asm-crypto "$commit"
    git -C "$crypto" checkout -q FETCH_HEAD
fi
