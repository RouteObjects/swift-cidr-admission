import csv
import json
from statistics import mean
from rerun import RUNS, SEQUENCE, WORK

P50 = 'wall_p50_sample_mean_ns_per_operation'
P99 = 'wall_p99_sample_mean_ns_per_operation'
THROUGHPUT = 'throughput_p50_operations_per_second'

def analyze():
    data = {}
    for name, *_ in SEQUENCE:
        with (RUNS / name / 'summary.csv').open() as f:
            data[name] = {r['benchmark']: r for r in csv.DictReader(f)}
    rows = []
    for case in sorted(data['baseline-full-1']):
        for profile in ['full', 'timing']:
            row = {'benchmark': case, 'metric_profile': profile,
                   'batch_size': data['baseline-full-1'][case]['batch_size'],
                   'wall_sample_unit': data['baseline-full-1'][case]['wall_sample_unit']}
            for variant in ['baseline', 'eager', 'deferred', 'phased']:
                samples = [data[f'{variant}-{profile}-{n}'][case] for n in [1, 2]]
                for n, sample in enumerate(samples, 1):
                    row[f'{variant}_run{n}_p50_ns_per_operation'] = sample[P50]
                    row[f'{variant}_run{n}_p99_ns_per_operation'] = sample[P99]
                row[f'{variant}_mean_run_p50_ns_per_operation'] = mean(float(s[P50]) for s in samples)
                row[f'{variant}_minimum_metric_samples'] = min(int(s['minimum_metric_samples']) for s in samples)
                row[f'{variant}_mean_throughput_p50_ops_per_second'] = mean(float(s[THROUGHPUT]) for s in samples)
            baseline = row['baseline_mean_run_p50_ns_per_operation']
            candidate = row['phased_mean_run_p50_ns_per_operation']
            eager = row['eager_mean_run_p50_ns_per_operation']
            row['speedup_ratio_of_mean_run_medians'] = baseline / candidate
            row['candidate_minus_baseline_ns_per_operation'] = candidate - baseline
            row['phased_over_eager_time_ratio'] = candidate / eager
            row['phased_over_deferred_time_ratio'] = candidate / row['deferred_mean_run_p50_ns_per_operation']
            rows.append(row)
    with (WORK / 'comparison.csv').open('w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)
    coverage = {name: json.loads((RUNS / name / 'coverage.json').read_text()) for name, *_ in SEQUENCE}
    assert sum(c['cases'] for c in coverage.values()) == 512
    assert sum(c['metric_records'] for c in coverage.values()) == 2816
    assert all(not c['cases_below_30_samples'] for c in coverage.values())
    counters = [k for k in next(iter(data['phased-full-1'].values())) if k.endswith('_p50_per_operation')]
    nonzero = [{'run': name, 'case': case, 'counter': column, 'value': r[column]}
               for name, _, profile, _ in SEQUENCE if profile == 'full'
               for case, r in data[name].items() for column in counters if float(r[column]) != 0]
    validation = {'captures': 16, 'cases_per_capture': 32, 'case_observations': 512, 'metric_records': 2816,
                  'minimum_metric_samples': min(c['minimum_samples'] for c in coverage.values()),
                  'nonzero_allocation_arc_p50_values': nonzero, 'coverage': coverage}
    (WORK / 'validation.json').write_text(json.dumps(validation, indent=2) + '\n')
    for row in rows:
        if row['metric_profile'] == 'full' and (row['benchmark'].endswith('.10000') or row['benchmark'].startswith('projection.')):
            print(row['benchmark'], 'baseline', round(row['baseline_mean_run_p50_ns_per_operation'], 3),
                  'eager', round(row['eager_mean_run_p50_ns_per_operation'], 3),
                  'deferred', round(row['deferred_mean_run_p50_ns_per_operation'], 3),
                  'phased', round(row['phased_mean_run_p50_ns_per_operation'], 3),
                  'speedup', round(row['speedup_ratio_of_mean_run_medians'], 3))
    print('Minimum samples:', validation['minimum_metric_samples'], 'Nonzero counter medians:', len(nonzero))

if __name__ == '__main__':
    analyze()
