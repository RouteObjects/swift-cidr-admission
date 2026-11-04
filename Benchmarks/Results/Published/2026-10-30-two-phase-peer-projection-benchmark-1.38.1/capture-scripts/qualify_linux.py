import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time

ROOT = Path(sys.argv[1])
OUT = ROOT / 'evidence'
OUT.mkdir()

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def run(args, label, env=None):
    print('+', label, flush=True)
    started = time.time()
    result = subprocess.run(list(map(str, args)), env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    with gzip.open(OUT / (label + '.log.gz'), 'wb') as f:
        f.write(result.stdout)
    (OUT / (label + '.command.json')).write_text(json.dumps({
        'command': list(map(str, args)), 'exit': result.returncode, 'started_unix': started,
        'elapsed_seconds': time.time() - started, 'path': env.get('PATH') if env else None,
    }, indent=2) + '\n')
    if result.returncode:
        print(result.stdout.decode(errors='replace')[-8000:], flush=True)
        raise SystemExit(result.returncode)
    return result.stdout

assert platform.machine() == 'x86_64'
for label, args in [('kernel', ['uname', '-a']), ('os', ['cat', '/etc/os-release']),
                    ('cpu', ['lscpu']), ('virtualization', ['systemd-detect-virt'])]:
    run(args, label)
expected = json.loads((ROOT / 'source-hashes.json').read_text())
original_lock = json.loads((ROOT / 'source/swift-cidr-admission/Package.resolved').read_text())
results = []
for version in ['6.2.4', '6.3.3']:
    source = ROOT / version
    shutil.copytree(ROOT / 'source', source)
    for rel, checksum in expected.items():
        assert sha(source / rel) == checksum, rel
    env = os.environ.copy()
    env['PATH'] = str(Path.home() / '.local/share/swiftly/toolchains' / version / 'usr/bin') + ':/usr/bin:/bin'
    run(['swift', '--version'], version + '-swift-version', env)
    package = source / 'swift-cidr-admission'
    prefix = ['swift', 'package', '--package-path', package]
    run(prefix + ['--disable-automatic-resolution', 'show-dependencies', '--format', 'json'], version + '-resolved', env)
    run(prefix + ['edit', 'swift-cidr', '--path', source / 'swift-cidr'], version + '-edit', env)
    graph = run(prefix + ['show-dependencies', '--format', 'json'], version + '-effective-graph', env)
    (OUT / (version + '-effective-graph.json')).write_text(json.dumps(json.loads(graph), indent=2) + '\n')
    for config in ['debug', 'release']:
        label = version + '-' + config
        log = run(['swift', 'test', '-j', '4', '-c', config, '--package-path', package], label, env).decode()
        assert '64 tests in 8 suites passed' in log
        results.append({'swift': version, 'configuration': config, 'passed_tests': 64, 'suites': 8})
        state = json.loads((package / '.build/workspace-state.json').read_text())
        edit = next(d for d in state['object']['dependencies'] if d['packageRef']['identity'] == 'swift-cidr')
        assert edit['state'] == {'name': 'edited', 'path': str(source / 'swift-cidr')}
        lock = json.loads((package / 'Package.resolved').read_text())
        assert lock['pins'] == [p for p in original_lock['pins'] if p['identity'] != 'swift-cidr']
        for rel, checksum in expected.items():
            if rel != 'swift-cidr-admission/Package.resolved':
                assert sha(source / rel) == checksum, rel
    (OUT / (version + '-effective-dependencies.json')).write_text(json.dumps(lock, indent=2) + '\n')
    (OUT / (version + '-workspace-state.json')).write_text(json.dumps(state, indent=2) + '\n')
    obj = package / '.build/x86_64-unknown-linux-gnu/release/CIDRAdmission.build/IPAdmissionPolicy.swift.o'
    run(['llvm-objdump', '-dr', '--no-show-raw-insn', obj], version + '-policy-assembly', env)
(OUT / 'verification.json').write_text(json.dumps({
    'native_architecture': platform.machine(), 'remote_directory': str(ROOT), 'tests': results,
    'source_hashes_match_before_after': True, 'other_dependency_pins_unchanged': True,
    'source_archive_sha256': sha(ROOT / 'source.tar.gz'),
}, indent=2) + '\n')
shutil.copy2(ROOT / 'source-hashes.json', OUT / 'source-hashes.json')
print(json.dumps(results), flush=True)
