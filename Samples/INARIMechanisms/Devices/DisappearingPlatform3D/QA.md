# Native Blender model + free orbit verification

Base: published feature commit `7ad3bb950aefcdd53369a9df7b5daad7ac97b4a3`, based on Inari `6134c742f98b3726fe06db66d8c98039ceb9e5d2`.
Tools: Godot 4.6.3 stable + Blender 4.3.2. The upstream project targets Godot 4.7.

Passed:
- Real native `Assets/DisappearingPlatform3D.blend` saved and reopened by Blender: 16 editable meshes, closed/manifold box surfaces, all front RGBA cells exactly match original nontransparent artwork.
- Clean direct `.blend` import into Godot, with all hidden poses, named palette materials, no textures and no lossy mesh compression.
- CPU front projection of all 16 actual imported meshes exactly matches source RGBA after transparent RGB normalization. This checks imported geometry/palette data, not GPU rendering.
- `geometry.json` deleted; loader preloads `.blend` and merges its imported surfaces, with no pixel-driven runtime geometry generation.
- StandaloneProbe with legacy sibling: 20,604 checks, including 3,840 lifecycle parity samples and transformed real 2D contacts.
- OrbitProbe: 1,230 checks in minimal real-workshop setup; 1,077 in relocated device-only setup. Repeated V, button drags, wheel limits, reset, teardown, per-instance isolation, exact camera/display/shadow restoration, continuing animation and blocked actor movement/attack covered.
- Original 2D device, old workshop and shared WorkshopPlayer remain unchanged.

Limits:
- No X11/Wayland service here; Godot headless uses dummy rendering. Actual Godot GPU visuals/alpha composition, mouse feel and target-device performance are not verified.
- Blender preview renders load the checked-in model and use Blender lighting. They are not game screenshots.
- Editing/importing `.blend` requires Blender configured in Godot Editor Settings. Exported games do not need Blender. Pillow is only used by optional developer regeneration/verification scripts.
- This is editable extruded pixel-relief geometry with 13 discrete mesh poses, not a continuous mechanical rig.
- Existing repository-wide Linux FMOD extension and missing Joystick-script import issues remain outside this change.

Publication policy for this revision: an explicitly approved `[skip ci]` marker avoids the repository's automatic build-and-deploy workflow. A skipped CI run is not a passing CI result. No workflow settings or branch protections are changed.
