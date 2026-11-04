import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

from prepare import WORK, OUT, check_workspace
from rerun import RUNS, SEQUENCE

ROOT = Path('REDACTED_HOME/Developer/Route Objects/swift-cidr-admission')
DEST = ROOT / 'Benchmarks/Results/2026-10-30-peer-projection-benchmark-1.38.1'
ALLOWED = {'Sources/CIDRAdmission/IPAdmissionPolicy.swift',
           'Benchmarks/CIDRAdmissionBenchmarkTarget/CIDRAdmissionBenchmarkTarget.swift',
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
    expected = json.loads((OUT / 'patched-sources.json').read_text())
    for rel, checksum in expected.items():
        if rel.startswith('swift-cidr-admission/') and rel.endswith('.swift'):
            assert sha(ROOT / rel.removeprefix('swift-cidr-admission/')) == checksum
    return result

def finalize():
    assert json.loads((OUT / 'default-discovery-verification.json').read_text())['default_cases'] == 174
    preserved = preserve()
    for variant in ['baseline', 'patched']:
        check_workspace(variant)
    check_workspace('patched', '')
    for name, _, profile, _ in SEQUENCE:
        folder = RUNS / name
        meta = json.loads((folder / 'metadata.json').read_text())
        assert hashlib.sha256(gzip.decompress((folder / 'baseline.json.gz').read_bytes())).hexdigest() == meta['native_baseline_sha256']
        coverage = json.loads((folder / 'coverage.json').read_text())
        assert coverage['cases'] == 32 and coverage['metrics_expected_per_case'] == (9 if profile == 'full' else 2)
    mac_tests = []
    for config in ['debug', 'release']:
        assert json.loads((OUT / ('patched-tests-' + config + '.command.json')).read_text())['exit'] == 0
        log = gzip.decompress((OUT / ('patched-tests-' + config + '.stdout.log.gz')).read_bytes()).decode()
        assert '61 tests in 8 suites passed' in log
        mac_tests.append({'configuration': config, 'tests': 61, 'suites': 8, 'passed': True})
    linux = json.loads((WORK / 'linux-evidence/verification.json').read_text())
    assert len(linux['tests']) == 4 and all(t['passed_tests'] == 61 for t in linux['tests'])
    (WORK / 'preservation.json').write_text(json.dumps({
        'repositories': preserved, 'macos_tests': mac_tests, 'native_linux_tests': linux['tests'],
        'original_snapshots_and_dependency_pins_unchanged': True,
        'new_production_source_change': 'Sources/CIDRAdmission/IPAdmissionPolicy.swift',
        'no_staging_commits_or_pushes': True,
    }, indent=2) + '\n')
    DEST.mkdir(parents=True, exist_ok=False)
    shutil.copytree(RUNS, DEST / 'runs')
    shutil.copytree(OUT, DEST / 'evidence')
    shutil.copytree(WORK / 'linux-evidence', DEST / 'linux')
    for path in (DEST / 'evidence').glob('*-discovery.txt'):
        path.write_text(path.read_text().rstrip() + '\n')
    for path in (DEST / 'evidence').glob('*-effective-graph.json'):
        path.write_text(json.dumps(json.loads(path.read_text()), indent=2) + '\n')
    for name in ['comparison.csv', 'validation.json', 'preservation.json']:
        shutil.copy2(WORK / name, DEST / name)
    scripts = DEST / 'capture-scripts'
    scripts.mkdir()
    for name in ['snapshot.py', 'prepare.py', 'rerun.py', 'summarize.py', 'analyze.py',
                 'validate_tests.py', 'linux.py', 'qualify_linux.py', 'postvalidate.py', 'finalize.py', 'seal.py']:
        shutil.copy2(WORK / name, scripts / name)
    print(json.dumps({'destination': str(DEST), 'preserved': preserved, 'macos_tests': mac_tests,
                      'linux_tests': linux['tests']}, indent=2))

if __name__ == '__main__':
    finalize()
