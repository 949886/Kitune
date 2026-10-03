"""Compare Blender 1px/unit front alpha with original source silhouettes.
Usage: python Tests/compare_mechanical_footprints.py /path/to/inspection-output
Needs original source repository + Pillow. This is NOT a Godot GPU or RGB test.
"""
import json,math,sys
from pathlib import Path
from PIL import Image,ImageChops
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT.parent/'DisappearingPlatform'/'Assets'
OUTPUT=Path(sys.argv[1]);doc=json.loads((SOURCE/'device.json').read_text())
record=doc['records']['level7_18316_0'];size=(192,160)
keys=[]
for _time,key in record['states'][1]['track']['frames']:
    if key not in keys:keys.append(key)
def source_mask(key):
    result=Image.new('1',size)
    for item in record['visuals']:
        if item['sprite'] in ['sharedassets0_446','sharedassets6_97']:continue
        selected=key if item['sprite']=='sharedassets2_1700' else item['sprite']
        entry=doc['sprites'][selected]
        alpha=Image.open(SOURCE/entry['path']).convert('RGBA').getchannel('A').point(lambda x:255 if x>128 else 0)
        overlay=Image.new('1',size)
        overlay.paste(alpha,(math.floor(96+item['transform'][4]+entry['offset'][0]+.5),math.floor(64+item['transform'][5]+entry['offset'][1]+.5)))
        result=ImageChops.logical_or(result,overlay)
    return result
def compare(path,key):
    source=source_mask(key)
    alpha=Image.open(path).convert('RGBA').getchannel('A').point(lambda x:255 if x>128 else 0).convert('1')
    native=Image.new('1',size);native.paste(alpha,(-2,5))
    pairs=list(zip(source.getdata(),native.getdata()))
    intersection=sum(bool(a) and bool(b) for a,b in pairs);union=sum(bool(a) or bool(b) for a,b in pairs)
    return {'source_key':key,'source_bbox':source.getbbox(),'native_bbox':native.getbbox(),'intersection':intersection,'union':union,'silhouette_IoU':intersection/union,'different_pixels':union-intersection}
result={'method':'Blender orthographic alpha>128, 1px/unit, versus original body+backplate alpha>128. Excludes ambient halo and inactive lamp. Integer(-2,+5)px alignment approximates exact runtime preset offset(-2.13384,+5.01617). 192x160 padded comparison canvas prevents folded-source clipping. Footprint only: no RGB, lighting, intermediate-pose or Godot GPU equivalence implied.','poses':{}}
for pose,key in [('ready',keys[0]),('folded',keys[-1])]:
    result['poses'][pose]=compare(OUTPUT/('blender-footprint-'+pose+'-192x128.png'),key)
sequence=[]
for i,key in enumerate(keys):
    file=OUTPUT/f'footprint-step-{i:02d}.png'
    if file.exists():sequence.append(compare(file,key))
if sequence:result['intermediate_samples']=sequence
(OUTPUT/'front-footprint-comparison.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
