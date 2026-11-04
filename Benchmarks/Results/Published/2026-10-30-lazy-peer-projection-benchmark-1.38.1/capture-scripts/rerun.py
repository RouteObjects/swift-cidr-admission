import datetime
import gzip
import hashlib
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import time

from prepare import WORK, OUT, TARGET, UNSET, environment

OLD = WORK.parent / 'admission-peer-projection.3SFHIj'
ROOTS = {'baseline': OLD / 'baseline', 'eager': OLD / 'patched', 'lazy': WORK / 'lazy', 'deferred': WORK / 'deferred'}
DRIVER = OLD / 'patched/swift-cidr-admission/Benchmarks/.build/arm64-apple-macosx/release/BenchmarkTool'

def check_workspace(variant):
    root = ROOTS[variant]
    expected = json.loads((OUT / (variant + '-sources.json')).read_text())
    for rel, checksum in expected.items():
        path = root / rel
        if rel in ['swift-cidr-admission/Benchmarks/Package.resolved', 'swift-cidr-admission/Package.resolved'] and sha(path) != checksum:
            original = json.loads((OUT / ('original-' + ('benchmark' if '/Benchmarks/' in rel else 'root') + '-dependencies.json')).read_text())
            assert json.loads(path.read_text())['pins'] == [p for p in original['pins'] if p['identity'] != 'swift-cidr']
        else:
            assert sha(path) == checksum, rel
    state = json.loads((root / 'swift-cidr-admission/Benchmarks/.build/workspace-state.json').read_text())
    edited = next(d for d in state['object']['dependencies'] if d['packageRef']['identity'] == 'swift-cidr')
    assert edited['state'] == {'name': 'edited', 'path': str(root / 'swift-cidr')}
    assert edited['basedOn']['state']['checkoutState']['revision'] == 'cdc2e592beb9095875bc42fc4c269396b20d99e3'
    binaries = json.loads((OUT / 'binaries.json').read_text())
    for path, checksum in binaries.items():
        assert sha(Path(path)) == checksum, path

RUNS = WORK / 'runs'
SIZES = [1, 10, 50, 100, 250, 500, 1000, 10000]
SEQUENCE = [
    ('baseline-full-1', 'baseline', 'full', False),
    ('eager-full-1', 'eager', 'full', False),
    ('lazy-full-1', 'lazy', 'full', False),
    ('deferred-full-1', 'deferred', 'full', False),
    ('deferred-timing-1', 'deferred', 'timing', False),
    ('eager-timing-1', 'eager', 'timing', False),
    ('baseline-timing-1', 'baseline', 'timing', False),
    ('baseline-timing-2', 'baseline', 'timing', False),
    ('eager-timing-2', 'eager', 'timing', False),
    ('deferred-timing-2', 'deferred', 'timing', False),
    ('deferred-full-2', 'deferred', 'full', False),
    ('eager-full-2', 'eager', 'full', False),
    ('baseline-full-2', 'baseline', 'full', False),
]

def timestamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def output(command):
    return subprocess.check_output(command, text=True).strip()

def compiler_processes():
    names = subprocess.check_output(['ps', '-axo', 'comm='], text=True).splitlines()
    return [name for name in names if Path(name.strip()).name in
            ['swift-build', 'swift-test', 'swift-frontend', 'clang', 'clang++', 'xcodebuild']]

def wait_for_compilers():
    quiet_since = None
    deadline = time.monotonic() + 900
    announced = False
    while True:
        now = time.monotonic()
        busy = compiler_processes()
        if busy:
            quiet_since = None
            if not announced:
                print('Waiting for other compilation to finish before measurement', flush=True)
                announced = True
        else:
            quiet_since = quiet_since or now
            if now - quiet_since >= 10:
                return
        if now >= deadline:
            raise RuntimeError('Compiler activity did not settle within 15 minutes; no new measurement started')
        time.sleep(5)

