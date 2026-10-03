#!/usr/bin/env python3
"""Compare every generated front-face cell to its original RGBA source."""
import hashlib,json
from pathlib import Path
from PIL import Image
root=Path(__file__).resolve().parents[1]
source=root.parent/'DisappearingPlatform'/'Assets'
recipe=json.loads((root/'Assets'/'geometry.json').read_text())
for key,entry in recipe.items():
    path=source/(key+'.png')
    assert hashlib.sha256(path.read_bytes()).hexdigest()==entry['source_sha256'],key
    expected=Image.open(path).convert('RGBA')
    actual=Image.new('RGBA',tuple(entry['size']))
    coverage=set()
    for x,y,w,h,r,g,b,a in entry['boxes']:
        assert w>0 and h>0 and a>0
        for py in range(y,y+h):
            for px in range(x,x+w):
                assert (px,py) not in coverage,(key,px,py)
                coverage.add((px,py));actual.putpixel((px,py),(r,g,b,a))
    for a,b in zip(actual.getdata(),expected.getdata()):
        assert a==b or a[3]==b[3]==0,key
print('PLATFORM_3D_GEOMETRY_SOURCE_PASS: all 16 projected RGBA recipes match exactly')
