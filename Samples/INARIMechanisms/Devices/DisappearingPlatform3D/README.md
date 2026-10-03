# DisappearingPlatform3D · Blender 模型 + 2D 游戏装置

原版 `DisappearingPlatform` 完整保留。本装置独立，基于 Inari `6134c742`，支持原碰撞、时间轴、14 个预设及音效。

## 模型在哪里？

**`Assets/DisappearingPlatform3D.blend` 就是真实、可编辑的原生 Blender 文件。**

- 用 Blender 4.3 或更新版本打开，默认显示待机姿态。Outliner 的 `01 Platform poses` 包含 13 个姿态，眼睛按钮可以切换查看；`02 Backplate, alarm, soft shadow` 包含机框、灯和阴影。
- 每个模型都是有六面封闭体积的真实网格，配色用可编辑材质，没有精灵贴图。平台厚 8 单位，灯/阴影厚 2 单位。
- 保持对象名（如 `sharedassets2_1700`）稳定，可以直接编辑网格和材质。Godot 重新导入后，重新打开/运行装置场景即使用新模型。局部轴：Blender Z 向上、正面朝 -Y；运行时使用网格局部坐标，位移/缩放由原装置数据统一设置。
- 当前是像素轮廓挤出的 3D 浮雕，13 个离散机械姿态，**不是连续骨骼/铰链动画**。文件里的材质为基础色；原灯红色调制、层透明度、时序在 Godot 装置里应用。

`geometry.json` 已删除，运行时也不会读取它。`GeometryLibrary.gd` 直接 preload 此 `.blend` 导入资源，收集真实导入网格，只把材质面合并为共享单一绘制面；不会在游戏中从图片或 JSON 生成几何。材质导入后按原像素风的 8-bit 色阶取整，避免颜色空间转换误差。

## 首次导入

Godot 通过标准 Blender → glTF 管线导入 `.blend`。开发电脑需要安装 Blender，在 Godot 编辑器设置 `Filesystem > Import > Blender > Blender Path` 选择 Blender 程序。**导出后的游戏不需要 Blender。**

保留随模型提交的 `.blend.import`：它导入所有隐藏姿态、保留调色板材质、关闭 LOD 和有损网格压缩。不要改为“仅可见对象”，否则会漏掉收起姿态。参考：[Godot 官方 Blender 导入说明](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)。

## 在 2D 场景使用

1. 实例化 `DisappearingPlatform3D.tscn`。根节点在原碰撞面的顶部中心，可移动、旋转、等比缩放，兼容宿主 Camera2D / CanvasLayer。
2. `actor_path` 指向 `CharacterBody2D`，或调用 `bind_actor(player, alive_predicate)`；角色碰撞掩码包含 `solid_layers`。自定义控制器可以调用 `activate()`。
3. `settings` 保留 `source_key`、`disappear_delay`、`hidden_seconds`、`time_scale`、`sound_enabled`；每实例修改前复制资源。
4. 默认踩踏 109/60 秒后移除碰撞，隐藏 1.25 秒立即恢复碰撞。红灯、警报、恢复期间再次踩踏的排队、信号、reset 均与旧装置一致。碰撞始终为 2D，不影响原角色控制器。

每实例有独立 World3D、透明 SubViewport、正交相机、可变材质；只读网格共享。最终唯一 Sprite2D 显示 ViewportTexture。默认正面一单位对应一像素，nearest 过滤，无 3D 抗锯齿。静止帧不持续重绘。

## 预览与自由视角

- 自包含预览：本目录 `Examples/Preview.tscn`，F6 运行；空格激活。
- 角色练习场：`Samples/INARIMechanisms/Examples/DisappearingPlatform3DWorkshop.tscn`，F6 运行；A/D 移动，空格跳跃。
- **V**：开启/退出自由观察。进入时转向初始斜视角，此后可任意拖动。
- **鼠标左/中/右键拖拽**：绕装置旋转；左右可转一整圈，上下俯仰限制 ±80°。
- **滚轮**：缩放，范围 0.15×–4×，避免零距离/翻转。
- **R**：重置并退出观察。

观察期间装置当前动画继续播放，巨大软阴影暂时隐藏以便看背面；练习场角色冻结，移动/跳跃/攻击输入不会穿透到角色。退出时精确恢复原相机位置、角度、缩放、投影、2D 显示位置和阴影可见性。三个练习场实例会同步接受鼠标操作，但相机和状态分别独立。

宿主 API：`enter_inspection()`、`exit_inspection()`、`is_inspecting()`、`handle_inspection_input(event) -> bool`。宿主应先在 `_input` 路由观察输入并消费，再交给游戏控制器。示例包含完整输入隔离；直接调用装置 API 不会擅自暂停任意外部角色。

## 验证与开发工具

- `Tests/StandaloneProbe.gd`：时间/帧/红灯与旧版比对、2D 真实碰撞、14 预设、几何厚度与实例隔离。
- `Tests/OrbitProbe.gd`：反复开关、拖拽、滚轮、重置、销毁、相机精确恢复、输入隔离。
- `Tests/ImportedModelProbe.gd`：审计真正导入的 Blender 网格，生成 CPU 正面投影用于逐像素数据比较；不是 GPU 截图。
- `Tests/verify_blend.py`：用 Blender 重开原生文件，验证 16 网格封闭性及每个正面 RGBA 与原图一致（源仓库中的旧 PNG 只用于此开发验证）。
- `Tests/CaptureProjection.gd`：有图形显示服务时采集真实 Godot 图像；headless 明确退出，不伪造截图。
- `Tools/render_blend_preview.py`：从已保存的 `.blend` 渲染 Blender 检查图。
- `Tools/build_blend.py`：开发时可从原 PNG 再生成 Blender 初始网格，需要 Blender 的 Python 可导入 Pillow；**会覆盖手工模型修改**，正常编辑/运行不需要执行。

已验证 Godot 4.6.3 + Blender 4.3.2 的干净导入、运行、旧行为和自由视角。当前无 X11/Wayland 图形服务，Godot headless 是 dummy renderer，**实际 Godot GPU 视觉、透明合成、交互手感及设备性能仍需图形环境复核**。Blender 图片明确是模型检查图。软阴影网格较大，大量实例需在目标设备测量性能。
