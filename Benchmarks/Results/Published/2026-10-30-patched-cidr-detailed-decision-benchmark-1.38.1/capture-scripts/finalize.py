import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

from prepare import WORK, OUT, check_workspace
from rerun import RUNS, SEQUENCE

DEST = Path('REDACTED_HOME/Developer/Route Objects/swift-cidr-admission/Benchmarks/Results/2026-10-30-patched-cidr-detailed-decision-benchmark-1.38.1')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def verify_originals():
    before = json.loads((WORK / 'before.json').read_text())
    preservation = {}
    for name, state in before.items():
        root = Path(state['root'])
        assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip() == state['head']
        assert subprocess.check_output(['git', 'branch', '--show-current'], cwd=root, text=True).strip() == state['branch']
        index = subprocess.check_output(['git', 'diff', '--cached', '--binary'], cwd=root)
        assert hashlib.sha256(index).hexdigest() == state['index_diff_sha256']
        for rel, checksum in state['files'].items():
            if name == 'admission' and rel == 'Benchmarks/Results/README.md':
                continue
            assert sha(root / rel) == checksum, f'Original file changed: {root / rel}'
        preservation[name] = {
            'head': state['head'], 'branch': state['branch'], 'index_unchanged': True,
            'original_files_verified': len(state['files']) - (1 if name == 'admission' else 0),
        }
    return preservation

def finalize():
    preservation = verify_originals()
    for variant in ['baseline', 'patched']:
        check_workspace(variant)
    check_workspace('patched', '')
    for name, _, profile, _ in SEQUENCE:
        folder = RUNS / name
        metadata = json.loads((folder / 'metadata.json').read_text())
        raw = gzip.decompress((folder / 'baseline.json.gz').read_bytes())
        assert hashlib.sha256(raw).hexdigest() == metadata['native_baseline_sha256']
        assert len(raw) == metadata['native_baseline_bytes']
        coverage = json.loads((folder / 'coverage.json').read_text())
        assert coverage['metrics_expected_per_case'] == (9 if profile == 'full' else 2)
    tests = {}
    for config in ['debug', 'release']:
        command = json.loads((OUT / ('patched-tests-' + config + '.command.json')).read_text())
        assert command['exit'] == 0
        text = '\n'.join(gzip.decompress((OUT / ('patched-tests-' + config + '.' + stream + '.log.gz')).read_bytes()).decode() for stream in ['stdout', 'stderr'])
        lines = [line for line in text.splitlines() if 'Test run with' in line and 'passed' in line]
        assert lines, config
        tests[config] = lines[-1]
    report = {'original_repositories': preservation, 'patched_admission_tests': tests,
              'original_root_and_benchmark_lockfiles_unchanged': True,
              'temporary_effective_locks_remove_only_the_edited_cidr_pin': True,
              'staging_commits_pushes_performed': False}
    (WORK / 'preservation.json').write_text(json.dumps(report, indent=2) + '\n')
    DEST.mkdir(parents=True, exist_ok=False)
    shutil.copytree(RUNS, DEST / 'runs')
    shutil.copytree(OUT, DEST / 'evidence')
    # Keep raw discovery output in the gzip logs; make the readable copies whitespace-clean.
    for path in (DEST / 'evidence').glob('*-discovery.txt'):
        path.write_text(path.read_text().rstrip() + '\n')
    for path in (DEST / 'evidence').glob('*-effective-graph.json'):
        path.write_text(json.dumps(json.loads(path.read_text()), indent=2) + '\n')
    for name in ['comparison.csv', 'diagnostics.csv', 'validation.json', 'preservation.json']:
        shutil.copy2(WORK / name, DEST / name)
    scripts = DEST / 'capture-scripts'
    scripts.mkdir()
    for name in ['setup.py', 'prepare.py', 'rerun.py', 'summarize.py', 'analyze.py', 'validate_tests.py', 'finalize.py', 'seal.py']:
        shutil.copy2(WORK / name, scripts / name)
    print(json.dumps(report, indent=2))
    print(DEST)

if __name__ == '__main__':
    finalize()
