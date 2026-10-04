# DisappearingPlatform3D

独立的「固定机框 + 单个活动踏板」装置。真实 3D 模型经透明 SubViewport 显示在 2D 场景，游戏碰撞仍为原版 2D 逻辑。原 `DisappearingPlatform` 不需要修改。

## 模型与导入

- `Assets/Backplate.blend`：固定机框、支撑、轴承、警示灯及空心轴护罩；内嵌一张 96×8 源色纹理。
- `Assets/Tread.blend`：一个活动厚板、双层凹框、转轴及两个 16 齿实体齿轮；内嵌一张 96×58 面板纹理。所有活动部件属于 `TreadHinge`，原生 `Fold` 动画驱动它。
- 26 个组件网格都有厚度。纹理承担细纹、铆点、边缘磨损的颜色；没有逐帧替换网格、13 张姿态贴图或面向相机的精灵平面。

开发时需安装 Blender（验证版本 4.3.2），在 Godot 的 `Editor Settings > Filesystem > Import > Blender > Blender Path` 指定程序。Godot 验证版本为 4.6.3；导出游戏不依赖 Blender。[官方导入说明](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)。

保留 `.blend.import`：UV 开启、纹理不解包为外部依赖、踏板动画优化关闭以保留全部 13 个角度键。编辑模型时保留 `TreadHinge`、`AlarmLamp`、`HingeCover`、`Fold` 名称。Blender 为 Z 向上、-Y 正面；Godot 导入后为 Y 向上、+Z 正面。

## 通用 Projection3D 与场景编辑

`Components/Projection3D/` 是可独立复制的通用组件，没有平台业务依赖。它是 `@tool Node2D`，Inspector 的 `scene: PackedScene` 接受任意 **Node3D 根场景**，自动生成透明、独立 World3D 的投影壳：

```text
Projection3D (Node2D，保存场景引用与投影配置)
├── Viewport3D (SubViewport，自动生成/隐藏)
│   ├── Scene3D (Node3D，应用 scene_transform)
│   │   └── 注入的3D场景实例
│   ├── Camera3D (正交投影、独立 Environment)
│   └── DirectionalLight3D
└── Projected3D (Sprite2D，独立 ViewportTexture)
```

生成的壳节点和注入根无 owner，使用内部节点模式，不出现在常规场景树、不保存进外层 `.tscn`。注入场景内部的 owner 关系保留，避免破坏 `%UniqueNode` 与嵌套场景语义。只有配置和 PackedScene 引用被保存。

平台的可编辑主场景现在是：

```text
DisappearingPlatform3D
├── Projection (Projection3D，scene 引用 MechanicalAssembly.tscn)
├── SolidBody2D
│   └── CollisionPolygon2D
└── ActivationAudio
```

- **编辑投影**：选择 `Projection`，修改画幅、相机位置/角度/尺寸/裁剪面、Scene3D 变换、Sprite 偏移/采样、环境模板和方向灯属性；这些参数保存并在重建时应用。无需手工维护相机和 viewport 节点。
- **编辑模型**：打开 `MechanicalAssembly.tscn`。其中 `MechanicalModel.gd` 与 `Backplate` / `Tread` 两个真实 Blender 场景实例仍可编辑，两个模型没有脚本固定路径 preload。需要修改导入实例内部属性时启用 Editable Children；网格仍在 Blender 编辑。装配根变换与 `Projection.scene_transform` 叠加，后者不覆盖根的手工变换。
- **替换内容**：通用组件仅要求 Node3D 根；此平台另外要求注入场景根挂载 `MechanicalModel.gd`，配置 `backplate`、`tread`、警示灯脚本引用，并包含唯一 `AlarmLamp` / `TreadHinge` 与一个 `Fold` 动画。尺寸/轴向仍须与2D碰撞配准。
- **布局预设**：默认 `layout_source_key` 记录已应用的预设。`auto_apply_source_layout` 开启且切换 `settings.source_key` 时才自动应用新布局；完全手工布局时关闭它。Inspector 的 **Apply source preset layout** 按钮明确更新投影画幅、相机位置/size、Sprite偏移、Scene3D位置和碰撞点。其余灯光、环境、音效、碰撞层保持原配置。
- **编辑器预览**：模型只绑定/验证，显示原生材质/作者姿态，不把运行时 palette、灯脚本或动画姿态写回资源。F6运行才启用游戏配色、警报与状态动画。
- **运行重建**：更换引用/调用 `rebuild()` 会销毁旧投影实例；平台监听生命周期信号，重新绑定并恢复当前折叠/警报、时钟和观察角度，不重建碰撞或音效。无效内容时暂停访问和业务推进，修复后恢复。状态机仍拥有折叠、灯alpha和碰撞启用状态。

