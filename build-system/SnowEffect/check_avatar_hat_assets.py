#!/usr/bin/env python3
"""Validate existing atlas alpha bounds/crop metadata, without rendering UIKit."""
import json
import re
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
geometry = (ROOT / 'submodules/SnowEffect/Sources/SnowHatGeometry.swift').read_text()
folder = ROOT / 'submodules/TelegramUI/Images.xcassets/SnowHatSprite.imageset'
assert any(i.get('filename') == 'SnowHatSprite.png' for i in json.loads((folder / 'Contents.json').read_text())['images'])
im = Image.open(folder / 'SnowHatSprite.png')
assert im.mode == 'RGBA' and im.size == (1536, 1024)
regions = [tuple(map(int, r)) for r in re.findall(r'CGRect\(x: (\d+), y: (\d+), width: (\d+), height: (\d+)\)', geometry)]
assert len(regions) == 10
cells = [(0, 90, 312, 380), (312, 90, 308, 380), (620, 90, 292, 380), (912, 90, 303, 380), (1215, 90, 321, 380), (0, 550, 312, 370), (312, 550, 308, 370), (620, 550, 288, 370), (908, 550, 307, 370), (1215, 550, 321, 370)]
for index, ((x, y, w, h), (cx, cy, cw, ch)) in enumerate(zip(regions, cells), 1):
    alpha = im.crop((cx, cy, cx + cw, cy + ch)).getchannel('A')
    actual = alpha.point(lambda a: 255 if a > 16 else 0).getbbox()
    assert actual, index
    ax, ay, bx, by = actual
    assert (cx + ax, cy + ay, bx - ax, by - ay) == (x, y, w, h), index
    assert 0 <= x - 3 < x + w + 3 <= im.width and 0 <= y - 3 < y + h + 3 <= im.height, index
    assert alpha.getpixel((cw // 2, ch - 5)) <= 16, index
print('PASS: 10 measured alpha bounds, guarded crops, transparent openings and catalog link')
