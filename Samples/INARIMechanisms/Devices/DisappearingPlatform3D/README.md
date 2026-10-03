# DisappearingPlatform3D · 双模型机械铰链版

原 `DisappearingPlatform` 保持不变。这个独立 3D 装置由**共用固定机框 + 单个活动踏板**组成，通过透明 SubViewport 在 2D 场景显示，继续使用原 2D 碰撞和倒计时。

## 两个独立原生模型

- **`Assets/Backplate.blend`**：固定机框和支撑、轴承、报警灯。它有真实结构厚度、凹槽和近黑色背衬，外轮廓从原背板的透明通道描出。
- **`Assets/Tread.blend`**：一个踏板、同一转轴、左右两个有厚度的实体齿轮。所有活动零件属于 `TreadHinge`，原生 `Fold` 动画驱动该铰链。

可以分别用 Blender 打开和编辑，再在 Godot 重新导入。保留 `TreadHinge`、`AlarmLamp` 和 `Fold` 名称以便运行时识别。Blender Z 向上、正面朝 -Y；Godot 转换为 Y 向上、正面朝 +Z。

已移除先前的 13 套姿态网格、旧合并 `.blend`、`geometry.json` 和逐帧几何生成代码。现在整个生命周期始终使用同一套踏板网格，变化的是铰链变换。不是隐藏/显示复制的踏板，也不是换精灵或贴图平面。

齿轮是带轴孔、齿顶、齿根、侧壁与轴向厚度的闭合网格。左右齿轮随同一转轴转动；它们不模拟额外的齿轮传动或 3D 刚体物理。

## 动画、外观和碰撞

- 待机踏板为水平，宽 96、深 59 个局部单位，绕 X 轴向下折叠到 90°；恢复时沿同一运动反向展开。
- 用 Blender 导入的真实 `Fold` 关键帧动画，在原动画收起区间（约 1.75–1.95 秒）按确定性时钟取样。不是运行时生成 13 个模型。
- 踩踏 109/60 秒后取消碰撞，隐藏 1.25 秒后立即恢复碰撞；红灯、警报、重复激活与恢复排队延续原行为。**恢复碰撞仍早于展开结束**，这是原游戏逻辑。恢复过渡保持结束后，转轴连续回转至原结束时刻，避免突然跳角。
- 碰撞为 `CollisionPolygon2D`，角色依然是 `CharacterBody2D`，不会让 2D 角色依赖 3D 物理。
- 这一版是重新制作的机械模型，保留深灰/青绿配色和基本轮廓，但**不再宣称逐像素复刻旧精灵**。游戏正面使用源调色的无光照材质，V自由视角恢复实体光照，退出/重置后还原；实体厚度、齿轮和连续转动仍会带来视觉差异；旧软阴影浮雕已移除。

## 首次导入与使用

开发电脑需安装 Blender（本次验证 4.3.2）并在 Godot 编辑器设置 `Filesystem > Import > Blender > Blender Path` 指定程序。Godot 标准 Blender → glTF 导入处理两份 `.blend`；导出游戏不需要 Blender。

保留附带 `.blend.import` 设置，尤其是踏板动画导入。官方说明：[Godot Blender 导入](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)。

1. 在 2D 场景实例化 `DisappearingPlatform3D.tscn`；根节点对应碰撞面顶部中心。
2. 设置 `actor_path`，或调用 `bind_actor(player, alive_predicate)`。角色碰撞掩码包含 `solid_layers`。
3. 保留原 14 个 `settings.source_key` 预设、延迟、隐藏时长、时间倍率和音效开关。每实例修改设置前复制资源。
4. 自定义角色可调用 `activate()`；`reset()` 恢复待机。

每实例有独立 World3D、正交相机、透明 SubViewport、灯光和可变报警灯材质；静态模型资源只读共享。生产正面用 nearest 过滤，根节点移动/旋转/缩放由 2D 宿主控制。

## 预览与自由视角

- 自包含预览：`Examples/Preview.tscn`，F6；空格激活，界面显示当前铰链角度。
- 角色练习场：`Samples/INARIMechanisms/Examples/DisappearingPlatform3DWorkshop.tscn`，F6；A/D 移动、空格跳跃。
- **V** 开关自由观察；鼠标任意主按钮拖拽旋转，滚轮缩放，俯仰 ±80°。
- **R** 重置并退出观察。

观察时装置动画继续，练习场角色冻结，移动/跳跃/攻击输入不会穿透。退出恢复原相机、显示位置及缩放。三个练习场装置分别有独立相机，同时响应观察输入。

宿主可用 `enter_inspection()`、`exit_inspection()`、`is_inspecting()` 和 `handle_inspection_input(event)`；应先在 `_input` 中消费观察输入。示例实现完整输入隔离，装置不会擅自冻结任意外部角色。

## 验证和图像来源

`Tests/StandaloneProbe.gd` 检查源时间轴、报警灯、真实接触和独立实例；`Tests/MechanicalProbe.gd` 检查双模型、原生动画、铰链、踏板网格不变及实体齿轮；`Tests/OrbitProbe.gd` 检查自由视角和输入隔离。

Blender 渲染用于展示拆分、结构和运动，标注为 Blender 模型检查；并不冒充 Godot 游戏截图。当前云环境没有 X11/Wayland，Godot headless 只使用 dummy renderer，实际 Godot GPU 视觉、透明度、鼠标手感与设备性能仍需图形环境复核。`Tests/CaptureProjection.gd` 可在图形环境采集游戏图像。


### 可复现的外形比较

`Tests/compare_mechanical_footprints.py <渲染目录>` 比较原装置与 Blender 正交渲染的 alpha 轮廓。条件为 1 单位/像素、alpha > 128、默认预设，排除原软阴影与未亮报警灯，按原位移近似整数对齐并补足画布。

上一轮模型的待机轮廓 IoU 为 **98.17%**，两者外包框均为 160×80；全折叠轮廓 IoU 为 **98.34%**，外包框分别为原图 160×100、新模型 160×99。这只是轮廓比较，**不代表 RGB、灯光或 Godot GPU 图像一致**。13 个对应位置的整机轮廓 IoU 范围为 93.72%–98.36%，中间位置下缘最大相差 7 像素；统计包含静止背板，并不代表踏板局部细节准确率。中间动画采用真实线性转轴而不是旧手绘换帧，因此可见角度与细节不同。

开发工具：`Tools/build_mechanical_models.py` 再生成两份初始模型（会覆盖手工编辑）；`Tools/render_mechanical_preview.py` 直接加载模型渲染。加 `--motion` 生成明确标注的慢放运动视频；加 `--only=footprints --footprint-sequence` 生成 13 个小尺寸正面轮廓图。开发再生成/对比需要 Blender Python 中的 Pillow，正常使用资产不需要。

### 正面外观修正（本地验证中）

用户实机截图暴露出整机轮廓统计不能检验颜色与局部零件：背板错误使用踏板灰色、实体齿轮直径不足、横条厚度/色层不足。此次按源RGBA的可见像素校准，而不是使用透明区域残留RGB。待机中央横条源尺寸为96×9；齿轮宽8、高42；铰链原点和前视轴向原本正确，保持不变。原Idle红灯alpha=0，保持待机熄灭。修正后的游戏GPU图像尚未验证，请勿把Blender参考图当作Godot验收结果。
