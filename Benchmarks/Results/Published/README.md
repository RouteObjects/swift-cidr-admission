# Sanitized Benchmark Publication Copies

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
