#!/usr/bin/env python3
"""Fetch, check and convert the consensus SSZ vectors into binary case files.

Usage: python tests/generator/generate.py OUT_DIR

Run it through tests/generator/run.sh, which uses the image from
platform/linux/Dockerfile and the packages in requirements.txt. The file format
is in README.md next to this script.
"""
import hashlib
import os
import pathlib
import re
import struct
import subprocess
import sys
import tarfile
import urllib.request

import snappy
from ruamel.yaml import YAML

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import descriptor  # noqa: E402

COMMIT = "aa16bb4c156184e9548a997d53efaf2a228a6304"  # consensus-specs v1.7.0-beta.4
RELEASE = "https://github.com/ethereum/consensus-specs/releases/download/v1.7.0-beta.4/"
ARCHIVES = {
    "mainnet": "67762986572372a08d3b182535aa760433c86e174e14e0bbd756f350dd19398c",
    "minimal": "26d09aea70c62ed235a120a95082d544ab1c2e6fe36bd35ea1bd5da62f3b7b68",
}
FORKS = ("phase0", "altair", "bellatrix", "capella", "deneb", "electra", "fulu")
# Spec files whose constant tables give a generalized index with its path.
GINDEX_SOURCES = {
    "altair": "specs/altair/light-client/sync-protocol.md",
    "capella": "specs/capella/light-client/sync-protocol.md",
    "electra": "specs/electra/light-client/sync-protocol.md",
}
GINDEX_ROW = re.compile(r'get_generalized_index\(((?:\w+\.)?\w+)((?:, "\w+")+)\)` \(= (\d+)\)')
CASE = re.compile(
    r"tests/(mainnet|minimal)/(\w+)/(ssz_static|merkle_proof/single_merkle_proof|"
    r"light_client/single_merkle_proof)/(\w+)/(.+)/([^/]+)$"
)

MAGIC = b"SSZVEC01"
KIND_STATIC, KIND_PROOF, KIND_GINDEX = 1, 2, 3


def fail(text):
    sys.exit("generate.py: " + text)


def u64(n):
    return struct.pack("<Q", n)


def blob(data):
    return u64(len(data)) + data


def fetch(url, sha256, path):
    """Download url to path once, then check its SHA-256 pin."""
    if not path.exists():
        request = urllib.request.Request(url, headers={"User-Agent": "asm-ssz-vector-generator"})
        with urllib.request.urlopen(request) as response, open(path, "wb") as f:
            while chunk := response.read(1 << 20):
                f.write(chunk)
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    if h.hexdigest() != sha256:
        fail(f"{url} has SHA-256 {h.hexdigest()}, expected {sha256}")


def spec_module(fork, preset):
    module = __import__(f"eth_consensus_specs.{fork}.{preset}", fromlist=["*"])
    return module


class Output:
    """One binary case file: a descriptor table, then the cases."""

    def __init__(self, kind):
        self.kind, self.descriptors, self.index, self.cases = kind, [], {}, []

    def descriptor(self, ssz_type):
        if ssz_type not in self.index:
            self.index[ssz_type] = len(self.descriptors)
            self.descriptors.append(descriptor.build(ssz_type))
        return self.index[ssz_type]

    def write(self, path):
        data = bytearray(MAGIC + u64(self.kind) + u64(len(self.descriptors)))
        for d in self.descriptors:
            data += blob(d)
        data += u64(len(self.cases))
        for case in self.cases:
            data += case
        path.write_bytes(data)
        return len(self.cases), hashlib.sha256(data).hexdigest()


def read_cases(archive):
    """Yield (preset, fork, format, type name, case, {file name: bytes}) from one archive."""
    current, files = None, {}
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar:
            m = CASE.search(member.name) if member.isfile() else None
            if not m or m.group(2) not in FORKS:
                continue
            key = m.groups()[:5]
            if key != current:
                if current:
                    yield (*current, files)
                current, files = key, {}
            files[m.group(6)] = tar.extractfile(member).read()
    if current:
        yield (*current, files)


def static_case(out, ssz_type, name, files):
    serialized = snappy.uncompress(files["serialized.ssz_snappy"])
    root_line = files["roots.yaml"].decode().strip()
    if not root_line.startswith("root: "):
        fail(f"{name}: unexpected roots.yaml")
    root = bytes.fromhex(root_line.split()[1].strip("'\"")[2:])
    index = out.descriptor(ssz_type)
    out.cases.append(blob(name.encode()) + u64(index) + blob(serialized) + root)
    return serialized, root


