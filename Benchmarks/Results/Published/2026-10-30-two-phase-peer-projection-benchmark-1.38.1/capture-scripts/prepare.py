import gzip
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import time

WORK = Path(__file__).parent
OUT = WORK / 'evidence'
TARGET = 'CIDRAdmissionBenchmarkTarget'
UNSET = ['CIDR_ADMISSION_BENCHMARK_TARGET', 'BENCHMARK_DISABLE_MALLOC_INTERPOSER',
         'BENCHMARK_DISABLE_JEMALLOC', 'MALLOC_INTERPOSER_LOCAL_PATH', 'RUNTIME_INTERPOSER_LOCAL_PATH',
         'CIDR_ADMISSION_BENCHMARK_DIAGNOSTICS', 'CIDR_ADMISSION_BENCHMARK_SAMPLING',
         'CIDR_ADMISSION_BENCHMARK_PEER_PROJECTION']

def environment(diagnostics=False):
    env = os.environ.copy()
    for k in UNSET:
        env.pop(k, None)
    env['CIDR_ADMISSION_BENCHMARK_SAMPLING'] = 'reference'
    env['CIDR_ADMISSION_BENCHMARK_PEER_PROJECTION'] = '1'
    if diagnostics:
        env['CIDR_ADMISSION_BENCHMARK_DIAGNOSTICS'] = '1'
    return env

def capture(command, label, cwd, env=None):
    print('+', label, flush=True)
    start = time.time()
    result = subprocess.run(list(map(str, command)), cwd=cwd, env=env or environment(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    for stream, data in [('stdout', result.stdout), ('stderr', result.stderr)]:
        with gzip.open(OUT / (label + '.' + stream + '.log.gz'), 'wb') as f:
            f.write(data)
    (OUT / (label + '.command.json')).write_text(json.dumps({
        'command': list(map(str, command)), 'cwd': str(cwd), 'exit': result.returncode,
        'started_unix': start, 'elapsed_seconds': time.time() - start,
    }, indent=2) + '\n')
    if result.returncode:
        print(result.stdout.decode(errors='replace')[-6000:] + result.stderr.decode(errors='replace')[-6000:], flush=True)
        raise SystemExit(result.returncode)
    return result.stdout

def check_workspace(variant, package='Benchmarks'):
    root = WORK / variant / 'swift-cidr-admission'
    package_root = root / package
    state = json.loads((package_root / '.build/workspace-state.json').read_text())
    edited = next(x for x in state['object']['dependencies'] if x['packageRef']['identity'] == 'swift-cidr')
    assert edited['state'] == {'name': 'edited', 'path': str(WORK / variant / 'swift-cidr')}
    assert edited['basedOn']['state']['checkoutState']['revision'] == 'cdc2e592beb9095875bc42fc4c269396b20d99e3'
    expected = json.loads((OUT / (variant + '-sources.json')).read_text())
    for rel, checksum in expected.items():
        path = WORK / variant / rel
        if rel in ['swift-cidr-admission/Benchmarks/Package.resolved', 'swift-cidr-admission/Package.resolved'] and hashlib.sha256(path.read_bytes()).hexdigest() != checksum:
            # SwiftPM removes an edited dependency's pin; every other pin must stay exact.
            original = json.loads((OUT / ('original-' + ('benchmark' if '/Benchmarks/' in rel else 'root') + '-dependencies.json')).read_text())
            effective = json.loads(path.read_text())
            assert effective['pins'] == [p for p in original['pins'] if p['identity'] != 'swift-cidr']
            continue
        assert hashlib.sha256(path.read_bytes()).hexdigest() == checksum, rel
    return state

def prepare(variant):
    root = WORK / variant / 'swift-cidr-admission'
    prefix = ['swift', 'package', '--package-path', 'Benchmarks']
    statepath = root / 'Benchmarks/.build/workspace-state.json'
    edited = statepath.exists() and any(x['packageRef']['identity'] == 'swift-cidr' and x['state']['name'] == 'edited'
                                         for x in json.loads(statepath.read_text())['object']['dependencies'])
    if not edited:
        capture(prefix + ['--disable-automatic-resolution', 'show-dependencies', '--format', 'json'], variant + '-resolved-graph', root)
        capture(prefix + ['edit', 'swift-cidr', '--path', WORK / variant / 'swift-cidr'], variant + '-edit', root)
    graph = capture(prefix + ['show-dependencies', '--format', 'json'], variant + '-effective-graph', root)
    (OUT / (variant + '-effective-graph.json')).write_bytes(graph)
    check_workspace(variant)
    capture(['swift', 'build', '-v', '-c', 'release', '--package-path', 'Benchmarks', '--product', TARGET], variant + '-build', root)
    driver = '/private/tmp/admission-peer-projection.3SFHIj/patched/swift-cidr-admission/Benchmarks/.build/arm64-apple-macosx/release/BenchmarkTool'
    listing = capture([driver, '--command', 'list', '--format', 'text', '--grouping', 'benchmark',
                       '--baseline-storage-path', WORK, '--targets', TARGET, '--benchmark-executable-paths',
                       root / 'Benchmarks/.build/arm64-apple-macosx/release' / TARGET], variant + '-discovery', root, environment(True))
    (OUT / (variant + '-discovery.txt')).write_bytes(listing)
    state = check_workspace(variant)
    (OUT / (variant + '-workspace-state.json')).write_text(json.dumps(state, indent=2) + '\n')
    shutil.copy2(root / 'Benchmarks/Package.resolved', OUT / (variant + '-dependencies.json'))
    build = root / 'Benchmarks/.build/arm64-apple-macosx/release'
    for module, filename in [('CIDRAdmission', 'AdmissionRule.swift'), ('CIDRAdmission', 'IPAdmissionPolicy.swift'), ('CIDR', 'IPPrefix.swift')]:
        capture(['xcrun', 'llvm-objdump', '-dr', '--no-show-raw-insn', build / (module + '.build') / (filename + '.o')], variant + '-' + filename + '-assembly', root)
    exe = build / TARGET
    (OUT / (variant + '-binary-sha256.txt')).write_text(hashlib.sha256(exe.read_bytes()).hexdigest() + '\n')

if __name__ == '__main__':
    for variant in sys.argv[1:] or ['baseline', 'patched']:
        prepare(variant)
