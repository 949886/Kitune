# INARI 可复用机关

整个 `INARIMechanisms` 文件夹是通用复制边界。复制到另一个 Godot 4 工程后，可改名或放入任意子目录；无需 Rossi、ArtDirection、Autoload、另行安装插件或全局输入配置。环境音模块附带 Windows x64 原生扩展，其平台与部署范围见文末。旧模块不要只复制某个 `.tscn` 而漏掉 `Core` 和 `Assets`。

新增限时消失平台提供更小的独立复制边界：只复制 `Devices/DisappearingPlatform` 整个文件夹即可，全部精灵、声音、参数和脚本都在里面。详见 [平台复用说明](Devices/DisappearingPlatform/README.md)。运行 `Examples/DisappearingPlatformWorkshop.tscn`，或在展厅选择“限时消失平台”，可以体验踩踏、红灯警报、延迟收起与恢复。

## 示例玩家显示层级

共用的 `Examples/WorkshopPlayer.gd` 根据当前示例中的实际绘制层级，将玩家显示在装置前方；环境粒子的层级从发射器配置读取，不依赖粒子是否已经生成。初始化、房间切换和重建挑战后都会延迟刷新，等待装置完成创建。多个示例角色不会互相抬高层级，UI 和切场遮罩仍由各自的 CanvasLayer 控制。

运行 `Tests/WorkshopDrawOrderProbe.gd` 可检查全部展厅入口、独立运行、切场和重试；图形模式还会读取机械门和电梯前的实际玩家像素。可将 `INARI_CAPTURE` 设置为已有目录以保存这两张验证截图。

## 教程喷焰装置

截图中的倒挂火柱使用 `Devices/SteamJet/TutorialFlame.tscn`，默认向下持续喷射；神殿的向上喷口保留为 `SteamJet.tscn`。移动、旋转、缩放根节点可改变安装位置和喷射方向；每个实例独立持有粒子状态。打开 `Examples/DeviceGallery.tscn` 按 F6，可选择喷焰、平台、机械门、冰冻、可破坏门、存档热阱、风增益、电梯、场景切换、隐藏奖励、限时挑战或分波战斗练习；`SteamJetShowcase.tscn` 也可单独运行。现有 ArtDirectionLab 选关页有同一展厅入口。

Inspector 参数：

| 参数 | 含义 |
| --- | --- |
| `emitting` | 是否继续产生粒子；关闭后已有粒子自然消散 |
| `simulation_speed` | 原始各层模拟速度的倍率，1 保留原值（主焰 3、短焰/烟 2），0 暂停 |
| `source_asset` | 包内 Assets 子目录，由两个场景预设选择各自原始实例 |
| `random_seed` | 当前实例的随机种子 |
| `preview_in_editor` | 编辑器内显示喷口，运行时播放粒子 |

外部逻辑调用 `activate()`、`deactivate()`、`toggle()`；监听 `emission_changed(active)`。不访问场景树中的玩家、管理器或其他装置。接口开关是为复用提供的控制方式；原版教程默认持续运行。

来源为本机 INARI v0.2.1。倒挂预设取自 `level24 / Scene_GameDesign_STG0_2_ART / SteamTrap (2)`（GO 566），主焰初速度为 7；神殿预设取自 `level13 / Scene_GameDesign_STG0_1_ART / SteamTrap`（GO 687），主焰初速度为 3。两者均包含四个 SpriteRenderer、三个 ParticleSystem 和默认风扇动画。对应 `Assets/TutorialFlame/device.json` 和 `Assets/SteamJet/device.json` 保存参数、组件列表、脚本类型及来源哈希。两个导出层级均没有伤害碰撞、启用的粒子碰撞/触发模块或 `Fire` 组件，因此装置默认不造成伤害；此结论不代表整个原关卡没有其他伤害区域。

