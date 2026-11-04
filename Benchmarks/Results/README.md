# Benchmark Captures

## Current Outcome

The typed containment performance fix shipped in `swift-cidr` 0.8.1.
`swift-cidr-admission` 0.3.3 normalizes the peer once at `decision(for:)` entry.
The lazy and two-phase scans below were investigated alternatives, not pending
production work. The indexed `allows(_:)` path is a separate measurement.

These are historical experiments, not a fresh benchmark of released 0.3.3.
Their source revisions, local patches, dependencies, and sampling configurations
are recorded with each capture. Statements about work being uncommitted or
validation pending describe the capture date, not the current project status.

## Publication Copies

The links below point to [sanitized publication copies](Published/README.md).
Original captures remain untouched locally and are explicitly ignored by Git.
Publication manifests distinguish original hashes from derivative hashes;
measurement values and historical case names are preserved.

- [Historical results](../README.md#results): the original 0.1 chart and dated 0.2.0 tables.
- [2026-10-30 full suite](Published/2026-10-30-main-5d01867-benchmark-1.38.1/README.md): capture of all 174 cases on main at `5d01867`.
- [2026-10-30 sampling follow-up](Published/2026-10-30-sampling-followup-benchmark-1.38.1/README.md): separately captured reruns, corrected percentile labels, and detailed-decision timing investigation.
- [2026-10-30 patched CIDR comparison](Published/2026-10-30-patched-cidr-detailed-decision-benchmark-1.38.1/README.md): repeated full-metrics and timing-only detailed decisions, same-session unpatched controls, and remaining-cost diagnostics.
- [2026-10-30 peer-projection candidate](Published/2026-10-30-peer-projection-benchmark-1.38.1/README.md): project-once evaluation, mixed/short-path controls, macOS benchmarks, and native Linux semantic validation.
- [2026-10-30 lazy peer-projection comparison](Published/2026-10-30-lazy-peer-projection-benchmark-1.38.1/README.md): lazy-property pilot and explicit local cache, repeated original/eager controls, full metrics and timing only, and the remaining short/long-path tradeoff.
- [2026-10-30 two-phase peer-projection comparison](Published/2026-10-30-two-phase-peer-projection-benchmark-1.38.1/README.md): projection at the first same-family network, a cache-check-free second phase, and repeated original/eager/lazy-cache controls.

Read [Sampling And Percentiles](../Sampling.md) before comparing captures. A
percentile of amortized batch durations is not an individual-call latency
percentile. The follow-up includes a relabeled copy of the original summary
without changing its numerical values or editing the original capture.
