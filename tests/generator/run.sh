#!/bin/sh
# Generate the asm-ssz vectors inside the image from platform/linux/Dockerfile.
# Usage: tests/generator/run.sh OUT_DIR    (OUT_DIR must be outside this repo)
#
# OUT_DIR keeps the downloads (sources/) and the Python environment (.venv/),
# so a second run downloads nothing again.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$1"
out=$(cd "$1" && pwd)
case "$out/" in
  "$root"/*) echo "run.sh: $out is inside the repo; vectors are stored outside it" >&2; exit 2 ;;
esac

docker build -q -t asm-ssz-build -f "$root/platform/linux/Dockerfile" "$root/platform/linux" >/dev/null
docker run --rm -v "$root:/src:ro" -v "$out:/out" asm-ssz-build sh -eu -c '
    commit=aa16bb4c156184e9548a997d53efaf2a228a6304    # consensus-specs v1.7.0-beta.4
    spec=/out/consensus-specs
    if [ "$(git -C $spec rev-parse HEAD 2>/dev/null)" != "$commit" ]; then
        rm -rf $spec
        git init -q $spec
        git -C $spec fetch -q --depth 1 https://github.com/ethereum/consensus-specs $commit
        git -C $spec checkout -q FETCH_HEAD
    fi
    ssz_commit=7bce07ff7d51b1a3c66ff4e2bd3233ac248ede70    # ssz-specs v0.1.0
    ssz_specs=/out/ssz-specs
    if [ "$(git -C $ssz_specs rev-parse HEAD 2>/dev/null)" != "$ssz_commit" ]; then
        rm -rf $ssz_specs
        git init -q $ssz_specs
        git -C $ssz_specs fetch -q --depth 1 https://github.com/ethereum/ssz-specs $ssz_commit
        git -C $ssz_specs checkout -q FETCH_HEAD
    fi
    [ -x /out/.venv/bin/python ] || python3 -m venv /out/.venv
    /out/.venv/bin/pip install -q --disable-pip-version-check -r tests/generator/requirements.txt
    (cd $spec && /out/.venv/bin/python -m pysetup.generate_specs --all-forks)
    PYTHONPATH=$spec/tests/core/pyspec:$spec CONSENSUS_SPECS=$spec SSZ_SPECS=$ssz_specs \
        /out/.venv/bin/python tests/generator/generate.py /out
'