首次启用的场景实例按源 `prewarm` 预热一个 5 秒模拟周期，首帧即有火柱；后续开关不重置已有粒子。初始 `emitting = false` 时不预热，首次调用 `activate()` 后正常生长。预热采用固定子步，不受宿主的模拟倍率影响；这一语义依据 [Unity MainModule.prewarm](https://docs.unity3d.com/ja/2022.1/ScriptReference/ParticleSystem.MainModule-prewarm.html)。层次排序保留 Unity 的先层、后层内顺序，火焰的 layer 6/order -500 位于喷口的 layer 0 前方；不再把 -500 直接当作 Godot 的背景层。父节点的 Z 改变时，存活粒子也同步更新。

展厅的“原版曝光”开关使用原 `VolumeManager.SetBrightness` 默认值计算 +1.7 stops，并在线性颜色空间应用曝光，UI 在处理之后绘制。这是示例的全画面设置，拖入单个装置不会修改宿主的曝光。需要同样明暗时，可参考展厅的 `OriginalExposure` shader 接入宿主后处理；已有曝光的工程无需叠加。

当前视觉差异：沿用现有粒子移植的随机采样和 3D 到 2D 转换；NoiseModule 尚未移植，未重建原场景的灯光、Bloom 与 FMOD 环境混音。独立展厅使用自己的背景。此场景已还原原始喷口、像素素材、发射模块和默认动画，不宣称原场景逐像素一致。

## 全部机关的迁移约定

每一类机关都应有独立 `.tscn`，资源和脚本都留在此复制边界内。运行参数来自 Resource/原始数据，场景坐标不写入行为脚本。玩家伤害、奖励、存档、换场景和战斗事件通过显式接口或信号接入宿主工程；不能要求宿主使用 Rossi 的角色或管理器。每个模块必须同时通过原 demo 回归和空白工程复制验证，再记为迁移完成。

SteamJet、Lever、MovingPlatform、MachineDoor、IceBox、BreakableDoor、Checkpoint、SpikeStrip、WindStation、Elevator、ScenePortal、SceneObserver、HiddenReward、TimerStart、TimerFinish、DoorContact、MonsterSpawnTrigger、SpawnStamp、SpawnRope、CameraDistanceZone、CameraFixedZone 已有独立场景；TimeTrial、RoutePreview、BattleEncounter（含 ThresholdEncounter 阈值预设）、RepeatingSpawner、ArrivalBatch 和 CameraZoneController 提供可选联动。AmbientZone、BGMZone、ReverbZone 和共享 EnvironmentAudio 已迁移。电梯到站 Timeline、战斗收尾 Timeline 尚未迁移到此目录。它们在 demo 中可玩不等于已经满足复制复用要求；迁移将按上述标准逐模块进行。

`Core/Native` 是由 `Samples/ArtDirection/Tools/build_mechanism_native_runtime.py` 生成的最小渲染依赖集合。`Core/native_sources.json` 记录对应源码哈希；修改来源后重新生成，避免手改两份代码。运行资源包不依赖生成工具或原版安装目录。

## 验证

在工程内运行 `Tests/SteamJetProbe.gd`：检查两个源预设、首帧预热、原始速度倍率、暂停、向下喷射、跨层顺序、父级 Z 变化、初始关闭、实例状态隔离及重开无积压。在图形模式下还读取实际渲染结果，检查喷口下方确有连续的亮黄/橙红火柱，避免“模拟有粒子但被背景遮住”的漏检。设置可选环境变量 `INARI_CAPTURE` 可输出截图。

开发记录：Godot 4.7.2，OpenGL Compatibility；在空白工程的 `Nested/RenamedDevices` 目录下导入、运行测试和打开单体场景均通过，没有脚本错误。

原 demo 回归：IceBoxProbe、TimeTrialProbe、LabProbe 以及展厅窗口入口检查通过。


## 拉杆与移动平台

`Devices/Lever/Lever.tscn` 与 `Devices/MovingPlatform/MovingPlatform.tscn` 可分别实例化。默认采用 level22 第一组机关的原碰撞、35 个平台视觉项、轮子/灯光、拉杆七帧动画和两段音效，根坐标归零。原关卡实例编号仅用于内部视觉绑定，不再指定外部目标。

连接方式：

```gdscript
$Lever.activated.connect($Platform.activate)
$Platform.bind_passenger($Player, $Player/CollisionShape2D)
```

宿主的攻击命中拉杆时调用 `receive_hit(interaction, actor, direction)`，普通攻击为 4、重击为 8；原始默认位掩码为 12，苦无瞬移 64 不拨动拉杆。也可通过实际物理查询命中其子碰撞体，再取 `get_meta("device")` 得到场景根。可监听 `activated` 和 `switched(enabled)`；拉杆只发出信号，不搜索平台或场景管理器。

平台 `settings` Resource 可修改移动偏移、像素/秒速度、等待、缓动、循环和到站停止。默认 448 像素、192 像素/秒、0.75 秒等待和 0.5 缓动，均由源数据导出到 `.tres`；可以将移动偏移改成竖直方向。单个实例需不同配置时，将其 Resource 设为独立资源。重复激活保留原版两点平台的连续换向行为。

平台可不绑定角色独立运动。绑定一个 `CharacterBody2D` 及其 `CollisionShape2D` 后，可搭乘、推挤及检测夹压，不要求角色具有 `dead`、`body_shape`、`climbing` 等 Rossi 字段。宿主通过 `set_passenger_grip(climbing, hanging)` 传入攀附状态，通过 `unbind_passenger()` 解除绑定。角色控制器应将 Godot 自带的 `platform_floor_layers` 设为 0，避免与本平台显式乘载重复叠加；示例已经配置。当前每个平台绑定一名乘客，未实现多人自动扫描。

`passenger_crushed(actor)` 通知宿主夹压，不自动删除角色或修改生命。`set_motion_scale(value)` 控制运动时间倍率，0 停止运动；等待时钟保留原全局时间语义。场景整体暂停可使用 Godot `process_mode`。移动平台暴露 `started`、`arrived` 信号。

示例物理层：平台在第 1 层、可攻击拉杆在第 2 层、示例角色在第 3 层；平台 `solid_layers` 和拉杆 `hit_layers` 可在 Inspector 调整。复制资源包不会改动宿主的层名称或输入映射。

`Examples/PlatformWorkshop.tscn` 是可玩的联动示例：A/D 移动、空格跳跃、J 攻击拉杆，走上平台到右岸。示例角色是独立的简易 CharacterBody2D，不依赖原版主角；测试使用真实按键事件、形状查询和物理搭乘完成路线。另外检查实例状态隔离、单次限制、连续换向、倍率暂停、缩放后的乘载和普通胶囊角色的夹压信号。

原 demo 的平台乘载边界差异仍适用：尚非 Unity Passenger 射线的逐项等价实现；独立资源包使用平面局部构图，不携带原关卡的 2.5D 背景透视与环境灯光。已验证平移及一致缩放，未验收任意倾斜平台的乘载。原 demo 继续使用同一份行为源码；生成工具将该源码及最小依赖同步到资源包，避免另写一套近似玩法。

复制验收工具只依赖 Python 标准库和 Godot，可随资源包使用：

```powershell
python Tests/verify_portability.py <Godot可执行文件> --output <包外的测试目录>
```

它创建空白工程，将整包放入改名后的子目录，执行喷焰、平台、机械门、冰冻装置、可破坏门、存档点与热阱、风增益、电梯、场景切换、隐藏奖励、计时挑战和分波封锁的十二组实际运行检查，并保留工程与日志供复查。重建素材和源默认参数使用原工程的导出工具，运行时不需要这些工具。


## 机械门

拖入 `Devices/MachineDoor/MachineDoor.tscn`；根节点在通道底部中心，可平移、旋转、缩放。门使用 level5 原封锁房间出口的 13 个视觉项、8 张独立贴图、开关动画轨道及两段齿轮音效。默认初始关闭，碰撞释放比例 0.801，均由原记录导出到 `DoorSettings.tres`。`solid_layers` 默认第 1 层，可按宿主调整。

```gdscript
$Lever.activated.connect($Door.toggle)
$Battle.encounter_completed.connect($Door.open)
```

公开方法 `toggle()`、`open()`、`close()`、`is_open()`、`is_passable()`。`open/close` 是幂等命令，重复调用不会重启动画；`toggle` 则每次换向。`state_changed(open)` 通知逻辑状态，`passability_changed(passable)` 通知实际通道状态。开门要等原动画通过 `collider_release_fraction` 且越过转场时间才释放碰撞；关门立即阻挡。中断后旧的释放时刻作废。宿主应区分“正在开门”和“已可通行”。

`attachments_invalidated(surfaces)` 将相关 StaticBody2D 发给宿主，用于清除插在门上的投射物；门不会寻找玩家或删除宿主对象。宿主可监听 `state_changed` 保存状态，并在场景入树前给独立 `settings` 资源设置 `initial_open` 以恢复。包内没有存档管理器。运行时初始打开会直接设置原动画的末帧，不播放一次开门；编辑器预览显示原导出构图。

核对 `Door.cs` 后保留原版的不对称逻辑：关门后表面保持 HardWall，下一次开门完成才恢复 Wall；对应子碰撞体元数据为 `source_layer` 和 `climbable`。禁用的上门扇碰撞体保持禁用，隐形墙单独控制通道。原 demo 同步修正此前误启用上门扇碰撞的问题。

`Examples/DoorWorkshop.tscn` 可单独 F6 运行：A/D 移动、空格跳跃、J 攻击任一侧拉杆。`Tests/MachineDoorProbe.gd` 通过实际角色移动与攻击查询验证双侧阻挡、拨杆、动画位移、延迟放行、立即关门、反复切换、命令幂等、通知、音效、初始打开、实例隔离、旋转缩放与自定义碰撞层，以及展厅切换释放节点。测试也在空白改名工程运行。原 demo 的 BattleRoomProbe、TimeTrialProbe、CameraZoneProbe 回归通过。

当前门的动画播放沿用原 demo 的轨道移植，未实现 Unity Animator 转场视觉混合；FMOD 空间混音、全局灯光和存档事件系统仍由宿主负责。它是独立机械门，不包含整套战斗波次控制器。


## 冰冻装置

`Devices/IceBox/IceBox.tscn` 使用原版 level5 第一个 ElectroBox 的四个视觉项、五张动画贴图、两股子冷雾、六个冻结爆发粒子系统与原循环/启动音效。根节点保留源装置原点，移动、旋转和一致缩放会同步变换范围网格与阻挡查询；不依赖原版玩家、敌人、地图或全局管理器。

`settings` 是独立 Resource，源默认值为范围 240 像素、蓄能 0.5 秒、冻结 5 秒，并保留闪烁间隔及轮廓淡入时间。实际爆发在原 `FasterBlit` 闪烁序列跨过等待时间后发生，未替换成精确的 0.5 秒 Timer。单个实例只能触发一次，消耗后保留实体作为附着目标；宿主如需重置可重新实例化。

```gdscript
$IceBox.bind_observer($Player, Vector2(0, -16))
$IceBox.register_target($Enemy, $Enemy.freeze, $Enemy.can_freeze)
```

`bind_observer(actor, local_offset)` 仅用于距离轮廓和接近后启动循环声，未绑定也可受击爆发。也可设置 Inspector 的 `observer_path` 和 `observer_offset`。默认 `hit_layers` 为第 2 层；宿主命中子碰撞体后通过其 `get_meta("device")` 取得场景根，调用 `receive_hit(interaction, actor, direction)`。原 ElectroBox 覆盖父类攻击掩码检查，不通过 `InteractableType=28` 限制所有伤害。苦无仅附着时不调用此方法，实际瞬移命中时再调用（交互值 64）；角色瞬移位置与投射物生命周期由宿主控制。

`register_target(actor, freeze, eligible)` 显式注册目标；`freeze(seconds) -> bool` 由宿主执行冻结并返回是否成功，可选的 `eligible() -> bool` 表示当前是否存活、可被冻结等资格。`unregister_target(actor)` 解除注册，已释放节点也会自动清理。没有注册的角色不会被处理。示例角色拒绝在已冻结时刷新时长，并在结束后恢复巡逻；装置不直接改宿主速度或动画。

`blocking_layers` 控制冻结扩散阻挡，`outline_occluder_layers` 控制轮廓遮挡，两者默认第 1 层，无需原版 `source_layer` 元数据。保留源算法“先记录已访问格，再检查阻挡/半径”的顺序，因此墙体所在格以及一圈半径外边界仍可纳入目标筛选。不能把它等同于圆形范围或一次视线射线。

监听 `charge_started`、`discharged(affected)` 和 `feedback_requested("Attack")` 接入宿主事件/相机。循环 WAV 使用导出的原时间轴帧数并按实例停止，启动音效不会被其他实例的清理中断；FMOD 内部循环区域与释放包络仍使用既有音频导出的近似。

`Examples/IceWorkshop.tscn` 可 F6 运行：A/D 移动，J 攻击，R 更换已消耗装置。四个普通 CharacterBody2D 分别演示附近目标、隔墙目标、免疫目标和远处目标。`Tests/IceBoxProbe.gd` 验证实际攻击、蓄能/冻结/恢复、冷雾动画开关、六组爆发粒子及清理、循环音效停止、一次性事件、重新实例化、无观察者调用、无效注册清理、旋转缩放后的物理阻挡与原访问边界。改名复制后的空白工程验证和原 demo IceBoxProbe、BattleRoomProbe 回归通过。

当前视觉仍沿用现有粒子与材质移植：未复刻源 Light 2D、环境灯光/Bloom、Particle NoiseModule 与青色条纹材质的全部细节。独立场景补全了原层级两股常驻冷雾；旧战斗房间入口尚未接入这两股子粒子。来源字段和动画轨道保留在资源数据中，未将这些差异标为完成。


## 可破坏门

`Devices/BreakableDoor/WoodDoor.tscn` 与 `HeavyDoor.tscn` 分别来自 level2 第一扇木门和 level22 第一扇重击门，使用同一脚本和不同源配置。每扇门包含 21 个原始碎片精灵；木门只保留 19 个原本启用的多边形碰撞体，另两块只有视觉和自由落体。根原点为完整碰撞范围的底部中心，便于放置到地面。

通过 `receive_hit(interaction, actor, direction)` 接收宿主实际命中，普通攻击为 4、重击为 8、苦无瞬移为 64；`direction` 表示沿装置局部 X 轴的正负方向。木门默认掩码 -1，重击门默认 12。重击门普通攻击只播放命中反馈，重击才破坏；64 被其掩码拒绝。一个攻击查询可能命中多块碎片，同一物理帧内仅接受一次事件。`can_attach_projectile()` 使用导出的原 `ShurikenComponent` 字段，木门允许、重击门不允许，已破坏时均返回 false。

`receive_enemy_damage(amount, direction)` 沿用原 demo 的敌人伤害累计路径；`settings.health` 用于该累计。`receive_hit` 沿用原 demo 的按交互类型破门入口，不额外模拟宿主武器伤害值。`settings` 还控制交互掩码、无敌、消散时间和 `initial_broken`。默认消散时间为场景实例覆盖后的 10 秒，并非 C# 类默认的 2.5 秒。无敌会阻止玩家/敌人两条入口；独立修改实例配置时应复制 Resource。

监听 `impacted(interaction)`、`broken`、`debris_cleared`、`feedback_requested(kind)`。`attachments_invalidated` 通知宿主清理门上投射物；瞬移交互 64 不抢先清理，保留宿主完成瞬移的机会。破坏事件立即发出，静态碰撞层在当前物理回调后延迟清除。宿主可保存 `is_broken()`，下次入树前设置独立资源的 `initial_broken`，直接恢复隐藏/无碰撞状态，不播放碎片和音效。

默认实体在第 1 层，可攻击表面在第 2 层。碎片层默认为 0、检测地面掩码为 1，避免成为玩家的额外障碍；Inspector 可分别配置 `solid_layers`、`hit_layers`、`debris_layers` 和 `debris_collision_mask`。原发射角、速度/质量关系、重力缩放、阻尼、旋转约束、CCD 等源参数保存在数据中。`random_seed` 为每扇门独立的随机序列，避免实例互相影响全局随机状态。

碎片物理体保持单位缩放，把装置的完整初始变换作用到碰撞形状和发射速度，支持移动、旋转与一致缩放。重力保持世界坐标下的源默认方向，不随门转向。已生成的物理体脱离父节点变换但仍由装置拥有，因此移动破坏后的门根节点不会拖走碎片，删除装置仍会清理全部碎片。使用 Godot 的接触求解，不能宣称与 Unity 轨迹逐帧一致；空物理材质的摩擦 0.4、弹性 0 是既有适配假设。

`Examples/BreakableDoorWorkshop.tscn` 可 F6 运行：A/D 移动、J 普攻、K 重击、R 重置。`Tests/BreakableDoorProbe.gd` 通过实际走路、形状命中与碎片物理验证两类门的阻挡/破坏、同帧去重、音效、碰撞禁用、落地旋转、十秒渐隐及释放；另验证初始破坏状态、无敌、敌人伤害累计、旋转缩放下的生成几何和速度、移动父节点后的绘制同步、节点清理及展厅切换。

原 demo 的 DoorPhysicsProbe、RifleDoorProbe、BowDoorProbe 回归通过；整包改名复制与两个独立场景的 OpenGL 编辑器预览通过。全局相机和存档由宿主接入；原重击门普通命中的短暂材质闪白尚未移植，现有声音/信号反馈不代表该视觉细节已完成。


## 存档点与热阱

`Devices/Checkpoint/Checkpoint.tscn` 是 level22 第一个 InteractiveSaveTrigger 的独立场景。源实例的美术子树未启用，因此运行时保留隐形触发区，编辑器显示边框与出生位置。`settings` 提供原始触发大小、偏移、出生偏移和朝向；根节点可平移、旋转及一致缩放。示例中的青色标记是宿主提示，不是原版神社素材。

```gdscript
$Checkpoint.bind_actor($Player, $Player.can_save)
$Checkpoint.saved.connect(_save_checkpoint)
$SpikeStrip.register_player($Player, $Player.take_damage, $Player.can_take_damage)
$SpikeStrip.register_enemy($Enemy, $Enemy.take_damage, $Enemy.can_take_damage)
```

存档点只接受显式绑定角色的首次有效进入。可选 `can_save() -> bool` 由宿主检查存活等条件；留在区域内才恢复资格不会自动保存，需要重新进入。`saved(actor, payload)` 提供 `id`、出生点世界坐标 `position`、局部朝向正负值 `facing`、变换后的世界方向 `direction`。保存事件不回血、不回复体力、不修改角色或写文件。宿主应按自身角色原点转换出生位置；示例的角色原点在脚底，转换逻辑在 `Survivor.gd`。

Inspector 的 `checkpoint_id` 应由宿主填写唯一且稳定的 ID；不会重复使用原场景 ID，也不自动用节点路径作为持久化标识。宿主保存已使用状态，下次入树前在独立 `settings` 上设置 `initially_activated = true`，可恢复已使用状态而不重发保存事件。`is_activated()` 查询当前状态。没有内置跨启动存档管理器；示例仅保留本次场景会话的复活点。默认 `actor_layers` 为第 3 层。

`Devices/SpikeStrip/SpikeStrip.tscn` 使用 level22 第一个 SettedSpike 的第一块连续多边形，原尺寸约 272 × 48 像素，根原点在碰撞区底部中心。对应四个 HeatTrap 的 24 个精灵和八股原始蒸汽已一并导出，保留连续平铺、边框、裁剪和原碰撞顶点。它是一段可重复摆放的热阱，不包含原地图另一个不相连的伤害区。装置只有触发碰撞，不提供地面阻挡。

源默认伤害为 999999，来自 `SpikeSettings.tres`；可复制设置资源后修改。默认检测第 3、4 物理层，`actor_layers` 可改。角色必须先显式注册，并匹配物理层，才能受伤；`unregister_target(actor)` 解除注册，已释放角色自动清理。`damage(amount) -> bool` 由宿主执行伤害并返回是否接受；可选 `eligible() -> bool` 应包含死亡、无敌等判断。玩家在每个重叠物理步尝试，因此无敌结束后仍站在区域内会受伤；敌人只在进入时尝试，无敌解除不补发，需离开再进入。

`damaged(actor, amount)` 仅在伤害回调返回 true 时发出。敌人进入还会独立发出 `feedback_requested("Attack")`，即使伤害被资格检查拒绝，保留源相机反馈语义。装置不直接调用相机，不发放玩家击杀奖励。节点暂停时不调用伤害回调；实例有各自的粒子随机序列和注册表。

`Examples/CheckpointHazardWorkshop.tscn` 可 F6 运行，也可在展厅选“存档点与热阱”。A/D 移动、空格跳跃、R 由宿主复活、I 临时无敌 4 秒、E 让敌人走进热阱。复活后示例等待两次物理步更新重叠表，避免传送前的旧接触在新出生点再次造成伤害；这属于示例控制器的传送处理。I/E 是练习控制，不是新增的原版机关功能。

`Tests/CheckpointHazardProbe.gd` 使用真实输入和物理重叠验证首次存档、不回血、复活、玩家持续接触、敌人仅进入、无敌和未注册过滤、自定义层、节点禁用、源多边形的旋转缩放、状态恢复与展厅释放。热阱视觉仍沿用既有粒子移植，源环境灯光、Bloom、粒子 Noise 及未支持的 Animator 轨道不在已完成范围。

本模块验收：Godot 4.7.2 OpenGL 下，整包复制到空白工程的 `Nested/RenamedDevices` 后导入与六组运行探针全部通过；两个新单体场景的编辑器预览通过。原 demo 的 CheckpointHazardProbe 和 PlayerDamageProbe 回归通过，无脚本或资源加载错误。原工程退出纹理析构诊断和沙箱用户目录缓存/证书提示仍存在。


## 风增益装置

`Devices/WindStation/WindStation.tscn` 使用 level15 第一个 MoveSpeedChangeTrigger 的原触发框、两个精灵、65 张所需精灵帧、四状态 Animator 和触发音效。包含 SpriteRenderer 的离散帧切换与材质曲线混合；各实例持有独立材质、音效节点、冷却和体力发放状态。根节点可平移、旋转及一致缩放，默认触发框为 128 × 128 像素。旋转装置只改变摆放与触发区域，不改变角色的增益移动方向。

可选 `WindBuff.tscn` 是放在宿主角色下的增益组件，共用原 demo 的衰减和升级代码。接入示例：

```gdscript
$Station.bind_actor($Player, $Player/WindBuff.request_from_station, $Player.is_spawning)
$Station.stamina_requested.connect(func(actor, amount): actor.add_stamina(amount))
$Station.story_heal_requested.connect(func(actor, amount): actor.heal_if_story_mode(amount))
```

`bind_actor(actor, receive_buff, is_spawning, can_receive)` 后三个参数是回调，只有 `receive_buff()` 必填；其余两个分别返回是否处于出生动作、当前是否允许接收。未提供出生回调时立即激活，未提供资格回调时接受已绑定且可处理的角色。没有注册的角色、物理层不匹配的角色与禁用节点均被排除。默认 `actor_layers` 为第 3 层；死亡等状态由宿主资格回调判断。可在入树前绑定，宿主信号连接应在首次物理接触前完成。

每次有效进入先发出 `story_heal_requested(actor, amount)`，宿主只在剧情模式应用原默认 100 点治疗。然后首次进入会发出 `stamina_feedback_requested(actor)` 与 `stamina_requested(actor, amount)`，原默认补充 45 体力；以后即使冷却结束也不再次补体力。装置本身不读写角色属性，体力上限、剧情模式与角色特效由宿主处理。

`began` 时立即开始原 On 动画和触发音效。如果角色还在出生动作中，装置等待该动作结束，再调用 `receive_buff()`、发出 `activated(actor)`，并开始原默认 5 秒冷却。角色离开触发框不会取消这次已开始的等待；解绑、释放或失去接收资格会取消等待，发出 `cancelled` 并恢复待机动画。`unbind_actor()` 或重新绑定不会把旧请求转交给新角色。

冷却按普通游戏时间推进，不跟随角色增益时间倍率。冷却结束还须等 Animator 离开 Ready，再触发 Off 和 `cooled`。站在触发框内不会在冷却结束后自动重复启动，需离开再进入。`is_cooling()` 查询冷却，`has_granted_stamina()` 查询一次性体力状态。入树前可在独立 `settings` 上设置 `stamina_already_granted` 恢复体力已发放状态；场景没有内置存档管理器，也不保存中途冷却。

`WindBuff.tscn` 的原默认配置是 1 级初始增加 64 px/s、持续 6 秒；2 级初始增加 96 px/s、持续 12 秒（已由 Unity 4/6 单位按 16 px/单位换算）。角色用只读 `extra_speed` 叠加自己的水平目标速度；`level` 和 `ratio` 提供当前等级和衰减比例。不会自动更改 CharacterBody2D 的速度、跳跃、攀爬或制动。`motion_time_scale` 控制增益时钟，0 暂停衰减；整个节点树暂停则同时停止装置和角色组件。

首次请求与刷新会先清零额外速度，下一次组件物理更新才采样源速度。保留原“先采样当前比例、再增加计时”的顺序和浮点精度：到达持续时间的那一步仍持有最后样本，下次更新才清除。`request_from_station()` 在无增益时给 1 级，有增益时刷新当前级。宿主确认玩家击杀后调用 `notify_player_kill()`，已有增益升一级至配置上限、满级则续期；没有增益时击杀不能凭空获得 1 级，但仍请求源体力反馈并播放续期音效。宿主应只对真正归属于该玩家的击杀调用一次。

监听 `changed(level)` 更新状态，监听组件的 `stamina_feedback_requested(current_level, previous_level)` 接入角色反馈。`reset()` 供死亡、复活等宿主事件清除增益。组件不依赖发放它的装置，删除装置不会删除角色当前增益；删除组件会释放其声音。续期音效在独立组件下播放，由角色拥有；原 demo 的敌人声音所有权和 FMOD 空间混音没有照搬到宿主。原角色专属描边、Eff_Accel、跑步尘埃和距离尾迹也仍由宿主接入，这些不是该装置层级的子效果，简单展厅角色只显示颜色与数值反馈。

`Examples/WindWorkshop.tscn` 可 F6 运行：A/D 移动，空格跳跃，J 攻击目标，E 重置练习目标。两台装置共享角色上的同一个增益组件，能观察首次加速、逐渐衰减、攻击目标升级、第二装置续期，以及每台装置独立的一次体力。展厅的目标是普通宿主物理体，原敌人的归属与声音路径另外通过原 demo 回归测试。

`Tests/WindStationProbe.gd` 检查真实移动/攻击、衰减与满级续期、不能从击杀获得首级、冷却期间独立治疗、一次体力、声音次数、材质和实例隔离、角色时间倍率与树暂停、旋转缩放后的实际触发、出生延迟、离区后完成请求、解绑/释放取消、零冷却 Animator 等待和展厅切换释放。

风增益模块验收：整包改名复制至空白工程后导入及七组运行探针通过；原 demo 的 WindBuffProbe、WindAnimationProbe、WindAudioProbe 回归通过。站点与角色增益组件使用同一份生成的原行为源码，源像素、参数与已有装置导出记录已核对。


## 单次启动电梯

`Devices/Elevator/Elevator.tscn` 来自 level14 的首台电梯，包含移动轿厢、按钮、两侧门、固定出发站蒸汽和途中出口。42 个视觉项、28 张精灵帧、两段音效、原触发框与碰撞形状均从源层级导出。根节点是源平台原点，轿厢地面在局部 Y = -32；出发站和出口不随轿厢移动。门扇动画偏移叠加平台位移，避免动画将门重置回出发位置。

在电梯进入场景树、完成 `_ready()` 后绑定普通 CharacterBody2D 与其碰撞形状；宿主输入调用交互：

```gdscript
$Elevator.bind_passenger($Player, $Player/CollisionShape2D, $Player.can_interact)
# 在宿主的交互输入处理函数内调用：
$Elevator.interact($Player)
$Elevator.projectile_recall_requested.connect(_recall_player_projectile)
$Elevator.scene_exit_requested.connect(_request_scene_change)
```

第三个资格回调可省略。按钮只接受已绑定、仍可处理、符合物理层且实际重叠的角色；`can_interact(actor)` 查询，`interaction_available(actor, available)` 通知提示与源描边变化。`interact(actor)` 返回是否接受；成功后立即消耗按钮、关门并请求宿主收回投射物，只能使用一次。`unbind_passenger()` 清理当前乘客与攀附状态，不重置已消耗按钮。重置应重新实例化。

`settings` 使用源默认值：位移 `(0, -1216)`、速度 160 px/s、等待 2 秒、缓动 0.5、到站碰撞释放延迟 0.2 秒、描边渐变约 0.2 秒。每台需要不同值时复制 Resource。`started` 表示已接受启动并开始等待；`arrived` 表示物理行程完成；`doors_changed(closed)` 表示门的实际阻挡状态。开门动画开始后仍需等释放延迟才能离开。循环声在到站时停止；出发站蒸汽按原动画再次启用并重播一次，不因连续 active 样本无限重启。

`solid_layers`、`actor_layers`、`particle_collision_mask` 分别配置实体、角色检测、粒子碰撞，默认第 1、第 3、第 1 层。搭乘适配沿用 MovingPlatform，支持一个显式乘客；宿主角色应设置 `platform_floor_layers = 0`，避免 Godot 自动搭乘再次叠加位移。需要攀附时传入 `set_passenger_grip(climbing, hanging)`；`passenger_crushed(actor)` 由宿主处理伤害。`set_motion_scale(value)` 只改变移动时间倍率，不暂停门和站点效果的普通时钟。根节点可平移、旋转与一致缩放，物理几何和局部行程一起变换；宿主角色的重力和控制方向不会自动旋转。

原 level14 的 SceneMoveTrigger 在轿厢到达物理终点前触发。这里保留源触发位置并发出一次 `scene_exit_requested(actor, destination)`，默认目的键 `level2`，不会直接加载宿主场景。`scene_exit_enabled` 可关闭它；改行程时也应修改 `settings.scene_exit_offset/scene_exit_size`，固定出口不会自动随新行程重定位。源出口的碰撞偏移仍保留在导出记录中。示例观察该信号后继续完整搭乘，以便测试到站开门；原 demo 仍按原流程换关并播放已有到站 Timeline。

`Examples/ElevatorWorkshop.tscn` 可 F6 运行：A/D 移动、空格跳跃、走进轿厢后 F 启动、到站后向右离开。`Tests/ElevatorWorkshopProbe.gd` 使用真实输入与碰撞，验证区外拒绝、单次启动、描边、门阻挡、等待、移动暂停、蒸汽重播、音频循环、乘客携带、动画随行、途中出口、延迟开门、出梯、变换后的几何、自定义粒子碰撞层、实例隔离及展厅释放。

此独立场景不包含 level2 的到站 Timeline、相机/玩家控制转交与全局存档；这些仍需独立迁移。沿用现有平面投影、粒子射线碰撞与 Animator 轨道适配，未实现源粒子的有限半径碰撞、Noise、环境 Bloom、FMOD 空间混音及所有未支持的动画绑定，不宣称与 Unity 逐帧相同。

本模块验收：Godot 4.7.2 OpenGL 下，整包复制至空白工程的 `Nested/RenamedDevices` 后导入及八组运行探针全部通过；电梯单体编辑器预览通过。原 demo 的 ElevatorProbe、MachineryProbe、IceBoxProbe 回归通过，无脚本或资源加载错误。33 项生成源码哈希、源文件/输入数据哈希已核对，旧十份装置/组件导出记录保持一致。已有沙箱缓存/证书提示及原工程退出纹理析构诊断未在本模块处理。


## 场景切换区域

`Devices/ScenePortal/ScenePortal.tscn` 默认使用 level14 电梯出口；`MaintainedInputPortal.tscn` 使用 level11，`RepeatablePortal.tscn` 使用 level12。`Presets` 内包含原安装包全部七个 SceneMoveTrigger 的设置资源，可直接更换 `settings`：

| 源关卡 | 目的键 | 一次性 | 保持输入 |
| --- | --- | --- | --- |
| level6 | level16 | 是 | 否 |
| level8 | level23 | 是 | 否 |
| level11 | level12 | 是 | 是 |
| level12 | level27 | 否 | 否 |
| level14 | level2 | 是 | 否 |
| level24 | level26 | 是 | 是 |
| level28 | level27 | 否 | 否 |

目的键由原 SceneReference GUID 与 BuildSettings 解析，原触发尺寸、偏移、一次性和输入字段均保留。七个源节点都没有 Renderer，美术预览只显示编辑器边框；展厅的青色矩形是宿主提示。层级中的 SpawnPoint 是没有脚本的空 Transform，已记录到来源数据，不把它误用为目的关卡出生点。实际出生点由目的场景/宿主决定。

将根节点移动、旋转或一致缩放即可摆放触发区；输入方向仍是世界输入，不随触发区旋转。`actor_layers` 默认第 3 层。`bind_actor(actor, can_transition, is_scene_loading)` 显式绑定普通物理角色，两个可选回调分别判断存活等资格、宿主共享加载状态；可在入树前绑定，以覆盖出生时已重叠的情况。未绑定、错误层、禁用节点和不满足资格的角色不会触发。所有出口都应使用同一个宿主加载状态，避免跨出口重复请求。

只有有效 Enter 才发出 `transition_requested(actor, request)`；加载中被忽略的进入不会在加载结束后变成持续接触触发，需要重新进入。状态先锁定再通知宿主，重复物理接触不会产生第二个 pending 请求。一次性出口同时变为非活动；可重复出口保持活动，宿主调用 `finish_request()` 清除待处理状态后，下次 Enter 可以再次触发。`finish_request()` 不会重新启用一次性出口。`is_active()`、`is_pending()` 查询状态，`set_active(value)` 对应原 Trigger 激活/存档恢复；重新启用时仍在范围内的角色会产生新 Enter。`unbind_actor()` 清除资格和加载回调，不改变已消费状态。

`portal_id` 由宿主填写稳定的保存键。监听 `active_changed(active)` 保存，下一次实例入树前给独立 Resource 设置 `initially_active`；没有内置存档文件。触发大小、偏移、once 和初始活动状态在入树时应用；不同实例修改前需复制设置资源。目的键及输入设置在每次请求时读取并深复制，后续修改不改变已经发出的请求。

请求包含 `id`、`destination`、原配置转换到 Godot 坐标的 `input_direction`、`maintain_input`、`preserve_last_input`、`injected_input`、`grant_invincibility` 和 `reset_dash`。原非零保持方向经 PlayerInputController 逐轴处理，Unity 的 Sign(0) 为 +1，源 `(1, 0)` 因此产生 Unity 输入 `(1, 1)`，转换到 Godot 为 `(1, -1)`；已从游戏的 UnityEngine.CoreModule.dll 核对，也见 [Mathf.Sign 官方说明](https://docs.unity3d.com/ScriptReference/Mathf.Sign.html)。配置为零向量且保持输入时，宿主应保留先前输入，不注入一个零方向。无敌与冲刺重置仅在 maintain_input 为 true 时请求，具体角色能力由宿主执行。

可选的 `SceneTransition.tscn` 是常驻 CanvasLayer 过渡器，放在被替换房间之外。`request(actor, request)` 成功返回非零 ticket，忙于淡出/加载或目的键为空时返回 0。默认淡出与淡入各 2 秒、OutQuad，与原序列一致；`settings` 可配置时长和颜色。使用独立时间，树暂停或 Engine.time_scale = 0 时仍会推进遮罩，不擅自修改宿主的全局时间倍率。

```gdscript
$Portal.bind_actor($Player, $Player.can_transition, $Transition.is_loading)
$Portal.transition_requested.connect($Transition.request)
$Transition.began.connect(_apply_actor_transition_policy)
$Transition.covered.connect(_load_destination)
# 宿主完成异步加载、出生位置和角色状态恢复后：
$Transition.finish_load(ticket)
$Transition.finished.connect(_restore_controls)
$Transition.cancelled.connect(_restore_controls_after_cancellation)
```

`began(actor, request, ticket)` 在淡出前通知输入策略；`covered(request, ticket)` 在全黑后要求宿主加载；宿主完成后调用 `finish_load(ticket)`，触发 `loaded(request, ticket)` 并开始淡入；`finished(request, ticket)` 在淡入后恢复控制。原 OnAfterSceneChanged 在淡入前清除保持输入与无敌，示例在 `loaded` 完成这一步。宿主自己负责出生点、回血/体力、过场、存档、音频和实际场景加载，过渡器不会把目的键当成任意资源路径加载。

`is_loading()` 仅覆盖淡出/全黑加载期，保留源管理器在淡入前结束 loading 的时机；`is_transitioning()` 则覆盖整个遮罩流程。淡入期间新的有效请求会取消旧视觉流程并从当前透明度重新淡出，旧 ticket 不能完成新加载。取消或移除组件会发出 `cancelled` 并移除遮罩；宿主应在取消时恢复角色控制。如果宿主保留原出口，可在 loaded/cancelled 后调用其 `finish_request()`；一次性出口如需因加载失败而重试，须由宿主明确调用 `set_active(true)`。

`Examples/PortalWorkshop.tscn` 可 F6 运行，也可在展厅选“场景切换区域”。A/D 向右经过两种出口，实际销毁旧房间并实例化目标 PackedScene；第一段保持输入，第二段停下等待。R 可中断并重新体验。三间房间是宿主练习场景，不是原关卡美术；示例角色没有攀爬/冲刺能力，只演示水平移动并记录冲刺重置请求，二维输入完整载荷仍传给宿主。

`Tests/ScenePortalProbe.gd` 检查真实移动/初始重叠、实际换房间、两类输入策略、源七个配置、一次性/重复/恢复、资格/层/禁用过滤、旋转缩放、世界输入与零向量保留、暂停和零时间倍率下的淡出淡入、加载防重入、旧 ticket 拒绝、取消及展厅释放。覆盖的是 SceneMoveTrigger 与可选过渡器；MoveSceneObserver、Timeline、关卡流式预加载和原全局管理器仍是独立待迁移内容。

本模块验收：Godot 4.7.2 OpenGL 下，整包改名复制后导入及九组运行探针全部通过，三个出口单体的编辑器预览通过；最终出口代码再次通过运行探针。原 demo ElevatorProbe、LabProbe 回归通过，无脚本或资源加载错误。全部七个源出口、33 项生成源码哈希、源资源/行为代码/导出输入哈希已核对，既有十一份装置/组件导出记录保持不变。已有沙箱缓存/证书及原工程退出纹理析构诊断仍未处理。


## 隐藏奖励与追踪光点

`Devices/HiddenReward/HiddenReward.tscn` 使用 level3 计时挑战房间的原 HiddenItem：80 × 80 像素触发框、9 个视觉项、32 张精灵帧、7 个追踪光点、8 组子粒子、原收集/生成音效和 Destroy 缓存动画。机关本身不判断计时成功，原版依靠门阻止角色提前接触；宿主可连接已有 MachineDoor 或资格回调。计时器起终点可使用下述 TimeTrial 组件连接。

```gdscript
$Reward.bind_actor($Player, $Player/CollisionShape2D, $Player.can_receive_reward)
$Reward.reward_granted.connect(_grant_and_save_reward)
$Reward.currency_requested.connect(_add_currency)
$Reward.renew_existing_buff_requested.connect(func(_actor): $Player/WindBuff.refresh_existing())
```

绑定可以在入树前完成。`bind_actor(actor, target, eligible)` 的 target 必须是角色本身或其子 Node2D，通常使用身体碰撞形状；回调可省略。默认 `actor_layers` 为第 3 层。只有绑定且可处理、物理层相符、满足资格的角色进入时才能领取，未绑定角色不会触发；不使用按键，也不依赖原项目玩家类型。资格在持续重叠时恢复不会补发 Enter。

领取立即消耗触发器并开始动画，发出 `renew_existing_buff_requested(actor)`、`reward_granted(actor, amount, reward_id)`。`reward_id` 由宿主给出稳定保存键，`settings.reward_amount` 原默认 1。风增益的 `refresh_existing()` 仅续期当前等级，零级保持零级，不升级，不模拟玩家击杀反馈。不同奖励和角色组件分别持有自己的状态。

光点按实际接触逐个发出 `currency_requested(actor, amount)`，`settings.currency_per_fragment` 原默认 1；领取主奖励不会立即加 7 个光点。原最大速度、起始速度、0.3 秒最短追踪时间及碰撞半径留在来源数据中；命中查询只接受绑定角色，其他同层物理体不能代收。根节点可平移、旋转、一致缩放，源触发区和视觉一起变换；追踪速度与碰撞半径保留世界空间数值，和源 Translate(Space.World)/OverlapCircle 相同。

`motion_time_scale` 控制光点的自定义移动时钟，0 停止位移与追踪进度，不暂停 Destroy 动画或子粒子的普通时钟。已超过最短时间的光点仍可按源逻辑在原地接触角色。`random_seed` 为每个实例独立的随机源，不影响其他装置。`received_fragment_count()` 查询已收到数量；`fragments_finished(received_count)` 在全部追踪完成或取消后发出一次，不代表所有粒子已经消失。

Destroy 动画源长度约 0.3333 秒、速度约 0.3，实际播放约 1.11 秒。前六个光点在开始时启用，第七个的 ShurikenChargePoint 组件在最后一帧才启用，不能把组件 m_Enabled 当成 SpriteRenderer 隐藏。收集光点只隐藏它的精灵，原 GameObject 仍启用，所以其子粒子继续发射；角色死亡、解绑、失去资格或释放时，剩余光点取消，相关尾迹停用。重新绑定不将已发出的奖励转送给另一角色，也不重发主奖励。

`settings.initially_collected` 在实例入树前用于恢复已领状态：隐藏视觉、禁用触发，不创建追踪光点，不补发事件/音效。示例 R 重载保留已领取标记和宿主数值；重载前尚未接触角色的光点不会补发。包不读写存档文件，持久化主奖励与逐个货币由宿主实现。

折射视觉使用原 Circle 的 12 个顶点、30 个索引及原 UV，避免把白色遮罩纹理当成普通精灵。SquareDistortion 的 Twirl、整数梯度噪声、范围/柔化、流动、屏幕取样、缩放与强度曲线根据原 D3D11 字节码和材质参数移植，程序与来源文件哈希保留在 device.json。当前 Godot 屏幕拷贝时机和原 Unity sorting-layer capture 不完全相同，时间相位也随宿主运行时间变化，因此不宣称逐像素一致。

三组源 Light2D 的亮度、半径、启用曲线保留，通过 `lights_changed(source_lights)` 和 `get_light_state()` 提供独立快照；其中 transform 为奖励根下的局部变换，宿主可接入自己的灯光。独立场景尚未重建 Unity 的分层环境灯光/Bloom；沿用现有粒子模块适配，NoiseModule 与部分 3D 细节仍未实现。MiniParticle 和七股跟随粒子已包含，未将这些剩余视觉差异记为完成。

`Examples/RewardWorkshop.tscn` 可 F6 运行：A/D 移动、空格跳跃、接触两件奖励。先领取左侧奖励证明无风增益时不会新增等级，再经过中间风装置领取右侧奖励观察续期；R 重载保存状态。该例的库存和保存字典属于宿主，不是包内全局管理器。

`Tests/HiddenRewardProbe.gd` 验证实际移动与接触、一次主奖励、七次光点入账、第七个延迟启用、粒子初始祖先可见性与随行、折射网格和实渲染不遮白、动画缩放/强度、源声音次数、风增益续期、移动倍率、恢复不重复奖励、资格/碰撞层/禁用节点、旋转缩放、自定义货币数值、角色释放及展厅清理。

本模块验收：Godot 4.7.2 OpenGL 下，整包改名复制后导入与十组运行探针通过；最终奖励代码再次通过 HiddenRewardProbe 和单体编辑器预览。原 demo TimeTrialProbe、ParticleProbe、WindBuffProbe 回归通过。35 项生成源码哈希已核对，无脚本、着色器或资源加载错误；已有沙箱缓存/证书/编辑器存储及原工程退出纹理析构诊断仍未处理。


## 计时起点、终点与路线预览

`Devices/TimeTrial/TimerStart.tscn` 和 `TimerFinish.tscn` 可分别实例化；每个终端保留 level3 原 16 个视觉项、12 张精灵帧、四位滚动数字、两态 Animator、触发框、接近描边与六种声音。原层级没有子 ParticleSystem。终端通过显式 `bind_actor(actor, can_use)` 绑定角色，再由宿主输入调用 `interact(actor)`；只接收绑定、可处理、资格满足且物理层相符的接触角色。`actor_layers` 可自定义，不读 InputMap，也不写玩家的 interaction_target。移动、旋转和一致缩放会一起变换触发区及视觉。

单体终端 `used(actor)` 发出一次使用事件；可选 `use_request(actor) -> bool` 决定是否接受并消耗，`proximity_changed(actor, nearby)` 供宿主显示操作提示。`disable()` 禁用交互；`play("timer_idle"/"timer_run")` 控制原动画。物理层切换后，静止角色可能未重新进入 Godot 的 Area2D 缓存；交互会在缓存缺失时补查当前物理形状接触，不能靠任意同层物体代替绑定角色。

`TimeTrial.tscn` 包含这两个终端与协调器，初始相对位置由源引用和坐标导出。实例入树后调用：

```gdscript
$Trial.bind_actor($Player, $Player.can_interact)
$Trial.start_door_requested.connect($StartDoor.toggle)
$Trial.reward_doors_requested.connect($RewardDoor.toggle)
$Preview.bind($Trial, $Camera2D, $Player, $Player.set_input_enabled)
# 在宿主的实际按键逻辑中调用；终端内部不会自动读取按键。
$Trial.starter.interact($Player)
```

`TrialSettings.tres` 的源默认时限是 30 秒，相机阻尼 2、接近阈值 32 像素；实例需要不同值时复制 settings Resource。第一次启动设置起点存档请求、发出 intro 保存请求，再发出 `preview_requested(ticket, stops, damping, threshold)`。预览完成前起点门保持关闭、时钟不走。宿主恢复相机和输入后调用 `complete_preview(ticket)`；取消、重绑定和旧 ticket 不能启动另一轮。没有绑定相机适配器时，应由宿主处理这个请求，不会自动超时跳过。

预览结束或已看过预览时，协调器请求起点门 Notify/toggle，启动两端数字和音效。`clock_scale` 为零只阻止倒计时；任何正数都使用普通 delta，不按倍率加速。源逻辑在减时间之前检查整秒边界，每帧最多滚动一次，并采用最短 UV 环绕的 1 秒 OutQuad；没有替换成 Label 或精确每秒 Timer。重试分支原 C# 会重复调用两次启动声和终点循环声，这些调用也保留；两端计时状态同步，不额外创建重复计时任务。

终点通过 `interact(actor)` 确认，停止计时/循环声并请求奖励门 toggle，随后宿主可沿真实通道接触 HiddenReward。源终点不判断是否先启动计时，原关卡用门限制路线；需要额外资格时由宿主回调给出。时限归零只禁用终点、播放结束音和 idle 动画，不杀死角色、不发奖、不自动重开门。协调器的 state 描述关卡结果，remaining 提供剩余时间，timer_changed(seconds, visible) 供宿主 UI 使用。

存档接口：`checkpoint_requested(actor, world_position)` 请求以起点位置保存出生点；`intro_save_requested` 请求保存已观看标记。`destination_save_requested(record, save_now)` 提供 IsTimeOver / CollEnabled 两个源字段：成功与存档后死亡立即请求保存；普通超时只改变待保存记录。用 `settings.intro_seen` 和 destination_saved/time_over/enabled 在入树前恢复。原 LoadData 只要读到终点记录就将该终端数字初始化为零，成功记录也一样。存档、门状态和奖励状态由宿主保存，包内没有全局文件存储。

将实际存档点事件连接 `notify_checkpoint_saved()`，将实际角色死亡事件连接 `notify_actor_died()`。源特殊行为也保留：存档后死亡立即禁用终点并保存失败，但已经启动的倒计时仍走到零，归零再次触发结束音；期间仍可有滚动数字和 tick。未经过该存档点的普通死亡不会自动判定超时。`cancel()` 用于宿主销毁或放弃尝试，禁用两端并停止声音，取消预览且恢复宿主输入；重新尝试请重新实例化。

可选 `RoutePreview.tscn` 使用源四个停靠点/等待时间、阻尼公式和返回时仅检查横向距离的条件。默认点位来自起点的局部源数据并转换为世界坐标；`route_override` 可接收宿主自己的世界点位、wait 和 distance 字典。Camera2D 接管期间宿主应暂停自己的跟随逻辑，适配器恢复原 offset 和平滑开关。等待使用普通 delta（原 MyWaitForSeconds 比较 Unity Time.time），不受自定义计时时钟为零影响。停止/释放时释放相机与输入控制；角色或相机在途中释放也会取消。

该适配器覆盖二维移动与等待，`depth_changed(source_depth_offset)` 保留源纵深变化供宿主投影使用，未将透视纵深伪装成固定 Camera2D zoom；独立示例没有原关卡透视背景和分层灯光。Cinemachine soft/dead zone、原全局模式管理和 Timeline 仍由宿主自己的相机系统处理。原 demo 的完整相机 rig 继续独立运行。

`Examples/TimeTrialWorkshop.tscn` 可 F6：A/D 移动、空格跳跃、F 启动/确认，第一次先预览，随后穿过起点门前往终点并进入奖励房。R 用宿主字典恢复状态，N 清空练习记录重新体验，H 模拟存档后死亡。示例关卡是短练习路线，不包含原战斗波次；机关美术、动画、30 秒规则及源停靠等待来自原记录。

`Tests/TimeTrialWorkshopProbe.gd` 使用实际输入、角色移动和门碰撞验证整条成功路线与七次光点接触；另验首轮预览/重试跳过、零/正数时钟语义、超时、存档恢复、死亡后计时继续、过期预览票据、取消输入恢复、独立旋转缩放终端、资格和自定义物理层、实例释放与展厅切换。

本模块验收：Godot 4.7.2 OpenGL 下，完整资源包改名复制到空白工程并重新导入，十一组运行探针通过。最终计时挑战额外通过死亡后继续计时与结束音检查、实际移动/门/奖励回归；起点、终点、组合场景的三次编辑器预览通过。原 demo TimeTrialProbe、LabProbe 通过。38 项生成源码哈希，以及两个新装置的导出输入、行为代码、配置、逐图像像素和音频内容均已核对；最终运行没有脚本、着色器或资源加载错误。已有缓存/证书/编辑器存储与原工程退出纹理析构诊断未在此模块处理。


## 分波封锁与接触封门

`Devices/BattleEncounter/BattleEncounter.tscn` 是独立波次协调器，`Devices/DoorContact/DoorContact.tscn` 是可单独使用的隐形门触发区。默认配置从 level5 的 SpawnManager 11791、DoorContactTrigger 11911 导出：两波各四名敌人，波间等待、清场收尾及入场后的静止等待各 0.25 秒，入场等待 1.2 秒。原 ID 只保留在 `Assets/BattleEncounter/device.json` 的审计映射；运行时使用宿主可编辑的成员名称，不按 ID 寻找节点。

波次成员、局部入场点、砸印/绳索类型和偏移来自 `EncounterSettings.tres`。原生已在场的第一波直接启用；后续波次先发出入场效果请求，注册成员，等待自定义 hit-stop 倍率非零，再开始 1.2 秒游戏时间等待，出现后静止 0.25 秒才恢复活动。波间和末尾等待使用实时时间，不受 Engine.time_scale 或自定义 hit-stop 影响；已经进入入场等待后，自定义倍率再归零不重新阻塞该等待。共享 `InariEncounterClock` 同时用于原 demo 和此可移植协调器。

宿主在父节点 `_ready` 中绑定已就绪的敌人：

```gdscript
$Encounter.bind_enemy(&"wave_1_enemy_1", enemy, enemy.set_active, enemy.set_peaceful)
enemy.defeated.connect(func(): $Encounter.notify_defeated(&"wave_1_enemy_1", enemy))
$Encounter.completed.connect($ExitDoor.toggle)
$Contact.bind_actor($Player, $Player.can_enter, host_is_loading)
$Contact.contacted.connect(func(_actor): $EntryDoor.call_deferred("toggle"))
```

两个敌人回调分别接受 `bool`。宿主决定 AI、碰撞和视觉如何响应 active/peaceful；协调器不要求特定玩家、血量类或攻击系统。绑定时先隐藏所有敌人，默认在 deferred start 中启动第一波。缺失成员不会被当作已死亡，补齐后可以显式调用 `start()`。`on_field = false` 的配置通过 `start_spawn()` 启动，重入调用返回 false；可连接下述 MonsterSpawnTrigger 独立延迟触发场景。

`notify_defeated(key, actor)` 只接受已注册且未计数成员的首次死亡通知，包括增援后留场的旧成员。尚未注册的未来波次、重复通知、错误对象与已释放对象不推动进度。不要用节点被卸载、走出屏幕或倒计时归零代替死亡；宿主重试时重新实例化协调器及敌人。入树前设置 `restored_end = true` 恢复完成记录，所有绑定敌人保持关闭，不重放开门/Timeline。门的持久状态由宿主单独恢复。

末波清空时立即发出 `save_requested({"isEnd": true})`，之后才等待收尾并发出一次 `completed`。`arrival_requested(key, world_position, kind)` 包含根据装置根变换与源 Y 偏移得到的砸印/绳索创建位置；`member_registered` 可接入宿主敌人列表；`state_changed` 提供状态、从零开始的波次与剩余数量。入场效果的翻转、排序、原动画与音效已由后文 ArrivalBatch 接入；战斗末尾 Timeline 仍待迁移。

DoorContact 先发出 `contacted(actor)`，然后发出 `outside_projectiles_cleanup_requested(actor)`。后者只请求清理房间外的飞行苦无；实际投射物集合、房间判定和 HardWall 消失反馈由宿主处理，不能清空全部投射物。默认是一次触发，消耗后提供 `save_requested({"isActivated": true})`；入树前用 `settings.restored_activated` 恢复。`once` 对应 Trigger.once，`door_once` 对应 DoorContactTrigger.isOnce，保留两个源字段；`activate()` 可重新启用区域并请求保存 isActive。加载期间、未注册对象、错误层或不满足资格的进入被忽略，停留不补发，需重新进入。根节点旋转/缩放同时作用于区域；物理层通过 `actor_layers` 配置。

`Examples/BattleWorkshop.tscn` 提供可玩联动：走进房间封住入口，跳到上下平台，以 J/K 的真实形状攻击消灭两波练习目标，出口动画释放碰撞后离开。R 重新实例化敌人、协调器与门；展厅切换会释放重试后的当前实例。练习敌人是包内独立宿主示例，有实际血量和受击碰撞，不是原 INARI AI；原 demo 仍使用原来的三种敌人行为与画面。

分波协调器已补入源 selectedEnemy 血量阈值增援与存活敌人跨波，见后文“残血增援”。Stamp/RifleManRope 原入场动画见后文；战斗末尾 Timeline 和其他未迁移事件链尚未完成。RepeatingMonsterSpawner 的独立宿主协调器见后文。

`BattleEncounterProbe` 验证实际进入封门、无法回退、八次真实攻击死亡、重复通知过滤、两波顺序、出口碰撞和通行、完成记录恢复、重试与展厅清理；另检查不同计时域、入场请求/注册的事件顺序、旧 peaceful 协程不能影响新波、空波不自动完成，以及接触区的旋转缩放、加载门控、资格和恢复再激活。

本模块验收：Godot 4.7.2 OpenGL 下，新空白工程整包改名导入和十二组运行探针全部通过；BattleEncounter 与 DoorContact 单体编辑器预览通过。最终原 demo BattleRoomProbe、CameraZoneProbe 通过，41 项生成源码哈希及本模块源数据、C# 行为哈希一致。实际攻击/通行与第二波截图已检查；已有沙箱缓存/证书提示及原工程退出纹理析构诊断未在本模块修复。

## 区域延迟召唤

`Devices/MonsterSpawnTrigger/MonsterSpawnTrigger.tscn` 是无可见美术的独立触发区。原机制名为 MonsterSpawnerTrigger，负责进入后延迟请求召唤；敌人、波次、门与存档由宿主连接。`Examples/SpawnWorkshop.tscn` 可直接运行，也可在展厅选择“区域延迟召唤”。A/D 移动、空格跳跃、J/K 攻击、R 重试。

导出器核对全部 29 个场景目录，找到 5 个原实例：

| Presets 配置 | 实时延迟 | 初始碰撞 |
| --- | --- | --- |
| level6_11494（默认） | 1.25 秒 | 启用 |
| level8_11810 / level8_11811 | 1.25 秒 | 禁用，等待外部激活 |
| level10_10070 / level21_10070 | 1 秒 | 启用 |

每个 `.tres` 保留原变换基、碰撞尺寸/偏移、once、初始激活与目标 IsOnField；只移除世界平移。移动、旋转、缩放场景根节点即可重新布置区域。独立实例参数应使用独立 Resource。`actor_layers` 配置宿主角色物理层，角色身份使用 WeakRef；资格及加载条件通过显式回调传入：

```gdscript
$SpawnTrigger.bind_actor($Player, $Player.can_enter, host_is_loading)
$SpawnTrigger.spawn_requested.connect($Encounter.start_spawn)
```

需在 Encounter 入树配置前设置 `settings.on_field = false`，并在召唤前绑定所有敌人。触发器的 `settings.on_field = true` 会按原 Start 关闭整个触发对象。加载中、错误角色/层或不具资格的进入被忽略；停留不会补触发，必须重新进入。进入有效区域后先发出 `entered(actor)`，再开始等待。

实时时间不受 `Engine.time_scale` 影响；离开区域、等待期间开始加载或角色释放都不会取消已启动的等待。每次有效进入保留独立等待，第一项完成后发出 `spawn_requested`，随后写入 `isActivated = true`、关闭对象并取消其余等待。因此召唤回调内读取的仍是旧存档值。等待从首次协程轮询起计时，零延迟在首次轮询完成，依据 [Unity WaitForSecondsRealtime 源码](https://github.com/Unity-Technologies/UnityCsReference/blob/master/Runtime/Export/Scripting/WaitForSecondsRealtime.cs)。

`set_active(false)` 取消等待，再启用需要重新触发；`activate_trigger()` 仅启用碰撞并发出 `save_requested(snapshot())`，不会唤醒已关闭对象或清除激活标志。`once` 立即消耗碰撞，但已启动等待继续。原工程 Physics2DSettings 的 callbacksOnDisable 为 true，保留关闭碰撞引起的 `exited(actor)`；参见 [Unity callbacksOnDisable](https://docs.unity3d.com/2022.3/Documentation/ScriptReference/Physics2D-callbacksOnDisable.html)。

`snapshot()` 始终返回 `{"isActivated": bool}`，宿主按自己的稳定 ID 保存。入树前可设 `restored_activated`，运行时可调用 `restore(record)`；恢复 true 不关闭碰撞，仍允许进入事件但不新建召唤等待。恢复操作也不取消已有等待。召唤完成仅发出 `activation_changed(true)`，原逻辑不会自动请求立即保存。

示例把 level6 触发区与已有两波练习房间组合；不是 level6 原三波关卡的完整复刻。level8 两个目标还涉及 Timeline，其中一个含 selectedEnemy 阈值增援；后文已迁移其阈值协调逻辑，但这不代表完整目标房间已实现。Stamp/RifleManRope 入场美术已接入后文模块，末尾 Timeline 仍待完成；重复刷怪协调器见后文。

`MonsterSpawnTriggerProbe` 使用真实物理进入检查五个预设、旋转缩放、加载/资格/层、重复进入与不同延迟、关闭再启用、存档/回调顺序、once、角色释放、零延迟和全局零时间倍率，并验证示例实际进入后召唤、R 重试及展厅清理。原 demo 的同名适配探针使用 level6 真实配置与成员桩验证触发→原波次协调器→入场/活动/声音，原 AI 战斗由 BattleRoomProbe 单独回归。

重建数据：

```powershell
python Samples/ArtDirection/Tools/export_portable_spawn_triggers.py G:/Misc/INARI_v0.2.1/Inari_Data
python Samples/ArtDirection/Tools/build_mechanism_native_runtime.py
python Samples/INARIMechanisms/Tests/verify_portability.py <Godot可执行文件> --output <包外测试目录>
```

本模块验收：Godot 4.7.2 OpenGL 下，新空白工程整包改名导入及十三组运行探针通过，最终新增边界断言再次通过定向探针。单体和组合示例的编辑器预览通过；原 demo MonsterSpawnTriggerProbe、BattleRoomProbe、LabProbe 通过。42 项生成源码、5 个源文件及导出配置/目录/行为哈希一致。已检查实际示例截图；已有缓存/证书与原工程退出纹理析构诊断未在本模块处理。

## 重复刷怪协调器

`Devices/RepeatingSpawner/RepeatingSpawner.tscn` 实现 RepeatingMonsterSpawner 的死亡、等待、创建、淡入和场景清理。`Examples/RepeatWorkshop.tscn` 可单独运行，也可从展厅选择“重复刷怪”：A/D 移动、空格跳跃、J/K 攻击、R 重试。练习目标具有实际碰撞和血量，必须攻击致死才开始等待。

该类是普通 MonoBehaviour，通过敌人死亡事件工作，旧 physics/inheritance 目录未包含它。新增导出器直接扫描全部 29 个序列化场景，找到一个有效实例：level5 / RepeatingMonterSpawner / 11886，初始敌人为 EnemyBombMan 11742。源 waitTime=8、alphaTime≈0.2；类默认值 2/1 不是此实例实际值。源组件字段、敌人及 prefab 引用、层级激活状态、29 个场景哈希和两份 C# 行为哈希保存在 `Assets/RepeatingSpawner/device.json`。这份补充扫描未覆盖运行时动态加载的 prefab 集合，不能据此宣称完整机关目录已经穷尽。

配置 Resource 包含 `wait_seconds`、`fade_seconds`、按键对应的 `kinds` 与 `placements`。位置由原 respawnPosition 转成相对装置根节点的坐标；复制后可重新平移、旋转、缩放整组。宿主给每种敌人提供工厂，给初始实体绑定死亡及渲染接口；不会在源整数 ID、节点名称或全局注册表中寻找对象：

```gdscript
# 在父场景 _ready 中连接信号，再绑定已就绪的初始敌人。
$Spawner.register_factory(&"EnemyBombMan", create_bomb)
$Spawner.flags_requested.connect(apply_repeat_flags)
$Spawner.member_registered.connect(register_replacement)
$Spawner.member_unregistered.connect(unregister_enemy)
$Spawner.persistence_remove_requested.connect(remove_persistence)
$Spawner.bind_enemy(&"enemy_1", initial_enemy, initial_enemy.force_idle, initial_enemy.apply_tint)
initial_enemy.defeated.connect(func(actor): $Spawner.notify_defeated(&"enemy_1", actor))

func create_bomb(world_point: Vector2) -> Dictionary:
    var actor = bomb_scene.instantiate()
    $Enemies.add_child(actor)
    actor.global_position = world_point
    return {"actor": actor, "idle": actor.force_idle, "tint": actor.apply_tint}

func register_replacement(key: StringName, actor: Node2D) -> void:
    # 此处接入宿主活动敌人列表，并连接新一代实体的死亡信号。
    actor.defeated.connect(func(dead_actor): $Spawner.notify_defeated(key, dead_actor))
```

工厂必须返回已入树的 Node2D 和两个有效 Callable：`idle()` 每帧强制 Idle，`tint(Color)` 设置源白色/透明度；BowMan 的独立 GFXObject 渲染器由宿主选择。源重复/加载标志通过 `flags_requested(actor, true, false)` 传出。初始绑定只设标志，不重复发出全局注册请求或淡入；新实体按“工厂→标志→member_registered→淡入”的顺序接入。缺少/失效工厂会发出 `replacement_failed(key)`，该次等待结束，不伪造成功或无限静默重试。

`notify_defeated(key, actor)` 按 WeakRef 身份拒绝重复、错误或旧代实体的死亡通知；接受后先移除逻辑死亡订阅，发出注销与持久化移除请求，再开始独立等待。等待使用死亡时采样的 waitTime 与实时时钟，首次轮询建立期限；暂停游戏时间仍会创建新实体。淡入使用游戏 delta，每帧强制 Idle 后按旧 timer/alphaTime 写入透明度，再累加 delta；暂停时停在当前透明度但仍执行 Idle。alphaTime 在每帧读取，运行时修改生效，零时长直接设为白色。死亡发生于淡入期间时，旧协程保留自己的实体，不能改到下一代实体。

`before_scene_changed()` 对应源切场景前事件，只销毁本装置动态创建的实体，保留初始场景对象；它本身不取消待重生协程。`set_active(false)` 对应关闭源 GameObject，取消等待与淡入，但保留已存在实体；关闭期间收到已绑定实体的死亡事件仍注销/移除存档，无法新建等待。重新启用不会补回已取消的重生。移除可复制装置时额外执行取消和动态实体清理，避免宿主的同级容器遗留新敌人。

移植边界：工厂负责真实敌人的 AI、碰撞、GFX 与 prefab 默认状态，宿主负责实体列表和持久化数据库。包内示例使用练习目标，尚未将原 BombMan 的全部美术/AI/prefab 搬入独立包。原 demo 的“机关工厂→重复刷怪”现已接入 level5 初始敌人与实际重生 prefab，使用本协调器驱动原 BombMan；该原版宿主仍依赖 ArtDirection，不属于整个 INARIMechanisms 文件夹的复制范围。用法参见 `Samples/ArtDirection/Runtime/InariRepeatingRoom.gd`。

重建来源数据：

```powershell
python Samples/ArtDirection/Tools/export_portable_repeating_spawner.py G:/Misc/INARI_v0.2.1/Inari_Data
python Samples/INARIMechanisms/Tests/verify_portability.py <Godot可执行文件> --output <包外测试目录>
```

本模块验收（2026-10-02）：Godot 4.7.2 OpenGL 下，整包复制改名到新空白工程并完成导入，十四组探针通过；最终定向探针再次检查关闭期间死亡、缺少工厂和零等待。新增生命周期探针覆盖两个成员、重复/旧代通知、变换、暂停、时长修改、清理与取消；示例通过两次实际物理重击和完整等待重生、R 重试及展厅释放。单体/示例编辑器预览、原 demo LabProbe/BattleRoomProbe 通过，29 个源场景、配置和行为哈希已核对，实际截图已检查。已有沙箱缓存/证书诊断未在本模块处理。

## 残血增援

`Devices/BattleEncounter/ThresholdEncounter.tscn` 是同一分波协调器的源阈值配置场景；`Presets/level8_11829.tres` 保留全部四波 `[2, 3, 1, 2]` 人数、八个成员键、原始位置和入场类型、0.25 秒波间等待、1.2 秒入场等待、0.25 秒静止时间和 0.5 秒结束等待。初始 `on_field=false`，由宿主调用 `start_spawn()`。默认普通两波场景保持原配置。

源唯一 selectedEnemy 为第三波 EnemySwordMan（11735），受到伤害后 HealthRatio **小于或等于 0.75** 时触发第四波两个 EnemyRifleMan。阈值字典使用成员键，例如 `thresholds = {"wave_3_enemy_1": 0.75}`，不在脚本中硬编码剑士编号或比例。设置阈值不会把敌人杀死、隐藏、回血或移动；旧成员保持原状态，最后清场计数包含它们。

在宿主完成既有 `bind_enemy` 后，把真实受伤和死亡按实际发生顺序接入。下面适用于示例 BattleTarget 的两个信号：

```gdscript
target.damaged.connect(func(actor, ratio):
    $Encounter.notify_damaged(&"wave_3_enemy_1", actor, ratio))
target.defeated.connect(func(actor):
    $Encounter.notify_defeated(&"wave_3_enemy_1", actor))
```

`notify_damaged(key, actor, health_ratio)` 接收**此次伤害生效后的比例**；若同一次攻击致命，先通知受伤，再通知死亡。初始绑定、恢复和治疗不应当作受伤通知。未开始/已结束、未注册、错误对象、已经死亡或已消耗阈值的通知均不推进；阈值以上的伤害不会消耗监听。一次触发后保留死亡监听，不能靠重复通知同一阈值跳波。

该顺序已核对 InGameEntity.ChangeHealth 与 EnemyInGameEntity.OnDamaged：源先更新 Health，再调用 OnDamaged，最后发出 onDead。零伤害也会发出 OnDamaged，接口因此按实际比例判断，不要求本次血量必须减少；治疗不会发出该通知。

原 NextPhase 将死亡计数先设为负的存活人数。共享内核据此把旧存活成员加到新波总数里，之后在波间等待、入场和战斗期间都接受旧成员的首次死亡；新波激活不会重置剩余数量。例：剑士残血后第四波总数为 3，先击败两名增援仍剩 1，出口保持关闭；最后击败剑士才立即请求保存 isEnd，再等结束延迟发出 completed。致命一击达到阈值时，同一剑士随后的死亡只扣一次。沿用原代码的特殊情况：若把阈值设在最终波，该阈值会直接启动结束流程，即使还有活着的成员；原游戏此次配置没有这样设置。

`Examples/ThresholdWorkshop.tscn` 与展厅“残血增援”提供实际可玩的四波示例，A/D、空格、J/K、R 操作保持一致。紫色练习目标有 4 点血，普通攻击造成 1 点伤害，便于观察 75% 边界。八个成员的展示坐标来自独立 profile，放在练习平台上；不是原 level8 地图布局。它保留原波次与门联动规则，但目标为宿主练习实体，SwordMan/SpikeMan 的原 AI、美术和末尾 Timeline 仍未完成；Stamp/RifleManRope 原入场动画现已接入。

导出器核对目录全部 30 个来源哈希（29 个场景和主程序集），再读取源 level8 组件逐字段比对。目录中只有这一组非空 selectedEnemy。原组件、八个身份/类型、阈值和 Timeline 引用保存在 `Assets/ThresholdEncounter/device.json`；入口、角色绑定、门、存储和 Timeline 仍由宿主明确接入。

```powershell
python Samples/ArtDirection/Tools/export_portable_threshold_battle.py G:/Misc/INARI_v0.2.1/Inari_Data
python Samples/ArtDirection/Tools/build_mechanism_native_runtime.py
python Samples/INARIMechanisms/Tests/verify_portability.py <Godot可执行文件> --output <包外测试目录>
```

本模块验收：Godot 4.7.2 OpenGL 下，整包改名复制到空白工程并重新导入，十五组运行探针通过；阈值单体与组合示例编辑器预览通过。新探针检查精确 75% 边界、未来/重复/错误身份、致命伤害事件顺序、等待和入场中的旧敌人死亡、激活不重置计数、最终波阈值、恢复及实际四波攻击/增援/最终开门/重试清理。原适配 ThresholdBattleProbe、原战斗 BattleRoomProbe、延迟召唤 MonsterSpawnTriggerProbe 与 LabProbe 通过。42 项生成源码与来源/输入/行为哈希核对一致，已检查旧目标与两名增援同时在场的截图；已有缓存/证书及原工程退出纹理析构诊断未处理。

## 事件切场

`Devices/SceneObserver/SceneObserver.tscn` 对应原 MoveSceneObserver，不带碰撞或美术；由其他机关或演出完成事件调用。`Examples/SceneObserverWorkshop.tscn` 可直接运行，展厅中选择“事件切场”：A/D 移动、J 攻击拉杆，第一次保存记录并更换房间，第二次返回示例菜单，R 重试。练习中的拉杆接线是宿主示例；原输入来自演出完成事件，其 Timeline 动画尚未移植。

`Presets` 保留全部 7 个原场景实例：

| 预设 | 普通通知目标 | 已解出的上游事件 |
| --- | --- | --- |
| level12_9156 | level0 | 未发现序列化 UnityEvent 调用 |
| level16_690 | level22 | OnTimelineCompleteEvent → OnEventNotify |
| level17_733 | level25 | OnTimelineCompleteEvent → OnEventNotify |
| level25_667 | level13 | OnTimelineCompleteEvent → OnEventNotify |
| level26_1173 | level18 | OnTimelineCompleteEvent → OnEventNotify |
| level27_269 | level0 | OnTimelineCompleteEvent → MainMenuMoveNotify |
| level28_8972 | level28 | OnTimelineCompleteEvent → MainMenuMoveNotify |

目标是可替换的语义键，由宿主映射到 PackedScene 或加载服务。原场景路径、GUID 引用、完整组件字段、上游事件参数/调用次序与来源哈希保存在 `Assets/SceneObserver/device.json`。导出前验证目录的 30 份源哈希，并独立扫描全部 29 个 level 的 MonoBehaviour 头部，确认空间目录没有漏掉此类实例。运行时 prefab 不在本次扫描范围。上游扫描有 28 个无法解码的组件（包含 TimelineBindingProvider 及音频、相机组件），清单明确保留这些缺口，不能据此断言全部事件链已发现。

接入宿主：

```gdscript
# 所有切场装置共享宿主持有的同一份 Dictionary。
var out_game_data := {"CurrentSceneName": "start", "SpawnPoint": Vector3.ZERO}

func _ready():
    $Observer.bind_context(out_game_data, $Transition.is_loading, "main_menu")
    $Observer.stop_player_requested.connect(_disable_player_input)
    $Observer.save_requested.connect(_save_out_game_data)
    $Observer.persistence_rebuild_requested.connect(_keep_only_player_persistence)
    $Observer.transition_requested.connect(_load_requested)
    $Cutscene.finished.connect($Observer.on_event_notify)
```

`notify(subject, observer_type)` 与 `on_event_notify()` 使用同一行为。该原类的 ObserverMask 为零，但 override 仍无条件调用一次 OnNotify，因此不按传入类型过滤。没有额外一次性状态：加载状态由必填的宿主回调实时读取。加载中返回 false，无停止输入、存档或请求副作用；加载结束后可以再次通知。显式调用方法不受节点 process_mode 禁用影响，符合原 MonoBehaviour 公共方法语义。

普通通知按顺序执行：可选的 `stop_player_requested` → 将 CurrentSceneName/SpawnPoint 复制到 BeforeSceneName/BeforeSpawnPoint → 写入新目标并把 SpawnPoint 归零 → `save_requested(snapshot)` → `persistence_rebuild_requested` → `transition_requested(request)`。SpawnPoint 使用 Vector3 存档值，不在装置内擅自转换坐标；其他存档字段保留。保存信号提供深复制快照，监听者须同步完成保存；持久化信号须先清空旧实体注册、仅注册玩家，再允许加载开始。示例用内存快照验证顺序，没有伪造磁盘存档。

`main_menu_move_notify()` 是独立入口：先发出 `back_to_main_menu`，再请求重建持久化和切场；不检查 loading、不发停止输入信号、不改写或保存关卡记录。目标来自 bind_context 第三个参数，而非 settings.destination；Boss 挑战实例的两个目标不能混用。未绑定上下文或未提供菜单键时返回 false。装置不去查找原 GameSettingManager；宿主必须显式提供菜单目标。`unbind_context()` 解除共享状态和回调引用。

两条路径的切场请求都带 `is_load=false`、`skip_transition=false`，菜单路径另带 `main_menu=true`。宿主负责实际加载、输入恢复、实体注册与存储。示例复用 SceneTransition 的票据与遮罩，它会拒绝重叠加载；这不代表原 Unity 加载器的所有并发协程已复刻。完整过场、相邻场景预加载、MoveBefore/MoveStage/MoveHubStageObserver 及原游戏跨启动存档仍未完成。

重建来源记录与预设：

```powershell
python Samples/ArtDirection/Tools/export_portable_scene_observer.py G:/Misc/INARI_v0.2.1/Inari_Data
```

`Tests/SceneObserverProbe.gd` 验证七个预设、加载门控、任意通知类型、重复通知、可选输入停止、存档快照与执行顺序、主菜单独立目标及不改写存档；随后通过真实移动和物理攻击完成两次房间切换，并检查旧节点释放、重试与展厅卸载。单体和组合场景编辑器预览及原 demo LabProbe 已通过。

本模块完整验收（2026-10-02）：在全新空白工程的 Nested/RenamedDevices 路径重新导入整包，包含原场景切换与新增事件切场在内的十六组运行探针全部通过。37 份来源文件、目录输入及三份 C# 行为哈希复核一致。没有脚本、着色器或资源加载错误；已有沙箱缓存/证书诊断及原工程退出纹理析构诊断未在此模块处理。

## 原版砸印与绳索入场

`Devices/ArrivalEffect/SpawnStamp.tscn` 和 `SpawnRope.tscn` 是真正原始 prefab 的独立动画场景。实例化后自动播放；`ArrivalBatch.tscn` 可选地创建整波特效，按原规则排序并处理枪兵翻转。原 demo 的战斗入口，以及 BattleWorkshop、SpawnWorkshop、ThresholdWorkshop，均使用这组场景；练习角色仍由各自宿主提供。

`export_portable_arrivals.py` 核对所有目录源哈希和 16 个 SpawnManager 实例，解析出同一组 sharedassets3.assets / SpawnStamp GO1112、Spawn_Rifleman GO1100。砸印含 12 个精灵、21 条完整动画绑定、5 个可见粒子系统；绳索含 7 个精灵、17 条绑定、4 个可见粒子系统和一个 SpriteMask。两个 Assets 目录保存原层级、精灵/遮罩像素、关节与杆件尺寸曲线、旋转、缩放、激活、透明度、枪兵逐帧引用、音频、原始点光字段及全部来源哈希。没有发射或子发射事件且禁用渲染的粒子父组保留在 ambient.json 的 inactive_renderers 中，运行时由对应层级节点控制其可见子系统。

使用同一波的世界坐标创建效果：

```gdscript
$Encounter.wave_arrival_requested.connect($ArrivalBatch.spawn_wave)

# 可选第五个回调返回敌人当前 GFX 的世界横向缩放，默认 1。
$Encounter.bind_enemy(&"guard", enemy, enemy.set_active, enemy.set_peaceful,
    func(): return enemy.gfx.global_scale.x)
```

原 `arrival_requested` 单成员信号保留，新增 `wave_arrival_requested` 一次给出整波数组。每个元素含 `key`、`kind`（stamp/rope）、`position`（加过源 Y 偏移的世界生成点）、`sort_y`（加偏移前的敌人世界 Y）、`gfx_scale_x`。直接调用 `ArrivalBatch.spawn_wave(records)` 也可复用，无需 BattleEncounter。

生成对象保持世界方向，不继承协调器的旋转/缩放，仍由批次节点管理生命周期。按 Godot Y 从小到大排序，相当于原 Unity Y 从大到小；`group_stride` 为独立 SortingGroup 的局部 Z 排序预留间隔。绳索仅在 GFX 世界 X 缩放约等于 -1 时翻转，负二倍缩放不会自动当作 -1。原 demo 从已核对的源 GFX 缩放与当前敌人转向计算该值。光栅遮罩只影响当前 prefab 内、原自定义排序范围内的 4 个渲染器，各实例私有材质避免互相遮挡。

`custom_time_scale` 只影响 Animator，粒子仍用游戏 delta；全局 Engine.time_scale 同时影响二者。所有节点保留真实父子变换，杆件尺寸变化重建连续平铺/九切片；不会把父节点运动丢掉或用整张图片拉伸。枪兵入场图像在原曲线的 1.2166667 秒隐藏，晚于敌人 1.2 秒出现一帧。关闭粒子分支时释放旧粒子，重新激活不会让已停止的旧粒子重新出现。

保留原版回收差异：绳索状态名 Spawn_Rappel 匹配 EnemySpawnStamp.aniName，normalizedTime 严格大于 1 后释放；砸印默认状态 Spawn_Stamp 与其配置 Animation_SpawnStamp1 不匹配，原协程会一直等待，装置也保留末帧直到宿主卸载。`animation_completed` 是复用接口，可由希望主动清理的宿主连接到 `queue_free`。批次/房间移除会释放全部子特效，含未自动回收的砸印。

参数还包括 `play_audio`、`random_seed` 和 `particle_collision_mask`。默认播放包内原 FMOD 渲染 WAV；原 demo 已有音效系统，因此关闭本地音频，避免叠放。音频为固定距离参数的原事件渲染，不含完整 FMOD 实时空间混音。

保留的视觉边界：`light_state_changed(states)` 提供原点光字段、动画强度、世界变换与激活状态，动态点光对场景的照明尚未接入；本模块没有用近似光斑冒充原 URP 照明。粒子继续沿用已有运行时的 NoiseModule 缺失、3D 到 2D 投影和碰撞近似。示例不承诺原场景逐像素一致，完整战后 Timeline 仍待迁移。

重建：

```powershell
python Samples/ArtDirection/Tools/export_portable_arrivals.py G:/Misc/INARI_v0.2.1/Inari_Data
```

验收：全新空白工程改名嵌套复制后导入和十七组运行探针通过。ArrivalEffectProbe 另核对 Python 直接从原曲线生成的五个时刻全部层级变换、伸缩几何、翻转/批次排序、音效创建、两个时间域、严格回收边界、粒子重启清理、真实物理进入后创建特效及宿主释放。遮罩开启/关闭的实际画面像素确有变化；最终点光接口和遮罩定向检查通过。两种单体场景编辑器预览通过；所有导出来源/输入/行为哈希、精灵与粒子逐像素哈希、WAV 文件哈希一致。

原 demo 的 BattleRoomProbe 通过真实重击清场并验证生成四个原 prefab、关闭重复音效和重载释放，截图已检查；ThresholdBattleProbe、MonsterSpawnTriggerProbe、LabProbe 回归通过。原工程全量编辑器导入发现现有 Game/UI/Joystick 与 addons/cherry 的重复 UID/全局类名错误，未修改这些非本模块文件；上述原 demo 定向运行和独立包导入没有脚本/资源加载错误。已有沙箱缓存/证书与原工程退出纹理析构诊断仍在。

## 镜头距离与固定目标区域

`Devices/CameraZone/CameraDistanceZone.tscn`、`CameraFixedZone.tscn` 是独立检测区；`CameraZoneController.tscn` 管理同一镜头的共享状态。`CameraZoneRig.gd` 为可选相机适配器，使用包内原 Cinemachine 构图、透视距离换算和阻尼，不需要原角色。展厅新增“镜头区域”，也可以直接运行 `Examples/CameraZoneWorkshop.tscn`，通过行走和跳跃观察变化，R 重试。

导出器独立扫描全部 60 个关卡/资源文件的 MonoBehaviour 头，并逐字段核对碰撞体与清单，保留全部 35 个源预设（26 个距离区、9 个固定区）。包括 level8 禁用碰撞体及 level12 未激活对象，合计 33 个初始启用。未把禁用实例从复用包删掉；宿主可显式 `set_active(true)` 启用。扫描同时记录另三种 MoveBefore/MoveStage/MoveHubStageSceneObserver 没有序列化实例；这不证明运行时代码绝不动态创建它们。

```gdscript
# 在角色与装置入树后、第一次物理帧前绑定。
$Controller.bind_actor(player, func(): return player.global_position,
    func(): return loader.is_loading(), func(): return camera_is_frozen)
$Distance.bind_controller($Controller)
$Fixed.bind_controller($Controller)
# 可选：使用包内构图适配器；也可读取 target_state() 驱动自己的相机。
var rig = preload("CameraZoneRig.gd").new()
add_child(rig)
rig.bind_controller($Controller)
```

上例 `preload` 路径以 CameraZone 目录为基准，宿主脚本按自己的相对位置调整。角色脚底为原点时，第二个回调应返回实际跟随点；可选 rig 的第二个参数传相同局部原点偏移，以便首帧对齐。所有区域共用一个 Controller，多个独立镜头分别绑定自己的 Controller。物理层通过 `actor_layers` 配置，Controller 只接收显式绑定对象，`eligible` 可加资格判断。`ignore_exit(body)` 可供宿主过滤暂停造成的物理退出，原 demo 保留其暂停策略。

Inspector 中 `settings` 可更换 35 个 `.tres` 预设，也可复制 Resource 后调整几何与参数。尺寸/偏移为 Godot 像素，`tracked_offset` 和 `distance` 保留原单位；`pixels_per_unit` 默认 16。移动、旋转、缩放区域节点即可布置检测区，固定构图混合的是区域世界原点与角色世界原点，不是碰撞框中心。`source_transform` 记录原版完整世界矩阵，默认不覆盖宿主摆放；若希望回到源坐标可显式赋给区域 transform。两个单体场景保留原 70×40 的根缩放；更换预设时，应按需求同步它的 source_transform 基向量。示例使用原尺寸和参数、独立练习位置，不代表原关卡地形。

距离区域进入及停留覆盖共享 offset/Z 阻尼，退出归零 offset 并恢复阻尼 1。固定区进入等待加载结束，停留按源 xDamp/yDamp 混合目标；当前单正权重目标组的构图使用固定目标，零权重的区域不会扩大边界。`target_state()` 提供 `fixed`、世界 `position`、源单位 `depth`、`z_damping`、`unlimited_soft_zone`。共享状态没有优先级或恢复栈：重叠区域的任意退出可重置当前设置，随后仍在区域内的 Stay 再覆盖。Godot 的遍历顺序不保证与 Unity 重叠回调逐帧一致。

`once` 在退出时消耗、关闭碰撞并清除自身源标志，不在进入时消耗。再次显式打开碰撞后变成可重复区域；要完全重置一次性语义，重新实例化场景。该状态没有自动写入全局存档。固定区在加载时进入后，原等待协程即使已经离开或消耗也会在加载结束执行，本模块保留这个行为；卸载区域取消其等待引用。

固定区的软区域过渡使用 **0.2 秒真实时间**，不随 Engine.time_scale 或固定 FPS 加速。多个过渡各自到期关闭，不延长为一个统一倒计时。冻结镜头只阻止新软区域过渡，不阻止区域状态更新。Controller 的 `advance_realtime(delta)` 可供确定性模拟显式推进，使用时关闭其自动 process。原 demo 已改用同一 Controller/区域逻辑，并修复旧版把此延迟当游戏时间的问题；原过场、挑战预览的相机所有权仍由 demo 宿主决定。

可选 rig 使用源主相机 profile、XY 构图和 Z 指数阻尼；五秒阻尼在五秒后留下 1% 残差。它面向二维平面，不包含原场景多深度投影层、动态灯光或全部 Cinemachine 功能；原 demo 的那些渲染系统保持原接线。完整 NPC/Timeline、环境音和其他机关目标仍在继续。

重建使用 `python Samples/ArtDirection/Tools/export_portable_camera_zones.py G:/Misc/INARI_v0.2.1/Inari_Data`，然后执行 `python Samples/ArtDirection/Tools/build_mechanism_native_runtime.py`。来源文件、目录输入和 C# 行为哈希保存在 `Assets/CameraZone/device.json`，生成的相机依赖记录在 `Core/native_sources.json`。

验收记录（2026-10-02）：空白工程 Nested/RenamedDevices 改名导入与十八组完整运行探针通过；最后追加的重复等待清理、相机控制权恢复分别通过独立包和原 demo 定向复验。两个单体编辑器预览通过，实际行走/跳跃截图已检查。原 CameraZoneProbe（含真实时间慢动作）、InariCameraProbe、TimeTrialProbe、ElevatorProbe、LabProbe 通过。61 份来源文件、全部目录/行为输入和 44 项生成依赖哈希一致。没有脚本、着色器或资源加载错误；原工程已有缓存/证书与退出纹理析构诊断未在本模块处理。

## 环境音、背景音乐与混响区域

`Devices/EnvironmentAudio/AmbientZone.tscn`、`BGMZone.tscn`、`ReverbZone.tscn` 是独立区域场景；同一游戏会话共用一个 `EnvironmentAudio.tscn`。展厅新增“环境音区域”，也可运行 `Examples/EnvironmentWorkshop.tscn`：A/D 在两个区域之间行走，空格跳跃，R 重试。示例使用原参数和简化练习地形。

```gdscript
# Mixer 放在不会随房间释放的宿主下。所有区域显式绑定角色和同一 Mixer。
$Ambient.bind_actor(player, func(): return loader.is_loading())
$Ambient.bind_audio($Mixer)
$Music.bind_actor(player)
$Music.bind_audio($Mixer)
```

在第一次物理帧前绑定。`actor_layers` 默认 4，宿主按角色碰撞层调整；包内示例角色与原 demo 的碰撞层不同，原 demo 适配器从角色读取这一配置。更换 Inspector 的 `settings` 可选择全部 224 个 `.tres` 原预设：86 个环境音、84 个 BGM、54 个混响区域。215 个初始启用，9 个禁用；两个原触发层为零的 BGM 区域不会自动响应身体接触，但可以显式调用 `interactive_shuriken()`。两个 `once` 源预设位于 level22/17453 与 level8/12004。

`trigger_size`、`trigger_offset` 为像素；`source_transform` 保存完整源世界变换，宿主可显式赋给区域 transform，或自行布置区域。设置资源默认共享；要修改单个实例参数，先 `settings = settings.duplicate(true)`。实际发出的参数字典是深复制，监听者不会改写预设。

进入时只覆盖该区域声明的参数，停留不反复设置，离开不复原。加载中仍执行派生音频参数写入，但不触发基类 entered/一次性消耗。初始重叠检查和物理进入回调可能重复写入，保留原行为。`once` 在进入时关闭碰撞、保留标志；`save_data()` 仅在状态改变后返回记录，否则返回 null。宿主负责保存它以及处理 `save_requested(record)`；`load_data(record)` 恢复状态，`activate()` 重新启用。显式苦无入口按原逻辑绕过物理层和已禁用的碰撞体。

Mixer 启动时创建原 Ambient、Reverb、DieSnapShot 三个持续事件。同一 BGM GUID 只改参数，不重播；更换 GUID 对旧事件 ALLOWFADEOUT/Release，再创建新事件。空 GUID 不操作；BGM 参数 null 表示把当前事件所有参数设为 1，空字典表示不改任何参数。`enter_menu()` 才会清零环境音/混响并播放菜单曲，不在每次换房时清零。`set_volume(value)` 控制原 BGM/AMB bus。`parameter(family, key)` 返回请求值与按原 seek speed 变化的最终值。

`Core/Fmod` 附带一个小型 Godot C ABI 桥接和原 fmodstudio.dll；五个原 bank 位于 `Assets/EnvironmentAudio/Banks`（约 73 MB）。真实混音、循环、参数自动化和淡出由 FMOD 执行，没有预先混成一段固定背景 WAV。原 demo 已接入全部当前关卡对应区域，换房沿用 Mixer、卸载旧区域，退出宿主释放全部事件和原生资源。

当前验证平台为 **Windows x64 / Godot 4.7.2**；扩展声明最低 ABI 4.2，尚未逐版本验证。复制后的散文件 Godot 工程可以直接运行，不需要 Python、编译器、原版游戏安装路径或另装插件。**当前 FMOD 按操作系统文件路径加载 bank，不支持只把 bank 打进 PCK 的发布方式**；其他系统的原生库和 PCK 资源部署尚未实现。原 demo 的现有音效仍由 Godot 播放，因此不会自动进入原 FMOD 混响总线；本模块不能代表所有原游戏音效、死亡状态和 Timeline 音频都已接通。

开发时可设置 `INARI_AUDIO_OUTPUT=silent` 使用无声离线 DSP，或给 Mixer 的 `capture_path` 设置绝对 WAV 文件路径；`render_frames(frame_count)` 只供离线模式推进实际 DSP 时钟。普通实时模式按 FMOD 音频线程计时，不跟随 Engine.time_scale。构建工具 `Samples/ArtDirection/Tools/build_portable_fmod.py` 使用本机 MSVC，并记录原库、banks、桥接源码和构建输出哈希；复制复用无需运行该工具。`export_portable_environment_audio.py` 从经过独立二进制核验的目录生成预设。

EnvironmentAudioProbe 对全部 224 个预设执行真实物理进入/退出，读回 2,760 个 FMOD 参数，并检查同曲不重播、换曲释放、菜单复位、加载/一次性保存、初始禁用、零层掩码和展厅实际行走/重试回收。离线 WAV 另以 PCM 样本核对：全零环境参数阶段无声，启用 Out4 后产生非零环境音。原 demo EnvironmentAudioProbe 验证源坐标下真实角色接触、房间切换沿用 Mixer 和卸载释放。

验收记录（2026-10-02）：改名嵌套复制的独立工程导入与十九组场景探针通过。离线流读取修正后，环境音探针与 PCM 检查定向复验通过（环境段 RMS 897.09、基线 0）；另三次快速离线重复输出均非零，实时设备静音启动/时钟推进通过。原 demo EnvironmentAudioProbe、LabProbe、TimeTrialProbe、CameraZoneProbe 通过；界面截图、224 个预设、源目录和 7 个原生/音频文件哈希已核对。最后版本没有脚本/资源加载错误，已有沙箱缓存/证书及原 demo 退出纹理诊断仍在。

## 苦无射程区域

`Devices/ShurikenDistance/ShurikenDistanceZone.tscn` 是独立区域，`ShurikenRange.tscn` 保存一个角色共享的射程加成。两个原预设来自 level12/9145 与 level28/8964，区域增加 20 Unity 单位；原角色基础射程 35、像素换算 16、飞行速度/质量均由 `controls.json` 导出，没有在场景逻辑重复写固定值。

```gdscript
$Zone.bind_actor(player, func(): return loader.is_loading())
$Zone.bind_range($PlayerRange)
# 创建每一枚苦无时记录，不能在飞行时重新读取区域加成：
projectile.bonus = $PlayerRange.capture_bonus()
# 飞行以及黏附期间，用角色当前世界原点检查：
var limit = $PlayerRange.limit_for(projectile.bonus)
if $PlayerRange.exceeds_limit(projectile.global_position, player_origin, limit):
    projectile.queue_free()
```

宿主负责自己的投射物、碰撞、特效和角色原点换算。`capture_bonus()` 返回源单位加成，`limit_for(bonus)` 返回像素距离，`current_limit()` 返回此刻新投掷的距离；`settings` 可替换基础射程/单位换算配置，`set_additive_distance(value)` 接受源世界单位。与原版一致，单枚只记录区域加成，基础战斗配置仍实时读取。比较条件为严格 `>`，恰好到达边界仍有效；不是累计飞行路程。区域节点的缩放只改变检测体，不改变加成数值。原 demo 的真实苦无已使用这个接口，手柄瞄准线仍保留源代码的基础射程显示。

进入覆盖加成、离开写零、停留不重复写入。多个区域没有优先级或恢复栈：离开其中一个会清零，即使仍在另一个区域中。加载时依旧执行派生射程写入；显式 `interactive_shuriken()` 按源行为绕过层和碰撞启用检查。初始重叠、一次性消耗及保存接口与环境音区域现在共用 `Core/SourceTriggerArea.gd` / `TriggerSettings.gd`，避免两套基类规则偏离。

默认只接收显式绑定角色，检测层由 `actor_layers` 配置。原碰撞尺寸、偏移、世界变换、启用状态和存档 ID 均保存在 `.tres`；`source_transform` 不会自动覆盖宿主摆放。复制多个需要独立保存的实例时，宿主应设置各自的 `persistence_id`。此模块本身不保存文件，也不把一枚已发射苦无的射程改为新的区域值。

展厅新增“苦无射程区域”，或直接运行 `Examples/ShurikenDistanceWorkshop.tscn`。A/D 移动，F 向面朝方向投掷，空格跳跃，R 重试。区域外投掷会在远墙前消失；进入蓝色区域再投掷可以命中远墙，随后走出区域仍保留该次投掷射程。示例角色、简化苦无外观和场地属于宿主，不代表原版关卡美术；练习只复制预设后调整实例几何，预设文件和射程值保持源数据。原关卡适配器按 source 名称生成区域，但 level12/28 的完整地图还未导入当前三张主场景。

`export_portable_shuriken_distance.py` 独立扫描 60 个 level/.assets 头，补正 MonoBehaviour 头对齐后逐字节回写核验两个对象，并独立核对碰撞和世界变换；另核验既有 45 份 root/Addressables 文件审计及其哈希，没有额外序列化射程区域。来源、C# 行为、目录与角色配置哈希保存在 `Assets/ShurikenDistance/device.json`。

ShurikenDistanceProbe 检查两份源预设、旋转/缩放父节点、初始重叠、错误角色/碰撞层、加载期间进出、重叠区域覆盖、边界和展厅真实移动/投掷/重试清理。原 demo 同名探针使用原角色与真实苦无，对两个区域原坐标下的碰撞墙验证超距消失、加成命中、离开后保留单枚射程，以及随玩家移动而变化的距离判定；它不把测试场地当成完整原地图。

验收记录（2026-10-02）：完整文件夹在新工程 Nested/RenamedDevices 下改名复制，导入与二十组场景探针全部通过，FMOD 波形基线 RMS 0、环境段 RMS 869.27。射程独立示例截图已检查；两个原坐标区域的真实角色投掷验证、KunaiFadeProbe、GamepadAimProbe、TeleportProbe、EnvironmentAudioProbe、LabProbe 通过。76 份来源文件、两个二进制对象和原有 44 项生成依赖核验通过。本轮另补齐 FMOD 离线 MIX_FROM_UPDATE 标志并验证 15 次独立进程输出，详见 Mechanisms.md 的官方说明链接。无脚本/资源加载错误；已有沙箱缓存/证书和原 demo 退出纹理诊断未在此模块处理。
