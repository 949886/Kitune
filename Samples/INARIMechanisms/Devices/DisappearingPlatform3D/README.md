# DisappearingPlatform3D

独立的「固定机框 + 单个活动踏板」装置。真实 3D 模型经透明 SubViewport 显示在 2D 场景，游戏碰撞仍为原版 2D 逻辑。原 `DisappearingPlatform` 不需要修改。

## 模型与导入

- `Assets/Backplate.blend`：固定机框、支撑、轴承、警示灯及空心轴护罩；内嵌一张 96×8 源色纹理。
- `Assets/Tread.blend`：一个活动厚板、双层凹框、转轴及两个 16 齿实体齿轮；内嵌一张 96×58 面板纹理。所有活动部件属于 `TreadHinge`，原生 `Fold` 动画驱动它。
- 26 个组件网格都有厚度。纹理承担细纹、铆点、边缘磨损的颜色；没有逐帧替换网格、13 张姿态贴图或面向相机的精灵平面。

开发时需安装 Blender（验证版本 4.3.2），在 Godot 的 `Editor Settings > Filesystem > Import > Blender > Blender Path` 指定程序。Godot 验证版本为 4.6.3；导出游戏不依赖 Blender。[官方导入说明](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)。

保留 `.blend.import`：UV 开启、纹理不解包为外部依赖、踏板动画优化关闭以保留全部 13 个角度键。编辑模型时保留 `TreadHinge`、`AlarmLamp`、`HingeCover`、`Fold` 名称。Blender 为 Z 向上、-Y 正面；Godot 导入后为 Y 向上、+Z 正面。

## 实例化与行为

1. 在 2D 场景实例化 `DisappearingPlatform3D.tscn`。根节点对应原碰撞面顶部中心。
2. 设置 `actor_path`，或调用 `bind_actor(player, alive_predicate)`；角色碰撞掩码须包含 `solid_layers`。
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
| `Assets/activate_01.wav` 与 `.import` | 动态加载的激活音效 |
| `Assets/device.json` | 预设、碰撞、动画/灯光曲线、布局及源提取审计信息；不是旧几何生成数据 |
| `Presets/`、`DefaultSettings.tres`、`PlatformSettings.gd` | 14 个可选预设和宿主配置 |
| 主场景、`DisappearingPlatform3D.gd`、`MechanicalModel.gd` | 状态机、2D 碰撞、3D 装配、投影和视角 |
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

最新完整/Workshop 项目的检查数分别为 **4170 / 21249 / 1254 / 2415**；改名嵌套的独立副本为 **4170 / 1273 / 1101 / 1019**，全部通过、干净导入无错误。独立副本缺少原版/Workshop 时会明确跳过对应对照。当前 26 个组件的闭合正体积验证及 101 个姿态间隙检查也通过；这些不是连续运动的数学证明。

## 视觉证据与限制

Blender 图像必须标为模型参考，不能当作 Godot 游戏截图。当前自动化运行环境仅能使用 Godot dummy/headless 渲染；实际 GPU 色彩、透明合成、交互手感和设备性能仍需图形环境验证。`Tests/CaptureProjection.gd` 在图形环境中采集同尺度的原 2D/新 3D 对照（原装置不在项目内时仅采新装置）。

13 帧的源图/Blender 面板下缘均对齐，但早期条纹位置及逐帧手绘明暗仍有差异。中央活动区域 RGB 平均误差在待机/末帧约 0.40/0.42（0–255），早期帧可到 46.51；这不包含齿轮或静止背板，也不是 Godot GPU 验收结果。

`Tests/compare_mechanical_footprints.py <渲染目录>` 仍可辅助比较 alpha 轮廓：默认预设、1 像素/单位、alpha >128，排除软阴影和未亮警示灯，按整数近似原位移。**轮廓吻合不代表面板细节、RGB 或动画视觉一致**。不再保留已被新模型取代的历史轮廓分数作为当前结论。
