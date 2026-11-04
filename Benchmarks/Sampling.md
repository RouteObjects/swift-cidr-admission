# Sampling And Percentiles

The default `quick` profile retains the existing two-second windows and batch
sizes. For reference captures, set `CIDR_ADMISSION_BENCHMARK_SAMPLING=reference`:

```bash
CIDR_ADMISSION_BENCHMARK_SAMPLING=reference ./scripts/benchmarks.sh run \
  --filter '^policy\.decision\..*\.combined\.denyMissAllowLast\.(250|500|1000)$' \
  --no-progress --time-units nanoseconds
```

The reference profile measures detailed decisions at 250 or more rules and
construction at 100 or more rules as individual operations. Decisions at
10,000 rules and construction at 1,000 or more rules were already unbatched.
When changing a kilo batch to a single-operation sample, it preserves the
number of logical warmup operations. Range-file loads with 10,000 rules use a
90-second window; all other windows remain two seconds. The runner can stop
earlier at its 10,000-sample cap. Inspect actual sample counts rather than
assuming a duration guarantees a particular count or percentile quality.

## What A Percentile Measures

Each timed closure invocation is one sample. With a batch size of 1,000,
dividing its duration by 1,000 gives an amortized operation cost. The p99 of
those values is a **p99 of batch means**, not a p99 of individual-call latency.
Single-operation samples permit individual-operation latency percentiles,
still including loop, timer, instrumentation, and system overhead.

Follow-up CSVs label these values `wall_p50_sample_mean_ns_per_operation` and
`wall_p99_sample_mean_ns_per_operation`, accompanied by `wall_sample_unit`
(`single_operation` or `batch_mean`) and `batch_size`. This definition also
applies to the `wall_p50_ns_per_operation` and `wall_p99_ns_per_operation`
columns in the immutable 2026-10-30 main snapshot: their original labels are
too broad for batched cases. That capture is preserved as evidence, not edited
in place. Its numerical values are unchanged.

Allocation and ARC medians are also divided by the batch size; for batched
cases, they describe median batch-averaged counts. A zero median is not proof
that every operation allocated nothing, and a retain/release delta alone is
not a leak diagnosis.

Throughput is different: Benchmark reverses percentile ranks for metrics that
prefer larger values. Its throughput p99 denotes the low-throughput tail.
Follow-up summaries therefore report only the ordinary, symmetric throughput
median and use ordinary percentile ranks for wall-clock time.

## Instrumentation Comparisons

The normal suite includes wall time, throughput, allocation, and ARC metrics.
A timing-only comparison uses the same source, fixture, sampling profile, and
build, with just these CLI metric overrides:

```bash
CIDR_ADMISSION_BENCHMARK_SAMPLING=reference ./scripts/benchmarks.sh run \
  --filter '^policy\.decision\..*\.combined\.denyMissAllowLast\.10000$' \
  --metric wallClock --metric throughput --no-progress --time-units nanoseconds
```

Keep differently instrumented runs separate. Do not combine their rows or
compare individual-operation p99 to batched p99 as though they were the same
latency distribution. Save the source revision, any uncommitted source patch,
profile, exact filters, metrics, dependencies, environment, and sample counts
with each capture. A repeatable current-source comparison is not a controlled
historical regression test.

For network-only diagnostic controls, also set
`CIDR_ADMISSION_BENCHMARK_DIAGNOSTICS=1` and filter
`^diagnostic\.decision\.`. These opt-in cases use single-operation samples,
30 warmups, and a ten-second window (subject to the 10,000-sample cap).
`production` calls the current `decision(for:)`, which normalizes the peer once
at entry as of 0.3.3. Historical captures retain the old `projectPerRule` name
because that describes the implementation measured then. `projectOnce` is a
benchmark-local network-only scan that also projects once; `addressBits`
compares address bits against the network mask directly; `erasedHost` projects
once and calls
`AnyIPNetwork.contains(address:)` instead of the concrete generic extension.
The alternatives preserve deny precedence and the first matching source-rule
reason for these network-only fixtures. Before
timing, they check allow, deny, miss, and zero-prefix-context peers against
production. They are not general replacements for the public evaluator or
measurements of the historical release.

The controls have different helper and inlining boundaries from production.
A timing difference is not, by itself, a measurement of projection overhead.
Projection here means retaining the peer's address bits with host-prefix
context (`/32` or `/128`); it is not another network-to-host byte-order conversion.

## Short And Mixed-Rule Controls

Set `CIDR_ADMISSION_BENCHMARK_PEER_PROJECTION=1` and filter
`^projection\.` for empty policies, early network/address/range matches, and
mixed-rule scans. These cases check complete decisions against a source-rule
reference before timing. They consume the complete decision, while the ordinary
network-only decision cases consume `isAllowed`; compare like cases, not the
absolute costs of these two groups.

```bash
CIDR_ADMISSION_BENCHMARK_PEER_PROJECTION=1 ./scripts/benchmarks.sh run \
  --filter '^projection\.' --no-progress --time-units nanoseconds
```

The default suite has 174 cases. Diagnostics add eight, projection controls
add 16, and enabling both yields 198. The sampling profile changes sample
configuration, not case discovery. Use the same opt-in flags for `list` and
`run`. See [Benchmark Captures](Results/README.md) for dated evidence and the
outcome of the original investigation.
