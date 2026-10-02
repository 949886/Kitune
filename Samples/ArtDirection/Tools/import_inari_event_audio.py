"""Render the installed game's actual FMOD events, without running the game.

Uses the source FMOD runtime and banks for authored timing, mixing and random
selection. Baked variants retain those mixes at Distance_Volume=1; continuous
spatial parameters and the original random sequence are not reproduced.
"""

import ctypes as c
import hashlib
import json
from pathlib import Path
import re
import struct
import tempfile
import uuid
import wave

from import_inari import UnityPy

BANKS = ("Master", "Master.strings", "SFX_Monster", "SFX_Voice", "Snapshot")
HEADER_VERSION = 131617  # FMODUnity.dll: Studio.System.create, version 2.02.33.
SAMPLE_RATE = 48000
BUFFER_FRAMES = 512


class AdvancedSettings(c.Structure):
    """Exact x64 Core ADVANCEDSETTINGS layout from the source FMODUnity.dll."""

    _fields_ = [
        (name, c.c_int)
        for name in (
            "cbSize",
            "maxMPEGCodecs",
            "maxADPCMCodecs",
            "maxXMACodecs",
            "maxVorbisCodecs",
            "maxAT9Codecs",
            "maxFADPCMCodecs",
            "maxPCMCodecs",
            "ASIONumChannels",
        )
    ] + [
        ("ASIOChannelList", c.c_void_p),
        ("ASIOSpeakerList", c.c_void_p),
        ("vol0virtualvol", c.c_float),
        ("defaultDecodeBufferSize", c.c_uint),
        ("profilePort", c.c_ushort),
        ("geometryMaxFadeTime", c.c_uint),
        ("distanceFilterCenterFreq", c.c_float),
        ("reverb3Dinstance", c.c_int),
        ("DSPBufferPoolSize", c.c_int),
        ("resamplerMethod", c.c_int),
        ("randomSeed", c.c_uint),
        ("maxConvolutionThreads", c.c_int),
        ("maxOpusCodecs", c.c_int),
        ("maxSpatialObjects", c.c_int),
    ]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_profile(source, decompiled, profile_name):
    """Read runtime EventReference GUIDs; generated trees expect editor-only data."""
    path = source / "sharedassets1.assets"
    env = UnityPy.load(str(path))
    objects = [
        obj
        for obj in env.objects
        if obj.type.name == "MonoBehaviour"
        and obj.parse_monobehaviour_head().m_Script.read().m_ClassName == "SFXSoundProfile"
    ]
    assert len(objects) == 1
    obj = objects[0]
    raw = obj.get_raw_data()
    # Runtime MonoBehaviour: GameObject PPtr, enabled + alignment, Script PPtr.
    offset = 28

    def integer():
        nonlocal offset
        value = struct.unpack_from("<I", raw, offset)[0]
        offset += 4
        return value

    def string():
        nonlocal offset
        size = integer()
        value = raw[offset : offset + size].decode("utf8")
        offset = (offset + size + 3) & ~3
        return value

    assert string() == obj.parse_monobehaviour_head().m_Name
    code = (decompiled / "SFXSoundProfile.cs").read_text(encoding="utf8")
    fields = re.findall(r"public SerializableDictionary<string, EventReference> (\w+)", code)
    result = {}
    for field in fields:
        keys = [string() for _ in range(integer())]
        values = []
        for _ in range(integer()):
            values.append(str(uuid.UUID(bytes_le=raw[offset : offset + 16])))
            offset += 16
        assert len(keys) == len(values)
        result[field] = dict(zip(keys, values))
    assert offset == len(raw), "All serialized fields must be accounted for"
    return result[profile_name], {
        "file": path.name,
        "object_id": obj.path_id,
        "sha256": sha256(path),
    }


