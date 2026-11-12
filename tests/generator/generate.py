#!/usr/bin/env python3
"""Fetch, check and convert the consensus SSZ vectors into binary case files.

Usage: python tests/generator/generate.py OUT_DIR

Run it through tests/generator/run.sh, which uses the image from
platform/linux/Dockerfile and the packages in requirements.txt. The file format
is in README.md next to this script.
"""
import ast
import hashlib
import json
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
from ssz.chunks import Chunk, Root
from ssz.exceptions import SSZValueError
from ssz.verification import verify_merkle_proof

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import descriptor  # noqa: E402
import refusals  # noqa: E402

COMMIT = "aa16bb4c156184e9548a997d53efaf2a228a6304"  # consensus-specs v1.7.0-beta.4
RELEASE = "https://github.com/ethereum/consensus-specs/releases/download/v1.7.0-beta.4/"
ARCHIVES = {
    "mainnet": "67762986572372a08d3b182535aa760433c86e174e14e0bbd756f350dd19398c",
    "minimal": "26d09aea70c62ed235a120a95082d544ab1c2e6fe36bd35ea1bd5da62f3b7b68",
}
FORKS = ("phase0", "altair", "bellatrix", "capella", "deneb", "electra", "fulu")
SSZ_SPECS_COMMIT = "7bce07ff7d51b1a3c66ff4e2bd3233ac248ede70"  # ssz-specs v0.1.0
SSZ_SPECS_VECTORS = ("https://github.com/ethereum/ssz-specs/releases/download/v0.1.0/"
                     "ssz-test-vectors-v0.1.0.tar.gz",
                     "e2a65f032b59835c26127295293ea1bc07d7ca0ea1fe0e4f1128dffed333f878")
# The ssz-specs vector groups whose types the live forks use. The other groups
# test compatible unions and progressive types.
SSZ_SPECS_GROUPS = ("test_basic_types", "test_decode_failure_smoke", "test_merkleization_boundaries")
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
KIND_STATIC, KIND_PROOF, KIND_GINDEX, KIND_VERIFY, KIND_REJECT, KIND_PROOF_OUTCOME = 1, 2, 3, 4, 5, 6
SSZ_INC = pathlib.Path(__file__).resolve().parents[2] / "include" / "ssz.inc"


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
    return obj, int(proof["leaf_index"]), leaf, branch


def status_codes():
    """The status constants of include/ssz.inc, by fault name."""
    return {m[1]: int(m[2]) for m in re.finditer(r"^\.set SSZ_(\w+), (\d+)", SSZ_INC.read_text(), re.M)}


def flip(node):
    """The node with its first bit changed."""
    return bytes([node[0] ^ 1]) + node[1:]


def verify_cases(out, codes, name, leaf, gindex, branch, root):
    """
    The case itself and changed copies of it. The spec's verify_merkle_proof gives
    each expected result: a status, and for status 0 whether the root matches.
    """
    variants = [
        ("as-given", leaf, gindex, branch, root),
        ("leaf-changed", flip(leaf), gindex, branch, root),
        ("root-changed", leaf, gindex, branch, flip(root)),
        ("first-node-changed", leaf, gindex, [flip(branch[0])] + branch[1:], root),
        ("last-node-changed", leaf, gindex, branch[:-1] + [flip(branch[-1])], root),
        ("sibling-index", leaf, gindex ^ 1, branch, root),
        ("node-missing", leaf, gindex, branch[:-1], root),
        ("node-extra", leaf, gindex, branch + [root], root),
        ("index-1", leaf, 1, [], root),
        ("index-0", leaf, 0, branch, root),
    ]
    for label, v_leaf, v_gindex, v_branch, v_root in variants:
        try:
            status, valid = 0, int(verify_merkle_proof(Chunk(v_leaf), [Chunk(n) for n in v_branch],
                                                       v_gindex, Root(v_root)))
        except SSZValueError as e:
            status, valid = codes[e.fault.name], 0
        out.cases.append(blob(f"{name}/{label}".encode()) + v_leaf + u64(v_gindex) + v_root
                         + u64(len(v_branch)) + b"".join(v_branch) + u64(status) + u64(valid))


