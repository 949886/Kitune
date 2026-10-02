"""Read CameraShakeManager's referenced impulse prefabs and raw noise profiles."""

import hashlib

from UnityPy.classes import PPtr

# CameraShakeType from the shipped Assembly-CSharp.dll, in serialized enum order.
SHAKE_TYPES = (
    "None",
    "Attack",
    "Damaged",
    "ShurikenDash",
    "ShurikenStack1",
    "ShurikenStack2",
    "ShurikenStack3",
    "InteractiveWall",
    "MovingPlatformTrigger",
    "ShurikenDispenser",
    "CashPack",
    "ShurikenDashDie",
    "StrongAttack",
)


def camera_impulses(source, manager_obj, camera_go, objects):
    manager = manager_obj.read_typetree()
    if manager["m_GameObject"]["m_PathID"] != camera_go:
        raise ValueError("CameraShakeManager must share the output camera transform")
    entries = {}
    source_files = {"level1", "Managed/Cinemachine.dll", "Managed/Assembly-CSharp.dll"}
    for kind, reference in zip(manager["camShake"]["keys"], manager["camShake"]["values"]):
        obj = PPtr(**reference, assetsfile=manager_obj.assets_file).deref()
        data = obj.read_typetree()
        definition = data["m_ImpulseDefinition"].copy()
        raw = PPtr(**definition.pop("m_RawSignal"), assetsfile=obj.assets_file).deref()
        noise = raw.read_typetree()
        source_files.update((obj.assets_file.name, raw.assets_file.name))

        # These source profiles use cosine oscillators, with no Perlin channels
        # or orientation noise. Fail explicitly if an updated game changes that.
        if definition["m_ImpulseType"] != 3 or noise["OrientationNoise"]:
            raise ValueError("Only the shipped positional legacy impulses are supported")
        for octave in noise["PositionNoise"]:
            for axis, channel in octave.items():
                if channel["Amplitude"] and (not channel["Constant"] or axis == "Z"):
                    raise ValueError("Unexpected Perlin or depth impulse channel")
        entries[SHAKE_TYPES[kind]] = {
            "source_id": obj.path_id,
            "noise_id": raw.path_id,
            "noise_name": noise["m_Name"],
            "definition": definition,
            "velocity": data["m_DefaultVelocity"],
            "position_noise": noise["PositionNoise"],
        }

    listener = None
    for obj in objects.values():
        if obj.type.name != "MonoBehaviour":
            continue
        head = obj.parse_monobehaviour_head()
        if head.m_Script.read().m_ClassName == "CinemachineImpulseListener":
            listener = obj.read_typetree()
            break
    if listener is None:
        raise ValueError("Gameplay impulse listener not found")
    return {
        "entries": entries,
        "listener": {
            key: value
            for key, value in listener.items()
            if key not in ("m_GameObject", "m_Enabled", "m_Script", "m_Name")
        },
        # GameSettingData starts at Full; GameSettingManager maps Full/Half/Off.
        "strengths": {"Full": 1.0, "Half": 0.5, "Off": 0.0},
        "default_setting": "Full",
        "source_sha256": {
            name: hashlib.sha256((source / name).read_bytes()).hexdigest()
            for name in sorted(source_files)
        },
    }
