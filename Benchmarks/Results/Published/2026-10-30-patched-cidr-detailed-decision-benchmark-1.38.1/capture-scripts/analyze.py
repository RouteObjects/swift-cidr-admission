import csv
import json
from pathlib import Path
from statistics import mean

from rerun import RUNS, SEQUENCE, SIZES, WORK

P50 = 'wall_p50_sample_mean_ns_per_operation'
P99 = 'wall_p99_sample_mean_ns_per_operation'
THROUGHPUT = 'throughput_p50_operations_per_second'

def read(name):
    with (RUNS / name / 'summary.csv').open() as source:
        return {r['benchmark']: r for r in csv.DictReader(source)}

def write_csv(path, rows):
    with path.open('w', newline='') as output:
        writer = csv.DictWriter(output, fieldnames=list(rows[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)

def analyze():
    data = {name: read(name) for name, *_ in SEQUENCE}
    comparisons = []
    for family in ['v4', 'v6']:
        for size in SIZES:
            case = f'policy.decision.{family}.combined.denyMissAllowLast.{size}'
            for profile in ['full', 'timing']:
                row = {'family': family, 'rules_per_list': size, 'metric_profile': profile,
                       'batch_size': data[f'patched-{profile}-1'][case]['batch_size'],
                       'wall_sample_unit': data[f'patched-{profile}-1'][case]['wall_sample_unit']}
                for variant in ['baseline', 'patched']:
                    samples = [data[f'{variant}-{profile}-{n}'][case] for n in [1, 2]]
                    for n, sample in enumerate(samples, 1):
                        row[f'{variant}_run{n}_p50_ns_per_operation'] = sample[P50]
                        row[f'{variant}_run{n}_p99_ns_per_operation'] = sample[P99]
                    row[f'{variant}_mean_of_two_run_p50_ns_per_operation'] = mean(float(s[P50]) for s in samples)
                    row[f'{variant}_min_metric_samples'] = min(int(s['minimum_metric_samples']) for s in samples)
                    row[f'{variant}_mean_of_two_throughput_p50_ops_per_second'] = mean(float(s[THROUGHPUT]) for s in samples)
                row['speedup_ratio_of_mean_run_medians'] = row['baseline_mean_of_two_run_p50_ns_per_operation'] / row['patched_mean_of_two_run_p50_ns_per_operation']
                comparisons.append(row)
    write_csv(WORK / 'comparison.csv', comparisons)
    diagnostics = []
    for family in ['v4', 'v6']:
        for method in ['projectPerRule', 'projectOnce', 'addressBits', 'erasedHost']:
            name = f'diagnostic.decision.{family}.{method}.10000'
            row = {'family': family, 'method': method, 'rules_per_list': 10000, 'batch_size': 1}
            for profile in ['full', 'timing']:
                source = data[f'patched-diagnostic-{profile}'][name]
                row[f'{profile}_p50_ns_per_operation'] = source[P50]
                row[f'{profile}_p99_ns_per_operation'] = source[P99]
                row[f'{profile}_minimum_metric_samples'] = source['minimum_metric_samples']
                row[f'{profile}_throughput_p50_operations_per_second'] = source[THROUGHPUT]
            diagnostics.append(row)
    write_csv(WORK / 'diagnostics.csv', diagnostics)
    coverage = {name: json.loads((RUNS / name / 'coverage.json').read_text()) for name, *_ in SEQUENCE}
    assert sum(c['cases'] for c in coverage.values()) == 144
    assert sum(c['metric_records'] for c in coverage.values()) == 792
    assert all(not c['cases_below_30_samples'] for c in coverage.values())
    counter_columns = [k for k in next(iter(data['patched-full-1'].values())) if k.endswith('_p50_per_operation')]
    nonzero = [{'run': name, 'case': case, 'counter': col, 'value': r[col]}
               for name, _, profile, _ in SEQUENCE if profile == 'full'
               for case, r in data[name].items() for col in counter_columns if float(r[col]) != 0]
    validation = {'captures': len(coverage), 'production_cases_per_capture': 16,
                  'diagnostic_cases_per_capture': 8, 'case_observations': 144, 'metric_records': 792,
                  'minimum_metric_samples': min(c['minimum_samples'] for c in coverage.values()),
                  'nonzero_allocation_arc_p50_values': nonzero, 'coverage': coverage}
    (WORK / 'validation.json').write_text(json.dumps(validation, indent=2) + '\n')
    for row in comparisons:
        if row['rules_per_list'] == 10000:
            print(json.dumps(row))
    for row in diagnostics:
        print(json.dumps(row))
    print('Minimum samples:', validation['minimum_metric_samples'], 'nonzero counter medians:', len(nonzero))

if __name__ == '__main__':
    analyze()
