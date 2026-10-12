#!/usr/bin/env python3
"""Regenerate invented contract/policy fixtures against a separate web checkout."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--web-root', required=True, type=Path)
args = parser.parse_args()
web = args.web_root.expanduser().resolve()
native = Path(__file__).resolve().parents[1]
runner = web / 'node_modules/.bin/vite-node'
if not runner.is_file() or not (web / 'src/lib/server/gradebook-adapter.ts').is_file():
    parser.error('Use an installed Grademaxxing web checkout (run npm ci there first).')
jobs = [
    ('emit-contract-fixture.ts', [], 'gradebook'),
    ('emit-contract-fixture.ts', ['--attendance'], 'attendance'),
    ('emit-contract-fixture.ts', ['--documents'], 'documents'),
    ('emit-contract-fixture.ts', ['--mailbox'], 'mailbox'),
    ('emit-contract-fixture.ts', ['--message'], 'message'),
    ('emit-grade-policy-fixture.ts', [], 'gpa-policy'),
    ('emit-assignment-fixture.ts', [], 'assignment-policy'),
]
# Two levels below the web root preserves the generators' relative imports.
# Temporary synthetic tooling is removed on success and failure.
outputs = {}
with tempfile.TemporaryDirectory(prefix='.native-fixtures-', dir=web) as temporary:
    scripts = Path(temporary) / 'scripts'
    scripts.mkdir()
    for name in {job[0] for job in jobs}:
        shutil.copy2(native / 'scripts' / name, scripts / name)
    for name, flags, output in jobs:
        result = subprocess.run([str(runner), str(scripts / name), *flags], cwd=web,
                                check=True, capture_output=True, text=True)
        outputs[output] = json.loads(result.stdout)
for name, value in outputs.items():
    destination = native / 'Tests/GrademaxxingCoreTests/Fixtures' / (name + '.json')
    destination.write_text(json.dumps(value, indent='\t', ensure_ascii=False) + '\n')
print('Regenerated seven synthetic fixtures against the selected web checkout.')
