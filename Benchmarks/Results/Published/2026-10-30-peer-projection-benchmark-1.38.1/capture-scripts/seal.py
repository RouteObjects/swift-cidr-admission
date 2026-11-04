import difflib
import gzip
import json
from pathlib import Path
import re
import subprocess

from finalize import DEST, ROOT, WORK, preserve, sha

preserve()
pairs = [
    ('baseline-policy.swift', 'Sources/CIDRAdmission/IPAdmissionPolicy.swift'),
    ('before-benchmark.swift', 'Benchmarks/CIDRAdmissionBenchmarkTarget/CIDRAdmissionBenchmarkTarget.swift'),
    ('before-index.md', 'Benchmarks/Results/README.md'),
]
new_files = [ROOT / 'Tests/CIDRAdmissionTests/IPAdmissionPolicyPeerProjectionTests.swift',
             ROOT / 'Benchmarks/CIDRAdmissionBenchmarkTarget/PeerProjectionBenchmarks.swift']
issues = []
for path in [*new_files, *sorted(DEST.rglob('*'))]:
    if not path.is_file():
        continue
    if path.suffix == '.gz':
        gzip.decompress(path.read_bytes())
    else:
        result = subprocess.run(['git', 'diff', '--no-index', '--check', '--', '/dev/null', str(path)], cwd=ROOT, text=True, capture_output=True)
        if result.stdout or result.stderr:
            issues.append(result.stdout + result.stderr)
assert not issues, '\n'.join(issues)
subprocess.run(['git', 'diff', '--check'], cwd=ROOT, check=True)
for document in [DEST / 'README.md', ROOT / 'Benchmarks/Results/README.md']:
    for link in re.findall(r'\]\(([^)]+)\)', document.read_text()):
        path = link.split('#')[0]
        if path and not path.startswith(('https:', 'http:')):
            assert (document.parent / path).is_file(), path
files = [p for p in sorted(DEST.rglob('*')) if p.is_file() and p.name != 'SHA256SUMS']
(DEST / 'SHA256SUMS').write_text(''.join(f'{sha(p)}  {p.relative_to(DEST)}\n' for p in files))
subprocess.run(['shasum', '-a', '256', '-c', 'SHA256SUMS'], cwd=DEST, check=True, stdout=subprocess.DEVNULL)
patch = b''
for old, new in pairs:
    patch += ''.join(difflib.unified_diff((WORK / old).read_text().splitlines(keepends=True),
                                         (ROOT / new).read_text().splitlines(keepends=True),
                                         fromfile='a/' + new, tofile='b/' + new)).encode()
for path in [*new_files, *sorted(DEST.rglob('*'))]:
    if path.is_file():
        result = subprocess.run(['git', 'diff', '--no-index', '--binary', '--', '/dev/null', str(path.relative_to(ROOT))], cwd=ROOT, capture_output=True)
        assert result.returncode == 1
        patch += result.stdout
review = WORK / 'peer-projection-review.patch'
review.write_bytes(patch)
subprocess.run(['git', 'apply', '--reverse', '--check', str(review)], cwd=ROOT, check=True)
result = {'checksummed_files': len(files), 'gzip_archives': len(list(DEST.rglob('*.gz'))),
          'whitespace_check_including_untracked_text': 'passed', 'readme_links': 'passed',
          'review_patch_reverse_check': 'passed', 'preservation': preserve(),
          'new_capture_bytes': sum(p.stat().st_size for p in DEST.rglob('*') if p.is_file())}
(WORK / 'verification.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