通用API：`ensure_built() -> bool` 幂等构建、`rebuild() -> bool` 明确重建、`request_redraw()` 请求刷新；通过 `viewport`、`camera`、`sprite`、`scene_container`、`scene_instance`、`light` 获取当前生成实例，重建后重新获取。监听 `rebuilding` / `rebuilt` / `build_failed(message)`，不要长期持有已销毁节点引用。空 scene 对通用组件有效；非Node3D根会明确拒绝。配置更新不无故重建内容。

独立最小用例：复制整个 `Components/Projection3D/` 目录到任意Godot项目，F6运行其中盒子示例；详见 [组件README](Components/Projection3D/README.md)。这不需要平台、Blender或原2D素材。可变投影资源彼此独立；注入模型本身遵守Godot正常资源共享规则，需要运行修改的自定义资源应设为 `resource_local_to_scene`。

## 实例化与行为

1. 在 2D 场景实例化 `DisappearingPlatform3D.tscn`。根节点对应原碰撞面顶部中心。
2. 设置 `actor_path`，或调用 `bind_actor(player, alive_predicate)`；角色碰撞掩码须包含 `SolidBody2D.collision_layer`。脚本的 `solid_layers` 兼容属性直接读写该节点。
3. `PlatformSettings` 提供 14 个原始 `source_key` 预设、延迟、隐藏时长、时间倍率及音效开关。每实例修改设置前复制资源。
4. 自定义宿主可调用 `activate()`；`reset()` 恢复待机并退出观察。

默认踩踏 109/60 秒后取消碰撞，隐藏 1.25 秒后恢复碰撞。恢复碰撞仍早于展开动画结束，保持原逻辑。重复激活、恢复排队、警报和灯光 alpha 使用同一确定性时钟；待机红灯 alpha 为 0。

踏板宽 96、最深 60，绕 X 轴折下 90°。原生动画在约 1.75–1.95 秒取样，13 个角度键按源图下缘位置缓动；恢复沿同一曲线反向展开。固定空心轴护罩自然露出青绿上沿，活动板/连接片的圆弧槽提供转动间隙。齿轮随轴转动，不模拟额外齿轮传动或 3D 刚体物理。

每实例有独立 World3D、相机、SubViewport、灯光及可变警示灯材质。游戏正面采用 nearest 采样的无光照源色材质；自由视角切回实体光照，退出还原。根节点的移动、旋转、缩放由 2D 宿主控制。

## 示例与自由视角

- `Examples/Preview.tscn`：F6 运行；空格激活。
- `Samples/INARIMechanisms/Examples/DisappearingPlatform3DWorkshop.tscn`：F6 运行；A/D 移动，空格跳跃。
- **V** 开关自由视角；鼠标主按钮拖拽旋转，滚轮缩放，俯仰范围 ±80°。
- **R** 重置并退出。观察中动画继续；练习场角色冻结，移动/跳跃/攻击不会穿透。
- 窗口 resize 后，场景等比适配、背景铺满 viewport，HUD 独立缩放/换行，不改变碰撞单位或鼠标 delta。

宿主调用 `enter_inspection()`、`exit_inspection()`、`is_inspecting()`、`handle_inspection_input(event)`，并在 `_input` 中消费观察输入。装置不会自行冻结任意外部角色。退出恢复相机变换、显示位置和缩放。

## 文件用途

| 目录/文件 | 保留原因 |
| --- | --- |
| `Assets/*.blend` 与 `.import` | 当前模型、内嵌纹理和必要导入设置 |
| `Assets/activate_01.wav` 与 `.import` | 场景直接引用的激活音效 |
| `Assets/device.json` | 预设、碰撞、动画/灯光曲线、布局及源提取审计信息；不是旧几何生成数据 |
| `Presets/`、`DefaultSettings.tres`、`PlatformSettings.gd` | 14 个可选预设和宿主配置 |
| 主场景、`DisappearingPlatform3D.gd`、`MechanicalModel.gd`、`MechanicalAssembly.tscn` | 状态机、2D碰撞、可编辑3D装配和观察控制 |
| `Components/Projection3D/` | 可独立复制的通用投影壳、最小盒子示例与生命周期测试 |
| `GeometryVisual.gd` | 当前实体警示灯的独立 alpha 材质，不是旧网格生成器 |
| `Examples/` | 自包含交互示例及被 3D Workshop 共用的窗口布局 |
| `Tests/` | 行为、机械模型、视角、resize 回归及图形采集/轮廓辅助诊断 |
| `Tools/` | 可编辑模型的重生成、Blender 结构/运动预览 |
| `.gd.uid` | Godot 脚本资源身份，不应当作缓存删除 |