class EventRenderer:
    """One isolated NRT mixer per render prevents tails leaking between events."""

    def __init__(self, source, destination, seed, banks=BANKS):
        self.lib = c.CDLL(str(source / "Plugins/x86_64/fmodstudio.dll"))
        self.system = c.c_void_p()
        self.call("Studio_System_Create", c.byref(self.system), HEADER_VERSION)
        self.core = c.c_void_p()
        self.call("Studio_System_GetCoreSystem", self.system, c.byref(self.core))
        self.call("System_SetOutput", self.core, 5)  # WAVWRITER_NRT, source OUTPUTTYPE.
        self.call("System_SetDSPBufferSize", self.core, BUFFER_FRAMES, 2)
        self.call("System_SetSoftwareFormat", self.core, SAMPLE_RATE, 3, 0)  # Stereo.
        settings = AdvancedSettings()
        settings.cbSize = c.sizeof(settings)
        self.call("System_GetAdvancedSettings", self.core, c.byref(settings))
        settings.randomSeed = seed
        self.call("System_SetAdvancedSettings", self.core, c.byref(settings))
        filename = c.create_string_buffer(str(destination.resolve()).encode("utf8"))
        self.call("Studio_System_Initialize", self.system, 128, 4, 0, filename)
        for name in banks:
            bank = c.c_void_p()
            path = str(source / f"StreamingAssets/{name}.bank").encode("utf8")
            self.call("Studio_System_LoadBankFile", self.system, path, 0, c.byref(bank))
        self.master = c.c_void_p()
        self.call("System_GetMasterChannelGroup", self.core, c.byref(self.master))

    def call(self, name, *args):
        result = getattr(self.lib, "FMOD_" + name)(*args)
        if result:
            raise RuntimeError(f"FMOD {name}: result {result}")

    def clock(self):
        clock, parent = c.c_ulonglong(), c.c_ulonglong()
        self.call("ChannelGroup_GetDSPClock", self.master, c.byref(clock), c.byref(parent))
        return clock.value

    def render(self, guid, allow_timeline_loop=False):
        desc = c.c_void_p()
        raw = c.create_string_buffer(uuid.UUID(guid).bytes_le)
        self.call("Studio_System_GetEventByID", self.system, raw, c.byref(desc))
        path, retrieved = c.create_string_buffer(1024), c.c_int()
        self.call("Studio_EventDescription_GetPath", desc, path, 1024, c.byref(retrieved))
        length, one_shot = c.c_int(), c.c_int()
        self.call("Studio_EventDescription_GetLength", desc, c.byref(length))
        self.call("Studio_EventDescription_IsOneshot", desc, c.byref(one_shot))
        assert one_shot.value or (allow_timeline_loop and length.value > 0), "Looping event needs an explicit export/runtime policy"
        self.call("Studio_EventDescription_LoadSampleData", desc)
        self.call("Studio_System_FlushSampleLoading", self.system)
        instance = c.c_void_p()
        self.call("Studio_EventDescription_CreateInstance", desc, c.byref(instance))
        distance_result = self.lib.FMOD_Studio_EventInstance_SetParameterByName(
            instance, b"Distance_Volume", c.c_float(1), 1
        )
        # Player StackHit events have no Distance_Volume. The native pool also
        # attempts this assignment and ignores ERR_EVENT_NOTFOUND (RESULT 74).
        if distance_result not in (0, 74):
            raise RuntimeError(f"FMOD Distance_Volume: result {distance_result}")
        samples = []

        @c.CFUNCTYPE(c.c_int, c.c_uint, c.c_void_p, c.c_void_p)
        def callback(kind, event, sound):
            if kind == 0x2000:  # SOUND_PLAYED, parameter is the native Core Sound.
                name = c.create_string_buffer(512)
                self.call("Sound_GetName", c.c_void_p(sound), name, 512)
                samples.append(name.value.decode("utf8"))
            return 0

        self.call("Studio_EventInstance_SetCallback", instance, callback, 0x2000)
        start_clock = self.clock()
        self.call("Studio_EventInstance_Start", instance)
        state = c.c_int()
        limit_seconds = 10 if one_shot.value else length.value / 1000 + 1
        loop_frames = round(length.value * SAMPLE_RATE / 1000)
        for _ in range(int(SAMPLE_RATE * limit_seconds / BUFFER_FRAMES)):
            self.call("Studio_System_Update", self.system)
            self.call("Studio_EventInstance_GetPlaybackState", instance, c.byref(state))
            if not one_shot.value and self.clock() - start_clock >= loop_frames:
                self.call("Studio_EventInstance_Stop", instance, 1)  # IMMEDIATE, offline boundary only.
                break
            if state.value == 2:  # STOPPED.
                break
        else:
            raise RuntimeError(f"Event did not finish: {path.value!r}")
        stopped_clock = self.clock()
        # Drain output buffers so the export can verify that STOPPED really has
        # no audible tail. This drain must not extend the runtime voice lifetime.
        for _ in range(24):
            self.call("Studio_System_Update", self.system)
        self.call("Studio_EventInstance_Release", instance)
        return {
            "guid": guid,
            "path": path.value.decode("utf8"),
            "timeline_ms": length.value,
            "one_shot": bool(one_shot.value),
            "distance_parameter": distance_result == 0,
            "samples": samples,
            "pre_start_frames": start_clock,
            "playback_frames": stopped_clock - start_clock,
            "timeline_loop_frames": loop_frames if not one_shot.value else 0,
        }

    def close(self):
        self.call("Studio_System_Release", self.system)


