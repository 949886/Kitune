# 限时消失平台

**只复制本文件夹即可复用**。可改名、嵌套到其他 Godot 4 工程；不依赖 INARIMechanisms/Core、Rossi、Autoload、InputMap、原版安装目录或 FMOD 扩展。已在 Godot 4.7.2 验证。

1. 实例化 `DisappearingPlatform.tscn`。根节点位于碰撞面的顶部中心，可移动、旋转、等比缩放。
2. 设置 `actor_path`，指向触发机关的 `CharacterBody2D`；也可调用 `bind_actor(player)`。角色的 `collision_mask` 必须包含平台的 `solid_layers`（默认第 1 层）。
3. 每个实例代表原版一组连续的 6 格平台，各自倒计时。要单独调整参数，先把该实例的 `settings` 设为唯一资源；运行时不修改共享资源。

自定义角色控制器可在确认脚底接触后调用 `activate()`。绑定的 CharacterBody2D 会自动检查真实顶部接触；侧面和底面碰撞不会触发。`bind_actor(player, alive_predicate)` 接受无参数、返回 bool 的存活判断，不需要游戏全局状态。

默认行为来自 INARI v0.2.1 的 `DisappearTiles`：

- 踩踏启动收起动画和原版警报声；红灯按源曲线逐渐加快闪烁。
- 动画第 109 帧移除碰撞，60 FPS 对应约 1.8167 秒。持续站立不会重置计时，跳走也不会取消。
- 失去碰撞 1.25 秒后立即恢复碰撞并播放展开动画。恢复碰撞先于展开结束；恢复过程中再踩踏会排队下一次动画触发。
- 机关不自行施加伤害；失足处理由宿主角色负责。

| 设置 | 含义 |
| --- | --- |
| `source_key` | `Presets` 中 14 个源实例之一；默认 `level7_18316_0` |
| `disappear_delay` | 小于 0 使用源时间；非负值覆盖碰撞消失延迟 |
| `hidden_seconds` | 小于 0 使用原版 1.25 秒；非负值覆盖无碰撞时长 |
| `time_scale` | 计时与精灵动画倍率；0 暂停 |
| `sound_enabled` | 播放打包的原版音效 |

信号：`activated`、`disappeared`、`recovered`、`state_changed(value)`。`activate()` 返回本次是否成功启动；`reset()` 恢复碰撞和待机动画并停止音效。更改计时不会重编音效的原始时间轴，声音仍按原速播放；自定义节奏可关闭内置声音并连接这些信号。

`Assets/device.json` 保留五个关卡、14 组实例的碰撞多边形、原始字段、逐字节解码审计、精灵与动画曲线。相邻单元分组和 Animator 顺序按原版计算。普通像素、颜色和透明度保留；Unity URP 环境光、发光后处理和完整地图不包含在机关里。恢复时的 Sprite 离散切换按源过渡时长实现，未声称跨引擎每一个混合子帧完全一致。音效由原事件渲染为一份 WAV，保留警报、收起、展开组合；不包含动态距离参数与随机变体选择。

仓库内练习场：`Samples/INARIMechanisms/Examples/DisappearingPlatformWorkshop.tscn`，F6 运行，A/D 移动、空格跳跃、R 重置；展厅下拉框新增“限时消失平台”。练习场使用简化角色和布局，不是视频中的整关地图。

独立目录测试：复制到空工程并完成资源导入后执行 `godot --headless --path <工程路径> --script res://<复制后的目录>/Tests/StandaloneProbe.gd`。验证源时间边界、红灯曲线、恢复、30/60/120 Hz 和旋转缩放后的实际碰撞。
