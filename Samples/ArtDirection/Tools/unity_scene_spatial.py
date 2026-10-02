"""Recover Unity world depth and the persistent gameplay camera from source data."""

from __future__ import annotations

import hashlib
from functools import cache

import UnityPy
from UnityPy.helpers.TypeTreeHelper import TypeTreeConfig, read_value
from UnityPy.streams import EndianBinaryReader
from unity_camera_impulse import camera_impulses


class WorldTransforms:
    """Compose full TRS matrices, including rotations around X and Y."""

    def __init__(self, transforms):
        self.transforms = transforms

    @cache
    def matrix(self, transform_id):
        if not transform_id:
            return [[float(row == column) for column in range(4)] for row in range(4)]

        transform = self.transforms[transform_id]
        q = transform["m_LocalRotation"]
        x, y, z, w = (q[axis] for axis in ("x", "y", "z", "w"))
        scale = transform["m_LocalScale"]
        position = transform["m_LocalPosition"]

        rotation = [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
        local = [
            [rotation[row][column] * scale[axis] for column, axis in enumerate("xyz")]
            + [position["xyz"[row]]]
            for row in range(3)
        ]
        local.append([0, 0, 0, 1])

        parent = self.matrix(transform["m_Father"]["m_PathID"])
        return [
            [sum(parent[row][k] * local[k][column] for k in range(4)) for column in range(4)]
            for row in range(4)
        ]

    def sprite_plane(self, transform_id, pixels_per_unit):
        world = self.matrix(transform_id)
        # A parallel plane has one depth for every sprite pixel. Tilted planes
        # require a perspective-correct quad, so mark them instead of flattening.
        parallel = abs(world[2][0]) < 1e-6 and abs(world[2][1]) < 1e-6
        result = {
            "depth": world[2][3],
            "parallel": parallel,
            "transform": [
                world[0][0],
                -world[1][0],
                -world[0][1],
                world[1][1],
                world[0][3] * pixels_per_unit,
                -world[1][3] * pixels_per_unit,
            ],
        }
        if not parallel:
            # Local sprite coordinates are pixels with Y pointing down. Depth
            # stays in Unity units, matching the native camera clipping planes.
            result["depth_gradient"] = [
                world[2][0] / pixels_per_unit,
                -world[2][1] / pixels_per_unit,
            ]
        return result


class SceneSpatial:
    """Apply the shipped water-camera follower before exporting visual planes."""

    def __init__(self, objects, transforms):
        self.transforms = transforms
        runtime_transforms = dict(transforms)
        by_go = {t["m_GameObject"]["m_PathID"]: tid for tid, t in transforms.items()}
        self.followers = set()

        for obj in objects:
            if obj.type.name != "MonoBehaviour":
                continue
            head = obj.parse_monobehaviour_head()
            if head.m_Script.read().m_ClassName != "WaterCameraController":
                continue

            data = obj.read_typetree()
            if not data.get("m_Enabled", True):
                continue
            tid = by_go[head.m_GameObject.path_id]
            transform = transforms[tid]
            if transform["m_Father"]["m_PathID"]:
                raise ValueError("Water camera world-space follower needs a root transform")

            # WaterCameraController.FixedUpdate assigns (mainCamera.x, offset.x,
            # offset.y). Store X relative to the camera; Y and Z are world values.
            runtime_transforms[tid] = dict(transform)
            runtime_transforms[tid]["m_LocalPosition"] = {
                "x": 0,
                "y": data["offset"]["x"],
                "z": data["offset"]["y"],
            }
            self.followers.add(tid)

        self.world = WorldTransforms(runtime_transforms)

    def sprite_plane(self, transform_id, pixels_per_unit):
        result = self.world.sprite_plane(transform_id, pixels_per_unit)
        tid = transform_id
        while tid:
            if tid in self.followers:
                result["follow_camera_x"] = True
                break
            tid = self.transforms[tid]["m_Father"]["m_PathID"]
        return result


def read_virtual_camera(obj, generator):
    head = obj.parse_monobehaviour_head()
    script = head.m_Script.read()
    node = generator.get_nodes_up(
        script.m_AssemblyName, script.m_Namespace + "." + script.m_ClassName
    )

    # The generated schema omits MonoBehaviour's enabled-byte alignment and
    # labels string[] as string. Read the corrected tree with the Python reader;
    # the accelerated reader retains the uncorrected interpretation.
    for child in node.m_Children:
        if child.m_Name == "m_Enabled":
            child.m_MetaFlag = (child.m_MetaFlag or 0) | 0x4000
        elif child.m_Name == "m_ExcludedPropertiesInInspector":
            child.m_Type = "vector"

    reader = EndianBinaryReader(obj.get_raw_data(), endian=obj.reader.endian)
    data = read_value(node, reader, TypeTreeConfig(True, obj.assets_file, False))
    if reader.Position != obj.byte_size:
        raise ValueError("Virtual camera schema did not consume the complete source object")
    return data


def gameplay_camera(source, generator):
    """Follow CameraShakeManager's actual reference, not a scene's water camera."""
    path = source / "level1"
    env = UnityPy.load(str(path))
    env.typetree_generator = generator
    objects = {obj.path_id: obj for obj in env.objects}

    for obj in objects.values():
        if obj.type.name != "MonoBehaviour":
            continue
        if obj.parse_monobehaviour_head().m_Script.read().m_ClassName != "CameraShakeManager":
            continue

        manager = obj.read_typetree()
        camera_obj = objects[manager["vCam"]["m_PathID"]]
        camera = read_virtual_camera(camera_obj, generator)
        owner = objects[camera["m_ComponentOwner"]["m_PathID"]].read_typetree()
        owner_go = owner["m_GameObject"]["m_PathID"]

        for component in objects.values():
            if component.type.name != "MonoBehaviour":
                continue
            head = component.parse_monobehaviour_head()
            if head.m_GameObject.path_id != owner_go:
                continue
            if head.m_Script.read().m_ClassName != "CinemachineFramingTransposer":
                continue

            framing = component.read_typetree()
            follow = objects[camera["m_Follow"]["m_PathID"]].read_typetree()
            follow_go = objects[follow["m_GameObject"]["m_PathID"]].read_typetree()
            transforms = {
                item.path_id: item.read_typetree()
                for item in objects.values()
                if item.type.name == "Transform"
            }
            camera_transform = next(
                item
                for item in transforms.values()
                if item["m_GameObject"]["m_PathID"] == camera["m_GameObject"]["m_PathID"]
            )
            output_go = transforms[camera_transform["m_Father"]["m_PathID"]]["m_GameObject"][
                "m_PathID"
            ]
            return {
                "source": "level1",
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "virtual_camera": camera_obj.path_id,
                "lens": camera["m_Lens"],
                "distance": framing["m_CameraDistance"],
                "tracked_offset": framing["m_TrackedObjectOffset"],
                "screen_position": [framing["m_ScreenX"], framing["m_ScreenY"]],
                "damping": [framing["m_XDamping"], framing["m_YDamping"], framing["m_ZDamping"]],
                "impulses": camera_impulses(source, obj, output_go, objects),
                "framing": {
                    k: v
                    for k, v in framing.items()
                    if k not in ("m_GameObject", "m_Enabled", "m_Script", "m_Name")
                },
                "follow": {
                    "transform": camera["m_Follow"]["m_PathID"],
                    "game_object": follow_go["m_Name"],
                },
                "implementation_sha256": hashlib.sha256(
                    (source / "Managed/Cinemachine.dll").read_bytes()
                ).hexdigest(),
            }

    raise ValueError("Persistent gameplay camera or its framing component was not found")