## 维护与回归

以下命令在装置目录执行；输出目录应选在项目之外：

```sh
blender -b --python Tools/build_mechanical_models.py -- /absolute/output
blender -b --python Tools/render_mechanical_preview.py -- /absolute/output
```

生成器会覆盖两份模型的手工修改。再生成需要同仓库原 `DisappearingPlatform/Assets` 及 Blender Python 的 Pillow；正常使用已打包模型不需要原素材或 Pillow。生成器输出重新加载、闭合性验证及 GLB 供检查。渲染器加 `--motion` 生成标为 Blender 检查的慢放视频（需 ffmpeg）；加 `--only=footprints --footprint-sequence` 输出 13 个小尺寸轮廓图。

先运行 Godot `--headless --editor --import`，再分别以 `--headless --script` 运行：

- `Tests/MechanicalProbe.gd`：双模型、13 个原生角度键、实体齿轮/轴护罩、UV、两张静态纹理和材质隔离。
- `Tests/StandaloneProbe.gd`：状态/报警灯时序、实际接触、多实例和原版对照。
- `Tests/OrbitProbe.gd`：重复 V/R、拖拽、缩放、相机恢复和输入隔离。
- `Tests/DemoResizeProbe.gd`：9 种尺寸、横竖/超宽窗口、拖拽中 resize、HUD、背景和世界坐标。
- `Tests/SceneAuthoringProbe.gd`：投影配置/场景引用、业务节点及模型手工调整的保存重载、预设布局选择和观察恢复。
- `Tests/MissingReferenceProbe.gd`：缺引用/无效模型的停用、明确报错与修复恢复；12 条配置错误是刻意触发的预期输出，不应把它当成普通零错误日志。
- `Tests/EditorAuthoringProbe.gd`：额外加 `--editor` 运行，确认配置与模型资源保存后不含生成投影壳、运行时材质/脚本/姿态污染。
- `Tests/ProjectionIntegrationProbe.gd`：活动/恢复/观察期间重建、替换与失效修复，不重启平台时序或泄露输入。
- `Components/Projection3D/Tests/ProjectionProbe.gd`：通用组件独立实例、替换、空/非法场景、配置更新、隐藏序列化、释放及重新入树；也以 `--editor` 运行。

完整/Workshop 项目的机械/时序/观察/resize 检查数分别为 **4170 / 21250 / 1254 / 2415**；改名嵌套的独立副本为 **4170 / 1274 / 1101 / 1019**。两套项目的场景配置/缺引用/投影集成检查分别为 **718 / 179 / 84**，通用组件运行/编辑器各 **968** 项，平台真实编辑器模式 **4475** 项；合计 **20 组**通过，两套干净导入无错误。

缺引用探针每组刻意产生12条配置诊断；通用/集成探针分别刻意产生2条非法根警告，其他运行日志无意外错误。`--editor --script` 的退出RID/ObjectDB清理告警与空编辑器脚本基线一致，不代表真实GPU编辑器验收。通用组件还在仅有组件本身及改名嵌套目录的独立项目中通过运行/编辑器测试。缺少原版/Workshop的便携副本会明确跳过对应对照。

抽象前后默认投影/相机/环境/灯光/碰撞/音效及装配世界位置的27项参数指纹一致，模型二进制未变。此前26组件闭合正体积及101姿态间隙验证仍适用于相同模型；这些不是连续运动的数学证明。

## 视觉证据与限制

Blender 图像必须标为模型参考，不能当作 Godot 游戏截图。当前自动化运行环境仅能使用 Godot dummy/headless 渲染；实际 GPU 色彩、透明合成、交互手感和设备性能仍需图形环境验证。`Tests/CaptureProjection.gd` 在图形环境中采集同尺度的原 2D/新 3D 对照（原装置不在项目内时仅采新装置）。

13 帧的源图/Blender 面板下缘均对齐，但早期条纹位置及逐帧手绘明暗仍有差异。中央活动区域 RGB 平均误差在待机/末帧约 0.40/0.42（0–255），早期帧可到 46.51；这不包含齿轮或静止背板，也不是 Godot GPU 验收结果。

`Tests/compare_mechanical_footprints.py <渲染目录>` 仍可辅助比较 alpha 轮廓：默认预设、1 像素/单位、alpha >128，排除软阴影和未亮警示灯，按整数近似原位移。**轮廓吻合不代表面板细节、RGB 或动画视觉一致**。不再保留已被新模型取代的历史轮廓分数作为当前结论。
