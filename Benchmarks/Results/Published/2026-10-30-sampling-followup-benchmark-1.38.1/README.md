# Sampling Follow-up And Decision Timing Investigation

> Sanitized historical copy; see [publication notes](../README.md). Embedded hashes and validation claims refer to the original capture.

Measured on 2026-10-30 on `chore/benchmark-sampling-validation`, based on main
commit `5d01867915f257d9d2086a510efe1c20f697b69a`, with uncommitted benchmark-only
changes. No production-library code or dependency pins were changed.

The [original 174-case capture](../2026-10-30-main-5d01867-benchmark-1.38.1/README.md)
is unchanged, including its README, CSV, archives, metadata, and checksums.
These are separate captures, not replacement rows spliced into that snapshot.

## Percentile Label Correction

The original summary's `wall_p50_ns_per_operation` and
`wall_p99_ns_per_operation` divide timed batch durations by their batch size.
For a 1,000-operation batch, these are percentiles of **batch means**, not
individual-call latency percentiles. The original README's phrase "median /
p99 microseconds per lookup" is therefore too broad for its batched cases.

[original-summary-relabeled.csv](original-summary-relabeled.csv) preserves all
174 original rows and every numerical value. It renames those columns to
`wall_p50_sample_mean_ns_per_operation` and
`wall_p99_sample_mean_ns_per_operation`, and adds `wall_sample_unit`:
`batch_mean` or `single_operation`. New summaries use the same explicit labels.
Allocation/ARC medians are likewise batch-normalized; throughput is the median
of the runner's rounded batches/second multiplied by batch size. Only its
symmetric median is reported because upstream reverses ranks for metrics
that prefer larger values. See [Sampling And Percentiles](../../../Sampling.md).

## The 18 Reruns

[rerun-18/summary.csv](rerun-18/summary.csv) contains exactly the 18 cases flagged
below 30 samples in the original capture, with all nine metrics: ten
construction, six detailed-decision, and two file-load cases.

All now use **one operation per sample** and have **1,124 to 10,000 samples**,
instead of 4 to 29. The 16 formerly batched cases retain their original logical
warmup counts: 2,000 construction operations or 3,000 detailed decisions.
Their sampling windows remain two seconds, subject to the 10,000-sample cap.
The two already-unbatched range-file loads use 90-second windows.

Selected detailed decisions, **p50 / p99 us per individual operation**:

| Family | Rules per list | Samples | p50 / p99 us |
| --- | ---: | ---: | ---: |
| IPv4 | 250 | 10,000 | 77.887 / 195.071 |
| IPv4 | 500 | 10,000 | 155.135 / 364.287 |
| IPv4 | 1,000 | 5,998 | 312.575 / 696.319 |
| IPv6 | 250 | 10,000 | 76.735 / 133.887 |
| IPv6 | 500 | 10,000 | 156.159 / 319.743 |
| IPv6 | 1,000 | 4,488 | 319.231 / 1980.415 |

IPv6 range-file construction at 10,000 rules,
**p50 / p99 ms per individual load**:

| Integrity | Samples | p50 / p99 ms |
| --- | ---: | ---: |
| Required checksum | 1,155 | 73.859 / 158.466 |
| Verify if present, no checksum file | 1,124 | 75.104 / 171.311 |

The medians retain the expected linear detailed-scan shape. Individual-call
tails can be higher than batch-mean tails because batching averages away
within-batch variation. The higher sample counts improve coverage; they do
not establish independent samples, stable production p99, or CI thresholds.

## Instrumentation Comparison

At 10,000 rules **per list**, a combined decision misses 10,000 deny rules and
matches the last of 10,000 allow rules. Four separate captures ran in
full/timing/timing/full order, with unchanged source and dependencies, one
operation per sample, three warmups, and two-second windows.

Full metrics include wall time, throughput, malloc, and ARC counters. Timing
uses only `wallClock` and `throughput`, which does not request malloc or ARC
hooks. All eight cases completed; sample counts range from 485 to 606.

**Median ms per individual detailed decision**:

| Family | Full 1 | Timing 1 | Timing 2 | Full 2 |
| --- | ---: | ---: | ---: | ---: |
| IPv4 | 3.193 | 3.471 | 3.250 | 3.183 |
| IPv6 | 3.185 | 3.400 | 3.224 | 3.432 |

Removing allocation and ARC measurement does **not** explain the timing gap.
The full-metrics decisions have zero median malloc, object-allocation, retain,
and release counts. These are current-build observations, not evidence of
zero allocations for every possible input or of negative instrumentation cost.

The older 0.2.0 README table records p99 of about 35 us / 45 us at this size.
Its raw capture is not checked in, the historical harness used batching, and
dependencies and OS differ. This is not a controlled historical regression
comparison. The current millisecond-scale detailed cost is reproducible even
without allocation/ARC measurement and warrants investigation on its own.

## Containment Controls

The initial diagnostic captures use the same network-only fixtures and return
the full `AdmissionDecision`, including the first matching source rule. They
use one operation per sample, 30 warmups, and ten-second windows, subject to
the 10,000-sample cap. Before timing, alternatives check allow, deny, miss, and
zero-prefix-context peers against production decisions.

