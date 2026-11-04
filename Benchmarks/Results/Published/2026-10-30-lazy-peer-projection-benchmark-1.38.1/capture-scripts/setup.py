import gzip
import io
import json
import shutil
import subprocess
import sys
import tarfile
from snapshot import WORK, OUT, ADMISSION, CIDR, sha, command

OLD = WORK.parent / 'admission-peer-projection.3SFHIj'
VARIANT = sys.argv[1] if len(sys.argv) > 1 else 'lazy'
for name, source in [('swift-cidr', CIDR), ('swift-cidr-admission', ADMISSION)]:
    dest = WORK / VARIANT / name
    dest.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(command(source, 'git', 'archive', 'HEAD'))) as archive:
        archive.extractall(dest, filter='data')
    for folder in (['Sources'] if name == 'swift-cidr' else ['Sources', 'Tests', 'Benchmarks/CIDRAdmissionBenchmarkTarget']):
        shutil.copytree(source / folder, dest / folder, dirs_exist_ok=True)
hashes = {str(p.relative_to(WORK / VARIANT)): sha(p) for p in (WORK / VARIANT).rglob('*')
          if p.is_file() and (p.suffix == '.swift' or p.name == 'Package.resolved')}
(OUT / (VARIANT + '-sources.json')).write_text(json.dumps(hashes, indent=2, sort_keys=True) + '\n')
for name, rel in [('root', 'Package.resolved'), ('benchmark', 'Benchmarks/Package.resolved')]:
    shutil.copy2(ADMISSION / rel, OUT / ('original-' + name + '-dependencies.json'))
for variant, old_variant in [('baseline', 'baseline'), ('eager', 'patched')]:
    for suffix in ['sources.json', 'effective-graph.json', 'workspace-state.json', 'dependencies.json', 'binary-sha256.txt']:
        shutil.copy2(OLD / 'evidence' / (old_variant + '-' + suffix), OUT / (variant + '-' + suffix))
    src = OLD / old_variant / 'swift-cidr-admission/Sources/CIDRAdmission/IPAdmissionPolicy.swift'
    with gzip.open(OUT / (variant + '-IPAdmissionPolicy.swift.gz'), 'wb') as f:
        f.write(src.read_bytes())
    original = json.loads((OUT / (variant + '-sources.json')).read_text())
    changed = [k for k in hashes if k in original and hashes[k] != original[k]]
    assert sorted(changed) == ['swift-cidr-admission/Sources/CIDRAdmission/IPAdmissionPolicy.swift',
                       'swift-cidr-admission/Tests/CIDRAdmissionTests/IPAdmissionPolicyPeerProjectionTests.swift'], changed
for name, root in [('admission', ADMISSION), ('cidr', CIDR)]:
    patch = command(root, 'git', 'diff', '--binary', '--', 'Sources', 'Tests', 'Benchmarks/CIDRAdmissionBenchmarkTarget')
    for rel in command(root, 'git', 'ls-files', '--others', '--exclude-standard', '-z', '--', 'Tests', 'Benchmarks/CIDRAdmissionBenchmarkTarget').decode().split('\0'):
        if rel:
            result = subprocess.run(['git', 'diff', '--no-index', '--', '/dev/null', rel], cwd=root, capture_output=True)
            assert result.returncode == 1
            patch += result.stdout
    with gzip.open(OUT / (name + '-source.patch.gz'), 'wb') as f:
        f.write(patch)
print('Lazy source snapshot created; baseline/eager build inputs checked')
