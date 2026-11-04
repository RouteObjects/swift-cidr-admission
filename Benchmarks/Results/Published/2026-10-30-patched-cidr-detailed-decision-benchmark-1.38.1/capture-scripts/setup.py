import gzip
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import tarfile

WORK = Path(__file__).parent
ADMISSION = Path('REDACTED_HOME/Developer/Route Objects/swift-cidr-admission')
CIDR = Path('REDACTED_HOME/Developer/Route Objects/Example Framework/Packages/swift-cidr')
EVIDENCE = WORK / 'evidence'
EVIDENCE.mkdir(exist_ok=True)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def output(root, *args):
    return subprocess.check_output(list(args), cwd=root)

def inventory(root):
    paths = output(root, 'git', 'ls-files', '-c', '-o', '--exclude-standard', '-z').decode().split('\0')
    return {p: sha(root / p) for p in sorted(set(paths)) if p and (root / p).is_file()}

def archive(root, destination):
    destination.mkdir(parents=True)
    data = output(root, 'git', 'archive', 'HEAD')
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        tar.extractall(destination, filter='data')

state = {}
for name, root in [('admission', ADMISSION), ('cidr', CIDR)]:
    state[name] = {
        'root': str(root), 'head': output(root, 'git', 'rev-parse', 'HEAD').decode().strip(),
        'branch': output(root, 'git', 'branch', '--show-current').decode().strip(),
        'status': output(root, 'git', 'status', '--short', '--branch').decode(),
        'files': inventory(root), 'index_diff_sha256': hashlib.sha256(output(root, 'git', 'diff', '--cached', '--binary')).hexdigest(),
    }
    patch = output(root, 'git', 'diff', '--binary', '--', 'Sources', 'Benchmarks/CIDRAdmissionBenchmarkTarget')
    if name == 'admission':
        extra = subprocess.run(['git', 'diff', '--no-index', '--', '/dev/null', 'Benchmarks/CIDRAdmissionBenchmarkTarget/DecisionTimingBenchmarks.swift'], cwd=root, stdout=subprocess.PIPE)
        assert extra.returncode == 1
        patch += extra.stdout
    with gzip.open(EVIDENCE / (name + '-working-source.patch.gz'), 'wb') as f:
        f.write(patch)
(WORK / 'before.json').write_text(json.dumps(state, indent=2, sort_keys=True) + '\n')
(EVIDENCE / 'source-provenance.json').write_text(json.dumps({k: {x: y for x, y in v.items() if x != 'files'} for k, v in state.items()}, indent=2) + '\n')

for variant in ['baseline', 'patched']:
    core = WORK / variant / 'swift-cidr'
    consumer = WORK / variant / 'swift-cidr-admission'
    archive(CIDR, core)
    if variant == 'patched':
        shutil.copytree(CIDR / 'Sources', core / 'Sources', dirs_exist_ok=True)
    archive(ADMISSION, consumer)
    for folder in ['Sources', 'Tests', 'Benchmarks/CIDRAdmissionBenchmarkTarget']:
        shutil.copytree(ADMISSION / folder, consumer / folder, dirs_exist_ok=True)
    for file in ['Package.swift', 'Package.resolved', 'Benchmarks/Package.swift', 'Benchmarks/Package.resolved']:
        shutil.copy2(ADMISSION / file, consumer / file)
    files = {}
    for root in [core, consumer]:
        for path in root.rglob('*'):
            if path.is_file() and (path.suffix == '.swift' or path.name == 'Package.resolved'):
                files[str(path.relative_to(WORK / variant))] = sha(path)
    (EVIDENCE / (variant + '-sources.json')).write_text(json.dumps(files, indent=2, sort_keys=True) + '\n')
base = json.loads((EVIDENCE / 'baseline-sources.json').read_text())
patched = json.loads((EVIDENCE / 'patched-sources.json').read_text())
changed = sorted(k for k in base if base[k] != patched[k])
assert changed == ['swift-cidr/Sources/CIDR/CIDR.swift', 'swift-cidr/Sources/CIDR/FixedWidthInteger+NetworkMask.swift', 'swift-cidr/Sources/CIDR/IPPrefix.swift']
shutil.copy2('/private/tmp/swift-cidr-admission-sampling.DB3nKk/summarize.py', WORK / 'summarize.py')
print(json.dumps({'source_difference': changed, 'workspace': str(WORK)}, indent=2))
