#!/usr/bin/env python3
#===----------------------------------------------------------------------===#
# This source file is part of the swift-cidr-admission project.
# Copyright (c) 2026 Craig A. Munro
# Licensed under the Apache License, Version 2.0. See LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#===----------------------------------------------------------------------===#

"""Create or verify separate, sanitized derivatives of the October captures."""

import argparse
import csv
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import tempfile


BUNDLES = tuple(
    f"2026-10-30-{name}-benchmark-1.38.1" for name in (
        "main-5d01867", "sampling-followup", "patched-cidr-detailed-decision",
        "peer-projection", "lazy-peer-projection", "two-phase-peer-projection",
    )
)
# Assemble sensitive markers so the repository's release gate can audit this tool.
HOME = re.compile(r"/(?:" + "Users|home" + r")/[^/\s\"'\\]+")
TEMP = re.compile(r"/(?:private/)?var/(?:folders/[^/]+/[^/]+/[TC]|tmp)(?=/|[\s\"'\\)]|$)")
PRIVATE = re.compile(r"/" + r"Users/|/" + r"home/[^/]+/|/" + r"private/var/")
HOST = re.compile(r"\b[\w.-]+-MacBook-Pro(?:\.local)?\b")
LINUX_HOST = re.compile("swift-" + r"dev(?: \([0-9.]+\))?")
SECRETS = re.compile(
    r"-----BE" + r"GIN (?:OPENSSH |RSA |EC |DSA |ENCRYPTED )?PRIVATE KEY-----"
    r"|(?:A" + r"KIA|A" + r"SIA)[0-9A-Z]{16}"
    r"|gh" + r"[pousr]_[A-Za-z0-9]{20,}"
    r"|github" + r"_pat_[A-Za-z0-9_]{20,}"
    r"|xo" + r"x[baprs]-[A-Za-z0-9-]{20,}"
    r"|sk" + r"-(?:live|proj)-[A-Za-z0-9_-]{16,}"
)

README = """# Sanitized Benchmark Publication Copies

These are derivatives of six dated October captures, not new measurements or
a performance baseline for released 0.3.3. See the [capture index](../README.md)
for the investigation's outcome and [sampling guide](../../Sampling.md) for
percentile interpretation. Historical case names and numerical results remain
unchanged, including the original full-suite CSV's overly broad percentile labels.
Use the sampling follow-up's `original-summary-relabeled.csv` for corrected labels.

## Provenance And Redaction

- Original captures remain outside this directory, unchanged and ignored by Git.
- Home and per-user temporary paths become `REDACTED_HOME/` and `REDACTED_TMP/`.
  Machine hostnames become `benchmark-host` or `linux-validation-host`.
  The Linux validation host's address is removed with its host description;
  benchmark IP fixtures, hardware, OS/compiler versions, and attribution remain.
- JSON strings and CSV fields are transformed with structured parsers; numerical
  values are preserved. Changed gzip payloads are recompressed deterministically.
  Unchanged artifacts are copied byte-for-byte. Relative sampling links are
  adjusted for this directory's extra nesting and capture READMEs get a notice.
- Each bundle's `ORIGINAL-SHA256SUMS` is the untouched original checksum manifest.
  `publication.json` maps every original file hash to its published file hash.
  `SHA256SUMS` checks the publication bytes, including this mapping. The root
  `SHA256SUMS` also covers all bundles and their manifests.
- Embedded historical hashes, byte counts, commands, source paths, and validation
  claims still refer to original captures. They are not silently rewritten to
  claim validation of sanitized bytes. Archived scripts/patches are evidence,
  not a turnkey reproduction workflow; redacted paths need local configuration.

Checksums detect byte changes, not producer authenticity. The automated privacy
scan covers known path, host, and credential patterns; it is not a guarantee
that arbitrary future captures contain no sensitive information.

## Verification

From the repository root (Python 3.9 or later, standard library only):

```bash
python3 scripts/prepare-benchmark-publication.py --verify-published
python3 -B -m unittest discover -s scripts/tests -p 'test_benchmark_publication.py'
```

Maintainers with the private originals can additionally run:

```bash
python3 scripts/prepare-benchmark-publication.py --verify
```

To regenerate, use `--destination` with a new empty location. The tool refuses
to overwrite an existing destination, validates every original checksum first,
and never modifies source captures. Regeneration is deterministic within the
same Python/zlib runtime; cross-runtime compression bytes can differ.
"""


def sha(data):
    return hashlib.sha256(data).hexdigest()


def files(root):
    paths = sorted(root.rglob("*"))
    if any(p.is_symlink() for p in paths) or root.is_symlink():
        raise ValueError("Symlinks are not supported in capture bundles")
    return {p.relative_to(root).as_posix(): p.read_bytes() for p in paths if p.is_file()}


def checksum_manifest(contents):
    return "".join(f"{sha(data)}  {name}\n" for name, data in sorted(contents.items())).encode()


def check_manifest(contents, name="SHA256SUMS"):
    expected = {}
    for line in contents[name].decode().splitlines():
        digest, path = line.split(maxsplit=1)
        path = path.removeprefix("*")
        parts = PurePosixPath(path)
        if parts.is_absolute() or ".." in parts.parts or path in expected:
            raise ValueError("Invalid or duplicate checksum path")
        expected[path] = digest
    actual = {p: sha(data) for p, data in contents.items() if p != name}
    if expected != actual:
        raise ValueError("Checksum mismatch or incomplete manifest")


