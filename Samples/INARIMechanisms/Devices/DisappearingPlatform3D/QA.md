# Panel surface and demo resize revision: local validation complete

This revision evaluates all 13 source poses, not only READY. Source main panel:96x57;4px side frame; two1px inset rings;84x49 mottled field;78 perimeter rivet pixels. The previous untextured inset/five ribs omitted those features.

The real closed tread now uses one packed surface albedo and physical inset geometry. Source-derived easing changes the13 native hinge angle keys while preserving state/collision timings. The default palette copy uses nearest sampling. No sprite plane or per-pose mesh/image swapping is introduced.

Actual graphical Godot rendering remains unavailable in this execution environment. Source-vs-Blender reference sheets are labelled explicitly and contain no user screenshots. Prior results below apply to their corresponding historical revision.

## Current verification

- Fixed HingeCover is a closed 96-wide annular sleeve (outer radius 4, bore 3.4); moving body/hinge leaves have a 4.15-radius coaxial clearance notch. It remains under Backplate while the tread rotates. The original READY front edge naturally occludes it, then the teal cover is exposed.
- One opaque packed image per native file: Backplate 96x8 source strip; Tread 96x58 source panel. No external image dependency or per-pose image swapping. Import UVs are enabled, image unpacking disabled, and animation optimizer disabled to retain all 13 native keys.
- Clean legacy/workshop project import: no errors. Mechanical 4,170; Standalone 21,249; Orbit 1,254; DemoResize 2,415 checks pass.
- Clean renamed/nested standalone import: no errors. Mechanical 4,170; Standalone 1,273; Orbit 1,101; DemoResize 1,019 pass.
- Resize probe covers 9 sizes (including 1478x831,1920x1080,800x1200,2560x720 and 160x120), repeated changes, dragging during resize, release/V/R, HUD bounds, opaque full-view background, world aspect/center and node teardown. Headless geometry/input validation only.
- All 26 base/evaluated component meshes are closed with positive volume. 101 sampled hinge poses have zero moving-vs-fixed-cover intersections, including shaft/leaves/gears. Existing frame clearance checks pass.
- All 862 opaque READY rail pixels retain their source positions/RGB. Full-fold central region RGB MAE 0.417/255 in the actual Blender unlit reference; READY 0.404. Early moving-frame MAE reaches 46.507/255 due remaining stripe placement/handdrawn brightness differences. These are local panel figures, excluding gears and static backplate; they are not Godot GPU results or whole-animation equivalence.
- The 13 source/model bottom-cell edges match at 1 pixel/unit:5,7,9,19,34,43,53,56,59,60,60,60,60. All 13 source-vs-model poses were viewed.
- Original DisappearingPlatform 59 files, old workshop and shared player remain unchanged.
- Final Backplate 162,289 bytes; Tread 204,800 bytes. Actual graphical Godot output and target-device interaction feel remain to be verified.

## Previous front-only correction

# Front appearance correction: local checks passed, graphical verification pending

The user-supplied actual gameplay screenshot demonstrated that the prior full-device alpha IoU was insufficient. It hid incorrect backplate RGB/detail, undersized gears and missing local rail color bands. Historical results below describe the previous published assets, not acceptance of the revised appearance.

- Source READY is an edge-on 96x9 visible rail, not the opaque-looking hidden RGB above/below the alpha mask. Axis conversion and per-preset hinge registration were correct.
- Source gears are 8x42 projected units; previous actual imported gears were 6.4x24.9726.
- Source backplate has 9,812 black opaque pixels and very dark outlined compartments, modulated by 0.7264; previous model incorrectly reused tread charcoal and PBR lighting.
- Gameplay now uses per-instance unshaded palette copies. V inspection restores native lit materials. Exit and R restore the same gameplay palette resources.
- Idle warning alpha is zero in the original. A missing red lamp in READY is expected; the first lit event is approximately 0.2167 seconds after activation.
- Existing Xorg cannot create local/unix listening sockets in this environment. Explicit headless + opengl3 still calls dummy texture storage and returns no image. No software was installed and no network/security settings were altered. Blender references are not Godot captures.
- CaptureProjection now records original2D and revised3D side-by-side when the original device exists in the same project. Actual graphical validation remains required.

- Revised native assets use one 13-component backplate and one 15-component tread. The source-colored rail remains one closed, 2-unit-deep structural lip with per-face materials; frame compartment marks are merged closed raised struts, not sprites or per-pixel nodes.
- New gameplay/orbit material checks verify shared imports are never mutated, repeated enter/exit returns identical palette resources, reset restores palette, and another instance stays unchanged.

## Revised local validation

- Clean native import in legacy/workshop and renamed device-only projects: no import/script errors.
- Legacy/workshop: Mechanical 3,528; Standalone 22,096; Orbit 1,254 checks passed.
- Renamed/nested device-only: Mechanical 3,528; Standalone 2,120; Orbit 1,101 checks passed.
- Mechanical checks now assert imported black frame RGB, 96x9 rail bounds, source silver/teal bands, 42-unit solid gear diameter and 8-unit axial width. These are resource/geometry assertions, not GPU image comparisons.
- Original 59-file DisappearingPlatform remains byte-identical to Inari.
- Final Backplate 146,505 bytes; Tread 173,471 bytes. Native reload/manifold-positive-volume checks pass. 13 sampled hinge poses have no moving/fixed BVH triangle intersections; intended bearing/shaft mating excluded.
- Blender unlit front reference is materially closer to source local proportions and colors. It still has renderer-specific antialiasing, and neither it nor historical alpha IoU establishes Godot gameplay appearance.

## Historical published-version QA (superseded appearance)

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