def filler_types(path):
    """
    The SSZ types that one ssz-specs filler file declares. Only its imports from
    the ssz package and its class definitions run, so the test framework is not needed.
    """
    tree = ast.parse(path.read_text())
    keep = [node for node in tree.body
            if isinstance(node, ast.ClassDef)
            or (isinstance(node, ast.ImportFrom) and node.module in ("ssz", "typing"))]
    names = {}
    exec(compile(ast.Module(body=keep, type_ignores=[]), str(path), "exec"), names)
    return names


def ssz_specs_cases(ssz_specs_dir, archive, codes):
    """
    The ssz-specs v0.1.0 vectors in the groups that the live forks need: valid
    cases as static cases, decode failures as reject cases. The Python spec checks
    each one. Returns the two outputs and the cases left out, with the reason.
    """
    import ssz
    static, reject, skipped = Output(KIND_STATIC), Output(KIND_REJECT), []
    with tarfile.open(archive, "r:gz") as tar:
        for member in sorted(tar.getmembers(), key=lambda m: m.name):
            m = re.match(r"fixtures/ssz/ssz/(\w+)/(\w+)\.json$", member.name)
            if not member.isfile() or not m:
                continue
            group = m.group(1)
            if group not in SSZ_SPECS_GROUPS:
                skipped.append((member.name, "union or progressive type"))
                continue
            types = filler_types(ssz_specs_dir / "tests/fillers/ssz" / f"{group}.py")
            for test_id, case in json.load(tar.extractfile(member)).items():
                ssz_type = types.get(case["typeName"]) or getattr(ssz, case["typeName"])
                try:
                    descriptor.build(ssz_type)
                except ValueError as e:
                    skipped.append((test_id, str(e)))
                    continue
                name = f"ssz-specs/{test_id}"
                if "rejectionReason" in case:
                    raw = bytes.fromhex(case["rawBytes"][2:])
                    try:
                        ssz_type.decode_bytes(raw)
                        fail(f"{name}: the spec decodes the rejected bytes")
                    except SSZValueError as e:
                        if e.fault.name != case["rejectionReason"]:
                            fail(f"{name}: the spec gives {e.fault.name}, the case {case['rejectionReason']}")
                    reject.cases.append(blob(name.encode()) + u64(reject.descriptor(ssz_type)) + blob(raw)
                                        + u64(codes[case["rejectionReason"]]))
                else:
                    serialized = bytes.fromhex(case["serialized"][2:])
                    root = bytes.fromhex(case["root"][2:])
                    if bytes(ssz_type.decode_bytes(serialized).hash_tree_root()) != root:
                        fail(f"{name}: the spec type does not give the case root")
                    static.cases.append(blob(name.encode()) + u64(static.descriptor(ssz_type))
                                        + blob(serialized) + root)
    return static, reject, skipped


