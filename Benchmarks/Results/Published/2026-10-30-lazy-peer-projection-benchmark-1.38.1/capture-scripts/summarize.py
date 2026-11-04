import argparse
import csv
import json
from collections import Counter
from decimal import Decimal
from pathlib import Path


LABELS = {
    "throughput": "Throughput(#/s)",
    "wallClock": "Time(wallclock)",
    "mallocCountSmall": "Malloc(small)",
    "mallocCountLarge": "Malloc(large)",
    "mallocCountTotal": "Malloc(total)",
    "objectAllocCount": "Objectallocs",
    "retainCount": "Retains",
    "releaseCount": "Releases",
    "retainReleaseDelta": "(Alloc+Retain)-Release\u0394",
}
REVERSE = {label: metric for metric, label in LABELS.items()}
PERCENTILES = {0, 25, 50, 75, 90, 99, 100}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def number(value):
    return format(value.normalize(), "f")


parser = argparse.ArgumentParser()
parser.add_argument("baseline", type=Path)
parser.add_argument("influx", type=Path)
parser.add_argument("inventory", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()

baseline = json.loads(args.baseline.read_text())
expected = args.inventory.read_text().splitlines()
require(expected and len(set(expected)) == len(expected), "Unexpected inventory")
encoded = baseline["results"]
require(isinstance(encoded, list) and len(encoded) % 2 == 0, "Unexpected native baseline schema")
cases = {}
for identifier, results in zip(encoded[::2], encoded[1::2]):
    require(identifier["target"] == "CIDRAdmissionBenchmarkTarget", "Unexpected target")
    name = identifier["name"]
    require(name not in cases, "Duplicate native case")
    metrics = {}
    for result in results:
        require(len(result["metric"]) == 1, "Unexpected metric encoding")
        metric = next(iter(result["metric"]))
        require(metric in LABELS and metric not in metrics, "Unexpected or duplicate metric")
        require(result["scalingFactor"] in (1, 1000), "Unexpected batch size")
        require(result["statistics"]["histogram"]["_totalCount"] > 0, "Metric has no samples")
        metrics[metric] = result
    require("wallClock" in metrics, "Missing wall-clock samples")
    require(len({r["scalingFactor"] for r in metrics.values()}) == 1, "Inconsistent batch sizes")
    cases[name] = metrics
require(set(cases) == set(expected), "Full suite did not produce every discovered case")

exported = {}
with args.influx.open(newline="") as source:
    for line in source:
        if line.startswith("measurement,hostName,"):
            header = next(csv.reader([line]))
            break
    else:
        raise ValueError("Missing Influx CSV header")
    for row in csv.DictReader(source, fieldnames=header):
        if not row["measurement"]:
            continue
        require(row["measurement"] == "CIDRAdmissionBenchmarkTarget", "Unexpected export target")
        name, metric = row["test"], REVERSE[row["metric"]]
        require(name in cases and metric in cases[name], "Export/native mismatch")
        percentile = int(Decimal(row["percentile"]))
        require(percentile in PERCENTILES, "Unexpected percentile")
        values = exported.setdefault((name, metric), {})
        require(percentile not in values, "Duplicate percentile")
        values[percentile] = Decimal(row["value"])
for name, metrics in cases.items():
    for metric in metrics:
        require(set(exported.get((name, metric), {})) == PERCENTILES, "Missing exported percentiles")

fields = ["benchmark", "batch_size", "wall_sample_unit", "wall_samples", "throughput_samples", "minimum_metric_samples", "metrics_recorded", "low_sample_count", "wall_p50_sample_mean_ns_per_operation", "wall_p99_sample_mean_ns_per_operation", "throughput_p50_operations_per_second"]
count_fields = {
    "mallocCountSmall": "malloc_small_p50_per_operation",
    "mallocCountLarge": "malloc_large_p50_per_operation",
    "mallocCountTotal": "malloc_total_p50_per_operation",
    "objectAllocCount": "object_allocations_p50_per_operation",
    "retainCount": "retains_p50_per_operation",
    "releaseCount": "releases_p50_per_operation",
    "retainReleaseDelta": "retain_release_delta_p50_per_operation",
}
fields += list(count_fields.values())
summary, missing = [], {}
for name in sorted(cases):
    metrics = cases[name]
    batch = metrics["wallClock"]["scalingFactor"]
    counts = {key: result["statistics"]["histogram"]["_totalCount"] for key, result in metrics.items()}
    row = dict(benchmark=name, batch_size=batch, wall_samples=counts["wallClock"], throughput_samples=counts.get("throughput", ""), minimum_metric_samples=min(counts.values()), metrics_recorded=len(metrics), low_sample_count=min(counts.values()) < 30)
    row["wall_sample_unit"] = "single_operation" if batch == 1 else "batch_mean"
    row["wall_p50_sample_mean_ns_per_operation"] = number(exported[(name, "wallClock")][50] / batch)
    row["wall_p99_sample_mean_ns_per_operation"] = number(exported[(name, "wallClock")][99] / batch)
    if "throughput" in metrics:
        row["throughput_p50_operations_per_second"] = number(exported[(name, "throughput")][50] * batch)
    for metric, column in count_fields.items():
        if metric in metrics:
            row[column] = number(exported[(name, metric)][50] / batch)
    absent = sorted(set(LABELS) - set(metrics))
    if absent:
        missing[name] = absent
    summary.append(row)

args.output.mkdir(parents=True, exist_ok=False)
with (args.output / "summary.csv").open("w", newline="") as output:
    writer = csv.DictWriter(output, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(summary)
coverage = {
    "cases": len(cases),
    "metrics_expected_per_case": len(next(iter(cases.values()))),
    "metric_records": sum(len(m) for m in cases.values()),
    "categories": dict(sorted(Counter(n.split(".")[1] for n in cases).items())),
    "unrecorded_metrics": missing,
    "minimum_samples": min(r["minimum_metric_samples"] for r in summary),
    "cases_below_30_samples": [r["benchmark"] for r in summary if r["low_sample_count"]],
    "baseline_name": baseline["baselineName"],
}
(args.output / "coverage.json").write_text(json.dumps(coverage, indent=2, sort_keys=True) + "\n")
print(json.dumps(coverage, indent=2))
