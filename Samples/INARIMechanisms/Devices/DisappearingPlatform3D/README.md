# DisappearingPlatform3D · 真实 3D 几何投影到 2D

独立新装置，基于 Inari 的 `DisappearingPlatform`（6134c742）。原装置目录及原练习场完全不改。只复制本目录即可在 Godot 4.x 工程使用，不依赖原装置、Autoload、输入映射或 Blender 运行时。

## 使用

1. 在 2D 场景实例化 `DisappearingPlatform3D.tscn`，根节点为碰撞面的顶部中心。
2. `actor_path` 指向 `CharacterBody2D`，或调用 `bind_actor(player, alive_predicate)`；自定义控制器可调用 `activate()`。角色碰撞掩码包含 `solid_layers`。
3. 可移动、旋转、等比缩放根节点，正常使用宿主的 Camera2D / CanvasLayer。碰撞仍是原精确 `CollisionPolygon2D`，不会引入与 2D 角色不兼容的 3D 物理。
4. `settings` 支持原 14 个 `Presets`、`disappear_delay`、`hidden_seconds`、`time_scale`、`sound_enabled`。每实例独立设置前请复制资源。默认 109/60 秒移除碰撞，1.25 秒后立即恢复；警报、红灯曲线、恢复过程排队再次激活、信号和 `reset()` 都沿用源行为。

仓库示例：`Samples/INARIMechanisms/Examples/DisappearingPlatform3DWorkshop.tscn`，F6 运行。A/D 移动，空格跳跃，R 重置，V 在正交正面与 35° 侧面检查间切换。V 只检查几何厚度，碰撞不会旋转成 3D。生产使用角度 0。

## 几何与投影

- 平台不是 Sprite3D，也不是贴有平台图片的平面。源轮廓中相邻同色像素合并成矩形，每个矩形挤出为六面封闭长方体，平台厚度 8 个局部单位，灯/阴影厚度 2。背面和侧壁都存在。
- 13 个收起/展开姿态为离散真实网格，按源帧切换；这是像素风 **3D 浮雕/体素重建**，不是连续铰链或骨骼动画。不同观察角度是可检查的 3D，但默认视角才对应原美术。
- 机框、灯、软阴影也由有颜色/透明度的几何构成。运行时完全不读取 PNG，不用源精灵纹理。唯一 Sprite2D 只显示最终 ViewportTexture。
- 每实例一套独立 World3D、正交相机、透明 SubViewport 和可变材质。网格只读共享；根节点变换只作用一次。无 3D 抗锯齿，2D nearest 过滤；全部姿态和阴影参与尺寸计算，避免收起时裁切。
- 无光照材质保留源配色；相机环境使用线性色调映射。源每层的颜色、透明度、排序、位移和缩放均保留。宿主后处理、颜色空间及 GPU 的最终像素还应在目标工程确认。
- 空闲/隐藏稳定帧不持续重绘，只有网格、红灯或检查相机变化时请求一次重绘。每层一个 MeshInstance3D，不是每像素一个节点。软阴影占 29,473 个合并盒子，几何保真有成本；大量实例需在目标设备测 GPU/显存，尚未做设备性能保证。

## 素材与再生成

`Assets/geometry.json` 是自包含、可审计的挤出几何配方；`device.json` 保存源碰撞及时间轴，WAV 保存原组合音效。无需 Blender 或外部下载。

仓库中执行 `python Samples/INARIMechanisms/Devices/DisappearingPlatform3D/Tools/build_geometry.py` 可从保留的原 PNG 重建配方（仅此开发步骤需要 Pillow）。运行时不需要原目录。`Tests/verify_geometry.py` 逐像素验证全部 16 个配方的正面 RGBA 与原图一致，透明像素的不可见 RGB 忽略。

## 验证

复制本目录到空工程任意位置，先运行 `godot --headless --path <工程> --editor --import --quit`，再执行 `godot --headless --path <工程> --script res://<本目录>/Tests/StandaloneProbe.gd`。覆盖时间边界、30/60/120 Hz、0/0.5/1/2 倍时间、重入/重置、物理顶部/侧面/底面、旋转缩放、14 预设、3D 隔离和几何厚度。若相邻目录存在原装置，还对比完整生命周期的源帧与红灯曲线。

引擎截图：在有图形显示的环境运行 `godot --path <工程> --script res://<本目录>/Tests/CaptureProjection.gd`；可用 `INARI_3D_CAPTURE_DIR` 指定输出目录，默认 user://platform3d-captures。脚本生成待机、警报、收起、隐藏、恢复与侧视图；headless 会明确失败而不伪造截图。

本次已在 Godot 4.6.3 headless 验证逻辑/几何和可移植性。当前执行环境没有 X11/Wayland，headless 仅有 dummy renderer，因此 **尚未验证 Godot 实际 GPU 投影、透明度合成及视觉像素误差**。附带 Blender 几何检查图只展示体积及姿态，不冒充游戏截图；它省略大软阴影，并采用简化透明度。目标工程标记 Godot 4.7，仍需在其图形环境复核。

本目录内还提供完全独立的 `Examples/Preview.tscn`，F6 可直接查看：空格激活、R 重置、V 检查厚度，无角色或项目输入映射依赖。