def refusal_outputs(codes, seeds, path_types, proof_values):
    """The generated refusal vectors (refusals.py), as four outputs by file name."""
    def need(group, seen):
        missing = [name for name in group if name not in seen]
        if missing:
            fail(f"no generated case for {', '.join(missing)}")

    static_out, reject_out = Output(KIND_STATIC), Output(KIND_REJECT)
    static, reject, seen = refusals.decode_cases(refusals.small_seeds() + seeds)
    need(refusals.DECODE_FAULTS, seen)
    for label, t, encoding, root in static:
        static_out.cases.append(blob(label.encode()) + u64(static_out.descriptor(t)) + blob(encoding) + root)
    for label, t, encoding, fault in reject:
        reject_out.cases.append(blob(label.encode()) + u64(reject_out.descriptor(t)) + blob(encoding)
                                + u64(codes[fault]))

    gindex_out = Output(KIND_GINDEX)
    small = [(f"small/{t.__name__}", t) for t in refusals.SMALL_TYPES + refusals.PATH_ONLY_TYPES]
    cases, seen = refusals.path_cases(small + path_types)
    need(refusals.PATH_FAULTS, seen)
    for label, t, steps, fault, index in cases:
        gindex_out.cases.append(blob(label.encode()) + u64(gindex_out.descriptor(t)) + u64(len(steps))
                                + b"".join(u64(x) for x in steps) + u64(codes[fault] if fault else 0)
                                + u64(index))

    proof_out = Output(KIND_PROOF_OUTCOME)
    cases, seen = refusals.proof_cases(refusals.small_values() + proof_values)
    need(refusals.PROOF_FAULTS, seen)
    for label, t, encoding, g, fault, branch in cases:
        proof_out.cases.append(blob(label.encode()) + u64(proof_out.descriptor(t)) + blob(encoding) + u64(g)
                               + u64(codes[fault] if fault else 0) + u64(len(branch)) + b"".join(branch))
    return {"generated-static.bin": static_out, "generated-reject.bin": reject_out,
            "generated-gindex.bin": gindex_out, "generated-proof.bin": proof_out}


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
                             + u64(len(indices)) + b"".join(u64(i) for i in indices) + u64(0)
                             + u64(int(expected)))
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
    codes = status_codes()

    gindex = gindex_cases(spec_dir)
    count, digest = gindex.write(out_dir / "gindex.bin")
    written.append(("gindex.bin", count, digest))

    ssz_specs_dir = pathlib.Path(os.environ["SSZ_SPECS"])
    if subprocess.run(["git", "-C", str(ssz_specs_dir), "rev-parse", "HEAD"], capture_output=True,
                      text=True).stdout.strip() != SSZ_SPECS_COMMIT:
        fail(f"{ssz_specs_dir} is not ssz-specs at {SSZ_SPECS_COMMIT}")
    archive = cache / "ssz-test-vectors-v0.1.0.tar.gz"
    fetch(SSZ_SPECS_VECTORS[0], SSZ_SPECS_VECTORS[1], archive)
    static, reject, skipped = ssz_specs_cases(ssz_specs_dir, archive, codes)
    for file_name, out in (("ssz-specs-static.bin", static), ("ssz-specs-reject.bin", reject)):
        count, digest = out.write(out_dir / file_name)
        written.append((file_name, count, digest))
    for name, reason in skipped:
        print(f"left out: {name}: {reason}")

    # Inputs for the generated refusal vectors: the two smallest minimal encodings
    # of each type, each type once, and the value of every proof case.
    seeds, path_types, proof_values, descriptors, built = {}, [], [], set(), {}
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
                    d = built.setdefault(ssz_type, descriptor.build(ssz_type))
                    if d not in descriptors:
                        descriptors.add(d)
                        path_types.append((f"{preset}/{fork}/{type_name}", ssz_type))
                        if preset == "minimal":
                            seeds[d] = (f"{preset}/{fork}/{type_name}", ssz_type, [])
                if preset == "minimal":
                    d = built[ssz_type]
                    if d in seeds:
                        smallest = sorted(seeds[d][2] + [serialized], key=len)[:2]
                        seeds[d] = (seeds[d][0], seeds[d][1], smallest)
            else:
                out = outputs.setdefault((fork, "proof"), Output(KIND_PROOF))
                obj, leaf_index, leaf, branch = proof_case(out, ssz_type, name, files)
                value = ssz_type.decode_bytes(obj)
                if [bytes(n) for n in spec.compute_merkle_proof(value, leaf_index)] != branch:
                    fail(f"{name}: the spec proof differs from the case branch")
                if not any(t is ssz_type and o == obj for _, t, o in proof_values):
                    proof_values.append((f"{preset}/{fork}/{type_name}/{case}", ssz_type, obj))
                verify = outputs.setdefault((fork, "verify"), Output(KIND_VERIFY))
                verify_cases(verify, codes, name, leaf, leaf_index, branch,
                             bytes(value.hash_tree_root()))
        for (fork, what), out in sorted(outputs.items()):
            file_name = f"{preset}-{fork}-{what}.bin"
            count, digest = out.write(out_dir / file_name)
            written.append((file_name, count, digest))
            print(f"{file_name} {count}", flush=True)

    values = [(label, t, t.decode_bytes(obj)) for label, t, obj in proof_values]
    for file_name, out in refusal_outputs(codes, list(seeds.values()), path_types, values).items():
        count, digest = out.write(out_dir / file_name)
        written.append((file_name, count, digest))
        print(f"{file_name} {count}", flush=True)

    lines = [f"{name} {count} {digest}" for name, count, digest in written]
    (out_dir / "manifest.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
