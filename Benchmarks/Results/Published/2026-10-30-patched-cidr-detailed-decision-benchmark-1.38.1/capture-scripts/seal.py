import difflib
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess

from finalize import DEST, WORK, verify_originals

ROOT = DEST.parents[2]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

verify_originals()
before = json.loads((WORK / 'before.json').read_text())
index = ROOT / 'Benchmarks/Results/README.md'
current = index.read_text()
added = [line for line in current.splitlines(keepends=True) if DEST.name in line]
assert len(added) == 1
original = current.replace(added[0], '', 1)
assert hashlib.sha256(original.encode()).hexdigest() == before['admission']['files']['Benchmarks/Results/README.md']

issues = []
for path in sorted(DEST.rglob('*')):
    if not path.is_file():
        continue
    if path.suffix == '.gz':
        gzip.decompress(path.read_bytes())
        continue
    result = subprocess.run(['git', 'diff', '--no-index', '--check', '--', '/dev/null', str(path)], cwd=ROOT, text=True, capture_output=True)
    if result.stdout or result.stderr:
        issues.append(result.stdout + result.stderr)
assert not issues, '\n'.join(issues)
subprocess.run(['git', 'diff', '--check'], cwd=ROOT, check=True)
for document in [index, DEST / 'README.md']:
    for link in re.findall(r'\]\(([^)]+)\)', document.read_text()):
        path = link.split('#')[0]
        if path and not path.startswith(('http:', 'https:')):
            assert (document.parent / path).is_file(), link

files = [path for path in sorted(DEST.rglob('*')) if path.is_file() and path.name != 'SHA256SUMS']
(DEST / 'SHA256SUMS').write_text(''.join(f'{sha(path)}  {path.relative_to(DEST)}\n' for path in files))
checked = subprocess.run(['shasum', '-a', '256', '-c', 'SHA256SUMS'], cwd=DEST, capture_output=True, text=True, check=True)
assert len(checked.stdout.splitlines()) == len(files)

patch = ''.join(difflib.unified_diff(original.splitlines(keepends=True), current.splitlines(keepends=True),
                                     fromfile='a/Benchmarks/Results/README.md', tofile='b/Benchmarks/Results/README.md')).encode()
for path in sorted(DEST.rglob('*')):
    if path.is_file():
        result = subprocess.run(['git', 'diff', '--no-index', '--binary', '--', '/dev/null', str(path.relative_to(ROOT))], cwd=ROOT, capture_output=True)
        assert result.returncode == 1
        patch += result.stdout
(WORK / 'patched-cidr-benchmark-rerun.patch').write_bytes(patch)

verification = {'sha256_files_verified': len(files), 'gzip_archives_verified': len(list(DEST.rglob('*.gz'))),
                'whitespace_check': 'passed (including untracked text)', 'relative_readme_links': 'passed',
                'parent_index_change': 'one added capture link', 'original_repositories': verify_originals(),
                'new_capture_bytes': sum(path.stat().st_size for path in DEST.rglob('*') if path.is_file())}
(WORK / 'final-verification.json').write_text(json.dumps(verification, indent=2) + '\n')
print(json.dumps(verification, indent=2))
print('Review patch:', WORK / 'patched-cidr-benchmark-rerun.patch')
