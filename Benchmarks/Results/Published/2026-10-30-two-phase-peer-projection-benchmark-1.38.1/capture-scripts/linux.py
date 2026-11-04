import hashlib
import io
import json
from pathlib import Path
import shlex
import subprocess
import tarfile

from prepare import WORK, OUT

SSH = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15', '-o', 'StrictHostKeyChecking=yes',
       '-o', 'ForwardAgent=no', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=3', 'linux-validation-host']

remote = subprocess.check_output(SSH + ['mktemp -d /tmp/admission-two-phase.XXXXXX'], text=True).strip()
(WORK / 'linux-remote.txt').write_text(remote + '\n')
hashes = {}
with tarfile.open(WORK / 'linux-source.tar.gz', 'w:gz') as tar:
    for name in ['swift-cidr', 'swift-cidr-admission']:
        source = WORK / 'phased' / name
        files = [source / 'Package.swift', source / 'Package.resolved']
        files += [p for folder in ['Sources', 'Tests'] for p in (source / folder).rglob('*') if p.is_file()]
        for path in files:
            rel = name + '/' + str(path.relative_to(source))
            data = (OUT / 'original-root-dependencies.json').read_bytes() if rel == 'swift-cidr-admission/Package.resolved' else path.read_bytes()
            hashes[rel] = hashlib.sha256(data).hexdigest()
            info = tarfile.TarInfo('source/' + rel)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))
    for name, data in [('qualify_linux.py', (WORK / 'qualify_linux.py').read_bytes()),
                       ('source-hashes.json', (json.dumps(hashes, indent=2) + '\n').encode())]:
        info = tarfile.TarInfo(name)
        info.size = len(data)
        tar.addfile(info, io.BytesIO(data))
scp = ['scp', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ForwardAgent=no']
subprocess.run(scp + [str(WORK / 'linux-source.tar.gz'), 'linux-validation-host:' + remote + '/source.tar.gz'], check=True)
extract = 'import tarfile; from pathlib import Path; p=Path(' + repr(remote) + '); tarfile.open(p/"source.tar.gz").extractall(p,filter="data")'
subprocess.run(SSH + [shlex.join(['python3', '-c', extract])], check=True)
command = SSH + [shlex.join(['python3', remote + '/qualify_linux.py', remote])]
print('Native Linux source directory:', remote, flush=True)
result = subprocess.run(command)
subprocess.run(scp + ['-r', 'linux-validation-host:' + remote + '/evidence', str(WORK / 'linux-evidence')], check=True)
if result.returncode:
    raise SystemExit(result.returncode)
verification = json.loads((WORK / 'linux-evidence/verification.json').read_text())
assert verification['source_archive_sha256'] == hashlib.sha256((WORK / 'linux-source.tar.gz').read_bytes()).hexdigest()
print('Native Linux verification complete', flush=True)