def export(
    source, decompiled, output, variants, profile_name, events, stem, actor_code, banks=BANKS,
    timeline_loops=(),
):
    profile, provenance = read_profile(source, decompiled, profile_name)
    output.mkdir(parents=True, exist_ok=True)
    result = {
        "profile": provenance,
        "sample_rate": SAMPLE_RATE,
        "distance_volume": 1.0,
        "groups": {},
        "renders": {},
        "source_sha256": {},
    }
    for name in ["Plugins/x86_64/fmodstudio.dll", "Managed/FMODUnity.dll"]:
        result["source_sha256"][name] = sha256(source / name)
    for name in banks:
        path = f"StreamingAssets/{name}.bank"
        result["source_sha256"][path] = sha256(source / path)
    for name in ["SFXSoundProfile.cs", "FmodSfxPool.cs", actor_code]:
        result["source_sha256"][name] = sha256(decompiled / name)
    with tempfile.TemporaryDirectory(prefix=f"inari-{stem}-audio-") as temporary:
        for event, group in events.items():
            result["groups"][group] = []
            for variant in range(variants):
                raw = Path(temporary) / "event.wav"
                renderer = EventRenderer(source, raw, variant, banks)
                try:
                    info = renderer.render(profile[event], allow_timeline_loop=event in timeline_loops)
                    info["random_seed"] = variant
                finally:
                    renderer.close()
                filename = f"{group}_{variant + 1:02d}.wav"
                target = output / filename
                with wave.open(str(raw), "rb") as original:
                    params = original.getparams()
                    original.setpos(info["pre_start_frames"])
                    frames = original.readframes(original.getnframes() - original.tell())
                    assert any(frames), f"Silent render: {event}"
                    playback_bytes = info["playback_frames"] * params.nchannels * params.sampwidth
                    assert not info["one_shot"] or not any(
                        frames[playback_bytes:]
                    ), "Audible tail requires explicit support"
                    frames = frames[:playback_bytes]
                    if not info["one_shot"]:
                        frames = frames[:info["timeline_loop_frames"] * params.nchannels * params.sampwidth]
                        info["loop_export_strategy"] = "Repeat one authored timeline length; internal FMOD loop regions and release envelopes are not reconstructed."
                with wave.open(str(target), "wb") as converted:
                    converted.setparams(params)
                    converted.writeframes(frames)
                import_path = Path(str(target) + ".import")
                if import_path.exists():
                    settings = import_path.read_text(encoding="utf8")
                    settings = re.sub(r"compress/mode=\d+", "compress/mode=0", settings)
                    import_path.write_text(settings, encoding="utf8")
                info["sha256"] = sha256(target)
                info["pcm_sha256"] = hashlib.sha256(frames).hexdigest()
                info["frames"] = len(frames) // (params.nchannels * params.sampwidth)
                result["groups"][group].append(filename)
                result["renders"][filename] = info
                print(filename, info["samples"])
    (output / f"{stem}_events.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf8"
    )
