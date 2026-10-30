#!/usr/bin/env python3
"""Bundle the repository's actual license/provenance text; --check detects drift."""
from pathlib import Path
import argparse
import json

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
asset = root / 'ios/App/Assets.xcassets/OpenSourceNotices.dataset'
text = '\n\n'.join(
    f'{name}\n\n{(root / name).read_text().strip()}'
    for name in ('NOTICE.md', 'LICENSE.txt')
) + '\n'
outputs = {
    asset / 'OpenSourceNotices.txt': text,
    asset / 'Contents.json': json.dumps({
        'data': [{'filename': 'OpenSourceNotices.txt', 'idiom': 'universal'}],
        'info': {'author': 'xcode', 'version': 1},
    }, indent=2) + '\n',
}
for path, content in outputs.items():
    if args.check:
        if not path.is_file() or path.read_text() != content:
            raise SystemExit('Bundled notices need regeneration: python3 scripts/bundle-notices.py')
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
print('Bundled license and notices match source.' if args.check else 'Bundled license and notices.')
