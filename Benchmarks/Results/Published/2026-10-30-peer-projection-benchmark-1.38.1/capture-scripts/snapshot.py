import gzip
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

WORK = Path(__file__).parent
ADMISSION = Path('REDACTED_HOME/Developer/Route Objects/swift-cidr-admission')
CIDR = Path('REDACTED_HOME/Developer/Route Objects/Example Framework/Packages/swift-cidr')
OUT = WORK / 'evidence'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def command(root, *args):
    return subprocess.check_output(args, cwd=root)

def before():
    OUT.mkdir()
    state = {}
    for name, root in [('admission', ADMISSION), ('cidr', CIDR)]:
        paths = command(root, 'git', 'ls-files', '-c', '-o', '--exclude-standard', '-z').decode().split('\0')
        state[name] = {
            'root': str(root), 'head': command(root, 'git', 'rev-parse', 'HEAD').decode().strip(),
            'branch': command(root, 'git', 'branch', '--show-current').decode().strip(),
            'index_diff_sha256': hashlib.sha256(command(root, 'git', 'diff', '--cached', '--binary')).hexdigest(),
            'files': {p: sha(root / p) for p in sorted(set(paths)) if p and (root / p).is_file()},
        }
    (WORK / 'before.json').write_text(json.dumps(state, indent=2) + '\n')
    shutil.copy2(ADMISSION / 'Sources/CIDRAdmission/IPAdmissionPolicy.swift', WORK / 'baseline-policy.swift')
    shutil.copy2(ADMISSION / 'Benchmarks/CIDRAdmissionBenchmarkTarget/CIDRAdmissionBenchmarkTarget.swift', WORK / 'before-benchmark.swift')
    shutil.copy2(ADMISSION / 'Benchmarks/Results/README.md', WORK / 'before-index.md')

def setup():
    for variant in ['baseline', 'patched']:
        for name, source in [('swift-cidr', CIDR), ('swift-cidr-admission', ADMISSION)]:
            dest = WORK / variant / name
            dest.mkdir(parents=True)
            with tarfile.open(fileobj=io.BytesIO(command(source, 'git', 'archive', 'HEAD'))) as archive:
                archive.extractall(dest, filter='data')
            for folder in (['Sources'] if name == 'swift-cidr' else ['Sources', 'Tests', 'Benchmarks/CIDRAdmissionBenchmarkTarget']):
                shutil.copytree(source / folder, dest / folder, dirs_exist_ok=True)
        if variant == 'baseline':
            shutil.copy2(WORK / 'baseline-policy.swift', WORK / variant / 'swift-cidr-admission/Sources/CIDRAdmission/IPAdmissionPolicy.swift')
        hashes = {str(p.relative_to(WORK / variant)): sha(p) for p in (WORK / variant).rglob('*')
                  if p.is_file() and (p.suffix == '.swift' or p.name == 'Package.resolved')}
        (OUT / (variant + '-sources.json')).write_text(json.dumps(hashes, indent=2, sort_keys=True) + '\n')
    a = json.loads((OUT / 'baseline-sources.json').read_text())
    b = json.loads((OUT / 'patched-sources.json').read_text())
    assert [k for k in a if a[k] != b[k]] == ['swift-cidr-admission/Sources/CIDRAdmission/IPAdmissionPolicy.swift']
    for name, rel in [('root', 'Package.resolved'), ('benchmark', 'Benchmarks/Package.resolved')]:
        shutil.copy2(ADMISSION / rel, OUT / ('original-' + name + '-dependencies.json'))
    for name, root in [('admission', ADMISSION), ('cidr', CIDR)]:
        patch = command(root, 'git', 'diff', '--binary', '--', 'Sources', 'Tests', 'Benchmarks/CIDRAdmissionBenchmarkTarget')
        for rel in command(root, 'git', 'ls-files', '--others', '--exclude-standard', '-z', '--', 'Tests', 'Benchmarks/CIDRAdmissionBenchmarkTarget').decode().split('\0'):
            if rel:
                result = subprocess.run(['git', 'diff', '--no-index', '--', '/dev/null', rel], cwd=root, capture_output=True)
                assert result.returncode == 1
                patch += result.stdout
        with gzip.open(OUT / (name + '-source.patch.gz'), 'wb') as f:
            f.write(patch)
    shutil.copy2('/private/tmp/admission-patched-cidr.2924yd/summarize.py', WORK / 'summarize.py')
    print('Both variants use the same patched CIDR; only IPAdmissionPolicy.swift differs')

if __name__ == '__main__':
    {'before': before, 'setup': setup}[sys.argv[1]]()
