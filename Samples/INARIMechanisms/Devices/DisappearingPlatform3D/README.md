# DisappearingPlatform3D 最小完整 Demo

可编辑的双 Blender 模型，经通用 `Projection3D` 显示在2D世界；碰撞仍为2D。整个目录可单独复制，不依赖原2D装置、源数据文件、预设库或宿主 Core。

## 运行

Godot 4.6+；首次导入 `.blend` 需在编辑器设置中配置 Blender 路径，导出后的游戏不需要 Blender。F6运行 `Examples/Preview.tscn`。原 `Samples/INARIMechanisms/Examples/DisappearingPlatform3DWorkshop.tscn` 入口指向同一demo。

- A/D或方向键移动，空格跳跃；踩上平台触发
- V开启/关闭自由观察；鼠标拖动旋转，滚轮缩放
- 观察时角色和操作冻结，平台动画继续
- R退出观察、重置平台和角色；J/K保留原练习场挥击显示
- 窗口缩放时等比适配，背景铺满，HUD独立排版

沿用原3D练习场的三平台/台阶位置、角色速度260、跳跃速度440、重力1000，以及出生、掉落重生和重试位置。

## 编辑

- `DisappearingPlatform3D.tscn`：根节点Inspector直接配置消失延迟、隐藏时长、时间倍率、折叠/恢复时序、警报切换时间和恢复透明度Curve。默认踩踏 **109/60秒** 后取消碰撞，隐藏 **1.25秒** 后恢复碰撞；碰撞恢复仍早于展开结束。没有预设选择或运行时布局覆盖。
- `Projection`节点：配置画幅、相机、灯光、环境、像素采样、位置和3D场景引用。投影基础节点自动生成并隐藏，不保存进外层场景。
- `SolidBody2D/CollisionPolygon2D`与`ActivationAudio`：直接编辑碰撞和音效。
- `MechanicalAssembly.tscn`：引用`Assets/Backplate.blend`和`Assets/Tread.blend`。固定机框、单活动踏板和实体齿轮均为真实3D几何。
- 模型以后直接在Blender维护；不附带历史生成/渲染工具。保留`TreadHinge`、`AlarmLamp`和`Fold`动画及现有轴向/尺寸约定。`.blend.import`保留UV、内嵌纹理和未优化的动画关键帧。

游戏正面使用无光照源色材质；自由观察恢复原生光照。编辑器只预览原生材质/保存的姿态，不把运行时材质或动画写回模型。

## 复用

实例化主装置后，设置`actor_path`或调用`bind_actor(player)`；也可主动`activate()`和`reset()`。宿主负责V/R及观察输入，将事件交给`handle_inspection_input()`，并冻结自己的角色控制。

只需要通用3D转2D时，复制`Components/Projection3D/`，实例化其中场景，再给`scene`指定任意Node3D根场景。组件不依赖此平台；详见其README。

## 手动验收

1. 在三块平台间移动跳跃，确认踩踏警报、折下、失去碰撞、恢复及再次触发。
2. 倒计时与恢复期间重复V、拖动和缩放；退出后相机及控制恢复，R回到原位置。
3. 调整宽屏、窄屏与竖屏窗口，确认背景、HUD和鼠标操作正常。
4. 编辑相机、碰撞、时序或模型引用，保存重开后确认保留。

开发回归与旧版对照已移出产品目录。自动验证使用Godot headless；实际GPU色彩、透明合成与手感仍需图形环境验收。两个模型与此前版本相同，连续机械动画与原手绘中间帧仍可能有明暗差异。
