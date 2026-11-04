import json
from rerun import ROOTS, DRIVER, TARGET, OUT, sha, check_workspace
from prepare import capture, environment

binaries = {str(DRIVER): sha(DRIVER)}
for variant, base in ROOTS.items():
    build = base / 'swift-cidr-admission/Benchmarks/.build/arm64-apple-macosx/release'
    for name in [TARGET, 'libMallocInterposerSwift.dylib']:
        binaries[str(build / name)] = sha(build / name)
(OUT / 'binaries.json').write_text(json.dumps(binaries, indent=2) + '\n')
for variant, base in ROOTS.items():
    check_workspace(variant)
    prefix = [DRIVER, '--command', 'list', '--format', 'text', '--grouping', 'benchmark',
              '--baseline-storage-path', OUT, '--targets', TARGET, '--benchmark-executable-paths',
              base / 'swift-cidr-admission/Benchmarks/.build/arm64-apple-macosx/release' / TARGET]
    for enabled in [False, True]:
        env = environment()
        if not enabled:
            env.pop('CIDR_ADMISSION_BENCHMARK_PEER_PROJECTION')
            env.pop('CIDR_ADMISSION_BENCHMARK_SAMPLING')
        label = variant + ('-control-inventory' if enabled else '-default-inventory')
        output = capture(prefix, label, OUT, env).decode()
        cases = sorted(line for line in output.splitlines() if line.startswith(('policy.', 'projection.', 'diagnostic.')))
        assert len(cases) == (190 if enabled else 174), (variant, len(cases))
        (OUT / (label + '.txt')).write_text('\n'.join(cases) + '\n')
print('All variants verified; 174 default / 190 opt-in cases; binaries and interposers hashed')
