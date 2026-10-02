"""Audit non-scene serialized assets for source-derived mechanism candidates.

Absence in this inventory is evidence about this installed build, not proof that
the corresponding C# class is unusable or absent from other game versions.
"""

import argparse
import hashlib
from pathlib import Path
from import_inari import UnityPy, dump
from import_inari_mechanism_catalog import source_types


def export(source, decompiled, output):
    candidates = source_types(decompiled)
    seen, records, errors, hashes = set(), [], [], {}
    paths = sorted(source.glob("*.assets")) + sorted(
        (source / "StreamingAssets/aa").rglob("*.bundle")
    )
    for path in paths:
        relative = path.relative_to(source).as_posix()
        hashes[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        for obj in UnityPy.load(str(path)).objects:
            key = (obj.assets_file.name, obj.path_id)
            if key in seen or obj.type.name != "MonoBehaviour":
                continue
            seen.add(key)
            try:
                header = obj.parse_monobehaviour_head()
                name = header.m_Script.read().m_ClassName
                if name not in candidates:
                    continue
                records.append(
                    {
                        "file": relative,
                        "asset": obj.assets_file.name,
                        "id": str(obj.path_id),
                        "go": str(header.m_GameObject.path_id),
                        "type": name,
                        "name": (
                            header.m_GameObject.read().m_Name if header.m_GameObject.path_id else ""
                        ),
                    }
                )
            except Exception as error:
                errors.append({"file": relative, "id": str(obj.path_id), "error": str(error)})
    dump(
        output,
        {
            "scope": "All installed root .assets files and Addressables bundles; scene components are inventoried separately.",
            "candidates": sorted(candidates),
            "records": records,
            "errors": errors,
            "source_sha256": hashes,
        },
    )
    print(
        "Asset files:",
        len(paths),
        "candidate records:",
        len(records),
        "decode errors:",
        len(errors),
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_directory", type=Path)
    parser.add_argument("decompiled_directory", type=Path)
    args = parser.parse_args()
    export(
        args.data_directory,
        args.decompiled_directory,
        Path(__file__).resolve().parents[1] / "Original/INARI/mechanism_asset_audit.json",
    )
