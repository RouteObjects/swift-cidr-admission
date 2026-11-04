# Detailed Decisions: Lazy Peer Projection

> Sanitized historical copy; see [publication notes](../README.md). Embedded hashes and validation claims refer to the original capture.

Captured on October 30, 2026 local time (October 31 UTC), separately from all
earlier snapshots. This follows the
[eager peer-projection experiment](../2026-10-30-peer-projection-benchmark-1.38.1/README.md).
All variants use the same pending three-annotation `swift-cidr` patch, not
unmodified published `swift-cidr` 0.8.0. Real repository dependencies are unchanged.

## Conclusion

Lazy projection recovers most of the short-path penalty, but does **not** retain
all of eager projection's long-scan performance. The explicit local cache flag
is a better compromise than the initial Swift `lazy` property experiment;
neither is a no-regression replacement for eager projection on this Mac.
The explicit-flag candidate is left uncommitted for review.

In artifact names, `baseline` is the original per-rule evaluator, `eager` is
the earlier project-at-entry candidate, and `deferred` is the final lazy
cache-flag candidate. `lazy-full-1` is a separate, unsuccessful lazy-property
pilot, not a repeat of the final candidate.

## Long Scans

Each value is the arithmetic mean of two separately captured run medians,
not a pooled median. These are single-operation samples, in **microseconds**.
There are 10,000 network rules in **each** list: deny misses and the final
allow rule matches, so a decision evaluates up to 20,000 rules.

| Family | Metrics | Original | Eager | Deferred | Original / deferred |
| --- | --- | ---: | ---: | ---: | ---: |
| IPv4 | Full | 96.863 | 29.967 | 39.375 | 2.46x |
| IPv4 | Timing only | 97.983 | 30.343 | 40.575 | 2.41x |
| IPv6 | Full | 103.743 | 40.335 | 47.551 | 2.18x |
| IPv6 | Timing only | 103.199 | 41.023 | 46.159 | 2.24x |

The final candidate is 12.5-33.7% slower than eager projection in these four
comparisons, while retaining roughly 85-92% of its absolute time savings over
the original evaluator. Full-metrics throughput medians, averaged across the
two runs, are 25,423 decisions/s for IPv4 and 21,055 for IPv6. Throughput is
exported independently, not calculated by taking the reciprocal of averaged
wall-time medians.

Mixed lists alternate address, network, and range rules, with 1,000 rules per
list. Full-metrics times in microseconds:

| Family | Scenario | Original | Eager | Deferred |
| --- | --- | ---: | ---: | ---: |
| IPv4 | Deny miss, allow last | 7.127 | 4.813 | 5.731 |
| IPv4 | Both miss, default allow | 7.023 | 4.751 | 5.835 |
| IPv6 | Deny miss, allow last | 7.127 | 5.065 | 5.981 |
| IPv6 | Both miss, default allow | 7.147 | 5.063 | 5.959 |

## Short Paths

Full-metrics values below are **nanoseconds per operation**, averaged across
two run medians of 1,000-operation batch means. They are not individual-call
latency percentiles. Cells show **original / eager / deferred**.

| Scenario | IPv4 | IPv6 |
| --- | ---: | ---: |
| Empty, default deny | 3.146 / 5.545 / 3.584 | 3.146 / 5.583 / 3.668 |
| Empty, default allow | 3.146 / 5.543 / 3.605 | 3.126 / 5.523 / 3.584 |
| First address rule denies | 5.293 / 7.459 / 6.043 | 5.211 / 7.773 / 6.023 |
| First range rule denies | 5.773 / 8.063 / 6.397 | 5.689 / 8.171 / 6.397 |
| First network rule denies | 7.419 / 6.481 / 6.875 | 7.771 / 7.231 / 6.835 |
| First network rule allows | 7.461 / 6.605 / 7.251 | 7.961 / 7.211 / 7.293 |

Empty policies remain about 0.4-0.5 ns above the original, and immediate
address/range matches about 0.6-0.8 ns above it. Removing host construction
does not make the entire changed decision body cost-free.

## Why Two Lazy Implementations

The first candidate used a private Swift `lazy` host property. Its one
full-metrics pilot measured 53.471 us for the longest IPv4 scan and 67.263 us
for IPv6. Empty policies were about 4.5 ns. Generated code retained an
out-of-line lazy getter called from the network loop, including cached uses.
This pilot was preserved rather than replaced with the better result.

The final candidate stores the peer and an `isProjected` flag in a private,
per-decision value. Address/range rules and opposite-family networks do not
trigger projection. The first same-family network replaces that local peer
with a host-only view, then reuses it across both scans. There are no added
inline annotations, public wrappers, policy-level caches, or lookup indexes.

The [assembly excerpts](evidence/deferred-decision-excerpt.txt) show no lazy
getter calls and host construction guarded by cache state. The cache flag
and changed loop control flow remain. This is consistent with the measured
tradeoff, but these experiments do not isolate a cost for any single branch
or instruction. Eliminating the steady-state cache check would require a
further experiment; it was not implemented here.

## Admission Semantics

Source arrays and their order, original rules returned in decision reasons,
deny precedence, defaults, public standalone rule containment, equality/hash
inputs, and indexed `allows(_:)` are unchanged. Peer prefix context is ignored
for membership without changing source address-rule context. Address families
remain separate, including IPv4-mapped IPv6 addresses. Cache state belongs to
one synchronous decision and is never stored on the policy.

