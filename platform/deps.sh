#!/bin/sh
# Fetch the dependencies that the README pins into build/deps/.
# Runs inside the image from platform/linux/Dockerfile, from the repo root.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
crypto=$root/build/deps/asm-crypto
commit=745aaf5954c57bb65289f474326d5c566e4d653e    # asm-crypto, README Dependencies
if [ "$(git -C "$crypto" rev-parse HEAD 2>/dev/null)" != "$commit" ]; then
    rm -rf "$crypto"
    git init -q "$crypto"
    git -C "$crypto" fetch -q --depth 1 https://github.com/bitminetech/asm-crypto "$commit"
    git -C "$crypto" checkout -q FETCH_HEAD
fi
