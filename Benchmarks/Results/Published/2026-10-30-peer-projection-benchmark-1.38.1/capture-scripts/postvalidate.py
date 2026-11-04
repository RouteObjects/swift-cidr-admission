import json
from prepare import WORK, OUT, TARGET, capture, check_workspace, environment

root = WORK / 'patched/swift-cidr-admission'
env = environment()
env.pop('CIDR_ADMISSION_BENCHMARK_PEER_PROJECTION')
env.pop('CIDR_ADMISSION_BENCHMARK_SAMPLING')
listing = capture(['swift', 'package', '--package-path', 'Benchmarks', 'benchmark', 'list',
                   '--target', TARGET, '--benchmark-build-configuration', 'release'],
                  'default-discovery', root, env).decode()
cases = [line for line in listing.splitlines() if line.startswith(('policy.', 'projection.', 'diagnostic.'))]
assert len(cases) == 174 and all(line.startswith('policy.') for line in cases)
(OUT / 'default-inventory.txt').write_text('\n'.join(sorted(cases)) + '\n')
check_workspace('patched')
(OUT / 'default-discovery-verification.json').write_text(json.dumps({
    'default_cases': len(cases), 'projection_controls_disabled_without_opt_in': True,
}, indent=2) + '\n')
print('Default discovery unchanged: 174 cases')