def redact(text):
    text = HOME.sub("REDACTED_HOME", text)
    text = TEMP.sub("REDACTED_TMP", text)
    text = HOST.sub("benchmark-host", text)
    return LINUX_HOST.sub("linux-validation-host", text)


def redact_json(value):
    if isinstance(value, str):
        return redact(value)
    if isinstance(value, list):
        return [redact_json(item) for item in value]
    if isinstance(value, dict):
        result = {redact(key): redact_json(item) for key, item in value.items()}
        if len(result) != len(value):
            raise ValueError("Redaction would merge JSON keys")
        return result
    return value


def check_privacy(data):
    text = data.decode("utf-8")
    if PRIVATE.search(text) or TEMP.search(text) or HOST.search(text) or LINUX_HOST.search(text):
        raise ValueError("Unredacted private path or host identity")
    if SECRETS.search(text):
        raise ValueError("Credential marker requires manual review")


def transform(name, data):
    zipped = name.endswith(".gz")
    payload = gzip.decompress(data) if zipped else data
    text = payload.decode("utf-8")
    logical_name = name[:-3] if zipped else name
    if logical_name.endswith(".json"):
        before = json.loads(text)
        after = redact_json(before)
        if before != after:
            # Native histograms contain large arrays; keep compressed JSON compact.
            formatting = {"separators": (",", ":")} if zipped else {"indent": 2}
            text = json.dumps(after, ensure_ascii=False, **formatting) + "\n"
    elif logical_name.endswith(".csv") or logical_name.endswith("export-influx.stdout.log"):
        rows = list(csv.reader(io.StringIO(text, newline="")))
        redacted = [[redact(field) for field in row] for row in rows]
        if rows != redacted:
            output = io.StringIO(newline="")
            csv.writer(output, lineterminator="\n").writerows(redacted)
            text = output.getvalue()
    else:
        text = redact(text)
    if name == "README.md":
        heading, remainder = text.split("\n", 1)
        text = heading + ("\n\n> Sanitized historical copy; see [publication notes](../README.md)."
                          " Embedded hashes and validation claims refer to the original capture.\n") + remainder
        text = text.replace("](../../Sampling.md)", "](../../../Sampling.md)")
    result = text.encode("utf-8")
    check_privacy(result)
    if result == payload:
        return data
    return gzip.compress(result, compresslevel=9, mtime=0) if zipped else result


def publication_bundle(source):
    original = files(source)
    check_manifest(original)
    output = {}
    mapping = []
    for name, data in original.items():
        target = "ORIGINAL-SHA256SUMS" if name == "SHA256SUMS" else name
        try:
            published = data if name == "SHA256SUMS" else transform(name, data)
        except (ValueError, OSError, EOFError) as error:
            raise ValueError(f"{source.name}/{name}: {error}") from error
        output[target] = published
        mapping.append({"original": name, "published": target,
                        "original_sha256": sha(data), "published_sha256": sha(published),
                        "changed": data != published})
    output["publication.json"] = (json.dumps({
        "schema_version": 1, "source_bundle": source.name,
        "scope": "Sanitized derivative; embedded historical hashes describe original artifacts.",
        "files": mapping,
    }, indent=2) + "\n").encode()
    output["SHA256SUMS"] = checksum_manifest(output)
    return output


def expected_publication(source):
    output = {"README.md": README.encode()}
    for name in BUNDLES:
        for path, data in publication_bundle(source / name).items():
            output[f"{name}/{path}"] = data
    output["SHA256SUMS"] = checksum_manifest(output)
    return output


def verify_published(destination):
    content = files(destination)
    check_manifest(content)
    for name, data in content.items():
        check_privacy(gzip.decompress(data) if name.endswith(".gz") else data)
    for name in BUNDLES:
        bundle = files(destination / name)
        check_manifest(bundle)
        mapping = json.loads(bundle["publication.json"])["files"]
        if {row["published"] for row in mapping} != set(bundle) - {"SHA256SUMS", "publication.json"}:
            raise ValueError("Publication mapping is incomplete")
        for row in mapping:
            if sha(bundle[row["published"]]) != row["published_sha256"]:
                raise ValueError("Publication mapping hash mismatch")
    return len(content)


def prepare(source, destination):
    if destination.exists():
        raise ValueError("Destination already exists; use --verify or a new destination")
    for name in BUNDLES:
        if destination.resolve().is_relative_to((source / name).resolve()):
            raise ValueError("Destination cannot be inside an original capture")
    output = expected_publication(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Publish only after the complete derivative passes checks; failures leave originals alone.
    with tempfile.TemporaryDirectory(prefix=".publication-", dir=destination.parent) as temporary:
        staging = Path(temporary) / "Published"
        staging.mkdir()
        for name, data in output.items():
            target = staging / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        verify_published(staging)
        staging.rename(destination)


def main():
    root = Path(__file__).resolve().parent.parent / "Benchmarks" / "Results"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=root)
    parser.add_argument("--destination", type=Path, default=root / "Published")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--verify", action="store_true", help="Compare derivatives against private originals")
    mode.add_argument("--verify-published", action="store_true", help="Verify without private originals")
    args = parser.parse_args()
    if args.verify:
        if files(args.destination) != expected_publication(args.source):
            raise ValueError("Publication differs from expected sanitized originals")
    elif not args.verify_published:
        prepare(args.source, args.destination)
    print(f"Verified {verify_published(args.destination)} publication files across {len(BUNDLES)} bundles")


if __name__ == "__main__":
    main()
