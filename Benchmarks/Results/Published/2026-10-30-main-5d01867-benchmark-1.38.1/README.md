# Full Benchmark Snapshot: main 5d01867

> Sanitized historical copy; see [publication notes](../README.md). Embedded hashes and validation claims refer to the original capture.

Measured on 2026-10-30 from clean `main` at
[`5d01867915f257d9d2086a510efe1c20f697b69a`](https://github.com/RouteObjects/swift-cidr-admission/commit/5d01867915f257d9d2086a510efe1c20f697b69a).
This is a dated main-branch observation, not a new library release or a
replacement for the historical 0.1 chart and 0.2.0 snapshot.

## Environment

- Apple M1 Max, native arm64, 10 logical processors, 64 GiB RAM.
- macOS 26.7.1 (25G241), Darwin 25.6.0.
- Apple Swift 6.3.3; Xcode 26.6 (17F113).
- Benchmark 1.38.1, malloc-interposer 1.6.1, swift-cidr 0.8.0, Swift Crypto 5.0.3.
- AC power; battery at 80% before and after the run.
- Invocation started at 15:37:43 UTC; successful completion was observed at 15:46:04 UTC.

Background workload was not controlled. Preflight load averages were
`7.48 / 12.49 / 15.20`; after the run they were `7.70 / 9.23 / 11.84`.
These instrumented timings are not production-server connection rates or
universal performance guarantees. Do not attribute differences from older
snapshots to the Benchmark update alone: dependencies, OS, instrumentation,
batching, and workload conditions also differ.

## Coverage

All **174 cases** completed with all **nine configured metrics**, producing
**1,566 metric records**: 98 indexed lookups, 16 detailed decisions,
36 construction cases, and 24 file-load cases. Allocation and ARC hooks
remained enabled; allocation-stack profiling was not enabled.

The minimum sample count was **four**. **18 cases** had fewer than 30 measured
batches and are flagged in `summary.csv` and listed in `coverage.json`.
This is a reporting heuristic, not a statistical significance test. In
particular, p99 from a handful of samples is not a stable tail estimate.

## Selected Results

Combined cases miss the deny set and match the final source allow rule.
Sizes are **per list**: 10,000 means 10,000 allow and 10,000 deny rules.
The indexed and detailed paths answer the same policy question; detailed
decisions additionally retain first-source-rule diagnostics.

Values below are **median / p99 microseconds per lookup**. An asterisk marks
a case with fewer than 30 measured batches. Values are rounded here;
`summary.csv` retains the exported precision and sample counts.

| Family | Path | 500 per list | 1,000 per list | 10,000 per list |
| --- | --- | ---: | ---: | ---: |
| IPv4 | Indexed `allows(_:)` | 1.691 / 3.490 | 2.096 / 6.337 | 2.509 / 5.534 |
| IPv6 | Indexed `allows(_:)` | 1.674 / 3.533 | 1.874 / 5.837 | 2.591 / 10.969 |
| IPv4 | Detailed `decision(for:)` | 179.306 / 445.172* | 313.786 / 331.900* | 3108.863 / 4861.951 |
| IPv6 | Detailed `decision(for:)` | 156.238 / 191.300* | 313.000 / 429.304* | 3162.111 / 9109.503 |

The corresponding **runner-reported median indexed lookups per second** are:

| Family | 500 per list | 1,000 per list | 10,000 per list |
| --- | ---: | ---: | ---: |
| IPv4 | 591,000 | 477,000 | 399,000 |
| IPv6 | 597,000 | 534,000 | 386,000 |

## Files And Units

- `summary.csv`: all 174 cases, per-operation wall-clock median/p99, throughput
  median, allocation/ARC medians, batch sizes, and sample counts.
- `coverage.json`: completeness checks and the list of sparsely sampled cases.
- `metadata.json`: exact source, dependency, environment, command, and normalization details.
- `dependencies.json`: the unchanged benchmark package lockfile used for this run.
- `baseline.json.gz`: exact native Benchmark 1.38.1 baseline, including all HDR
  histograms. Its uncompressed size is 68,262,921 bytes. This is the runner's
  version-specific internal format; do not assume compatibility with future versions.
- `metrics-batched.csv.gz`: the runner's Influx percentile export of that same
  baseline. Numeric values are raw batch measurements, not per-operation values.
- `results.txt.gz`: the runner's full default scaled tables, exported from the
  saved baseline without remeasurement. Respect its unit prefixes and `*` markers.
- `SHA256SUMS`: checksums for the files in this directory, excluding itself.

For the summary, raw wall-clock nanoseconds and allocation/ARC counts are
divided by the recorded batch size. Raw throughput is batches per second,
so it is multiplied by that size. The runner rounds batch throughput to an
integer before scaling; rates for slow, large batches can therefore be coarse
and need not equal the reciprocal of the median wall-clock value.

The runner reverses percentile rank for metrics that prefer larger values:
its throughput p99 label denotes the low-throughput tail, not the ordinary
99th percentile. The summary uses the symmetric median for throughput and
ordinary p99 for wall-clock time. The upstream CSV `test_average` and unit
labels are not used for normalization; native batch sizes and raw numeric
percentiles are used instead. Upstream CSV timestamps are export times.

## Reproduction

From the repository root, with the source and dependency lock above:

```bash
env -u CIDR_ADMISSION_BENCHMARK_TARGET \
  -u BENCHMARK_DISABLE_MALLOC_INTERPOSER -u BENCHMARK_DISABLE_JEMALLOC \
  -u MALLOC_INTERPOSER_LOCAL_PATH -u RUNTIME_INTERPOSER_LOCAL_PATH \
  swift package --package-path Benchmarks --allow-writing-to-package-directory \
  benchmark baseline update NEW_UNIQUE_SNAPSHOT_NAME \
  --target CIDRAdmissionBenchmarkTarget --benchmark-build-configuration release \
  --no-progress --time-units nanoseconds
```

Use a new baseline name; do not overwrite an existing snapshot. Exporting a
saved baseline with `benchmark baseline read NAME` does not rerun workloads.
The exact executed command and baseline name are retained in `metadata.json`.

Local `BenchmarkTool` linking emitted missing `.pcm` module-cache warnings.
The complete run, discovery, and exports exited successfully. Source files,
dependency locks, the existing benchmark README, and the historical chart
were unchanged during capture.
