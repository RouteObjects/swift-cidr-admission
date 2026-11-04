#===----------------------------------------------------------------------===#
# This source file is part of the swift-cidr-admission project.
# Copyright (c) 2026 Craig A. Munro
# Licensed under the Apache License, Version 2.0. See LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#===----------------------------------------------------------------------===#

import csv
import gzip
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "publication", Path(__file__).resolve().parents[1] / "prepare-benchmark-publication.py"
)
publication = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publication)


class PublicationTests(unittest.TestCase):
    def test_paths_and_attribution(self):
        home = "/" + "Users/alice/source.swift"
        linux = "/" + "home/alice/source.swift"
        temporary = "/" + "private/var/folders/aa/bb/T/cache"
        text = f"{home}\n{linux}\n{temporary}\nCopyright (c) 2026 Craig A. Munro"
        result = publication.transform("source.swift", text.encode()).decode()
        self.assertEqual(result.count("REDACTED_HOME/source.swift"), 2)
        self.assertIn("REDACTED_TMP/cache", result)
        self.assertIn("Copyright (c) 2026 Craig A. Munro", result)
        publication.check_privacy(result.encode())

    def test_temp_and_home_directory_roots(self):
        source = ('"/' + 'private/var/tmp" "/' + 'var/folders/aa/bb/T" "/' + 'Users/alice"')
        self.assertEqual(publication.redact(source), '"REDACTED_TMP" "REDACTED_TMP" "REDACTED_HOME"')

    def test_json_preserves_numbers_and_fixture_addresses(self):
        source = {"hostname": "alice-MacBook-Pro.local", "iterations": 10000,
                  "wall": 0.000029375, "histogram": [1, 7, 39],
                  "fixture": "192.0.2.67/32", "host": "swift-" + "dev (192.0.2.67)"}
        result = json.loads(publication.transform("baseline.json", json.dumps(source).encode()))
        self.assertEqual(result["hostname"], "benchmark-host")
        self.assertEqual(result["host"], "linux-validation-host")
        for key in ("iterations", "wall", "histogram", "fixture"):
            self.assertEqual(source[key], result[key])

    def test_csv_preserves_numeric_strings_and_quoting(self):
        source = 'hostName,value,test\nalice-MacBook-Pro.local,1.2300,"case,with comma"\n'
        result = publication.transform("metrics.csv", source.encode()).decode()
        rows = list(csv.DictReader(io.StringIO(result)))
        self.assertEqual(rows, [{"hostName": "benchmark-host", "value": "1.2300", "test": "case,with comma"}])

    def test_compression_is_deterministic_and_unchanged_bytes_are_reused(self):
        source = gzip.compress(b'alice-MacBook-Pro.local\n', mtime=123)
        first = publication.transform("run.log.gz", source)
        self.assertEqual(first, publication.transform("run.log.gz", source))
        self.assertEqual(gzip.decompress(first), b'benchmark-host\n')
        unchanged = gzip.compress(b'10000,29.375\n', mtime=123)
        self.assertEqual(publication.transform("run.log.gz", unchanged), unchanged)
        with self.assertRaises((OSError, EOFError)):
            publication.transform("run.log.gz", source[:-8])

    def test_readme_notice_and_relative_link(self):
        source = b'# Capture\n\n[Sampling](../../Sampling.md)\nprojectPerRule = 42\n'
        result = publication.transform("README.md", source).decode()
        self.assertIn("](../../../Sampling.md)", result)
        self.assertIn("projectPerRule = 42", result)
        self.assertIn("Sanitized historical copy", result)

    def test_compressed_json_remains_compact(self):
        source = {"hostname": "alice-MacBook-Pro.local", "counts": [0, 1, 10000]}
        result = publication.transform("baseline.json.gz", gzip.compress(json.dumps(source).encode()))
        payload = gzip.decompress(result)
        self.assertEqual(payload.count(b'\n'), 1)
        source["hostname"] = "benchmark-host"
        self.assertEqual(json.loads(payload), source)

    def test_unsafe_or_incomplete_manifests_are_rejected(self):
        for name in ("../escape", "/absolute", "missing"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                publication.check_manifest({"SHA256SUMS": f"{'0' * 64}  {name}\n".encode()})
        with self.assertRaises(ValueError):
            publication.check_manifest({"SHA256SUMS": b"", "extra": b"content"})

    def test_secrets_require_manual_review(self):
        marker = "gh" + "p_" + "A" * 30
        with self.assertRaisesRegex(ValueError, "manual review"):
            publication.transform("run.log", marker.encode())

    def test_round_trip_and_original_preservation(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(publication, "BUNDLES", ("capture",)):
            root = Path(temp)
            source = root / "source"
            bundle = source / "capture"
            bundle.mkdir(parents=True)
            content = {"README.md": b"# Capture\n", "raw.log": b"alice-MacBook-Pro.local\n"}
            content["SHA256SUMS"] = publication.checksum_manifest(content)
            for name, data in content.items():
                (bundle / name).write_bytes(data)
            destination = root / "published"
            publication.prepare(source, destination)
            publication.verify_published(destination)
            self.assertEqual(publication.files(bundle), content)
            self.assertEqual(publication.files(destination), publication.expected_publication(source))
            self.assertEqual((destination / "capture/ORIGINAL-SHA256SUMS").read_bytes(), content["SHA256SUMS"])
            with self.assertRaisesRegex(ValueError, "already exists"):
                publication.prepare(source, destination)
            with self.assertRaisesRegex(ValueError, "inside an original"):
                publication.prepare(source, bundle / "nested")
            (destination / "capture/raw.log").write_bytes(b"tampered")
            with self.assertRaisesRegex(ValueError, "Checksum mismatch"):
                publication.verify_published(destination)

    def test_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "link").symlink_to("missing")
            with self.assertRaisesRegex(ValueError, "Symlinks"):
                publication.files(root)


if __name__ == "__main__":
    unittest.main()
