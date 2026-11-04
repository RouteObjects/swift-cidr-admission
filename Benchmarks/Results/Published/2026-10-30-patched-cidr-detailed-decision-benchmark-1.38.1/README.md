# Patched CIDR Detailed-Decision Rerun

> Sanitized historical copy; see [publication notes](../README.md). Embedded hashes and validation claims refer to the original capture.

Captured on 2026-10-30. This is a separate, same-session comparison against a
local `swift-cidr` patch. The [original full-suite snapshot](../2026-10-30-main-5d01867-benchmark-1.38.1/README.md),
[sampling follow-up](../2026-10-30-sampling-followup-benchmark-1.38.1/README.md),
and historical charts and tables are unchanged.

## Results

The three `@inlinable` changes in `swift-cidr` substantially improve ordinary
production `IPAdmissionPolicy.decision(for:)` calls without changing admission
source or requiring a different containment API. At 10,000 rules in each list,
the patched decision is about **32x faster for IPv4 and 30x faster for IPv6**.
Full-metrics and timing-only results closely agree at this size.

Each row below reports the arithmetic mean of two independently captured run
medians, not a pooled-sample median. Each decision misses all 10,000 deny rules
and matches the last of 10,000 allow rules: up to 20,000 rule evaluations.

| Family | Metrics | Baseline p50 (us) | Patched p50 (us) | Speedup |
| --- | --- | ---: | ---: | ---: |
| IPv4 | Full | 3082.239 | 96.703 | 31.87x |
| IPv4 | Timing only | 3089.407 | 96.607 | 31.98x |
| IPv6 | Full | 3108.863 | 103.487 | 30.04x |
| IPv6 | Timing only | 3153.919 | 103.295 | 30.53x |

Across the four patched production captures, individual run medians span
96.511-96.895 us for IPv4 and 103.167-103.679 us for IPv6 at this size.
The corresponding mean full-metrics throughput medians increase from 324.5 to
10,347 decisions/s for IPv4 and from 322 to 9,671 decisions/s for IPv6.
Throughput is exported independently; it is not calculated as the reciprocal
of the table's averaged wall-time median.

Full-metrics results across all policy sizes, again averaging two run medians:

| Rules per list | IPv4 baseline / patched (us) | IPv6 baseline / patched (us) |
| ---: | ---: | ---: |
| 1 | 0.308 / 0.013 | 0.314 / 0.013 |
| 10 | 3.098 / 0.111 | 3.130 / 0.119 |
| 50 | 15.364 / 0.499 | 15.557 / 0.532 |
| 100 | 30.843 / 0.988 | 31.212 / 1.054 |
| 250 | 76.351 / 2.542 | 76.895 / 2.646 |
| 500 | 151.871 / 4.875 | 153.279 / 5.313 |
| 1,000 | 304.767 / 9.731 | 312.063 / 10.399 |
| 10,000 | 3082.239 / 96.703 | 3108.863 / 103.487 |

The first four rows use batches of 1,000 operations. Their percentiles describe
batch-averaged operation costs, not individual-call latency. The remaining
rows use single-operation samples. Per-run p50, p99, throughput, and counts
are retained in [comparison.csv](comparison.csv) and `runs/*/summary.csv`.

All recorded full-metrics allocation and ARC counter medians were zero.
This is not proof that every sample allocated nothing or that an application
cannot leak memory. This comparison does not attribute historical changes to
the OS or Benchmark version; those are held fixed here.

## Remaining Detailed-Decision Gap

The existing network-only diagnostics were rerun against the patch, once in
each metric mode. These are single-run p50 values in us, all with 10,000 samples:

| Diagnostic | IPv4 full | IPv4 timing | IPv6 full | IPv6 timing |
| --- | ---: | ---: | ---: | ---: |
| Production (`projectPerRule`) | 96.895 | 96.703 | 103.359 | 103.295 |
| Typed containment, project once | 25.887 | 25.887 | 38.815 | 38.719 |
| Address bits and mask | 21.887 | 21.887 | 34.015 | 34.143 |
| Family-erased containment, project once | 51.519 | 51.487 | 51.647 | 51.519 |

Ordinary typed containment is now faster than the family-erased control when
both project the peer once. The earlier reason to seek a faster family-erased
wrapper no longer applies to this measured path.

Production still has additional per-rule work. The saved
[assembly excerpts](evidence/codegen-containment.txt) show that the generic
`IPPrefix.contains(address:)` call is gone from patched `AdmissionRule.contains`;
masking and comparison are emitted directly. `decision(for:)` still calls
`AdmissionRule.contains` for each rule, and the network branches still call
`PrefixLength.maximum` while constructing a host-address candidate.

