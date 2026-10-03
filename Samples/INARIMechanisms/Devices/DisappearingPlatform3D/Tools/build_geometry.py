#!/usr/bin/env python3
"""Reproducible closed-solid rectangle recipe from original RGBA silhouettes.
Build-time Pillow only; runtime never loads source PNGs or sprite textures.
Adjacent equal-color runs are merged vertically, including exact alpha values.
"""
import hashlib,json
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT.parent/'DisappearingPlatform'/'Assets'
def rectangles(image):
    rows=[]; active={}
    for y in range(image.height):
        runs={}; x=0
        while x<image.width:
            color=image.getpixel((x,y)); end=x+1
            while end<image.width and image.getpixel((end,y))==color: end+=1
            if color[3]:
                key=(x,end,color)
                runs[key]=active.pop(key,[x,y,end-x,0,*color]);runs[key][3]+=1
            x=end
        rows.extend(active.values());active=runs
    rows.extend(active.values());return rows
if __name__=='__main__':
    doc=json.loads((SOURCE/'device.json').read_text());out={}
    for key,entry in doc['sprites'].items():
        path=SOURCE/entry['path']; image=Image.open(path).convert('RGBA')
        out[key]={'size':list(image.size),'offset':entry['offset'],'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'boxes':rectangles(image)}
        print(key,len(out[key]['boxes']))
    (ROOT/'Assets'/'geometry.json').write_text(json.dumps(out,separators=(',',':'))+'\n')
