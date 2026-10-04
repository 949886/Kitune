# Projection3D

A reusable `@tool` `Node2D` that projects an arbitrary `Node3D` scene into 2D.
It has no dependencies on the surrounding platform sample, its mechanics, controls,
assets, physics, or animation scripts. Copy this entire folder into another Godot
4.6+ project to use it independently.

## Quick start

1. Instance `Projection3D.tscn`, or attach `Projection3D.gd` to a `Node2D`.
2. Assign a `PackedScene` with a `Node3D` root to **scene**.
3. Set **camera_size**, **camera_position**, **sprite_position**, and
   **viewport_size** to frame it. **scene_transform** transforms a wrapper around
   the injected scene, preserving its root's authored transform.
4. The Inspector and 2D editor preview update automatically. No child-node setup,
   viewport texture paths, scene ownership changes, or editor plugin is needed.

Open/run `Examples/BoxProjection2D.tscn` for the independent minimal example. Its
only content is `Examples/BoxScene3D.tscn`, which uses a built-in `BoxMesh` and
material. It requires no Blender imports, sample data, or project autoloads.

## Stored configuration

- **Content:** `scene: PackedScene` (null is valid),
  `scene_transform: Transform3D = Transform3D.IDENTITY`.
- **Viewport:** `viewport_size = Vector2i(169, 109)`,
  `viewport_update_mode = SubViewport.UPDATE_WHEN_VISIBLE`.
- **Camera:** `camera_size = 109`,
  `camera_position = Vector3(-2.5, -15.5, 500)`,
  `camera_rotation = Vector3.ZERO`, `camera_keep_aspect = Camera3D.KEEP_HEIGHT`,
  `camera_near = 0.05`, `camera_far = 1000`. Rotation is in radians and projection
  is always orthographic. Invalid sizes are clamped; invalid clip ordering reports
  an editor warning and clamps the effective far plane without changing the
  exported settings.
- **Sprite:** `sprite_position = Vector2(-87, -39)`, `sprite_centered = false`,
  `sprite_texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST`.
- **Environment:** optional `environment: Environment` template. Each projection
  receives a deep private copy, including its nested resources. Without a template,
  a fresh environment uses clear background, color ambient light
  `Color(0.68, 0.74, 0.8)` and ambient energy `0.8`.
- **Key light:** `light_rotation` defaults to -25° X / -30° Y (stored in radians),
  `light_color = Color.WHITE`, `light_energy = 1.1`,
  `light_shadow_enabled = false`.

The viewport always has a transparent background, disabled GUI input, and an
independent `World3D`. Every instance owns its environment, world, viewport and
viewport texture. Injected scene resources otherwise follow normal Godot
`PackedScene` rules: enable **Local To Scene** on any mesh/material/resource that
its own scripts will mutate separately per instance. The box example does this.

## Runtime API

```gdscript
@onready var projection: Projection3D = $Projection3D

func _ready() -> void:
    projection.rebuilding.connect(_release_old_content)
    projection.rebuilt.connect(_bind_content)
    projection.build_failed.connect(_report_invalid_scene)
    if projection.ensure_built():
        _bind_content()

func _bind_content() -> void:
    var model: Node3D = projection.scene_instance
    var camera: Camera3D = projection.camera
    # Model animation and any application-specific logic belongs here or in model.
```

Typed read-only accessors: `viewport: SubViewport`, `camera: Camera3D`,
`sprite: Sprite2D`, `scene_container: Node3D`, `scene_instance: Node3D`, and
`light: DirectionalLight3D`.

- `ensure_built() -> bool`: synchronous, idempotent, safe before/after tree entry.
  Repeated successful calls keep the same instances and do not reset direct
  camera/content changes or animation state.
- `rebuild() -> bool`: synchronous replacement of the generated pipeline. The old
  generated nodes are freed before new nodes are exposed. Refresh any cached
  references through the accessors after `rebuilt`.
- `request_redraw()`: render one frame if the viewport is currently disabled,
  including a consumed `UPDATE_ONCE`; active continuous update modes remain intact.
- `rebuilding`: emitted before old generated content is destroyed; stop accessing
  cached model/camera references until `rebuilt`.
- `rebuilt`: emitted after the complete valid pipeline and injected content exist.
  This includes a valid empty/null scene.
- `build_failed(message: String)`: emitted if a scene cannot instantiate or has a non-`Node3D` root.
  The invalid temporary instance and old pipeline are freed, public node accessors
  return null, and an editor configuration warning explains the problem. Repeated
  `ensure_built()` calls do not retry an unchanged invalid scene; assign another
  scene or explicitly call `rebuild()` to retry.

Assigning `scene` in the tree coalesces changes into a deferred rebuild. Call
`ensure_built()` immediately after assignment if the new scene is needed
synchronously. Reimport/content `changed` signals also invalidate the instance.
Exported camera, lighting, viewport and transform changes apply to the live nodes
without rebuilding or disturbing unrelated settings and animation. They refresh a
consumed `UPDATE_ONCE`; deliberate `UPDATE_DISABLED` stays disabled unless
`request_redraw()` is called explicitly. Edit exported settings to save changes;
direct accessor edits are transient and are discarded by an explicit rebuild.

## Generated structure and ownership

```text
Projection3D (authored Node2D)
  Viewport3D (internal SubViewport)
    Scene3D (internal Node3D; scene_transform)
      <injected Node3D scene> (internal root; original root transform)
    Camera3D (internal orthographic camera + private environment)
    DirectionalLight3D (internal)
  Projected3D (internal Sprite2D + viewport texture)
```

All generated infrastructure and the injected scene root have `owner = null`.
Injected descendants retain their native internal scene owners, preserving
`%UniqueName` lookups and nested scene behavior. Ownership pointing outside the
injected subtree is cleared; no generated node is assigned to the outer scene.
The unowned internal scene root is the serialization boundary. Generated roots
use `Node.INTERNAL_MODE_BACK`, stay out of the editable scene tree and ordinary
`get_children()`, and are not saved into scenes. Use `get_children(true)` only for
diagnostics. Authored children of the component are not touched by rebuilding.

Removing and readding the component retains its existing internals; their tree
lifecycle follows the component without generating duplicates. Freeing the
component frees the entire pipeline normally. Multiple projections use isolated
worlds, so one projection's camera/light/content cannot affect another.

## Verification

Run `Tests/ProjectionProbe.gd` with Godot `--headless --script`; add `--editor`
for the real editor-hint save/reload path. The component-only fixture and a renamed,
nested copy each pass 968 checks in runtime and editor modes. Two invalid-root
warnings are intentional. Headless editor shutdown diagnostics match an empty
editor-script baseline; these checks do not verify GPU pixel output. Native
`%UniqueName`, hidden serialization, resource isolation, partial helper removal,
reentry, redraw policies and failure recovery are covered.