All **63 tests in eight suites passed in both Debug and Release** on macOS
Swift 6.3.3 for both lazy candidates. The existing differential tests include
31,740 decisions covering every legal peer prefix length for selected boundary
peers and policy combinations, plus 8,192 seeded mixed-policy decisions.
They compare complete decisions against the unchanged public-rule scan and
check indexed `allows` agreement and original source-prefix preservation.
Two additional tests cover delayed first projection, reuse from deny into
allow, and 1,000 decisions from concurrent tasks sharing an immutable policy.

**Linux validation is outstanding.** Two SSH attempts reached `linux-validation-host` but
failed during SSH-agent signing, before source upload or tests. The earlier
eager-candidate Linux results do not qualify these new implementations. See
the [recorded limitation](evidence/linux-validation.json).

## Capture Method

- Admission base: `5d01867915f257d9d2086a510efe1c20f697b69a`.
- CIDR base: `cdc2e592beb9095875bc42fc4c269396b20d99e3`, with identical pending `@inlinable` changes to `IPPrefix.contains(address:)`, `CIDR.mask`, and `FixedWidthInteger.networkMask(for:)`.
- Apple M1 Max, 10 logical CPUs, 64 GiB; macOS 26.7.1 (25G241); Apple Swift 6.3.3; Xcode 26.6.
- Benchmark 1.38.1, malloc-interposer 1.6.1, Crypto 5.0.3; remaining pins held fixed.
- 32 cases per capture: the existing 16 network decisions at 1, 10, 50, 100, 250, 500, 1,000, and 10,000 rules per list, plus 16 short/mixed controls.

There are 12 main-comparison captures: three variants, two metric profiles,
and two runs per profile. The additional lazy-property pilot brings the total
to **13 captures, 416 case observations, and 2,400 metric records**. Minimum
sample count is 1,703; no case has fewer than 30 samples. All full-metrics
allocation and ARC counter medians are zero. This does not prove every sample
allocated nothing or establish a memory-leak guarantee.

All measurements are new. Original/eager release binaries were reused from
the prior isolated source copies after checking their source inventories,
dependency graphs, compiler identity, and executable hashes. The lazy variants
were built in new isolated copies, not worktrees. Benchmark compilation inputs
differ only in `IPAdmissionPolicy.swift`; the two added tests are not benchmark
target inputs. Temporary SwiftPM edits select patched CIDR; only that edited
dependency's pin is absent from temporary effective lockfiles.

The same official `BenchmarkTool` executable drives every capture directly,
without invoking a SwiftPM build during measurement. This is the runner used
by the package plugin; exact commands and binary/interposer hashes are saved.
Only new baseline-storage paths were used. Run order is original full,
eager full, lazy-property pilot, then final-candidate full/timing, eager timing,
original timing/timing, eager timing, final-candidate timing/full, eager full,
and original full. Candidate builds occurred between the pilot and final
candidate measurements, not during timed runs.

Full metrics means the nine configured metrics: throughput, wall time, three
malloc counters, object allocations, retains, releases, and retain/release
delta. Timing-only requests wall time and throughput from the same linked
executable, with allocation/ARC hooks unrequested. It is not an interposer-free
build. Allocation stacks are disabled. The reference sampling profile is
unchanged; default discovery is still 174 cases, or 190 with projection
controls enabled. Original decision cases consume `isAllowed`; projection
controls consume the complete decision. Compare like-for-like cases.

No agent-initiated compilation overlapped timing. Other compiler processes
were checked before and after captures, not continuously. Background work was
not controlled; load and AC-power state are retained per run. Two runs are not
a statistical significance study, and these Mac timings are not Linux/iOS or
universal performance guarantees.

## Evidence And Reproduction

- [Comparison CSV](comparison.csv): both individual run p50/p99 values, correctly labeled batch units, throughput, and ratios.
- [Validation](validation.json): case/metric/sample coverage and counter checks.
- [Preservation](preservation.json): original file hashes, refs, staging, and dependency preservation.
- [Example run metadata](runs/deferred-full-1/metadata.json): exact commands, environment, timing, and native-baseline hash.
- [Generated-code summary](evidence/codegen.json): static call sites, not dynamic call counts.
- [Admission patch](evidence/admission-source.patch.gz) and [CIDR patch](evidence/cidr-source.patch.gz): source changes relative to the recorded base commits.

Each run has an untouched compressed native baseline, raw text/Influx exports,
stdout/stderr, normalized summary, and coverage checks. The evidence directory
contains all four policy source snapshots, dependency locks/graphs, builds,
test logs, assembly, and hashes. Capture scripts record the exact procedure
and temporary paths used; they are provenance, not a location-independent CLI.
To reconstruct, apply the source patches to isolated copies of the stated base
commits, select the desired policy snapshot, edit the temporary CIDR dependency
to the patched source, and build Release with the recorded toolchain and pins.
After a SwiftPM dependency edit, do not use `--disable-automatic-resolution`,
which can restore the remote checkout instead of the patched source.

Verify the bundle with `shasum -a 256 -c SHA256SUMS` from this directory.
No earlier snapshot, chart, repository manifest, or lockfile was changed.
Nothing was staged, committed, pushed, merged, or tagged.