**Median ms per individual decision**, from `diagnostic-full` and
`diagnostic-timing` (at least 2,677 samples per case):

| Family | Path | Full metrics | Timing only |
| --- | --- | ---: | ---: |
| IPv4 | Production, project per rule | 3.238 | 3.219 |
| IPv4 | Project once, concrete generic containment | 3.238 | 3.207 |
| IPv4 | Address bits with generic mask getter | 1.353 | 1.368 |
| IPv6 | Production, project per rule | 3.228 | 3.201 |
| IPv6 | Project once, concrete generic containment | 3.111 | 3.148 |
| IPv6 | Address bits with generic mask getter | 1.377 | 1.359 |

Moving host projection outside the scan does not materially improve it.
Removing the hierarchical check helps, but the generic mask expression is
still expensive. This motivated an additional, separately captured control:
project once and call `AnyIPNetwork.contains(address:)`, letting the existing
CIDR implementation dispatch to its concrete-family arithmetic.

The additional `erased-host-full` and `erased-host-timing` captures repeat the
production control alongside that alternative, with the same sampling
configuration (at least 2,706 samples; both alternatives reach 10,000):

| Family | Production, full ms | Erased host, full us | Production, timing ms | Erased host, timing us |
| --- | ---: | ---: | ---: | ---: |
| IPv4 | 3.135 | 58.015 | 3.172 | 58.559 |
| IPv6 | 3.148 | 57.983 | 3.265 | 57.759 |

That is roughly **54-57x lower median cost** for the alternative in these
runs, with the same checked network-only decisions and source-rule reasons.
It is not an improvement to production: the evaluator was not edited.

### Diagnosis And Scope

The [ARM64 assembly evidence](assembly/README.md) supports an avoidable generic
API/code-generation cost in this release build. Production's network branch
calls the unspecialized `IPPrefix.contains(address:)` extension, whose body
performs associated-type/conformance witness lookups and indirect calls.
The family-erased CIDR API's shared implementation instead contains compact
family-specific comparison and mask arithmetic. The controls reproduce a
microsecond-scale scan without changing dependencies, instrumentation, or the
underlying linear source-rule algorithm.

The adaptation since 0.2.0 changed the network branch from the family-erased
containment API to concrete generic hierarchical containment, with host
projection to preserve admission semantics. The projection remains necessary
for peers carrying broader prefix context; dropping it for speed is not a
correct fix. The historical gap is consistent with the current call-shape
cost, but this is not a reconstruction of the old release's raw measurements.

A separate production change could retain host-bit admission semantics while
using the efficient call shape. It must preserve address and range rules,
mixed families, deny precedence, defaults, and first-source-rule diagnostics,
and should be checked on supported native platforms. These controls only
validate network-only fixtures, not a general replacement evaluator.
No trie, new index, or production API change was introduced here.

## Environment And Evidence

Apple M1 Max, native arm64, ten logical processors, 64 GiB RAM; macOS 26.7.1
(25G241), Darwin 25.6.0; Apple Swift 6.3.3 and Xcode 26.6 (17F113).
Dependencies remain Benchmark 1.38.1, malloc-interposer 1.6.1, swift-cidr 0.8.0,
and Swift Crypto 5.0.3. AC power remained attached. Background workload was
**not controlled**; each capture records load averages and power before and
after execution. No other benchmark or build was deliberately run in parallel
with a measured benchmark. Do not generalize these tails to an isolated host.

Each capture directory retains its native baseline and raw percentile export,
runner tables, stdout/stderr, inventory, dependency lock, summary, completeness
checks, and metadata with exact commands, metric overrides, source hashes,
environment, timestamps, and exit status. Native baselines are specific to
Benchmark 1.38.1's internal format. CSV timestamps are export times.

The first rerun uses [sampling-source.patch](sampling-source.patch). The
instrumentation and initial network-only diagnostic comparisons use
[diagnostics-source.patch](diagnostics-source.patch). The additional
family-erased controls use [erased-host-source.patch](erased-host-source.patch).
Apply the appropriate patch to the base commit to reproduce its benchmark
source. These are not captures of an unchanged main checkout. The exact environment and command
for each capture are in its `metadata.json`. Use a fresh unique baseline name.

Checksums cover this follow-up separately. The original capture, historical
benchmark README, and historical chart remain byte-for-byte unchanged.

## Verification And Review

[verification.json](verification.json) records the completed checks: all nine
captures, 46 case observations, and 316 metric records; byte-exact native
archives; percentile normalization; and reproduction of all captured source
hashes by applying each archived source patch to the base commit in scratch
directories. The relabeled original CSV is numerically identical to its source.

`swift test --disable-automatic-resolution` passed 57 tests in seven suites.
The release benchmark target built successfully. Default and reference
discovery each retain the same 174 cases; diagnostics add exactly eight cases
for a total of 182. No production files, dependency locks, historical results,
Git index entries, commits, tags, or remote refs were changed.

The work remains uncommitted for review. To roll back the benchmark edits,
restore only `Benchmarks/CIDRAdmissionBenchmarkTarget/CIDRAdmissionBenchmarkTarget.swift`
from main and remove the newly added diagnostic source, sampling notes,
results index, and this follow-up directory. Keep the original full capture;
do not remove `Benchmarks/Results/` wholesale.