def compress(source, destination):
    with source.open('rb') as raw, destination.open('wb') as target:
        with gzip.GzipFile(filename='', mode='wb', fileobj=target, mtime=0) as encoded:
            shutil.copyfileobj(raw, encoded)

def execute(command, cwd, env, stem):
    with stem.with_suffix('.stdout.log').open('wb') as stdout, stem.with_suffix('.stderr.log').open('wb') as stderr:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=stdout, stderr=stderr)
    if result.returncode:
        print(stem.with_suffix('.stderr.log').read_text()[-5000:], flush=True)
        raise RuntimeError(f'{stem}: exit {result.returncode}')

def capture_run(name, variant, profile, diagnostics):
    root = ROOTS[variant] / 'swift-cidr-admission'
    check_workspace(variant)
    wait_for_compilers()
    destination = RUNS / name
    destination.mkdir(parents=True, exist_ok=False)
    temporary = WORK / 'raw' / name
    temporary.mkdir(parents=True, exist_ok=False)
    if diagnostics:
        names = [f'diagnostic.decision.{family}.{path}.10000' for family in ['v4', 'v6']
                 for path in ['projectPerRule', 'projectOnce', 'addressBits', 'erasedHost']]
    else:
        names = [f'policy.decision.{family}.combined.denyMissAllowLast.{size}'
                 for family in ['v4', 'v6'] for size in SIZES]
        names += [f'projection.{family}.{scenario}' for family in ['v4', 'v6'] for scenario in [
            'empty.defaultDeny', 'empty.defaultAllow', 'network.denyFirst.10000',
            'network.allowFirst.10000', 'address.denyFirst.1', 'range.denyFirst.1',
            'mixed.denyMissAllowLast.1000', 'mixed.defaultAllowMiss.1000',
        ]]
    (destination / 'inventory.txt').write_text('\n'.join(sorted(names)) + '\n')
    prefix = [str(DRIVER), '--grouping', 'benchmark', '--baseline-storage-path', str(WORK),
              '--targets', TARGET, '--no-progress', '--time-units', 'nanoseconds']
    label = 'lazy-peer-projection-' + name
    pattern = '^(' + '|'.join(re.escape(case) for case in names) + ')$'
    command = prefix + ['--command', 'baseline', '--baseline-operation', 'update', '--baseline', label,
                        '--format', 'text', '--benchmark-executable-paths',
                        str(root / 'Benchmarks/.build/arm64-apple-macosx/release' / TARGET), '--filter', pattern]
    metrics = ['wallClock', 'throughput'] if profile == 'timing' else []
    for metric in metrics:
        command += ['--metrics', metric]
    env = environment(diagnostics)
    executable = root / 'Benchmarks/.build/arm64-apple-macosx/release' / TARGET
    expected_binary = (OUT / (variant + '-binary-sha256.txt')).read_text().strip()
    assert sha(executable) == expected_binary
    metadata = {
        'schema_version': 3, 'name': name, 'variant': variant,
        'sequence_index': [x[0] for x in SEQUENCE].index(name) + 1,
        'admission_base_commit': '5d01867915f257d9d2086a510efe1c20f697b69a',
        'cidr_base_commit': 'cdc2e592beb9095875bc42fc4c269396b20d99e3',
        'cidr_local_patch_applied': True,
        'admission_peer_projection': variant,
        'launcher': 'Direct official BenchmarkTool, identical driver for all variants; no SwiftPM rebuild during timing.',
        'control_binaries_reused_from_previous_experiment': variant in ['baseline', 'eager'],
        'source_inventory': '../../evidence/' + variant + '-sources.json',
        'effective_dependency_graph': '../../evidence/' + variant + '-effective-graph.json',
        'binary_sha256': expected_binary, 'binary_path': str(executable),
        'sampling_profile': 'reference', 'metric_profile': profile,
        'metrics_override': metrics or None, 'allocation_stacks': False,
        'allocation_and_arc_hooks_requested': profile == 'full',
        'same_linked_instrumentation_for_both_metric_profiles': True,
        'diagnostics_enabled': diagnostics, 'expected_cases': len(names),
        'baseline_name': label, 'command': shlex.join(command), 'cwd': str(root),
        'environment_unset': UNSET,
        'environment_set': {k: v for k, v in env.items() if k.startswith('CIDR_ADMISSION_BENCHMARK_')},
        'swift_version': output(['swift', '--version']), 'macos': output(['sw_vers']),
        'kernel': output(['uname', '-a']), 'xcode': output(['xcodebuild', '-version']),
        'developer_directory': output(['xcode-select', '-p']),
        'hardware': output(['sysctl', 'machdep.cpu.brand_string', 'hw.logicalcpu', 'hw.memsize']),
        'power_before': output(['pmset', '-g', 'batt']), 'load_before': output(['sysctl', 'vm.loadavg']),
        'compiler_processes_before': compiler_processes(),
        'background_workload_controlled': False,
        'percentile_definition': 'Quantiles of measured closure duration divided by batch size; individual-operation quantiles only for batch_size == 1.',
        'throughput_definition': 'Median rounded batches/s multiplied by batch size.',
        'invocation_started_at_utc': timestamp(),
    }
    metadata_file = destination / 'metadata.json'
    metadata_file.write_text(json.dumps(metadata, indent=2) + '\n')
    print(f'START {name}: {len(names)} cases, {timestamp()}', flush=True)
    started = time.monotonic()
    execute(command, root, env, temporary / 'run')
    metadata.update(exit_code=0, execution_finished_at_utc=timestamp(), elapsed_seconds=time.monotonic() - started,
                    load_after=output(['sysctl', 'vm.loadavg']), power_after=output(['pmset', '-g', 'batt']),
                    compiler_processes_after=compiler_processes())
    baseline = WORK / '.benchmarkBaselines' / TARGET / label / 'results.json'
    assert baseline.is_file()
    for fmt in ['influx', 'text']:
        export = prefix + ['--command', 'baseline', '--baseline-operation', 'read', '--baseline', label,
                           '--format', fmt, '--path', 'stdout']
        metadata[f'export_{fmt}_command'] = shlex.join(export)
        execute(export, root, env, temporary / ('export-' + fmt))
    subprocess.run([sys.executable, str(WORK / 'summarize.py'), str(baseline),
                    str(temporary / 'export-influx.stdout.log'), str(destination / 'inventory.txt'),
                    str(temporary / 'summary')], check=True, stdout=subprocess.DEVNULL)
    for file in ['summary.csv', 'coverage.json']:
        shutil.copy2(temporary / 'summary' / file, destination / file)
    compress(baseline, destination / 'baseline.json.gz')
    for file in temporary.glob('*.log'):
        compress(file, destination / (file.name + '.gz'))
    metadata.update(native_baseline_bytes=baseline.stat().st_size, native_baseline_sha256=sha(baseline),
                    export_finished_at_utc=timestamp())
    check_workspace(variant)
    assert sha(executable) == expected_binary, 'Executable changed during run'
    metadata_file.write_text(json.dumps(metadata, indent=2) + '\n')
    coverage = json.loads((destination / 'coverage.json').read_text())
    assert coverage['cases'] == len(names)
    assert coverage['metric_records'] == len(names) * (9 if profile == 'full' else 2)
    assert coverage['minimum_samples'] >= 30, coverage
    print(f'DONE {name}: minimum {coverage["minimum_samples"]} samples, {timestamp()}', flush=True)

if __name__ == '__main__':
    # Build both variants before starting; never overlap compilation with measurement.
    for variant in ROOTS:
        assert (OUT / (variant + '-binary-sha256.txt')).is_file()
    for run in SEQUENCE:
        if len(sys.argv) == 1 or run[0] in sys.argv[1:]:
            capture_run(*run)
