"""Build the minimal Windows x64 C ABI bridge and copy exact source audio banks.

No installed Godot plugin, Python runtime or compiler is needed by copied games.
The tool uses the local MSVC compiler; vendor header retains Godot's MIT notice.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def build(source):
    root = Path(__file__).resolve().parents[3]
    package = root / 'Samples/INARIMechanisms'
    native = package / 'Core/Fmod'
    output = native / 'bin'; output.mkdir(exist_ok=True)
    temporary = root / 'tmp/art-direction/fmod-extension-build'; temporary.mkdir(exist_ok=True)
    vswhere = Path('C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe')
    installation = subprocess.check_output([str(vswhere), '-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath'], text=True).strip()
    if not installation: raise RuntimeError('MSVC C++ toolchain was not found')
    setup = Path(installation) / 'VC/Auxiliary/Build/vcvars64.bat'
    command = f'@echo off\ncall "{setup}" >nul\nif errorlevel 1 exit /b 1\ncl /nologo /LD /EHsc /std:c++17 /MT /O2 /W4 "{native / "inari_fmod.cpp"}" /link /OUT:"{output / "inari_fmod.dll"}" /IMPLIB:"{temporary / "inari_fmod.lib"}"\n'
    batch = temporary / 'build_fmod.cmd'
    batch.write_text(command, encoding='utf8')
    subprocess.run(f'cmd /d /s /c ""{batch}""', cwd=temporary, check=True)
    files = {'Plugins/x86_64/fmodstudio.dll': output / 'fmodstudio.dll'}
    banks = package / 'Assets/EnvironmentAudio/Banks'; banks.mkdir(parents=True, exist_ok=True)
    for name in ['Master', 'Master.strings', 'AMB', 'BGM', 'Snapshot']:
        files[f'StreamingAssets/{name}.bank'] = banks / f'{name}.bank'
    for name, destination in files.items(): shutil.copy2(source / name, destination)
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    manifest = dict(platform='Windows x86_64', godot_minimum='4.2', fmod_version='2.02.33',
        source_sha256={name: sha(source / name) for name in files},
        bridge_inputs={p.name: sha(p) for p in [native / 'inari_fmod.cpp', native / 'gdextension_interface.h']},
        copied_files={p.relative_to(package).as_posix(): sha(p) for p in [output / 'inari_fmod.dll', *files.values()]})
    (native / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf8', newline='\n')
    print('PORTABLE_FMOD_BUILD_PASS', output)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    build(parser.parse_args().source)
