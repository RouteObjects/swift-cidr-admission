import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

from prepare import WORK, OUT, check_workspace as check_edited_package
from rerun import RUNS, SEQUENCE, ROOTS, OLD, check_workspace

ROOT = Path('REDACTED_HOME/Developer/Route Objects/swift-cidr-admission')
DEST = ROOT / 'Benchmarks/Results/2026-10-30-lazy-peer-projection-benchmark-1.38.1'
ALLOWED = {'Sources/CIDRAdmission/IPAdmissionPolicy.swift',
           'Tests/CIDRAdmissionTests/IPAdmissionPolicyPeerProjectionTests.swift',
           'Benchmarks/Results/README.md'}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def preserve():
    state = json.loads((WORK / 'before.json').read_text())
    result = {}
    for name, before in state.items():
        root = Path(before['root'])
        assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip() == before['head']
        assert subprocess.check_output(['git', 'branch', '--show-current'], cwd=root, text=True).strip() == before['branch']
        assert hashlib.sha256(subprocess.check_output(['git', 'diff', '--cached', '--binary'], cwd=root)).hexdigest() == before['index_diff_sha256']
        verified = 0
        for rel, checksum in before['files'].items():
            if name == 'admission' and rel in ALLOWED:
                continue
            assert sha(root / rel) == checksum, f'Unexpected original file change: {root / rel}'
            verified += 1
        result[name] = {'head': before['head'], 'branch': before['branch'],
                        'original_files_hash_verified': verified, 'index_unchanged': True}
    expected = json.loads((OUT / 'deferred-sources.json').read_text())
    for rel, checksum in expected.items():
        if rel.startswith('swift-cidr-admission/') and rel.endswith('.swift'):
            assert sha(ROOT / rel.removeprefix('swift-cidr-admission/')) == checksum
    return result

def finalize():
    for variant in ROOTS:
        assert len((OUT / (variant + '-default-inventory.txt')).read_text().splitlines()) == 174
        assert len((OUT / (variant + '-control-inventory.txt')).read_text().splitlines()) == 190
    preserved = preserve()
    for variant in ROOTS:
        check_workspace(variant)
    check_edited_package('deferred', '')
    for name, _, profile, _ in SEQUENCE:
        folder = RUNS / name
        meta = json.loads((folder / 'metadata.json').read_text())
        assert hashlib.sha256(gzip.decompress((folder / 'baseline.json.gz').read_bytes())).hexdigest() == meta['native_baseline_sha256']
        coverage = json.loads((folder / 'coverage.json').read_text())
        assert coverage['cases'] == 32 and coverage['metrics_expected_per_case'] == (9 if profile == 'full' else 2)
    mac_tests = []
    for config in ['debug', 'release']:
        assert json.loads((OUT / ('deferred-tests-' + config + '.command.json')).read_text())['exit'] == 0
        log = gzip.decompress((OUT / ('deferred-tests-' + config + '.stdout.log.gz')).read_bytes()).decode()
        assert '63 tests in 8 suites passed' in log
        mac_tests.append({'configuration': config, 'tests': 63, 'suites': 8, 'passed': True})
    linux = json.loads((OUT / 'linux-validation.json').read_text())
    (WORK / 'preservation.json').write_text(json.dumps({
        'repositories': preserved, 'macos_tests': mac_tests, 'native_linux_validation': linux,
        'original_snapshots_and_dependency_pins_unchanged': True,
        'new_production_source_change': 'Sources/CIDRAdmission/IPAdmissionPolicy.swift',
        'no_staging_commits_or_pushes': True,
    }, indent=2) + '\n')
    for variant, base in ROOTS.items():
        source = base / 'swift-cidr-admission/Sources/CIDRAdmission/IPAdmissionPolicy.swift'
        with gzip.open(OUT / (variant + '-IPAdmissionPolicy.swift.gz'), 'wb') as f:
            f.write(source.read_bytes())
    for variant, old_variant in [('baseline', 'baseline'), ('eager', 'patched')]:
        for suffix in ['command.json', 'stdout.log.gz', 'stderr.log.gz']:
            shutil.copy2(OLD / 'evidence' / (old_variant + '-build.' + suffix),
                         OUT / (variant + '-reused-build.' + suffix))
    (OUT / 'method.json').write_text(json.dumps({
        'comparison_variants': ['baseline', 'eager', 'deferred'],
        'additional_pilot': 'lazy-full-1 uses a Swift lazy property, not the final explicit-flag cache',
        'chronological_sequence': [r[0] for r in SEQUENCE],
        'control_builds_reused': ['baseline', 'eager'],
        'driver': 'Same official BenchmarkTool 1.38.1 executable for every new capture',
        'all_measurements_are_new': True,
        'benchmark_inputs_differ_only_in_policy_implementation': True,
        'new_tests_in_lazy_variants_are_not_benchmark_target_inputs': True,
        'all_variants_use_same_pending_cidr_patch': True,
        'no_agent_initiated_compilation_overlapped_measurement': True,
        'other_compiler_activity_checked_before_and_after_not_continuously': True,
        'background_workload_controlled': False,
    }, indent=2) + '\n')
    DEST.mkdir(parents=True, exist_ok=False)
    shutil.copytree(RUNS, DEST / 'runs')
    shutil.copytree(OUT, DEST / 'evidence')
    for path in (DEST / 'evidence').glob('*-discovery.txt'):
        path.write_text(path.read_text().rstrip() + '\n')
    for path in (DEST / 'evidence').glob('*.json'):
        path.write_text(json.dumps(json.loads(path.read_text()), indent=2) + '\n')
    for name in ['comparison.csv', 'validation.json', 'preservation.json']:
        shutil.copy2(WORK / name, DEST / name)
    scripts = DEST / 'capture-scripts'
    scripts.mkdir()
    for name in ['snapshot.py', 'setup.py', 'prepare.py', 'ready.py', 'codegen.py', 'rerun.py', 'summarize.py', 'analyze.py',
                 'validate_tests.py', 'finalize.py', 'seal.py']:
        shutil.copy2(WORK / name, scripts / name)
    print(json.dumps({'destination': str(DEST), 'preserved': preserved, 'macos_tests': mac_tests,
                      'linux_validation': linux}, indent=2))

if __name__ == '__main__':
    finalize()
