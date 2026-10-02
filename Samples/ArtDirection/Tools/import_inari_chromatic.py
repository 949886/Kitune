"""Trace the active volume and attack profile used by native weak-dash chroma."""

import argparse
import hashlib
import re
from pathlib import Path

from import_inari import UnityPy, TypeTreeGenerator, PPtr, dump


def export(source, decompiled, urp_sources, output):
    generator = TypeTreeGenerator("2022.3.62f3")
    generator.load_local_game(str(source.parent))
    env = UnityPy.load(str(source / "level1"), str(source / "sharedassets1.assets"))
    env.typetree_generator = generator
    objects = {}
    for obj in env.objects:
        if obj.type.name != "MonoBehaviour":
            continue
        script = obj.parse_monobehaviour_head().m_Script
        if script:
            objects[script.read().m_ClassName] = obj
    manager = objects["VolumeManager"]
    volume = PPtr(**manager.read_typetree()["GlobalVolume"], assetsfile=manager.assets_file).deref()
    volume_data = volume.read_typetree()
    profile = PPtr(**volume_data["sharedProfile"], assetsfile=volume.assets_file).deref()
    components = [
        PPtr(**pointer, assetsfile=profile.assets_file).deref()
        for pointer in profile.read_typetree()["components"]
    ]
    chromatic = next(
        obj
        for obj in components
        if obj.parse_monobehaviour_head().m_Script.read().m_ClassName == "ChromaticAberration"
    )
    combat = objects["PlayerCombatProfile"]
    attack = PPtr(**combat.read_typetree()["AttackProfile"], assetsfile=combat.assets_file).deref()
    info = attack.read_typetree()["AttackInfo"]
    post = (urp_sources / "PostProcessPass.cs").read_text(encoding="utf-8-sig")
    amount_scale = float(
        re.search(r"_Chroma_Params, m_ChromaticAberration.intensity.value \* ([\d.]+)f", post)[1]
    )
    parameter = (urp_sources / "VolumeParameter.cs").read_text(encoding="utf-8-sig")
    interpolation = (urp_sources / "FloatParameter.cs").read_text(encoding="utf-8-sig")
    assert re.search(r"void Override\(T x\).*?m_Value = x;", parameter, re.S)
    assert "m_Value = from + (to - from) * t;" in interpolation
    wait = (decompiled / "MyWaitForUpdate.cs").read_text(encoding="utf8")
    assert "if (!done)" in wait and "done = true;" in wait and "return true;" in wait
    data = chromatic.read_typetree()
    evidence = {
        "profile": profile.read_typetree()["m_Name"],
        "component_id": chromatic.path_id,
        "active": bool(data["active"]),
        "initial_intensity": data["intensity"]["m_Value"],
        "volume_weight": volume_data["weight"],
        "attack_profile_id": attack.path_id,
        "duration": info["ChromaticAberrationTime"],
        "intensity": info["ChromaticAberrationIntensity"],
        "shader_amount_scale": amount_scale,
        "override_bypasses_clamp": True,
        "wait_polls": 2,
        "clock": "MonoBehaviour coroutine: unscaled by INARI TimeManager",
        "shader_source": "https://github.com/Unity-Technologies/Graphics/blob/2022.3/staging/Packages/com.unity.render-pipelines.universal/Shaders/PostProcessing/UberPost.shader",
        "source_sha256": {},
    }
    files = [
        source / name
        for name in [
            "level1",
            "sharedassets1.assets",
            "Managed/Assembly-CSharp.dll",
            "Managed/Unity.RenderPipelines.Core.Runtime.dll",
            "Managed/Unity.RenderPipelines.Universal.Runtime.dll",
        ]
    ]
    files += [
        decompiled / name
        for name in ["PlayerDashAttackState.cs", "PlayerStateMachine.cs", "MyWaitForUpdate.cs"]
    ]
    files += [
        urp_sources / name
        for name in [
            "PostProcessPass.cs",
            "VolumeParameter.cs",
            "FloatParameter.cs",
            "ClampedFloatParameter.cs",
            "ChromaticAberration.cs",
        ]
    ]
    for path in files:
        evidence["source_sha256"][path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    dump(output / "chromatic.json", evidence)
    print("Native chroma:", evidence["intensity"], evidence["duration"], "scale", amount_scale)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    parser.add_argument("urp_sources", type=Path)
    args = parser.parse_args()
    export(
        args.data_directory,
        args.decompiled_directory,
        args.urp_sources,
        Path(__file__).resolve().parents[1] / "Original/INARI",
    )
