import json
import sys
from prepare import WORK, OUT, capture, check_workspace

variant = sys.argv[1] if len(sys.argv) > 1 else 'lazy'
root = WORK / variant / 'swift-cidr-admission'
capture(['swift', 'package', '--disable-automatic-resolution', 'show-dependencies', '--format', 'json'], variant + '-tests-initial-graph', root)
capture(['swift', 'package', 'edit', 'swift-cidr', '--path', WORK / variant / 'swift-cidr'], variant + '-tests-edit', root)
graph = capture(['swift', 'package', 'show-dependencies', '--format', 'json'], variant + '-tests-effective-graph', root)
(OUT / (variant + '-tests-effective-graph.json')).write_bytes(graph)
check_workspace(variant, '')
for config in ['debug', 'release']:
    log = capture(['swift', 'test', '-c', config], variant + '-tests-' + config, root)
    assert b'63 tests in 8 suites passed' in log
    check_workspace(variant, '')
if (root / 'Benchmarks/.build/workspace-state.json').exists():
    check_workspace(variant)
(OUT / (variant + '-tests-workspace-state.json')).write_text(json.dumps(check_workspace(variant, ''), indent=2) + '\n')
print('Patched admission debug/release tests completed with source and pin checks', flush=True)
