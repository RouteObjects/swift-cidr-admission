import gzip
import json
import re
import shutil
from finalize import DEST, WORK, preserve

source = WORK / 'linux-evidence'
verification = json.loads((source / 'verification.json').read_text())
assert verification['native_architecture'] == 'x86_64'
assert len(verification['tests']) == 4
assert all(t['passed_tests'] == 64 and t['suites'] == 8 for t in verification['tests'])
assert verification['source_hashes_match_before_after']
assert verification['other_dependency_pins_unchanged']
codegen = {}
for version in ['6.2.4', '6.3.3']:
    version_log = gzip.decompress((source / (version + '-swift-version.log.gz')).read_bytes()).decode()
    assert 'Swift version ' + version in version_log
    for config in ['debug', 'release']:
        log = gzip.decompress((source / (version + '-' + config + '.log.gz')).read_bytes()).decode()
        assert '64 tests in 8 suites passed' in log
        assert json.loads((source / (version + '-' + config + '.command.json')).read_text())['exit'] == 0
    lines = gzip.decompress((source / (version + '-policy-assembly.log.gz')).read_bytes()).decode().splitlines()
    starts = [i for i, line in enumerate(lines) if re.match(r'^[0-9a-f]+ <.+>:$', line)]
    excerpts = []
    codegen[version] = []
    for n, start in enumerate(starts):
        if '8decision3for' in lines[start] or 'DecisionPeer' in lines[start]:
            body = '\n'.join(lines[start:starts[n+1] if n+1 < len(starts) else len(lines)]).rstrip() + '\n'
            excerpts.append(body)
            codegen[version].append({'function': lines[start],
                'static_call_instructions': re.findall(r'^\s*[0-9a-f]+:\s+call\w*\s+.*$', body, re.MULTILINE)})
    assert excerpts
    (source / (version + '-decision-excerpt.txt')).write_text('\n'.join(excerpts).rstrip() + '\n')
(source / 'codegen.json').write_text(json.dumps(codegen, indent=2) + '\n')
shutil.copytree(source, DEST / 'linux')
preservation = json.loads((DEST / 'preservation.json').read_text())
initial = preservation['native_linux_validation']
preservation['native_linux_validation'] = {
    'status': 'passed_after_ssh_agent_authorization', 'initial_attempt': initial,
    'retry': verification, 'benchmark_timings_collected_on_linux': False,
}
preservation['repositories'] = preserve()
for path in [WORK / 'preservation.json', DEST / 'preservation.json']:
    path.write_text(json.dumps(preservation, indent=2) + '\n')
for name in ['linux.py', 'qualify_linux.py', 'add_linux.py']:
    shutil.copy2(WORK / name, DEST / 'capture-scripts' / name)
print(json.dumps({'tests': verification['tests'], 'codegen': codegen}, indent=2))
