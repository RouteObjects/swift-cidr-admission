import gzip
import json
import re
import subprocess
from rerun import ROOTS, OUT

report = {}
for variant, base in ROOTS.items():
    obj = base / 'swift-cidr-admission/Benchmarks/.build/arm64-apple-macosx/release/CIDRAdmission.build/IPAdmissionPolicy.swift.o'
    raw = subprocess.check_output(['xcrun', 'llvm-objdump', '-dr', '--no-show-raw-insn', str(obj)])
    with gzip.open(OUT / (variant + '-policy-assembly.log.gz'), 'wb') as f:
        f.write(raw)
    lines = raw.decode().splitlines()
    starts = [i for i, line in enumerate(lines) if re.match(r'^[0-9a-f]+ <.+>:$', line)]
    selected = []
    report[variant] = {}
    for n, start in enumerate(starts):
        header = lines[start]
        kind = 'decision' if '8decision3for' in header else 'lazy-getter' if 'DecisionPeer' in header and '4host' in header else None
        if kind:
            body = '\n'.join(lines[start:starts[n+1] if n+1 < len(starts) else len(lines)]).rstrip() + '\n'
            selected.append(body)
            calls = re.findall(r'ARM64_RELOC_BRANCH26\s+(\S+)', body)
            report[variant][kind] = {'call_relocations': calls, 'static_call_sites': len(calls)}
    (OUT / (variant + '-decision-excerpt.txt')).write_text('\n'.join(selected).rstrip() + '\n')
(OUT / 'codegen.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