That evidence and the project-once control identify a narrower follow-up:
per-rule peer preparation and call boundaries. They do **not** isolate the
entire remaining difference to host conversion alone: the diagnostic scan also
has different inlining boundaries. No additional optimization was made here.

These alternatives validate full decision equality, including the matching
source-rule reason, for allow, deny, miss, and zero-prefix-context candidates
before timing. They cover network-only fixtures and are not general replacements
for the evaluator's address, network, and range semantics.
See [diagnostics.csv](diagnostics.csv) and [Sampling And Percentiles](../../../Sampling.md).

## Method

- Admission base: `5d01867915f257d9d2086a510efe1c20f697b69a`, plus the existing
  uncommitted reference-sampling and diagnostic harness changes, identical in both variants.
- CIDR baseline: `cdc2e592beb9095875bc42fc4c269396b20d99e3` (`0.8.0`).
- Patched CIDR: that same revision with only the existing `@inlinable` annotations
  on `IPPrefix.contains(address:)`, `CIDR.mask`, and `FixedWidthInteger.networkMask(for:)`,
  plus their comments. This is a local patch, not a published dependency version.
- Benchmark `1.38.1`, malloc-interposer `1.6.1`, and Crypto `5.0.3`; all other pins unchanged.
- Apple M1 Max, 10 logical CPUs, 64 GiB RAM; macOS `26.7.1` (`25G241`), Darwin `25.6.0`.
- Apple Swift `6.3.3` (`swiftlang-6.3.3.1.3`), Xcode `26.6` (`17F113`), ordinary SwiftPM Release builds.

Both variants were built in isolated temporary source copies before measurement.
SwiftPM local dependency edits selected their respective CIDR copies. In these
temporary copies, SwiftPM removes the edited CIDR pin from `Package.resolved`;
every other pin was checked against the original lockfile. Original locks,
effective graphs, workspace state, source hashes, and binary hashes are saved.
The real repositories' manifests and lockfiles were not changed.

Preparation caught `--disable-automatic-resolution` reverting a local edit to
the published dependency. Measurement began only after removing that flag from
edited-package commands and verifying the effective source path. Every capture
then rechecked source hashes, dependency state, and the executable hash.

Run order was baseline full/timing, patched full/timing/timing/full, baseline
timing/full, then patched diagnostic full/timing. Within each variant, full and
timing-only runs used the same executable. Full metrics recorded throughput,
wall-clock time, three malloc counters, object allocations, retains, releases,
and retain/release delta. Timing-only requested just wall-clock and throughput.

Benchmark enables allocation/ARC hooks when their metrics are requested; the
[source excerpt](evidence/benchmark-metric-hooks.txt) records those conditions.
The timing-only runs still link the same instrumentation dependencies: they are
not separately built interposer-free executables. Allocation stacks were disabled.

All production captures used the existing `reference` sampling profile and
the same fixtures, inputs, and compiler settings. Existing compiler activity
was allowed to finish before each capture. Other background activity was not
controlled or continuously monitored; per-run load and power state are recorded.
These are local macOS results, not new Linux/iOS benchmark measurements or a
universal performance guarantee.

## Validation And Artifacts

- Eight production captures, each containing all 16 requested cases; two diagnostic captures of eight cases each.
- 144 case observations and 792 metric records; nine metrics per full case and two per timing-only case.
- Minimum 63 samples overall; minimum 1,685 across patched production captures.
- Every patched 10,000-rule production case and every diagnostic case reached 10,000 samples.
- All 57 admission tests in seven suites passed in both Debug and Release against the patched dependency.
- Original source files, historical results, snapshots, charts, and repository lockfiles were hash-checked; staging and refs were unchanged.

Each `runs/` subdirectory contains the native baseline JSON compressed without
changing its bytes, raw exports/logs, normalized CSV, coverage, case inventory,
and command/environment metadata. [validation.json](validation.json) records
coverage and counter checks; [preservation.json](preservation.json) records test
outcomes and preservation checks. `evidence/` contains source patches, original
and effective dependency records, build/test logs, and disassembly.

`capture-scripts/` preserves the session's orchestration and normalization
scripts for audit. Setup uses session-specific paths and existing working-copy
changes; these are not general-purpose repository commands. Exact commands and
paths for this capture are also recorded in the metadata.

Verify the bundle from this directory with `shasum -a 256 -c SHA256SUMS`.
No files were staged or committed. To discard this rerun, remove only this
capture directory and its link from the parent results index.
