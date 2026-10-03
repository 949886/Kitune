# Verification record

Base: Inari `6134c742f98b3726fe06db66d8c98039ceb9e5d2`.
Engine available: Godot 4.6.3 stable; upstream project targets 4.7.

Passed:
- Clean isolated project import and runtime parse.
- StandaloneProbe: 20,604 checks with a legacy sibling, including 3,840 sampled lifecycle parity points.
- StandaloneProbe: 628 checks with only this device, moved and renamed to a nested folder.
- All 16 geometry recipes match original nontransparent RGBA pixels exactly, including per-pixel alpha and no overlaps.
- Real transformed 2D physics contacts: top activation, underside and sides excluded, dead actor excluded, fall through on disappearance, weak-reference teardown.
- Independent World3D, camera/material/mesh ownership, geometry thickness, no source textures in 3D materials.
- CaptureProjection explicitly exits 2 with an explanatory error on dummy headless renderer.
- New repository workshop loads and runs headless; unrelated existing Linux FMOD extension emits load warnings.
- Original device and original workshop bytes unchanged.

Blocked / not claimed:
- Godot GPU-rendered visual QA, exact final pixels/alpha and performance. This machine has no active X11/Wayland display and headless supports only dummy rendering.
- Full repository import is not a clean pass: existing FMOD extension has no Linux binary and TouchUI references missing Game/UI/Joystick scripts. These existing files were not changed for this device.
- Blender inspection output is a real geometry render, with thresholded alpha and no large soft shadow. It is not a screenshot of the game.

Run CaptureProjection and the workshop in the target Godot 4.7 graphics environment before approving final visual equivalence.