def proof_case(out, ssz_type, name, files):
    obj = snappy.uncompress(files["object.ssz_snappy"])
    proof = YAML(typ="safe").load(files["proof.yaml"])
    leaf = bytes.fromhex(proof["leaf"][2:])
    branch = [bytes.fromhex(node[2:]) for node in proof["branch"]]
    index = out.descriptor(ssz_type)
    out.cases.append(blob(name.encode()) + u64(index) + blob(obj) + u64(int(proof["leaf_index"]))
                     + leaf + u64(len(branch)) + b"".join(branch))
    return obj, int(proof["leaf_index"]), branch


def gindex_cases(spec_dir):
    """The generalized indices that the spec states with their paths."""
    out = Output(KIND_GINDEX)
    for fork, path in GINDEX_SOURCES.items():
        rows = GINDEX_ROW.findall((spec_dir / path).read_text())
        if not rows:
            fail(f"no generalized index rows in {path}")
        for type_name, steps, expected in rows:
            type_fork, type_name = type_name.split(".") if "." in type_name else (fork, type_name)
            spec = spec_module(type_fork, "mainnet")
            ssz_type = getattr(spec, type_name)
            names = re.findall(r'"(\w+)"', steps)
            got = spec.get_generalized_index(ssz_type, *names)
            if got != int(expected):
                fail(f"{path}: the spec gives {got} for {names}, its table says {expected}")
            indices, current = [], ssz_type
            for step in names:
                indices.append(descriptor.field_index(current, step))
                current = dict(current._FIELD_TYPES)[step]
            name = f"{fork}/{type_fork}.{type_name}/{'.'.join(names)}"
            out.cases.append(blob(name.encode()) + u64(out.descriptor(ssz_type))
                             + u64(len(indices)) + b"".join(u64(i) for i in indices) + u64(int(expected)))
    return out


def main():
    if len(sys.argv) != 2:
        fail("usage: generate.py OUT_DIR")
    out_dir = pathlib.Path(sys.argv[1]).resolve()
    cache = out_dir / "sources"
    cache.mkdir(parents=True, exist_ok=True)
    spec_dir = pathlib.Path(os.environ["CONSENSUS_SPECS"])
    if subprocess.run(["git", "-C", str(spec_dir), "rev-parse", "HEAD"], capture_output=True,
                      text=True).stdout.strip() != COMMIT:
        fail(f"{spec_dir} is not consensus-specs at {COMMIT}")
    written = []

    gindex = gindex_cases(spec_dir)
    count, digest = gindex.write(out_dir / "gindex.bin")
    written.append(("gindex.bin", count, digest))

    for preset, sha256 in ARCHIVES.items():
        archive = cache / f"{preset}.tar.gz"
        fetch(RELEASE + f"{preset}.tar.gz", sha256, archive)
        outputs, checked = {}, set()
        for _, fork, fmt, type_name, case, files in read_cases(archive):
            spec = spec_module(fork, preset)
            ssz_type = getattr(spec, type_name)
            name = f"{preset}/{fork}/{fmt}/{type_name}/{case}"
            if fmt == "ssz_static":
                out = outputs.setdefault((fork, "static"), Output(KIND_STATIC))
                serialized, root = static_case(out, ssz_type, name, files)
                if (fork, type_name) not in checked:
                    # One check per type that the descriptor's type is the one the case uses.
                    checked.add((fork, type_name))
                    if bytes(ssz_type.decode_bytes(serialized).hash_tree_root()) != root:
                        fail(f"{name}: the spec type does not give the case root")
            else:
                out = outputs.setdefault((fork, "proof"), Output(KIND_PROOF))
                obj, leaf_index, branch = proof_case(out, ssz_type, name, files)
                value = ssz_type.decode_bytes(obj)
                if [bytes(n) for n in spec.compute_merkle_proof(value, leaf_index)] != branch:
                    fail(f"{name}: the spec proof differs from the case branch")
        for (fork, what), out in sorted(outputs.items()):
            file_name = f"{preset}-{fork}-{what}.bin"
            count, digest = out.write(out_dir / file_name)
            written.append((file_name, count, digest))
            print(f"{file_name} {count}", flush=True)

    lines = [f"{name} {count} {digest}" for name, count, digest in written]
    (out_dir / "manifest.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
