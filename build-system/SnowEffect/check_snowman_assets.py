#!/usr/bin/env python3
"""Targeted asset check; developer dependency: Pillow. Does not edit images."""
import json
import re
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / 'submodules/TelegramUI/Images.xcassets'
PROVENANCE = ROOT / 'submodules/SnowEffect/Resources/SnowmenV2'


def main():
    manifest = json.loads((PROVENANCE / 'manifest.json').read_text())
    assert manifest['version'] == 2
    expected = {key for key, value in manifest['presets'].items() if 'star_gold' not in value['layers']}
    actual = {p.name.removeprefix('SnowmanReady_').removesuffix('.imageset')
              for p in CATALOG.glob('SnowmanReady_*.imageset') if not p.name.endswith('_Full.imageset')}
    assert actual == expected
    images = 0
    for name in expected:
        for full in (False, True):
            folder = CATALOG / ('SnowmanReady_' + name + ('_Full' if full else '') + '.imageset')
            contents = json.loads((folder / 'Contents.json').read_text())
            assert {r['scale'] for r in contents['images']} == ({'1x'} if full else {'1x', '2x', '3x'})
            for row in contents['images']:
                path = folder / row['filename']
                with Image.open(path) as image:
                    size = 512 if full else 60 * int(row['scale'][0])
                    assert image.mode == 'RGBA' and image.size == (size, size), path
                    alpha = image.getchannel('A')
                    bbox = alpha.getbbox()
                    assert alpha.getextrema()[0] == 0 and bbox, path
                    assert bbox[0] > 0 and bbox[1] > 0 and bbox[2] < size and bbox[3] < size, path
                images += 1
    policy = (ROOT / 'submodules/SnowEffect/Sources/WinterSnowmanAppearance.swift').read_text()
    selectable = re.findall(r'case \w+ = "(\d\d_[a-z_]+)"', policy)
    assert set(selectable) == {'01_classic_red', '05_santa_blue_scarf'}
    assert set(selectable) <= expected
    resources = (ROOT / 'submodules/SnowEffect/Sources/WinterSnowmanResources.swift').read_text()
    assert {int(i) for i in re.findall(r'texture = (\d+)', resources)} == set(range(1, 11))
    assert 'SnowHatConfiguration' not in resources
    print(f'OK: {images} RGBA PNGs, 16 image sets, 2 completed-state presets, 10 preserved hat texture mappings; no festive/stage selection.')


if __name__ == '__main__':
    main()
