"""Compare ImportedModelProbe's CPU images against original artwork.
Usage: python Tests/compare_imported_fronts.py /path/to/imported-model-audit
Requires source repository + Pillow; this is not GPU screenshot comparison.
"""
import sys
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
files=list(Path(sys.argv[1]).glob('*.png'))
assert len(files)==16,'Expected all 16 imported mesh projections'
for file in files:
    actual=Image.open(file).convert('RGBA')
    expected=Image.open(ROOT.parent/'DisappearingPlatform'/'Assets'/file.name).convert('RGBA')
    assert actual.size==expected.size
    for a,b in zip(actual.getdata(),expected.getdata()):
        assert a==b or a[3]==b[3]==0,file.name
print('IMPORTED_BLEND_EXACT_RGBA_PASS: 16 actual imported mesh projections')
