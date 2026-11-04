import json
from prepare import WORK, OUT, capture, check_workspace

root = WORK / 'patched/swift-cidr-admission'
capture(['swift', 'package', '--disable-automatic-resolution', 'show-dependencies', '--format', 'json'], 'tests-initial-graph', root)
capture(['swift', 'package', 'edit', 'swift-cidr', '--path', WORK / 'patched/swift-cidr'], 'tests-edit', root)
graph = capture(['swift', 'package', 'show-dependencies', '--format', 'json'], 'tests-effective-graph', root)
(OUT / 'tests-effective-graph.json').write_bytes(graph)
check_workspace('patched', '')
for config in ['debug', 'release']:
    capture(['swift', 'test', '-c', config], 'patched-tests-' + config, root)
    check_workspace('patched', '')
check_workspace('patched')
(OUT / 'tests-workspace-state.json').write_text(json.dumps(check_workspace('patched', ''), indent=2) + '\n')
print('Patched admission debug/release tests completed with source and pin checks', flush=True)
