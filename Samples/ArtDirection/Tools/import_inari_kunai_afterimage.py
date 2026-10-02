"""Export the AfterimageEmitter attached to ShurikenObject.TrailEffect."""

import argparse
import hashlib
from pathlib import Path

from import_inari import Importer, UnityPy, TypeTreeGenerator, PPtr, dump


def export(source, decompiled, output):
    env = UnityPy.load(str(source / "sharedassets1.assets"))
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    env.typetree_generator = generator
    kunai = next(
        obj
        for obj in env.objects
        if obj.type.name == "MonoBehaviour"
        and obj.parse_monobehaviour_head().m_Script.read().m_ClassName == "ShurikenObject"
    )
    state = kunai.read_typetree()
    trail = PPtr(**state["TrailEffect"], assetsfile=kunai.assets_file)
    components = [
        PPtr(**entry["component"], assetsfile=trail.assetsfile).deref()
        for entry in trail.read_typetree()["m_Component"]
    ]
    emitter = next(
        obj
        for obj in components
        if obj.type.name == "MonoBehaviour"
        and obj.parse_monobehaviour_head().m_Script.read().m_ClassName == "AfterimageEmitter"
    )
    data = emitter.read_typetree()
    assert data["Target"] == state["spriteRenderer"]
    assert not data["stopWhenTargetInvisible"] and not data["useUnscaledTime"]
    material = PPtr(**data["overrideMaterial"], assetsfile=emitter.assets_file)
    importer = Importer.__new__(Importer)
    importer.output = output
    importer.materials, importer.material_details, importer.texture_assets = {}, {}, {}
    importer.material(material)
    material_data = importer.material_details[material.read().m_Name]
    ghost = (decompiled / "AfterimageGhost.cs").read_text(encoding="utf8")
    emitter_code = (decompiled / "AfterimageEmitter.cs").read_text(encoding="utf8")
    assert "public float startAlpha = 0.7f;" in ghost and "public float life = 0.2f;" in ghost
    assert "_fadeCo = StartCoroutine(Fade());" in ghost
    assert emitter_code.index("obj.AddComponent<AfterimageGhost>()") < emitter_code.index(
        "afterimageGhost.startAlpha = startAlpha;"
    )
    fields = [
        "spawnInterval",
        "useDistanceGate",
        "minDistance",
        "life",
        "startAlpha",
        "alphaOverLife",
        "useUnscaledTime",
        "sortingOrderOffset",
        "stopWhenTargetInvisible",
    ]
    files = {
        name: source / name
        for name in [
            "sharedassets1.assets",
            material.deref().assets_file.name,
            "Managed/Assembly-CSharp.dll",
        ]
    }
    files.update(
        {name: decompiled / name for name in ["AfterimageEmitter.cs", "AfterimageGhost.cs"]}
    )
    dump(
        output / "kunai_afterimage.json",
        {
            **{key: data[key] for key in fields},
            "material": material_data,
            "first_update_defaults": {"startAlpha": 0.7, "life": 0.2},
            "source_sha256": {
                name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in files.items()
            },
        },
    )
    print("Native afterimage:", data["spawnInterval"], data["startAlpha"], material.read().m_Name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    export(
        args.data_directory,
        args.decompiled_directory,
        Path(__file__).resolve().parents[1] / "Original/INARI",
    )
