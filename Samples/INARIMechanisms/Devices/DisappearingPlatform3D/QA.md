# Single-hinge mechanical revision QA

Base: `af5bcfee95d4bd8ad9cef1efff2b87623325e1e7`, feature based on Inari `6134c742`.
Tools: Godot 4.6.3 stable, Blender 4.3.2. Upstream project declares Godot 4.7.

## Passed

- Both native assets save/reload. Backplate: 12 component meshes, 104,907 bytes. Tread: 15 component meshes, 114,149 bytes; exactly one TreadBody, one hinge, and two gears. No duplicate per-frame tread assemblies.
- All 27 base and modifier-evaluated meshes are closed, positive-volume solids with no image textures.
- Fold is a real imported Blender action: 13 LINEAR keys, one X rotation channel, 0–90° over 0–0.2 seconds. Runtime seeks that action with the original game clock; meshes remain identical throughout cycles.
- Left/right gears each have 16 physical tooth crests, bores, side walls and 6.4 units axial thickness. Evaluated moving deck/gears have zero triangle intersections with frame, backing or face mounting bolts at the 13 sampled angles. Intended shaft/bearing mating surfaces are excluded from this clearance test.
- Clean imports and six probes all exit 0:
  - Legacy/workshop project: Mechanical 2,818; Standalone 21,665; Orbit 1,254 checks.
  - Renamed/nested device-only project: Mechanical 2,818; Standalone 1,689; Orbit 1,101 checks.
- Direct legacy parity covers 3,840 lifecycle samples: state, time boundary, source frame bookkeeping, alarm alpha, recovery queue and contact behavior.
- Continuous hinge movement, fixed backplate, unchanged model identities over six cycles, recovery hold continuity, independent materials/lights/cameras/worlds, repeated V/R/drag/zoom, input isolation and room teardown covered.
- Original 59-file DisappearingPlatform directory, old workshop and shared WorkshopPlayer remain unchanged.
- `git diff --check` passes.

## Visual comparison and limits

The fixed outline is traced from the original backplate alpha. Source base RGB values are reused for charcoal, teal, inset and steel. Runtime preserves each preset's artwork offset independently of the original 2D collider.

Actual Blender transparent orthographic footprint comparison at one pixel/unit, alpha >128, excluding the original ambient halo/inactive lamp, using default-preset integer alignment:
- Ready: silhouette IoU 98.17%; both bounds 160×80.
- Fully folded: silhouette IoU 98.34%; source bounds 160×100, new bounds 160×99.

Across all 13 matched source-frame positions, complete-device silhouette IoU ranges from 93.72% to 98.36%. The largest lower-edge difference is 7 pixels at the middle pose. This statistic includes the fixed backplate and must not be read as local tread-detail accuracy.

These are footprint statistics, not RGB accuracy or GPU gameplay validation. Physical materials/lighting, gear detail and intermediate linear hinge poses differ from the original discrete sprite artwork. Collision is intentionally restored before the opening animation completes, matching the original behavior.

All presentation stills and slow-motion GIF/MP4 load the real native assets and are labelled Blender inspection. The slowed video is for seeing the mechanism, not the original gameplay speed.

This environment has no active X11/Wayland display; Godot headless is a dummy renderer. Real Godot GPU visuals, alpha composition, interaction feel and target-device performance remain unverified. Use CaptureProjection in a graphical environment. Existing repository-wide FMOD/Joystick import issues are outside this change.

Publication of this revision was separately approved on the existing feature branch with `[skip ci]` to prevent its automatic build/deploy workflow. Skipped CI is not a passing CI result. No workflow configuration, branch protection, merge or deployment change is included.
