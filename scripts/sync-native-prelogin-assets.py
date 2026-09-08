#!/usr/bin/env python3
"""Copy approved embedded artwork into native image catalogs, without editing its pixels."""
from pathlib import Path
from html.parser import HTMLParser
import base64, hashlib, json

workspace = Path(__file__).resolve().parents[2]
source = workspace / 'good-copy-welcome.html'
class Images(HTMLParser):
    def __init__(self):
        super().__init__(); self.images = {}
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'img':
            for name in ['wLogo']:
                if name in attrs.get('class', '').split():
                    self.images[name] = attrs['src']

parser = Images(); parser.feed(source.read_text())
manifest = {}
for key, name in [('wLogo', 'NativePreloginLogo')]:
    uri = parser.images[key]
    assert uri.startswith('data:image/png;base64,')
    data = base64.b64decode(uri.split(',', 1)[1], validate=True)
    ios = workspace / f'Poplur2025-iOS/Poplur2025/Assets.xcassets/{name}.imageset'
    android = workspace / 'Poplur2025-Android/app/src/main/assets/native-prelogin'
    ios.mkdir(parents=True, exist_ok=True); android.mkdir(parents=True, exist_ok=True)
    (ios / f'{name}.png').write_bytes(data)
    (ios / 'Contents.json').write_text(json.dumps({'images': [{'filename': f'{name}.png', 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
    (android / f'{name}.png').write_bytes(data)
    manifest[name] = hashlib.sha256(data).hexdigest()
print(json.dumps({'source': source.name, 'images': manifest}, indent=2))
