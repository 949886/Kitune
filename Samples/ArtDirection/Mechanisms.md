# INARI 机关复刻与验收

目标是让 demo 可操作地覆盖本机 INARI v0.2.1 的机关类型。原版两关的视觉还原不等于全部机关已实现。

## 限时消失平台（2026-10-03 视频优先模块）

新增 `Samples/INARIMechanisms/Devices/DisappearingPlatform`，该目录自身是独立复制边界，不依赖共享 Core 或原生扩展。展厅新增“限时消失平台”和独立三段跳跃练习场。

源脚本 `DisappearTiles` 在 level7、8、19、22、23 共 5 个组件、14 组连续地格上使用。导出器扫描 60 个 level/.assets 文件，以原版四邻接及首格 x+y 排序关联 Animator，保留原 CompositeCollider 多边形。源字段均为 targetFrame=109、appearTerm=1.25；动画 60 FPS、速度 1，因此踩踏约 1.8167 秒后失去碰撞，1.25 秒后恢复。顶部接触触发，离开不取消，已运行组不重复启动；恢复碰撞发生在展开动画开始时。

导出 16 张原精灵、四段状态动画、独立 Emission 透明度曲线和 TrapPlatform 原声音事件。红灯越来越快的闪烁来自源曲线，不能只读 Sprite 帧。WAV 包含警报、收起、展开组合，核对 PCM 非静音和哈希。恢复混合采用源过渡时长；Unity URP 光照/发光后处理、FMOD 动态距离和随机音色、完整源地图不是本模块的完成范围。

验证：独立 struct 读取器复核五个原始二进制组件；14 个预设实例化；真实脚底、侧面、底面接触；离开继续计时；失去碰撞后的真实跌落；死亡谓词；恢复重触发；30/60/120 Hz；旋转缩放碰撞；实际 A/D/空格穿过三段平台、R 重试和展厅切换释放。仅复制本目录到改名嵌套的空工程通过导入与运行。整包 21 组运行探针及 FMOD PCM 回归通过；红灯补全后的平台探针再次通过。旧模块仍使用整包复制边界，不应把本次独立目录能力误认为所有旧模块都已拆分。

## 原版范围审计

`Tools/import_inari_mechanism_catalog.py` 扫描安装包全部 29 个 level 文件，以反编译类的继承关系、物理回调、主动 Physics2D.Overlap 查询及 Trigger 类名发现候选组件。发现范围包含 MonoSubject 事件源，避免遗漏没有直接物理回调的 SpawnManager，也包含通过主动范围检测拾取的 ShurikenChargePoint。结果保存于 `Original/INARI/mechanism_catalog.json`，包含 42 类、938 个场景组件（包含未启用对象、敌人及角色碰撞辅助类；其中有 16 个刷怪管理器、49 个光点），保留路径、启用状态、碰撞体、原始字段、事件引用、世界变换及来源 SHA-256。

初始目录中 224 个音频参数触发器保留 `decode_error`。后续 `environment_audio.json` 已通过修正私有类型树完整解码，并用逐字节回写、独立二进制读取和原 FMOD 参数 API 核对，见末尾“环境音参数来源解码”。初始目录的历史哈希保持不变；后续实时 FMOD 与可复用区域接线已完成，见末尾对应章节。计数包含音频、镜头、刷怪和观察者辅助组件，不是 938 种独立机关。

`Tools/import_inari_mechanism_asset_audit.py` 另扫描安装包根目录 .assets 与全部 Addressables bundle，共 45 个文件，保留哈希及 14 个候选组件的文件/对象引用，头部读取无失败；结果见 `mechanism_asset_audit.json`。候选包括敌人预制体、苦无、箭、Boss 子弹、黏附炸弹、光点及两个 UI EventTrigger。反编译中存在的爆炸桶、灭火器、狐狸牢笼、钱袋、苦无气球在此版本的场景及上述资源中未发现序列化组件，因此不凭类名虚构可玩实例；这也不是其他版本或动态代码构造绝不存在的证明。扫描是范围证据，不等于预制体已实现或每条字段已解码。

## 进度与下一步

| 类别 | 原版组件 | 当前覆盖 |
| --- | --- | --- |
| 破坏门 | InteractiveDoor | 原两关已接入；木门/重击门共享原版交互标志 |
| 风增益 | MoveSpeedChangeTrigger | 原工厂两处已接入，含动画、音效、体力和增益续期 |
| 存档点 | InteractiveSaveTrigger | 原工厂与机关工厂各两处原始触发体、出生点及朝向已接入；当前为单次关卡会话状态，跨启动存档待实现 |
| 尖刺 | SettedSpike | 原工厂两处、机关工厂一处原始多边形触发区；玩家持续接触伤害、无敌保护及敌人进入伤害已接入 |
| 拉杆、移动平台 | InteractableTrigger、PlatformController、PlatformControllerObserver | level22 两组原始连接、攻击启动、横向搭乘与纵向攀附、苦无附着及到站已可玩；视觉提示和乘载边界还有下述差异 |
| 电梯 | ElevatorPlatform、InteractableObjectTrigger | level14 单次按钮、关门碰撞、原始等待/运动/音效、level2 换场景及到站过场已接入；其他实例及视觉差异见下文 |
| 机械门与战斗封锁 | Door、DoorContactTrigger、SpawnManager、MonsterSpawnerTrigger、Trigger、ObserverEvent | level5 双波房间已接入入口封锁、真实敌人死亡驱动的换波和出口开门；MonsterSpawnerTrigger 尚无可玩实例验证，通用事件及其他房间仍待接入 |
| 冰冻装置 | ElectroBox | level5 原战斗房间可投掷/瞬移或剑击触发，原网格阻挡扩散、单次延时与敌人冻结恢复已验证；其余实例及青色条纹材质待校准 |
| 隐藏墙 | HiddenWallTileMap | 唯一 level16 序列化对象只有远离地图的一格无纹理 Tile，复合碰撞路径为空；未虚构隐藏通道，渐隐行为仍待验证 |
| 计时挑战 | TimeAttackTrigger、TimeAttackTriggerDest | level3 的启动、四处镜头预览、30 秒计时、失败、清怪门和终点奖励门已验证；其他实例待接入 |
| 场景、奖励、对话 | SceneMoveTrigger、MoveSceneObserver、RewardObserver、ShurikenChargePoint、NpcInteractiveTrigger、InputableTrigger、ShowMapNameTrigger | level14 → level2 场景连接、level3 接触奖励和七个光点已可玩；其余场景连接、奖励及对话待接入 |
| 镜头区域 | CameraDistanceTrigger、CameraFixTargetTrigger | 现有场景接入九个区域；level5 固定视角出入、level22 拉远和 level15 距离恢复已验证；其他实例待逐场景验收 |
| 教程喷焰装置 | SteamTrap（Animator / ParticleSystem） | 按截图补充 level24 教程倒挂火柱，保留 level13 神殿预设；独立场景、预热/速度/层次及曝光对照已实现，原环境灯光与粒子 Noise 尚待校准 |
| 环境 | VolumeTrigger、AmbientParameterTrigger、BGMParameterTrigger、ReverbParameterTrigger | 三类音频触发器的 224 个预设、实时 FMOD、独立场景与 demo 接线已完成；VolumeTrigger 后处理切换仍待实现 |
| 苦无射程 | ShurikenDistanceTrigger | level12/28 两个预设已导出为独立区域，展厅有投掷练习；原角色按投掷时加成判断距离，原两关完整地图尚未导入 |

每个模块必须有玩家可到达的入口和实际触发验证；纯清单、静态摆件、测试替身不计作机关完成。原版行为与 Godot 适配差异在对应模块记录，完成验证后本地提交。

## 工厂存档点与尖刺

`Tools/import_inari_checkpoint_hazards.py` 按 `Profiles/levels.json` 的可玩场景选择，从审计清单读取原版坐标、碰撞体和出生朝向。尖刺伤害值直接从 `SettedSpike.cs` 两条伤害路径核对提取。神殿没有这两类实例，不添加虚构机关。

进入存档区域会设置当前关卡的复活点，R 和死亡后重生使用该位置及朝向。原版玩家原点转换为当前角色的脚底原点，与相机的原点换算保持一致。`TrySave` 的防重入只允许单个触发器保存一次；原版未使用 `addStamina` 和 `animator` 字段，因此不添加回血或体力奖励。HUD 显示已保存提示；后续人工路线检查点不覆盖原版存档点。

工厂 `SettedSpike` 的 TilemapCollider 已禁用，实际使用同一对象上的 PolygonCollider；旧导入器没有保留这两个触发多边形。现按原始顶点创建有内部面积的检测区。玩家无敌期间不受伤，留在尖刺内部直到无敌消失会受致命伤害；敌人进入时独立受伤并触发 Attack 镜头反馈，不计为玩家击杀奖励。Tab 对照中禁用的玩家不继续结算尖刺伤害。

`CheckpointHazardProbe` 在实际工厂中通过物理重叠测试两处存档点接入、首次保存、不回血/回体力、复活朝向、路线检查点优先级、尖刺内部持续伤害、真实敌人命中及关卡重开清理。Headless 与 OpenGL GPU 运行均通过；另通过原有 `RouteProbe`、`PlayerDamageProbe` 和固定 60 FPS 的 `WindBuffProbe`。当前验证并不证明 Unity/Godot 帧内事件次序完全一致。全工程编辑器仍有既存 Cherry Joystick 重复类/UID 报错；独立 demo 探针可正常运行。

重建清单：

```powershell
python Samples/ArtDirection/Tools/import_inari_mechanism_catalog.py G:/Misc/INARI_v0.2.1/Inari_Data tmp/art-direction/decompiled
```

## 拉杆与移动平台：机关工厂

第三个 demo 入口 `Scenes/INARI_Machinery.tscn` 使用原版 level22。左上角两颗按钮分别进入横向平台和纵向移动墙的原始区域；不是通过改动原地图墙体强行连接两个练习点。两组原生 InteractableTrigger → PlatformControllerObserver → PlatformController 引用由数据解析，运行时代码不保存机关坐标或配对表。

`Tools/import_inari_machinery.py` 从 `Profiles/mechanism_levels.json` 选择场景，导出实际 CompositeCollider 路径、局部路点、速度、等待、缓动、灯光和轮子引用，以及拉杆 Animator 的状态和帧。此阶段新增 221 张原始精灵；旧有 1740 条精灵和 36 条材质记录逐项保持不变，新材质使用场景前缀区分。`machinery.json` 保留源场景及相关反编译代码哈希。后续电梯模块在此导入器增加独立的按钮、门体与场景连接数据。

平台移植了原版启动等待、`EaseAmount + 1` 幂函数、移动中连续换向、循环/折返和到站停止规则。全局等待时钟独立于角色时间倍率，运动使用源 TimeScale；选关、原图对照暂停整套场景。平台的碰撞、子精灵、轮子和灯光随实体运动。角色可站立搭乘、攀附侧面或悬挂；苦无保存命中表面的局部变换，平台移动后仍使用更新后的瞬移位置，退出关卡释放绑定。

拉杆按原 InteractableType 接受普攻/重击，拒绝冲刺和苦无瞬移触发；状态动画与原版 Lever 音效已接入。源码允许苦无附着拉杆而不拨动开关，这一行为使用独立表面接口，未套用敌人的弱点伤害接口。

`MachineryProbe` 通过真实输入完成两条路线：攻击拉杆后跳上横向平台、投掷苦无并瞬移攀附纵向墙直至到站。纵向原路线会穿过单向平台边角，测试持续检查相对位置，防止 Godot 的边角碰撞将角色挤离移动墙。另检验源速度/等待/缓动、时间缩放、换向连续性、顶部与侧面乘载、移动表面苦无瞬移、实墙挤压、暂停及重载清理。路线完成同时要求原机关状态到位；`RouteProbe` 继续验证原有两条移动路线，机关路线由专用探针驱动。

本模块在固定 60 FPS、OpenGL 下通过 `MachineryProbe`、`LabProbe`、`RouteProbe`、`KunaiProbe`、`KunaiFadeProbe`、`ClimbProbe` 和 `CheckpointHazardProbe`。已检查选关和纵向到站截图。全工程编辑器仍有既存 Cherry 重复类/UID 诊断；独立探针没有脚本错误。沙箱运行仍会报告用户目录着色器缓存/证书存储不可访问，部分退出有纹理资源析构诊断，未把它们计为脚本检查成功的证据。

仍未宣称完成的差异：普通平台循环运行音效、拉杆距离轮廓提示与跨启动机关存档待接入；Godot 乘载使用原碰撞轮廓的边界检测与实体移动，尚未逐项等价移植 Unity 的乘客射线数组及挤压时下穿单向平台分支。原版 level22 的其他事件链和战斗敌人不属于本次练习入口的已实现范围。后续仍需补机械门、冰冻装置、隐藏墙、计时挑战和运行时生成的交互物。

重建与验证：

```powershell
python Samples/ArtDirection/Tools/import_inari_machinery.py G:/Misc/INARI_v0.2.1/Inari_Data
python Samples/ArtDirection/Tools/import_inari_machinery_audio.py G:/Misc/INARI_v0.2.1/Inari_Data tmp/art-direction/decompiled
python Samples/ArtDirection/Tools/import_inari_checkpoint_hazards.py
godot --path . --rendering-method gl_compatibility --fixed-fps 60 --script res://Samples/ArtDirection/Tests/MachineryProbe.gd
```

给最后一条命令追加 `-- --capture-preview` 可重建选关卡片截图；普通测试只将截图写到忽略的 `tmp/art-direction/`。

## 电梯与跨场景到站

机关工厂新增「电梯」入口，使用 level14 的原始轿厢、按钮、门碰撞体、子碰撞体、两秒等待、速度和缓动。靠近按钮出现 F / Y 提示，按下后立即关门、收回苦无、禁用按钮并启动电梯。反编译核对了全部五个 ElevatorPlatform 场景实例；它们均走单次按钮规则，未发现可供玩家呼叫或往返的按钮，因此没有添加这种玩法。当前可玩验证覆盖 level14，另外四个实例还不能计为已验证。

按钮和门的 Animator 状态、开关位移、蒸汽启动时刻都来自资源数据。平台实体带动原有子碰撞和视觉；到站触发 Open，源码 `DeferredColliderDisable` 的 0.2 秒后释放门碰撞。level14 的实际路线在电梯到达物理终点之前进入 SceneMoveTrigger，因此玩家体验同时需要换场景逻辑，不能只验平台终点。

场景引用通过原安装包 SceneReference GUID 映射和 BuildSettings 解析，连到 level2；不是手写关卡配对。换场景使用源 SceneTranslationUI 的两秒淡出/淡入时间，关闭重复触发，释放旧场景并读取原出生点。按原 `OnAfterSceneChanged` 恢复配置中的最大生命值，保留当前体力；仍未接入完整的跨启动存档管理。重载练习或切换入口会取消进行中的换场景。

level2 自动播放 `CUTSCENE_ELEVATOR_ARRIVED_00`。导入器沿实际启用的 Timeline 轨道树解析，排除导演中残留的旧绑定，导出角色 PhysicalBinding、轿厢、门和风扇运动的原始三次曲线、片段时刻、音频事件及完成信号。角色和轿厢同步上升 480 像素，8.116666 秒完成信号恢复控制，保存原到站出生点和朝向。玩家可以走出轿厢继续探索，R 使用新的存档点。导出资产及反编译行为保留 SHA-256；新增 29 张原始精灵，此前 1961 条精灵、60 条材质记录逐项保持不变。

电梯与蒸汽音效由原 FMOD bank 离线渲染。循环电梯事件保留一个 27 秒原时间线周期供 Godot 重复，并随平台/Timeline 所有者停止。这个适配尚未重建 FMOD 内部循环区域、释放包络、空间音效与音量环境触发器；不宣称与实时 FMOD 完全一致。按钮 Unity UI、距离轮廓、部分材质/透明度及 Steam 激活轨道仍未还原；未支持的 Timeline 曲线保留于导出 `unsupported`，没有当作成功。Animator 状态切换暂未混合过渡帧。淡出时暂停旧场景、淡入时继续到站 Timeline，是目前 Godot 的调度适配，尚非原版帧内时序的逐项等价实现。level2 的其他事件、敌人及外出连接仍待接入。

`ElevatorProbe` 使用真实输入完成接近、启动、平台搭乘、原碰撞触发换场景、到站过场及走出轿厢，检查按钮不可重复使用、苦无回收、源等待时间、乘载相对位置、生命恢复、控制权、出生点和重载取消。另使用导入的真实平台推进至终点，独立验证门碰撞延迟释放；测试不会伪造到站信号。

本模块通过固定 60 FPS 的 OpenGL `ElevatorProbe`、`MachineryProbe`、`LabProbe`、`RouteProbe`、`KunaiFadeProbe` 和 `CheckpointHazardProbe`，并人工检查到站与出梯截图。源文件哈希、旧资产记录不变及 Python 语法检查通过。全工程编辑器仍报告既存的 Cherry 重复全局类；六项独立 demo 探针未出现脚本错误。

重建与验证：

```powershell
python Samples/ArtDirection/Tools/import_inari_machinery.py G:/Misc/INARI_v0.2.1/Inari_Data
python Samples/ArtDirection/Tools/import_inari_elevator_audio.py G:/Misc/INARI_v0.2.1/Inari_Data tmp/art-direction/decompiled
python Samples/ArtDirection/Tools/import_inari_checkpoint_hazards.py
godot --path . --rendering-method gl_compatibility --fixed-fps 60 --script res://Samples/ArtDirection/Tests/ElevatorProbe.gd
```

## 机械门与双波战斗房间

「战斗门」入口使用 level5 的原始房间，DoorContactTrigger 单次关闭入口 Door；SpawnManager 第一波包含两名弓兵、一名自爆兵和一名枪兵，第二波包含两名自爆兵和两名枪兵。每个实际敌人的 `defeated` 通知减少当前波计数，第一波全部死亡才进入下一波，第二波全部死亡才通知出口 Door。未使用固定倒计时冒充清怪条件。

场景原始订阅、相位对象、敌人引用、出生坐标、0.25 秒换波间隔、1.2 秒生成等待、0.25 秒和平等待及最终 0.25 秒开门延迟由序列化数据和 SpawnManager.cs 提取。换波时先关闭未来波的显示、碰撞、目标选取与全局敌人查询，再按实际阶段激活。生成计时开始前等待全局 hit-stop 释放。普通选关会暂停整个场景；死亡或 R 重开此练习会释放旧房间和一次性触发状态，这是 demo 的重试流程，跨启动存档仍未实现。

Door 使用原始两块 BoxCollider、Animator 开关轨道和材质。关闭立即启用不可见墙；开门达到源 `colliderTiming` 后才释放它，门叶碰撞随原动画位移。运动期间切为 HardWall，新苦无反弹，已附着门体的苦无销毁。原源码的协程明确只等待 Open 状态，因而关门完成后仍保持 HardWall，直至下次开启达到阈值；没有擅自改成对称的开关时机。门及生成音效来自原 FMOD 事件。

`unity_enemy_bindings.py` 为新场景分别解析弓兵发射点、枪兵瞄准线/弹道、弱点分支及轮廓材质，绑定保存在各自敌人记录里，不复用 level15 的 GameObject ID。旧工厂继续读取原有配置。新增 25 张原始精灵；此前 1990 条精灵和 125 条材质记录保持不变。导入器还修复了跨场景材质字典共享引用，避免后导入的轮廓数据污染旧场景。

当前边界：尚未播放 Stamp/RifleManRope 的原生成视觉预制体；已保留其引用、位置、音效与阶段等待。弓兵按原距离、同排筛选和遮挡条件发出警报，首次播放原 Alarm 动画并使邻近敌人获得目标；接收者暂复用当前追击适配，原 AlarmAction 经由发出者的中间路径尚待移植。DoorContactTrigger 对房间外苦无的清理、Animator 过渡帧混合、通用 UnityEvent / ObserverEvent、血量阈值换波和战后 Timeline 尚待接入。MonsterSpawnerTrigger 已有数据/计时适配，但 level5 没有该组件，不能算作已通过可玩实例验证。该练习只导入当前地图块，不包含出口外的相邻地图流式加载。其余战斗房间仍未计为完成。

`BattleRoomProbe` 用实际移动验证进门封锁、返回受阻与重试，使用真实重击输入和敌人伤害判定完成两波，再穿过出口。伤害流程检查期间冻结敌人移动以排除随机战术；不会伪造死亡、波次完成或开门通知。另一次运行保持全部 AI 启用，验证本房间能进入战斗且无脚本错误。这些检查不等于人工完成整场无伤战斗。固定 60 FPS、OpenGL 下另通过 BowCombatProbe、RifleCombatProbe、BombCombatProbe、EnemyOutlineProbe、ElevatorProbe、MachineryProbe 和 LabProbe。

随后通过 EnemyContactProbe、CheckpointHazardProbe；全部十项独立探针无脚本错误。重复执行机关导出后，machinery、materials、sprites 和 level5 的 JSON 数据逐项一致，来源哈希与旧素材记录检查通过。全工程编辑器仍存在原有 Cherry 重复全局类诊断。

```powershell
python Samples/ArtDirection/Tools/import_inari_machinery.py G:/Misc/INARI_v0.2.1/Inari_Data
python Samples/ArtDirection/Tools/import_inari_battle_audio.py G:/Misc/INARI_v0.2.1/Inari_Data tmp/art-direction/decompiled
python Samples/ArtDirection/Tools/import_inari_checkpoint_hazards.py
godot --path . --rendering-method gl_compatibility --fixed-fps 60 --script res://Samples/ArtDirection/Tests/BattleRoomProbe.gd
```


## 冰冻装置与敌人暂停

「冰冻装置」练习入口从 level5 战斗房间上层出发，向上方装置投掷苦无，命中后按 Q 触发；剑击同样有效。该装置也保留在「战斗门」入口的同一原始位置，可用于两波战斗。不是按键直接发出全屏眩晕：原始 BoxCollider 承接攻击和苦无射线，ObjectShurikenComponent 只在查询瞬移位置时造成伤害，单纯附着不启动装置。ElectroBox 的伤害覆写没有调用父类 InteractableType 过滤，运行时保留这一差异。释放后装置不重置，仍可作为苦无锚点；R 重载整个练习。

所有已导入场景的四个实例（level5 三个、level22 一个）读取各自原始碰撞、变换、Animator、轮廓参数和 TileMapPathManager 的第一张地图网格。可玩触发验证覆盖 level5 上层这一个实例，不能把另外三个已绑定实例或未导入的 level7 实例算作已验收。网格使用原始 16 像素单位、地图原点及锚点，保留 Unity 负坐标向下取整后再反射 Y 的顺序。扩散检查 Ground、HardWall、Door、Wall、InteractiveWall；原代码先记录访问再检查半径，因此阻挡格与外围一圈格子仍在受影响集合中，未擅自改成简单圆形或射线范围。

源等待字段为 0.5 秒，FasterBlit 每次按累加时间缩短下一次等待间隔，最后一次等待可能超过该值。保留这一计时方式及由 0.2 降至 0.01 秒的闪烁间隔。接近时按 Ground 遮挡和 15 单位距离更新原轮廓；60 单位内首次启动原环境循环声，离开范围不主动停声，触发时停循环并播放 IceMachineStart。两段音效由原 FMOD 事件离线渲染；循环仍采用已记录的整段时间轴重复策略，未重建 FMOD 内部循环区间和空间衰减。

释放使用原 Eff_Freezing 的六组粒子和 aircon_boom 动画。实际命中集合中的已激活、可被苦无命中的敌人进入 Hit 状态，取消待发攻击并冻结现有动作 5 秒；再次冻结不刷新计时。弱点到期、重力、受击伤害和击退继续工作，全局停止会暂停冻结计时，死亡会释放冻结状态。原版的青色 Hologram 条纹材质尚未移植；当前敌人保留原姿态，不能把静止视为着色器也已复刻。粒子沿用现有模块适配，NoiseModule 等既有渲染差异仍存在。敌人 Buff 速度变化、和平敌人冻结结束边界和其他敌人类型仍待验证。

`IceBoxProbe` 使用实际苦无发射/命中/瞬移及剑击输入，验证附着不触发、延时、实际受影响敌人、动画冻结、5 秒后恢复、重复冻结不续期、停止计时、冻结中击退及 R 重试。冻结时长检查先暂停敌人步进以取样，再恢复实际敌人逻辑；没有替代房间扩散或伪造命中名单。另用真实物理阻挡构造封闭网格检查墙体阻挡与外围访问顺序。已人工检查释放后的房间截图。旧精灵、材质和粒子定义逐项保持不变，新增一个原始精灵帧与冰冻效果定义。

重建：

```powershell
python Samples/ArtDirection/Tools/import_inari_machinery.py G:/Misc/INARI_v0.2.1/Inari_Data
python Samples/ArtDirection/Tools/import_inari_particles.py G:/Misc/INARI_v0.2.1/Inari_Data
python Samples/ArtDirection/Tools/import_inari_ice_audio.py G:/Misc/INARI_v0.2.1/Inari_Data tmp/art-direction/decompiled
godot --path . --rendering-method gl_compatibility --fixed-fps 60 --script res://Samples/ArtDirection/Tests/IceBoxProbe.gd
```

本模块通过固定 60 FPS 的 OpenGL IceBoxProbe、BattleRoomProbe、BowCombatProbe、RifleCombatProbe、BombCombatProbe、ElevatorProbe、MachineryProbe 和 EnemyProbe。新增的冻结中击退与停止计时检查也通过。38 项来源哈希、Python 语法及 git diff --check 通过；此前 2015 条精灵、167 条材质和 17 个粒子效果定义保持不变。全工程编辑器既有的 Cherry 重复全局类诊断仍存在，八项独立 demo 探针没有脚本错误。

## 计时挑战、接触奖励与追踪光点

「计时挑战」使用 level3 的原始地图、起点与终点 BoxCollider、四处镜头目标、30 秒时限、四道 Door、单波六名敌人、终点前存档点及隐藏奖励。`unity_scene_trials.py` 沿实际对象引用导出这些连接、数字条材质参数、Animator、SimpleAnimator 曲线和 RewardObserver 事件；运行时不保存关卡坐标或门的配对表。

起点按 F / Y 后禁用一次性按钮并设置当前出生点，首次进行原四处镜头预览，随后打开起点门。重试保留已看过预览的会话标志。起终点各有四位原始数字条，按原 UV 裁剪、每秒最短循环偏移及 OutQuad 缓动滚动；附近交互轮廓沿原 alphaTime 渐变。计时只在源 TimeScale 大于零时减去全局 delta，正数分数倍率不减慢它。超时禁用终点、恢复其待机动画并停止循环声，不凭空杀死玩家，也不关闭已经打开的起点门。

六名原始敌人全部死亡后，SpawnManager 延时打开战斗门；仍需在归零前到终点按 F / Y，才会通知原奖励 Door。接触奖励使用原 Trigger 的一次性事件，RewardObserver 增加一个奖励并续期已有风增益，不提高层数。SimpleAnimator 使用源 0.3 播放速度、透明度/旋转/启用曲线以及三盏灯的亮度、半径和启用轨道。七个 ShurikenChargePoint 按原字段随机散开后追踪玩家，通过实际圆形范围检测逐个增加一点金钱；其移动响应源时间倍率，玩家死亡后隐藏。点数当前只记录在该 demo 会话，尚未接入商店或跨启动数据。

起点、终点、镜头移动、倒计时、失败、完成与奖励光点音效来自八个原 FMOD 事件。保留循环时间线的既有离线适配，不宣称等价还原 FMOD 的空间混音及内部循环区间。奖励和已看过预览的标志在切换入口、R 重试时保留；门、敌人和计时会随练习重新加载。原版终点存档后死亡会禁止终点，已接入当前房间的死亡通知；跨重载的失败存档尚未实现，R 仍可重新挑战。

镜头的目标、停留、阈值和阻尼来自原数据；后续镜头区域模块已将预览接到统一 Z 阻尼和透视投影，替换直接改取景范围的旧适配。预览期间暂时冻结角色处理，原版是禁用输入。奖励的 SquareDistortion 材质、MiniParticle 子发射器及缩放曲线尚未完整移植；已实现的拾取、光点计分和灯光熄灭不能算作这些视觉效果也已完成。两处倾斜大齿轮增加透视采样以避免空材质报错，原 Custom/RotatingCog 的模糊仍待还原。其他计时房间、奖励实例与普通资源池光点仍未验收。

`TimeTrialProbe` 用真实 F 输入验证预览、启动、一次性限制和终点开门，单独推进时钟验证超时和停止倍率；使用真实重击与敌人伤害流程完成六人清怪，再实际走过奖励门接触领取、观察七个光点全部进入角色并检查重载不重复领取。伤害链检查会冻结敌人移动并调整角色到各个交战位置，因此不等于完成一遍正常路线挑战；另一次短程运行保留全部 AI，从起点实际走入战斗。探针也通过原始存档区域与真实伤害入口验证死亡封锁。截图检查了数字显示、奖励消失、灯光熄灭和领取反馈。

本模块另通过 OriginalUVProbe、FactoryUVProbe、TiltedPlaneProbe、LightingProbe、InariCameraProbe、IceBoxProbe、BattleRoomProbe、ElevatorProbe 和 MachineryProbe。旧 2016 条精灵及 167 条材质记录逐项保持不变，新增 20 条精灵和 49 条场景材质；45 项机关来源哈希已核对。原全工程 Cherry 重复类及沙箱退出诊断仍存在，独立 demo 探针无脚本错误。

```powershell
python Samples/ArtDirection/Tools/import_inari_mechanism_catalog.py G:/Misc/INARI_v0.2.1/Inari_Data tmp/art-direction/decompiled
python Samples/ArtDirection/Tools/import_inari_mechanism_asset_audit.py G:/Misc/INARI_v0.2.1/Inari_Data tmp/art-direction/decompiled
python Samples/ArtDirection/Tools/import_inari_machinery.py G:/Misc/INARI_v0.2.1/Inari_Data
python Samples/ArtDirection/Tools/import_inari_timer_audio.py G:/Misc/INARI_v0.2.1/Inari_Data tmp/art-direction/decompiled
python Samples/ArtDirection/Tools/import_inari_checkpoint_hazards.py
godot --path . --rendering-method gl_compatibility --fixed-fps 60 --script res://Samples/ArtDirection/Tests/TimeTrialProbe.gd
```

## 镜头距离与固定目标区域

`camera_zones.json` 从 29 个场景的完整清单提取 35 个镜头触发器中的 33 个启用实例；level12 的一个对象未激活、level8 的一个碰撞体被禁用，因此不启动它们。保留原始 BoxCollider 尺寸、偏移、非均匀缩放、坐标及脚本字段。当前已导入场景绑定其中 9 个区域，不将其余导出记录算作可玩验收。

CameraDistanceTrigger 在进入及停留时写入目标偏移和 Z 阻尼，离开时归零偏移并恢复源代码指定的阻尼 1。CameraFixTargetTrigger 按区域原点和玩家原点分别混合 X/Y，跟随源目标组中唯一正权重成员；零权重的区域成员不扩大构图边界，源最大自动推拉距离为零。一次性区域在离开时消费，重新进入不再接管镜头。固定目标进入会等待场景加载结束，进出使用源 0.2 秒软区域过渡，并遵守瞬移镜头冻结；暂停菜单引起的 Godot 物理退出不会误消费一次性区域。

相机按原 Cinemachine 的指数阻尼移动 Z，五秒阻尼在五秒后保留百分之一残差。实际透视范围随距离变化，XY 构图边界仍按源 m_CameraDistance 计算。场景深度平面、倾斜精灵及投影灯光同步更新，计时挑战的镜头预览也接入该距离流程。神殿片段使用 Timeline 绑定的镜头，因此玩家虚拟相机的区域不会抢走其跟随目标。

新增「镜头区域」练习从 level5 下层房间内部出发，实际向左穿过原本开启的入口门，验证恢复角色跟随及单次限制。该入口关闭刷怪，但仍初始化原两道 Door 的开关状态、动画和碰撞。「横向平台」入口处的拉远区域通过实际行走验证。工厂距离区域使用角色位置测试夹具检查进入、离开和重复触发；这不代表已正常走通该工厂区域的完整路线。

`CameraZoneProbe` 检查上述路径、暂停恢复、重载、加载等待、原 XY 混合、独立 Z 阻尼公式、各深度平面投影比例、灯光更新和神殿镜头归属。截图检查固定构图、离开区域及工厂拉远效果。另通过 TimeTrialProbe、InariCameraProbe、TiltedPlaneProbe、LightingProbe、WaterProbe、IceBoxProbe、BattleRoomProbe、MachineryProbe、ElevatorProbe、RouteProbe、LabProbe，共 12 项固定 60 FPS 的 OpenGL 探针，无脚本错误。LabProbe 的分辨率检查改为根据实际镜头距离计算可视范围，并独立检查原始构图边界。全工程原有 Cherry 重复类诊断仍存在。

当前边界：区域重叠按源共享状态的覆盖方式处理，未建立额外优先级或恢复栈；Godot 的确定性遍历顺序尚未与 Unity 重叠回调顺序逐帧对齐。运行时仅移植当前源单正权重目标组的等价计算，不是通用 Cinemachine 目标组实现。计时预览期间由预览控制镜头，结束后恢复区域状态，这一协调方式尚未覆盖所有原版重叠过场。其他未导入关卡、未逐个穿行的区域、动态启用的禁用触发器仍待验收。

```powershell
python Samples/ArtDirection/Tools/import_inari_camera_zones.py
godot --path . --rendering-method gl_compatibility --fixed-fps 60 --script res://Samples/ArtDirection/Tests/CameraZoneProbe.gd
```

导出依赖既有 mechanism_catalog.json 及 tmp/art-direction 下的五份反编译源码；JSON 记录各源码、清单和 Cinemachine DLL 的 SHA-256，便于核对来源。重复导出须保持语义一致。


## 教程喷焰装置与可复制场景

按用户补充的倒挂火柱截图，预设选择更新为 level24（STG0_2_ART）的 SteamTrap (2)，GO 566；原 level13（STG0_1_ART）的向上 SteamTrap 保留。二者主焰初速度分别为 7 和 3，不能只旋转同一份参数来代替。它们依靠三个粒子系统和默认 aircon_idle 风扇动画表现喷焰，导出层级没有 Fire 组件、Collider2D 或启用的粒子 Collision/Trigger 模块。此前基于脚本继承和物理回调的机关清单没有包含此类纯 Animator / ParticleSystem 装置，后续范围审计需覆盖这些层级。

独立场景 `Samples/INARIMechanisms/Devices/SteamJet/TutorialFlame.tscn` 与 `SteamJet.tscn` 包含本地原始像素和独立粒子配置。外部可调用开关方法，三个实例不共享可变状态；停止发射时保留存活粒子，重开不补发关闭期间的积压粒子。原版默认持续发射；可调用开关是复用接口，不虚构原关卡的按钮或伤害规则。选关页有独立展厅入口。

截图复核修正了三处实际缺失：恢复原模拟速度 3/2/2、按 source prewarm 预热一个周期、按 SortingLayer 后 SortingOrder 排序而非将火焰 -500 直接放到背景后。展厅增加源默认曝光 +1.7 stops 的可关闭对照，处理顺序为世界画面→曝光→UI；装置不擅自改变宿主视口。实际渲染检查验证下喷火柱的暖色像素、连续覆盖高度和亮黄区域，功能检查还覆盖初始关闭、暂停、重开及父级 Z 改变。共享粒子预热为显式调用，其他一次性特效的初始化未自动改变。

资源包使用相对 preload/include 和脚本资源位置定位数据，不依赖工程绝对路径、Autoload 或全局类名。整包复制到空白 Godot 工程并放入 Nested/RenamedDevices 后，SteamJetProbe、导入和单体场景打开通过。默认工具预览显示喷口，运行时播放全部粒子。NoiseModule、原场景环境照明/Bloom 和音频空间混音仍未完整还原。

用户新增“所有机关都能直接复制文件夹复用”的目标。该阶段仅喷焰装置完成此验收；既有可玩机关将逐项拆成独立场景，不能把已经可玩或可导出数据视为已完成复用迁移。复制边界和接口约定见 `Samples/INARIMechanisms/README.md`。

```powershell
python Samples/ArtDirection/Tools/import_inari_steam_jet.py G:/Misc/INARI_v0.2.1/Inari_Data
python Samples/ArtDirection/Tools/build_mechanism_native_runtime.py
godot --path . --rendering-method gl_compatibility --fixed-fps 60 --script res://Samples/INARIMechanisms/Tests/SteamJetProbe.gd
```

喷焰模块另通过原工程的 IceBoxProbe、TimeTrialProbe、LabProbe 和展厅入口检查（OpenGL）；来源哈希、最小依赖引用检查及 git diff --check 通过。完整文件夹连同导入侧文件复制到改名目录后再次导入和运行也通过。


## 拉杆与移动平台的独立场景迁移

`Samples/INARIMechanisms` 新增 Lever 和 MovingPlatform 两个可单独复制复用的场景。素材导出从既有 level22 校验数据中提取第一组机关的 SpriteRenderer、平台 Tilemap 单元、碰撞多边形、动画全部帧及原拉杆音效，归零根坐标；外部 PlatformControllerObserver 配对替换成宿主场景的显式信号连接。运动、等待、缓动、连续换向、轮子转动和灯光仍调用同一份原版移植代码。

平台新增显式乘客适配入口，使用宿主 CharacterBody2D 和 CollisionShape2D；角色状态与夹压响应由接口/信号连接，不强制继承原 demo 主角。原 demo 保留既有角色分支和死亡处理。位移乘载按父节点基底转为世界坐标，形状边界使用 Shape2D 的实际外接矩形；矩形原角色与新增胶囊示例均验证。未绑定乘客时可作为独立动态物件运行。

PlatformWorkshopProbe 使用真实键盘事件、攻击形状查询和普通控制器完成拨杆、上平台、搭乘、到站下船；另验证第二实例隔离、单次拉杆、拒绝苦无瞬移拨杆、连续换向不跳位置、暂停倍率、一致缩放后的位移换算及上升夹压信号。空白工程改名复制后同一检查通过，展厅切换会释放上一组装置。原工程 MachineryProbe、ElevatorProbe 和 SteamJetProbe 回归通过。OpenGL 编辑器内单体场景预览也已检查；Headless Dummy 渲染器仍可能报告既有 shader custom_samplers 诊断，不据此宣称其图形预览正常。

当前独立场景覆盖喷焰、拉杆、移动平台、机械门、冰冻装置、可破坏门、存档点、热阱与风增益九类；电梯、战斗/计时/奖励等模块仍待迁移。独立平台当前绑定一名乘客，未声明任意旋转、多人乘载、原版 Passenger 射线及下穿单向平台边界均已等价。

```powershell
python Samples/ArtDirection/Tools/export_portable_platforms.py
python Samples/ArtDirection/Tools/build_mechanism_native_runtime.py
python Samples/INARIMechanisms/Tests/verify_portability.py tmp/art-direction/runtime/godot.exe --output tmp/art-direction/portable-verification
```


## 机械门的独立场景迁移

新增 `INARIMechanisms/Devices/MachineDoor/MachineDoor.tscn`，采用 level5 出口门的原动画、碰撞时序、13 个视觉项和开关音效。既有本地化导出工具同时处理门、拉杆和平台，复制包不引用原关卡；`.tres` 存放来源默认值。独立门仅通过公开方法与信号连接宿主，不要求原角色或战斗管理器。DoorWorkshop 用两个独立拉杆控制一扇门，提供实际通行练习。

重新核对反编译 Door.Start / DoorRoutine 与动画绑定：doorColliders 的层会变更，但上门扇原有 disabled 状态不会被开启；只有 invisibleCollider 的 enabled 随通行状态切换。移植代码以前误启用了上门扇，这次在原 demo 与生成包同时修正。保留 Close 后 HardWall 直到下一次 Open 才复位的原协程语义。分离逻辑状态与可通行状态通知，为宿主提供投射物失效信号。

MachineDoorProbe 检查真实走路/攻击/门两侧阻挡、动画位移、延迟释放、关闭立即阻挡、切换取消旧释放时刻、幂等命令、音效、初始打开、独立设置和碰撞层、旋转缩放、释放节点及展厅切换。整包改名复制到空白工程后与既有喷焰/平台测试共同通过；OpenGL 编辑器内独立门预览检查通过。原 demo 的 BattleRoomProbe、TimeTrialProbe、CameraZoneProbe 通过。轨道播放尚不包含 Unity Animator 视觉转场混合；全局存档、完整战斗房间与其他机关的可移植场景仍待后续模块完成。


## 冰冻装置的独立场景迁移

新增 `INARIMechanisms/Devices/IceBox/IceBox.tscn` 与 IceWorkshop 展厅。源实例为 level5 / ElectroBox GO3526，参数来自既有已核对数据，保留蓄能闪烁、网格四向扩散、阻挡查询、访问顺序、原始默认动画和爆发音效。原行为源码新增显式宿主适配分支，原 demo 的角色/敌人路径继续使用；复制包通过生成器同步同一份源码。

宿主显式绑定观察者，注册目标与冻结/资格回调；未绑定观察者仍可工作，装置不查找角色、存档或战斗单例。网格与物理查询随根变换，原“先访问再测试半径/阻挡”的边界保留。原循环 WAV 与启动声音按实例管理。单次触发没有自行添加冷却复用，示例 R 键通过重新实例化演示生命周期。

原始 Unity 层级核对发现两股 cold_steam 子粒子，单独导出其模块、贴图、世界矩阵和来源哈希；动画 active 轨道在爆发时关闭它们。另带六组原 Eff_Freezing 爆发粒子。旧战斗房间入口尚未迁入这两股常驻子粒子；灯光、Noise 和条纹材质差异仍未声明完成。

Portable IceBoxProbe 在普通可移动宿主角色上通过真实按键与物理命中，验证蓄能延时、资格过滤、隔墙阻挡、冻结时长/恢复、拒绝刷新、一次性状态、音效与粒子清理、实例更换、无观察者调用、失效注册清理，以及旋转/缩放后的闭环墙与无墙扩散，以及轮廓遮挡和第二装置不能刷新已有冻结。完整改名复制工程中的喷焰、平台、门与冰冻检查通过；原 demo IceBoxProbe、BattleRoomProbe 通过；OpenGL 编辑器独立场景预览无脚本错误。

```powershell
python Samples/ArtDirection/Tools/export_portable_platforms.py
python Samples/ArtDirection/Tools/export_device_emitters.py G:/Misc/INARI_v0.2.1/Inari_Data IceBox
python Samples/ArtDirection/Tools/build_mechanism_native_runtime.py
python Samples/INARIMechanisms/Tests/verify_portability.py tmp/art-direction/runtime/godot.exe --output tmp/art-direction/portable-verification
```

材质贴图首次用于独立编辑器预览时发现动态资源根未初始化；将纯资源辅助脚本标为 `@tool`，确保改名复制后编辑器与运行时均使用包内路径。复制验收同时将资源加载失败纳入失败条件，避免仅检查脚本错误而漏掉贴图加载问题。


## 木门与重击门的独立场景迁移

新增 `INARIMechanisms/Devices/BreakableDoor`，通过两个场景/来源配置共用一份实现。导出 level2 木门和 level22 重击门的 21 个原碎片、实际启用多边形、材料、质量/阻尼/重力/约束和声音；根坐标归到碰撞底部中心。原 canShurikenHit 从机制审计字段读取，没有按门名称推断。木门两块原禁用碰撞的碎片保持只有自由落体和视觉。

OriginalDoor 支持宿主显式传入物理配置、碎片碰撞层/掩码与独立随机生成器。世界空间适配把装置根变换烘焙到碰撞形状和初速度，刚体保持单位缩放，保留整体旋转/一致缩放；破坏后的根变换不再拖动已生成的碎片，视觉在完成的绘制帧与物理体对齐。原 demo 保留本来的源场景坐标/投影分支。玩家直接交互也补上已有 invincible 字段的拦截，和敌人伤害路径保持一致。

宿主接口包含普通/重击/瞬移标志命中、敌人伤害累计、破坏/命中/碎片清理通知，以及投射物清理、相机反馈信号。可通过初始 broken 配置恢复保存状态而不重播特效。示例控制器增加 K 重击，在实际碰撞查询中调用同一公开入口；库不添加宿主 InputMap 或全局单例。

BreakableDoorProbe 验证真实走路阻挡、普攻击破木门、普通攻击不破重击门、K 重击后通行、同帧多碎片命中去重、原禁用碰撞、落地接触转动、十秒淡出/释放、保存状态初始化、无敌、敌人伤害累积、旋转缩放后的生成形状/速度，以及移动根节点后的世界空间绘制同步。改名复制整包后运行通过；两个单体场景 OpenGL 编辑器预览通过。原 demo DoorPhysicsProbe、RifleDoorProbe、BowDoorProbe 回归通过。

保留既有 Godot 碰撞求解和空物理材质摩擦/弹性假设；不能声称 Unity/Godot 碎片轨迹逐帧等价。原重击门轻击的短暂材质闪白尚未接入，现有音效/宿主反馈信号不等同于完成该视觉。全局存档与相机仍由宿主控制。

导出器会跳过内容一致的音频/共享资源，避免在编辑器正映射 WAV 时无意义地重写文件；资源字节和已有装置数据保持一致。重建仍使用 `export_portable_platforms.py` 与 `build_mechanism_native_runtime.py`，复制验收使用包内 `Tests/verify_portability.py`。


## 存档点与热阱的独立场景迁移

新增 `INARIMechanisms/Devices/Checkpoint`、`Devices/SpikeStrip` 和可玩的 `Examples/CheckpointHazardWorkshop.tscn`。通过 `Profiles/portable_hazards.json` 选择 level22 原存档点与第一段连续危险区，`export_hazard_selection.py` 根据源层级名称、父级和多边形空间位置定位四个 HeatTrap，不在行为脚本中硬编码场景对象编号或坐标。源存档点主 SpriteRenderer 关闭，美术子树也未启用，因此独立装置保留隐形触发区，示例提示标记由宿主绘制。

热阱导出 24 个精灵、八个原生蒸汽系统与约 272 × 48 像素的源碰撞路径。平铺素材直接读取 Unity 的连续平铺模式、原始边框、pivot、trim，补齐旧 slicing 清单没有覆盖的素材；独立渲染复用 OriginalSpriteSlicing 的分片规则，不把短条纹理拉伸。原 Tilemap 上另一块不连通的危险区未收入这一个可复制条带，源场景原有两个路径保持不变。

共享 InariCheckpoint 移除对整个 Rossi 玩家脚本的预加载，原 demo 显式传入自己的玩家，独立场景通过资格回调与 saved 信号连接宿主。保存是首次有效 Enter，默认无回血/体力奖励。公开载荷包括宿主自定 ID、世界出生位置、局部朝向及世界方向，原点换算、存档文件和复活由宿主控制；独立配置可恢复已使用状态。StudyHazard 增加宿主适配分支，保留玩家 Stay、敌人 Enter 与独立镜头反馈，不把独立敌人要求为 Rossi 类型。

独立探针通过真实走路完成保存、入阱死亡和宿主复活，检查无敌解除后的持续伤害、敌人进入失败后不补发、未注册及错误层过滤、禁用节点、已保存状态恢复、变换后的世界出生点/朝向与危险区、平铺几何、粒子和整组场景释放。示例修正传送后旧重叠表仍可能伤人的时序问题，复活后等两次物理步再接受伤害。

重建顺序：

```powershell
python Samples/ArtDirection/Tools/export_hazard_selection.py G:/Misc/INARI_v0.2.1/Inari_Data
python Samples/ArtDirection/Tools/export_portable_platforms.py
python Samples/ArtDirection/Tools/export_device_emitters.py G:/Misc/INARI_v0.2.1/Inari_Data SpikeStrip
python Samples/ArtDirection/Tools/build_mechanism_native_runtime.py
```

全部机关可复用的总目标仍未完成；电梯、计时/奖励/战斗事件、换场景、镜头区和环境触发器仍需独立封装与验收，跨启动存档系统也未实现。

本模块完整改名复制验收：SteamJetProbe、PlatformWorkshopProbe、MachineDoorProbe、IceBoxProbe、BreakableDoorProbe、CheckpointHazardProbe 全部通过；两个新独立场景的 OpenGL 编辑器预览通过。原 demo CheckpointHazardProbe、PlayerDamageProbe 回归通过。核对了 28 项生成源码哈希与选择来源哈希，已有六类装置导出记录保持不变；未将既有退出纹理析构及沙箱缓存/证书提示称为已修复。


## 风增益装置的独立场景迁移

新增 `INARIMechanisms/Devices/WindStation/WindStation.tscn` 与可选角色侧 `WindBuff.tscn`。`Profiles/portable_wind.json` 选择 level15 的首个 MoveSpeedChangeTrigger，导出器核对原层级并提取两个精灵、65 张使用到的原精灵帧、四状态 Animator 的材质曲线/过渡与两组共 16 个音效样本。通用像素裁剪、材质相对路径和内容一致时跳过复制的逻辑提取到 `portable_device_assets.py`，旧八类导出数据保持不变。

InariWindTrigger 不再预加载原玩家类型，原 stage 在角色创建后的 bind_source_mechanisms 阶段显式绑定；独立场景使用 WeakRef、资格/出生/请求回调及体力、剧情治疗和反馈信号，不要求宿主继承 Rossi 控制器。初次补体力、出生等待前的 On 动画和声音、出生结束后才开始的五秒冷却、留在区域内不自动重触发，均保留原顺序。可移植路径还保留冷却归零后等待 Animator 离开 Ready 的条件，解绑或销毁待处理角色会取消延迟请求并恢复待机。

InariWindBuff 的可移植分支使用独立数组及宿主自定义时间倍率，仍走原来的采样后计时、下一更新初始化、上限升级、续期和清除逻辑。默认 1/2 级为 64/96 px/s 与 6/12 秒，来自 controls.json 的源数值换算。组件只输出额外水平速度，不直接改角色；删除装置后增益可以继续，角色死亡由宿主调用 reset。确认玩家击杀后才调用 notify_player_kill，未激活的增益不会因为击杀获得首级。

WindWorkshop 使用实际物理角色走入两台装置、J 形状攻击击倒宿主练习目标并报告归属，能观察增益衰减、升级和续期。WindStationProbe 检查这条可玩路线，并验证体力/治疗/冷却分离、音效次数、变换后的触发体、出生期间延迟和离区后激活、解绑/释放取消、倍率与暂停、零冷却的动画条件和整组释放。原角色描边、跑步尘埃、距离尾迹及 Eff_Accel 仍由宿主角色效果适配，独立示例没有声称其简易外观与原角色一致。

重建与验证：

```powershell
python Samples/ArtDirection/Tools/export_portable_wind.py G:/Misc/INARI_v0.2.1/Inari_Data
python Samples/ArtDirection/Tools/build_mechanism_native_runtime.py
python Samples/INARIMechanisms/Tests/verify_portability.py <Godot可执行文件> --output <包外测试目录>
```

全部机关复刻和可复用的目标保持未完成：电梯、计时/奖励/战斗管理、换场景、镜头区及环境触发器尚需独立封装；NPC 对话、部分事件链与音频参数解码仍有未完成内容。

本模块在 Godot 4.7.2 OpenGL 下完成整包改名复制验收：导入及喷焰、平台、机械门、冰冻、破坏门、存档热阱、风增益七组探针均通过。原 demo 的 WindBuffProbe、WindAnimationProbe、WindAudioProbe 均通过，无脚本或资源加载错误；已有沙箱缓存/证书及原工程退出纹理诊断仍未处理。31 项生成源码哈希、选择来源哈希及旧八类导出记录一致性已核对。


## 电梯的独立场景迁移

新增 `INARIMechanisms/Devices/Elevator/Elevator.tscn` 与 `Examples/ElevatorWorkshop.tscn`。`Profiles/portable_elevator.json` 选择 level14 首个 MoveElevator 与 SceneMoveTrigger，导出器沿实际 target 引用寻找平台，合并轿厢、按钮、门动画和出发站层级，得到 42 个视觉项、28 张精灵帧、两段原声音与一组蒸汽。Tilemap 展开逻辑提取到公共导出工具；两个连续平铺精灵直接读取源 border/pivot/trim。按钮默认材质采用 C# Start 实际替换后的 InteractableObjectOutline，描边渐变使用已有源证据确认的 OutQuad。

可移植入口通过显式乘客绑定、资格回调、交互/门状态/投射物收回/出口信号连接宿主，不访问 Rossi 玩家字段。一次性按钮、关门、两秒等待、1216 像素行程、160 px/s 速度和到站后 0.2 秒延迟放行均来自源数据。原 demo 保留自己的玩家和场景切换分支。固定出发站与固定出口保留在装置根下，只有轿厢、按钮及门跟随平台。

DeviceSprite 改为增量叠加动画位移，修复门扇动画覆盖平台整体位移的问题。DeviceEmitter 在 inactive → active 时恢复源 playOnAwake 一次性发射时钟，持续 active 不重复重启。源蒸汽使用 world/2D 碰撞，导出工具仅接受当前已适配且无需力反馈/碰撞消息的组合；粒子运行时允许宿主传入碰撞掩码，原 demo 默认层保持不变。

ElevatorWorkshopProbe 使用实际角色从左侧进梯、F 启动、闭门阻挡、完整上升、到站释放和右侧离开；沿途校验门动画与轿厢同步、出口提前触发、蒸汽重播和原声音循环。额外检查旋转/缩放后的门几何、自定义碰撞层真实射线命中、资格/禁用角色过滤、独立实例以及清理。展厅选择电梯后再切回喷焰会释放全部节点。

重建：

```powershell
python Samples/ArtDirection/Tools/export_portable_elevator.py G:/Misc/INARI_v0.2.1/Inari_Data
python Samples/ArtDirection/Tools/export_device_emitters.py G:/Misc/INARI_v0.2.1/Inari_Data Elevator
python Samples/ArtDirection/Tools/build_mechanism_native_runtime.py
python Samples/INARIMechanisms/Tests/verify_portability.py <Godot可执行文件> --output <包外测试目录>
```

独立包仅发出原出口语义信号；示例继续完整行程，原 demo 仍完成 level14 → level2 与 CUTSCENE_ELEVATOR_ARRIVED_00。该到站 Timeline 尚未独立封装。全部可交互机关目标仍未完成，计时/奖励/战斗事件、通用换场景、镜头区域和环境触发器等仍待迁移；未把原 demo 可玩视为所有模块均可复制。

本模块验收：Godot 4.7.2 OpenGL 下，整包复制至空白工程的 `Nested/RenamedDevices` 后导入及八组运行探针全部通过；电梯单体编辑器预览通过。原 demo 的 ElevatorProbe、MachineryProbe、IceBoxProbe 回归通过，无脚本或资源加载错误。33 项生成源码哈希、源文件/输入数据哈希已核对，旧十份装置/组件导出记录保持一致。已有沙箱缓存/证书提示及原工程退出纹理析构诊断未在本模块处理。


## 场景切换触发器的独立迁移

新增 `Devices/ScenePortal`，导出器扫描完整 mechanism_catalog 的 SceneMoveTrigger，而非只导出此前 machinery 选中的 level14。共七个源实例，含五个一次性、两个可重复、两个保持输入出口；目的地经 SceneReference GUID → 原路径 → BuildSettings 索引解析。七个预设均保留实际碰撞大小与偏移。全部原节点无 Renderer，唯一子节点 SpawnPoint 只有 Transform，作为来源元数据保留，不伪造门框或拿它当目的地出生点。

共享 InariScenePortal 增加 once/active、共享 loading 回调、结束待处理请求和显式激活接口。默认电梯出口保留一次性行为。独立场景用 WeakRef 绑定宿主角色、资格和加载回调；只有 Enter 触发，加载时进入被忽略后不会在 Stay 上补发。角色状态、存档和场景资源由宿主处理，活动状态可按稳定宿主 ID 保存/恢复。

反编译 PlayerInputController 与游戏自带 UnityEngine.CoreModule.dll，确认保持输入的非零方向逐轴经过 Mathf.Sign，且 Sign(0) = +1。因此原 (1,0) 注入的是 Unity (1,1)，转换到 Godot 为 (1,-1)；方向为全零时保留原输入。请求同时携带原设置、注入结果、保留标志、无敌与冲刺重置信号，示例只按其水平分量驱动简单角色。官方交叉参考：https://docs.unity3d.com/ScriptReference/Mathf.Sign.html 。

可选 SceneTransition 场景实现源两秒 OutQuad 淡出/淡入和独立时钟，不依赖 Autoload，也不直接加载目的路径。宿主在 covered 后替换场景并用对应 ticket 完成加载；过期/重复完成请求被拒绝。loading 在淡入前清除，淡入时新请求可接管遮罩。取消或移除时通知宿主恢复角色控制。原管理器还涉及流式加载、存档、回血、时间倍率等全局策略，这些没有塞进可复制出口。

PortalWorkshop 使用三个实际 PackedScene 展示保持输入和普通出口、全黑替换、清理旧场景、淡入前清除保持状态及结束后恢复控制。ScenePortalProbe 通过真实输入和物理重叠验证该链路，并覆盖七个源配置、重复/一次/初始禁用恢复、世界输入、共享加载过滤、暂停/零倍率、过期 ticket、取消及展厅清理。

重建：

```powershell
python Samples/ArtDirection/Tools/export_portable_portals.py G:/Misc/INARI_v0.2.1/Inari_Data
python Samples/ArtDirection/Tools/build_mechanism_native_runtime.py
python Samples/INARIMechanisms/Tests/verify_portability.py <Godot可执行文件> --output <包外测试目录>
```

尚未完成全部机关目标：电梯到站 Timeline、MoveSceneObserver、计时/奖励/战斗管理、镜头区域、环境音触发、NPC 及部分事件链仍需继续迁移或补齐。七个 SceneMoveTrigger 已提取不代表原游戏所有场景内容已移植。

本模块验收：Godot 4.7.2 OpenGL 下，整包改名复制后导入及九组运行探针全部通过，三个出口单体的编辑器预览通过；最终出口代码再次通过运行探针。原 demo ElevatorProbe、LabProbe 回归通过，无脚本或资源加载错误。全部七个源出口、33 项生成源码哈希、源资源/行为代码/导出输入哈希已核对，既有十一份装置/组件导出记录保持不变。已有沙箱缓存/证书及原工程退出纹理析构诊断仍未处理。


## 计时挑战隐藏奖励的独立迁移

计时挑战资源审计确认 RewardObserver 和 HiddenItem Trigger 可独立拆出，不应绑定整套战斗/计时管理器。新增 `Devices/HiddenReward/HiddenReward.tscn` 与 `Examples/RewardWorkshop.tscn`，从 level3 导出 9 个视觉项、32 个精灵帧、7 个追踪光点、8 组原子粒子、Destroy 缓存动画、灯光曲线与两段声音。配置选择来自 `Profiles/portable_reward.json`，生成工具保留来源、行为 C#、动画和音频输入哈希。

共享 InariTrialReward / InariChargePoint 增加显式宿主回调与信号路径，不读写 Rossi 玩家字段或库存。领取只发出一次主奖励和已有增益续期请求；每个光点按真正接触角色后发出一次货币。新增 WindBuff.refresh_existing，不能创造首级或升级。初始已领状态不重播效果/事件，资格丢失或角色释放取消余下光点，重绑定不转送。

原 cached Destroy 里 m_Enabled 的目标类型是 ShurikenChargePoint，不能用作精灵可见性。第七个组件只在动画最后一帧启用，修正了原 demo 与可移植路径共同的提前启动问题。原 TimeTrialProbe 的固定 80 帧领取等待因这一源时序修正不再足够，改为在 180 帧上限内等待实际七次接触，仍断言全部到账与全部 received，不强行移动光点或发放奖励。

粒子导出补上祖先有效激活状态与祖先 ID，避免把 inactive 光点下 activeSelf 的发射器提前播放。可移植发射器使用父光点相对初始变换更新世界发射姿态，保留移动/旋转和世界空间尾迹。光点捕获仅关闭其 SpriteRenderer，子粒子按源保持活动；角色无效或失去资格后关闭尾迹。共享粒子代码默认仍使用原 effect.global_transform。

实渲染检查发现 SquareDistortion 被旧普通精灵适配画成大白圆。已从该材质实际引用的原着色器提取 vertex/fragment D3D11 程序与参数，恢复 Twirl、整数 hash 梯度噪声、反向边界饱和多项式和屏幕折射；使用原 12 顶点/30 索引网格及 Sprite UV，而非新增圆形近似。缩放和强度由 Destroy 原曲线采样。该独立网格适配目前只接入可移植奖励；原关卡通用渲染器的此材质仍需后续统一。

三组 Light2D 的原曲线作为宿主信号数据保留，未移植原场景分层灯光/Bloom；Godot 屏幕取样时机和 Unity sorting-layer capture 也有差异。粒子 NoiseModule 仍缺失。测试覆盖接触奖励、追踪/第七个延迟、真实屏幕渲染无白色遮挡、尾迹、音效、倍率、恢复、资格、变换和清理，不将这些画面差异宣称为已完成。

重建：

```powershell
python Samples/ArtDirection/Tools/export_portable_reward.py G:/Misc/INARI_v0.2.1/Inari_Data
python Samples/ArtDirection/Tools/export_device_emitters.py G:/Misc/INARI_v0.2.1/Inari_Data HiddenReward
python Samples/ArtDirection/Tools/build_mechanism_native_runtime.py
python Samples/INARIMechanisms/Tests/verify_portability.py <Godot可执行文件> --output <包外测试目录>
```

全部机关目标仍在进行：计时起终点/路线预览、战斗封锁、到站 Timeline、镜头区、环境触发与未完成事件链仍待迁移；此模块是可连接这些流程的独立奖励场景。

本模块验收：Godot 4.7.2 OpenGL 下，整包改名复制后导入与十组运行探针通过；最终奖励代码再次通过 HiddenRewardProbe 和单体编辑器预览。原 demo TimeTrialProbe、ParticleProbe、WindBuffProbe 回归通过。35 项生成源码哈希已核对，无脚本、着色器或资源加载错误；已有沙箱缓存/证书/编辑器存储及原工程退出纹理析构诊断仍未处理。


## 计时终端与路线预览的独立迁移

新增 TimerStart、TimerFinish 单体场景，以及可选 TimeTrial 协调器、RoutePreview 相机适配器。原版只有 level3 一组起终点；导出按 TimeAttackTrigger.dest 实际引用寻找终点，相对坐标由导出器写入组合场景，不在行为脚本中硬编码。每端 16 个视觉项、12 张帧图、4 位 UV 数字、接近轮廓、两态 Animator 和 6 类音效均来自原记录；实际 Unity 对象审计确认两端层级没有 ParticleSystem。

InariTimerClock / InariTimerDigits 从旧 InariTimeTrial 抽出，原 demo 和可移植组件复用整秒边界、零时钟门控和 UV 滚动计算。InariTrialTerminal 增加显式宿主资格/使用/接近信号；原 demo 仍保留自己的 interaction_target 分支。宿主交互检测补充实际形状查询，解决 Godot 静止物体切层后 Area2D 缓存未更新导致无法交互的问题。

依据 TimeAttackTrigger / TimeAttackTriggerDest / TimeAttackTimerBase 反编译代码保留首次预览、重试跳过、源重复声音调用、超时不杀人、成功开门、IsTimeOver/CollEnabled 恢复及存档后死亡继续计时到零的特殊行为。旧 demo 管理器的死亡分支仍沿用 failed 后停更的既有实现；可移植路径补齐了这条 C# 细节，尚未统一原 demo 的该管理分支。

RoutePreview 使用实际停靠顺序、等待和阻尼；MyWaitForSeconds 经本地 C# 核对，等待基于 Time.time，不能乘 GameManager 自定义 TimeScale。适配器在等待时仍保持相机跟随，返回只检测横向距离，保留 depth_changed 给宿主投影。Camera2D 示例不实现原完整 Cinemachine 分区、透视背景与灯光，也不包含原战斗波次，不据此宣称所有机关已经完成。

重建：

```powershell
python Samples/ArtDirection/Tools/export_portable_time_trial.py
python Samples/ArtDirection/Tools/build_mechanism_native_runtime.py
python Samples/INARIMechanisms/Tests/verify_portability.py <Godot可执行文件> --output <包外测试目录>
```

首次冷导入曾发生无脚本报错的编辑器退出崩溃，随后的 OpenGL 导入与新空白工程完整导入通过。另一次增量复制覆盖了测试工程的 .import 映射却未重新导入，出现贴图缺失；那次运行虽打印 PASS，因资源/脚本错误作废，已用全新工程重新导入后验证。复制到其他工程必须等 Godot 完成素材导入再运行。

本模块验收：Godot 4.7.2 OpenGL 下，完整资源包改名复制到空白工程并重新导入，十一组运行探针通过。最终计时挑战额外通过死亡后继续计时与结束音检查、实际移动/门/奖励回归；起点、终点、组合场景的三次编辑器预览通过。原 demo TimeTrialProbe、LabProbe 通过。38 项生成源码哈希，以及两个新装置的导出输入、行为代码、配置、逐图像像素和音频内容均已核对；最终运行没有脚本、着色器或资源加载错误。已有缓存/证书/编辑器存储与原工程退出纹理析构诊断未在此模块处理。


## 可复用分波控制与接触封门

新增 BattleEncounter、DoorContact 独立场景和 BattleWorkshop。配置从 level5 的原 SpawnManager/DoorContactTrigger 导出，包含两波八个原成员的对应键、原始 SpawnPoint、砸印/绳索类型与局部偏移、等待时长、触发矩形、行为代码和输入数据哈希。入场美术仍由后续独立模块承接，本次不把示例圆环当作原 Stamp/RifleManRope。

普通波次计时抽出 InariEncounterClock，由原 InariBattleRoom 与复制包共同使用。保留实时时钟的波间/收尾等待、游戏时钟的入场/静止等待、自定义 TimeScale 仅在进入 SpawnRoutine 等待前门控的条件，以及清场先标记 isEnd 后延迟通知门。旧波次的 peaceful 等待独立保留，不能把新波提前变为 Wild；重复死亡不会扣减新波。原 demo 的入口场景和原敌人保持原有绑定。

宿主接口显式绑定敌人、门和玩家；无硬编码场景节点搜索、全局 InputMap 或 Autoload。门触发器提供房间外苦无清理请求与源 isActivated 存档字段。独立练习目标通过真实物理攻击、血量归零发出死亡信号，不靠计时模拟清场。示例 R 重试和展厅更换通过显式 replace_exhibit 更新所有权，避免残留旧房间。

全部机关目标仍未完成。两类入场动画/音效已由后续模块接入；末尾 Timeline、到站 Timeline、镜头区、环境触发器、NPC 与其他事件链仍需继续迁移或校准。MonsterSpawnerTrigger、重复刷怪及 selectedEnemy 阈值协调逻辑见后续章节；完整敌人资源的复制复用仍未完成。

本模块验收：Godot 4.7.2 OpenGL 下，新空白工程整包改名导入和十二组运行探针全部通过；BattleEncounter 与 DoorContact 单体编辑器预览通过。最终原 demo BattleRoomProbe、CameraZoneProbe 通过，41 项生成源码哈希及本模块源数据、C# 行为哈希一致。实际攻击/通行与第二波截图已检查；已有沙箱缓存/证书提示及原工程退出纹理析构诊断未在本模块修复。

## 可复用区域延迟召唤

新增 MonsterSpawnTrigger 独立场景、五个原实例预设和 SpawnWorkshop 组合示例。导出器从完整 mechanism_catalog 找出 level6、level8（两个）、level10、level21 的 MonsterSpawnerTrigger，并对本机原场景哈希、组件字段、碰撞、SpawnManager 引用及全局 callbacksOnDisable=true 逐项核对。保留原变换基和碰撞偏移，只归零世界平移；level8 两个区域初始碰撞禁用，不能默认提前召唤。

共享 InariMonsterSpawnTrigger 替换原 demo 的单次 trigger_delay 近似。按反编译代码保留进入事件先于等待、每次进入启动独立实时时间等待、离开/角色释放/等待中加载不取消、关闭对象取消所有等待、先 StartSpawn 后更新激活状态和停用的顺序。WaitForSecondsRealtime 首次轮询设置期限，零延迟首次轮询完成；实现依据 [Unity 官方源码](https://github.com/Unity-Technologies/UnityCsReference/blob/master/Runtime/Export/Scripting/WaitForSecondsRealtime.cs)。原生入口由 ArtDirectionLab 显式绑定加载状态，不通过节点搜索读取管理器。

恢复 isActivated 不禁用碰撞、不停止已经启动的等待；SaveData 始终返回标志。ActivateTrigger 只开碰撞并请求局部存档，不重新激活已经关闭的对象，也不清除标志。独立包通过 WeakRef 与回调绑定玩家和资格，通过 spawn_requested 连接宿主；碰撞层可配置，不依赖 Autoload/InputMap。完整用法见 `Samples/INARIMechanisms/README.md` 的“区域延迟召唤”。

SpawnWorkshop 组合 level6 触发区与原有两波训练示例，并在子节点初始化之前配置 on_field=false；R 使用当前 scene_file_path 重建，保留继承场景。它没有把源 level6 的三波房间替换成两波原版内容。level8 的 selectedEnemy 协调逻辑已在后续模块补齐，原角色适配与 Timeline 仍未实现，五个触发器导出不代表这些战斗流程已完成；全部机关目标保持进行中。

本模块验收：整包改名复制到空白工程后导入及十三组探针通过；最终定向探针补验实际物理进入、重复/零延迟、取消再启用、保存与回调顺序、恢复、资格/加载/层、角色释放、全局零时间倍率、示例召唤与重试清理。单体及组合场景编辑器预览通过。原 demo MonsterSpawnTriggerProbe 使用源 level6 配置与成员桩验证原协调器接线，BattleRoomProbe 与 LabProbe 回归通过。42 项源码及五个源文件、配置、目录和两份 C# 哈希一致；实际示例截图已检查。原有缓存/证书和退出纹理析构诊断仍未处理。

## 重复刷怪的来源补查与可复用协调器

RepeatingMonsterSpawner 不继承 Trigger/Observer，也没有自己的物理回调；它通过敌人死亡事件工作，因此旧 mechanism_catalog 的发现规则漏掉了它。新增 `export_portable_repeating_spawner.py`，独立扫描全部 29 个 level 文件（包括 inactive 对象），保留每份原文件哈希；发现唯一场景实例 level5/11886，所属层级全部激活，初始 EnemyBombMan=11742，等待 8 秒、淡入约 0.2 秒。完整字段、四种 prefab 引用和源位置保存在独立包的 `Assets/RepeatingSpawner/device.json`。这也说明仅审计 physics/inheritance 目录不足以证明全部机关已完成；其他间接事件组件和运行时 prefab 仍需继续核查。

新增 RepeatingSpawner 场景，以显式敌人工厂与 Idle/Color 回调解耦宿主 AI 和 GFX。初始实例设置 IsRepeated=true/IsLoaded=false；死亡后注销实体、移除持久化、按实时时间延迟创建，再注册新实体并按游戏时间淡入。独立成员、每代身份、等待采样与首轮询、淡入期间死亡、运行时 alphaTime 修改、切场景只清理新实体和关闭对象取消协程均保留源语义。宿主转发切场景事件，移除装置时另做所有权清理；无 Autoload、全局 InputMap 或场景节点搜索。

RepeatWorkshop 提供真实攻击和无限重生练习，保留导出的 8/0.2 秒设置；展厅增加“重复刷怪”，重试保持正确实例所有权。原 BombMan 完整 prefab/美术/AI 的独立化尚未完成；level5 原房间的替换对象适配已在下一节接入，不以单个刷怪机制宣称整个关卡完整还原。

本模块验收（2026-10-02）：全新空白工程整包改名导入及十四组探针通过；最终定向测试再次通过关闭期间死亡、缺失工厂和零等待边界。实际两次重击死亡、8 秒重生、淡入、全局零时间倍率、不同成员/代际、变换、清理/取消和重试均已验证。单体/示例编辑器预览、原 demo LabProbe 与 BattleRoomProbe 通过；29 个场景、配置和 C# 哈希一致，截图已检查。已有沙箱缓存/证书诊断未处理。

## 原版重复刷怪房间接入

原场景 EnemyBombMan 11742 与真正重生的 sharedassets5.assets / Enemy_Boom GO210 / EnemyBombMan673 不是同一份配置：前者 isScout=true、scoutDistance=6，后者 isScout=false、scoutDistance=5。`export_repeating_enemy_art.py` 按原 enemyPrefabDictionary 的 BombMan 键解析 prefab，分别提取初始和替换实体；不能用复制死亡角色代替原 Instantiate 路径。每份均为 15 个渲染节点，保留碰撞、弱点、默认/战斗动画、GFX 分支与 profile。数据保存在 `repeating_enemies.json`，附带原场景、prefab 资产、Assembly-CSharp 和补充目录的哈希。

Importer.scene 增加可选资产文件/根节点子树入口，保留源祖先变换、激活和 SortingGroup，不引入祖先美术或同文件其他 prefab。原普通关卡调用方式保持不变；使用 HEAD 原导入器和新版分别完整提取 level5，两个 3209 精灵场景的 JSON 深度比较一致。所有原精灵 metadata 保持原样，新记录复用已有像素；七个新材质放入 Repeating/ 命名空间，原 216 个材质内容未变。

InariRepeatingRoom 作为原 demo 宿主接入可复制 RepeatingSpawner：每次创建新 OriginalEnemy 及其私有渲染节点、材质和动画对象，不复用旧尸体或全局 GO 映射。平移同时更新 GFX、原碰撞范围中心和视觉世界坐标，弱点接触能在实际重生位置工作。每帧 Idle 保留敌人物理处理，淡入仅写原 GFX 主渲染器；初始巡逻配置和重生 prefab 的非巡逻配置分别保留。活动敌人列表、玩家苦无目标列表、AI 目标和自定义时间域同步接入，场景切换前转发清理，再由原场景释放所有节点。

新增“机关工厂→重复刷怪”入口，位置由源实体和 `Profiles/native_repeating_preview.json` 的展示偏移生成。目标是击败 BombMan 并等待重生两次；它使用原 level5 场景、原敌人视觉和现有 BombMan 索敌/追击/自爆逻辑。原 demo 尚无完整敌人持久化数据库，此处观察移除事件而不伪造存档。此原版宿主仍依赖 ArtDirection，完整敌人资源/AI 的独立文件夹迁移未完成，可复制协调器仍通过工厂接入宿主敌人。

重建：

```powershell
python Samples/ArtDirection/Tools/export_repeating_enemy_art.py G:/Misc/INARI_v0.2.1/Inari_Data
```

本模块验收：RepeatingRoomProbe 通过原玩家真实重击杀死初始实体、完整等待和淡入、独立新 prefab 配置/血量/材质、实际重生位置、弱点范围接触、活跃 AI 自爆再次启动等待及切关释放。弱点接触部分为配置了源存活时长的几何夹具，未把它表述为完整苦无输入测试。初次失败定位为夹具未设置存活时长、导致原 update 正确清空弱点，修正夹具后通过。原 demo LabProbe、BattleRoomProbe 通过；源哈希、导入前后等价性与实际截图已检查。已有沙箱缓存/证书和退出时纹理析构诊断仍未处理。

## 血量阈值增援与跨波存活成员

核对完整目录的 29 个场景及主程序集哈希后，唯一非空 selectedEnemy 为 level8/SpawnManager11829 的第三波 EnemySwordMan11735，hpRatio=0.75；四波人数 `[2,3,1,2]`。新增导出器逐字段比对实际组件，保留所有波次、成员/类型、原位置、等待和 Timeline 引用，生成 ThresholdEncounter 场景及源 Resource 预设。练习布局单独置于 profile，不改写源位置。

共享 InariEncounterClock 增加一次性伤害阈值监听及已注册成员集合。达到阈值只推进阶段，不记作死亡；对应原 remainingEnemyCount 和负 dieMonsterCount，把旧波存活数量带入新波。旧成员在波间等待或入场期间死亡同样扣减，新波激活不能覆盖剩余数量。致命伤害先触发阈值再发出死亡，仍只扣该成员一次。普通计数波次继续使用同一内核；最终波阈值直接开始结束流程的原行为也被明确保留。

BattleEncounter 新增 `settings.thresholds`、`notify_damaged(key, actor, ratio)`，保持显式身份绑定和保存顺序。原 InariBattleRoom 连接对应原敌人的 damaged 信号，并读取真实 health/maxHealth 比例。导入器解除阈值数据本身的拒绝，但仍拒绝未实现的结束 Timeline 和不支持的敌人种类，未把源 level8 完整房间算作已可玩。

ThresholdWorkshop 保留源四波人数，使用真实形状攻击和血量事件驱动练习实体；第三波紫色目标残血时最后两名目标加入，击败增援后旧目标仍阻止开门。其 SwordMan/SpikeMan AI、美术及 Timeline 未实现，属于可复制宿主示例；原入场动画已由后续模块接入。原版适配探针使用同一份 level8 数据和实体桩检查 damage→比例→阈值→旧死亡→清场的接线，与真实原敌人 AI 验收分开。

事件顺序另核对 InGameEntity.ChangeHealth 与 EnemyInGameEntity.OnDamaged：先更新 Health，再通知伤害，最后检查死亡；零伤害仍会触发 OnDamaged，治疗不会。来源记录包含这两份 C# 与 SpawnManager/SelectedEnemy 的行为哈希。

本模块验收：新空白工程整包改名导入与十五组探针通过；ThresholdEncounter 单体/ThresholdWorkshop 编辑器预览通过。精确阈值、重复/未来/错误实体、致命事件顺序、跨波死亡、最终波阈值、恢复、真实四波攻击和增援后的旧目标清场、保存/开门、重试清理均已验证。ThresholdBattleProbe 原适配夹具、BattleRoomProbe、MonsterSpawnTriggerProbe、LabProbe 回归通过。42 项生成源码及本模块来源/输入/行为哈希一致，实际三名存活目标同屏截图已检查；已有缓存/证书和退出纹理析构诊断未处理。

## 事件切场观察者的独立复用

新增 SceneObserver 独立场景及七个 MoveSceneObserver 源实例预设。export_portable_scene_observer.py 在核对全部 30 个源哈希后，对 29 个 level 独立扫描 MonoBehaviour 头部并与目录交叉检查，避免只扫描空间变换而漏掉 UI/无变换组件。目的地由 SceneReference GUID、原资源映射及 BuildSettings 解析，保留原路径、源字段与完整上游 UnityEvent 调用。

源上游已解出 level16→22、level17→25、level25→13、level26→18 的演出结束通知；level27 与 level28 则调用 MainMenuMoveNotify。后者调用 GameManager.MainMenuScene，不能用观察者自己的目标代替（level28 自身字段指向 level28）。该组件由宿主显式提供菜单键；原全局管理器的完整持久化与加载实现不在本模块内。七个源场景的入站事件扫描有 28 个组件字段解码失败（包含 TimelineBindingProvider 及音频、相机组件），已保存在 provenance，不将未找到序列化调用等同于运行时不可触发；运行时 prefab 和间接绑定继续待查。

普通通知保留 IsLoadingScene 门控、可选停止输入、前场景/出生点保存、新场景/零出生点写入、同步保存、清空持久化并仅注册玩家、最后请求切场的顺序。ObserverMask=0 并不阻断此 override 的通知。主菜单入口保留不检查加载、不停止输入、不改写关卡存档的差异。纯信号和显式共享上下文使装置不依赖 Autoload、场景路径搜索或 Rossi 控制器。

SceneObserverWorkshop 用实际拉杆攻击发出通知，复用现有遮罩、玩家与房间加载，演示普通保存切场及独立菜单返回；这是宿主接线练习，不以替代拉杆声称原过场已完成。PortalWorkshop 的初始房间与文案增加导出参数以支持继承场景，其原默认配置不变。展厅新增“事件切场”。后续仍须迁移上游完整 Timeline、其角色/演出绑定、其他三类移动观察者及游戏级存档。

本模块定向验收：SceneObserverProbe 在改名嵌套的空白工程通过全部七个预设、加载期间拒绝、重复/任意类型通知、禁用处理时的显式调用、存档顺序和快照隔离、菜单入口及真实物理攻击两次换场景；重试、淡出期间卸载与展厅切换释放通过。单体及组合场景编辑器预览、原 demo LabProbe 通过，实际运行截图已检查。整包回归结果见本节后续记录。

整包验收补记（2026-10-02）：全新空白工程 Nested/RenamedDevices 重新导入与十六组探针全部通过（包括原 ScenePortalProbe 回归）；37 份来源文件、目录输入及三份行为 C# 哈希复核一致。无脚本、着色器或资源加载错误；已有沙箱缓存/证书及原工程退出纹理析构诊断未处理。完整机关目标保持进行中。

## 原版战斗入场 prefab 与独立复用

新增 SpawnStamp、SpawnRope、ArrivalBatch，提取 16 个源 SpawnManager 实际引用的两个 sharedassets3.assets prefab。砸印 12 精灵/21 轨道/5 个可见粒子系统，绳索 7 精灵/17 轨道/4 个可见粒子系统；另外保留不渲染且不发射的粒子父组证据。此处采用完整原层级及 streamed/constant 通道，补上通用扁平动画导入没有覆盖的父级运动、缩放、SpriteRenderer 尺寸、透明度、粒子分支激活与 SpriteMask。所有绑定均按类型明确解码，未支持的新绑定会阻止导出。

ArrivalBatch 按原敌人 Y 排序，枪兵只在源 GFX 世界 X 缩放约等于 -1 时翻转。源实例的 GFX 缩放单独导出，并在原 demo 按当前转向调整；可复制宿主通过显式回调提供此值。BattleEncounter 新增整波 wave_arrival_requested 信号，保留旧单成员信号。原 InariBattleRoom 和所有 BattleWorkshop 派生示例均接入同一份可复制效果；原生宿主关闭效果内部音频，沿用现有 stage 音效，以免重复播放。

保留 EnemySpawnStamp 的源码边界：Animator 自定义时间倍率与粒子游戏时钟分开；枪兵图像在 1.2166667 秒隐藏，未提前到 1.2 秒。绳索匹配状态名，normalizedTime > 1 后释放；砸印 aniName=Animation_SpawnStamp1 与唯一默认状态 Spawn_Stamp 不匹配，原协程不会自行销毁它。宿主卸载释放全部效果，animation_completed 可供其他工程选择主动清理。修复共享 DeviceEmitter 在隐藏后只清空粒子列表、未释放可见节点的问题，防止重新激活时旧粒子重现。

点光原始字段及强度轨道保留，并通过 light_state_changed 提供动态世界变换；尚未移植它们对场景的 URP 照明，NoiseModule/3D 粒子及碰撞近似沿用现有边界。完整敌人资源独立化、战后 Timeline 和所有机关目标仍未完成。此前章节中“原入场 prefab 未播放”的阶段性边界由本模块更新。

验收：全新空白工程整包改名导入及十七组探针通过；两个单体编辑器预览通过。五个源采样时刻的全部节点世界矩阵与独立 Python 源曲线结果一致；真实 GPU 遮罩像素、枪兵逐帧、杆件伸缩、镜像、排序、音效、时钟、回收、物理触发及释放均通过定向检查。原 BattleRoomProbe 在真实攻击换波时确认四个原 prefab、关闭双重音效、截图及切关释放；ThresholdBattleProbe、MonsterSpawnTriggerProbe、LabProbe 回归通过。全部本模块源/输入/行为哈希、图像逐像素和 WAV 文件哈希一致。

全量原工程编辑器导入暴露 Game/UI/Joystick 与 addons/cherry 中现有重复 UID/全局类名错误；本模块未修改这些文件，独立包和原 demo 定向运行通过。缓存/证书及原工程退出纹理析构诊断仍未处理。

## 镜头区域复制复用与真实时间修正

新增 CameraDistanceZone、CameraFixedZone、CameraZoneController 三个独立场景与可选 CameraZoneRig 适配器。全部 60 个关卡及资源文件的组件头已独立扫描，35 个区域预设逐字段核对；保留 33 个初始启用实例及 2 个禁用实例。导出原碰撞几何、世界矩阵、一次标志、混合比例、跟随偏移、距离和阻尼。扫描另证实 MoveBeforeSceneObserver、MoveStageSceneObserver、MoveHubStageSceneObserver 没有序列化实例，未仅因反编译目录存在类名而创建虚构关卡机关。

原 InariCameraZone/InariCameraZones 现在是便携区域与共享 Controller 的宿主适配器。InariCameraRig 新增显式 configure_host，原角色入口只负责原点换算和信号接线；同份相机渲染源码通过生成器加入包内，避免另写一套阻尼。固定目标仍采用现有单正权重组的适配边界，不把它宣称为完整 Cinemachine；源重叠事件先后次序、任意目标组和全部关卡路线仍未逐帧重现。

修正了旧适配把 WaitForSecondsRealtime(0.2) 当作游戏 delta 的问题。新时钟读取单调真实时间，不随慢动作/固定 FPS 改变；各次软区域过渡独立到期。固定区加载期间已进入又离开的等待仍在加载结束执行，保留源协程行为；一次区域在退出时清除标志，宿主显式恢复碰撞后成为可重复区域。原 demo 的暂停过滤、挑战镜头与神殿 Timeline 所有权保留在宿主适配中。

CameraZoneWorkshop 使用原检测尺寸和镜头参数，在独立练习走廊展示拉远、固定构图、跳跃时的混合跟随与一次退出。已加入可复制展厅第 17 项。CameraZoneProbe 对全部 35 预设做旋转父级下真实碰撞、禁用启用、退出/再次进入、时钟与释放检查，并验证加载后延迟进入、冻结、错误对象/层、重叠覆盖和实际行走/跳跃/重试/展厅切换。该模块不代表 NPC/战后/到站 Timeline 或全部机关已完成。

验收记录（2026-10-02）：空白工程 Nested/RenamedDevices 改名导入与十八组完整运行探针通过；最后追加的重复等待清理、相机控制权恢复分别通过独立包和原 demo 定向复验。两个单体编辑器预览通过，实际行走/跳跃截图已检查。原 CameraZoneProbe（含真实时间慢动作）、InariCameraProbe、TimeTrialProbe、ElevatorProbe、LabProbe 通过。61 份来源文件、全部目录/行为输入和 44 项生成依赖哈希一致。没有脚本、着色器或资源加载错误；原工程已有缓存/证书与退出纹理析构诊断未在本模块处理。

## 环境音参数来源解码

`Tools/unity_parameter_triggers.py` 修复读取副本中的两个具体问题：TypeTreeGenerator 将 `SerializableDictionary<string, float>.keys` 的 List<string> 标成 string；MonoBehaviour.m_Enabled 后漏掉四字节对齐。修复在构造私有 TypeTreeNode 之前完成，避免 UnityPyBoost 缓存类型分派；没有改写原游戏文件、第三方库或已有清单。m_Script 指针额外与原生 MonoBehaviour 头比较，修正后不再产生误位的文件 ID。

`Tools/export_environment_audio_catalog.py` 扫描全部 60 个关卡/资源文件，补充导出 `Original/INARI/environment_audio.json`。全部 86 个 AmbientParameterTrigger、84 个 BGMParameterTrigger、54 个 ReverbParameterTrigger 和 1 个 BGMProfile 均能完整读取，回写字节与原组件完全一致。原几何由源 Transform 独立计算并与清单核对，碰撞字段逐项核对；保留全部 UnityEvent、源存档 ID、触发层、once、激活状态与原列表，不根据名字猜参数。

215 个对象初始激活，另 9 个未激活对象均在 level11；level14 两个 BGM 区的触发层为零且 once=false；两个 once=true 实例实际位于 level22/17453 与 level8/12004，不能因为有碰撞体就当作可通过普通玩家进入触发。派生参数字典遵循 OnAfterDeserialize 的 min(keys, values) 与重复键保留首项规则，而非让后项覆盖前项。全部源 UnityEvent 列表为空。检测层 64 是源 Unity 层位，后续宿主需显式转换成自己的玩家层。

沿实际 BGMProfile/Emitter GUID 解析 12 个 FMOD 事件，记录事件路径、时间轴长度、参数默认值/范围/ID/类型/标志。使用原 fmodstudio.dll、Master/AMB/BGM/Snapshot banks 创建真实事件实例，全部 2,760 次 setParameterByName 返回成功；getParameterByName 读回每个请求值完全一致。只查询和设置未开始播放的事件，不修改原 bank。路径中有 Snapshot 字样的两个对象实际是承载快照逻辑的普通事件（isSnapshot=false），运行时必须按真实事件处理。

行为核对：三类派生 OnEnter 在 base.OnEnter 返回后仍调用 BGMManager，因此场景加载只阻止基类的一次消耗/enterEvent，不阻止音频参数写入。OnExit 不恢复参数，也没有 Stay 持续重写。BGMManager 仅更新传入键；同 GUID 保留当前事件实例并改参数，不重新 start；换 GUID 时按 ALLOWFADEOUT 停止并释放旧实例，再创建、设参、start 新实例；空 GUID 不操作。环境/混响常驻实例无效时不写参数。ResetAmbience/ResetReverb 由 GameManager 进入 MenuMode 时调用，不能当作任意换关或每次区域离开事件。后续实时混音接线需保留这些语义。

独立验证 `Tests/verify_environment_audio_catalog.py` 不使用生成类型树，按 struct 顺序重新读取全部 225 个对象并核对所有字段；同时拒绝截断或附加尾字节，检查几何来源哈希与音频赋值证据。导出重复运行得到相同 SHA256。FMOD PARAMETER_DESCRIPTION ABI 另由原 FMODUnity.dll 反编译核对，未使用旧 pyfmodex 的过时结构。

重建与验证：

```powershell
$env:PYTHONPATH='tmp/art-direction/pydeps;Samples/ArtDirection/Tools'
python Samples/ArtDirection/Tools/export_environment_audio_catalog.py G:/Misc/INARI_v0.2.1/Inari_Data
python Samples/ArtDirection/Tests/verify_environment_audio_catalog.py G:/Misc/INARI_v0.2.1/Inari_Data
```

以上是前一数据解码里程碑的验证范围；实时播放与可复用接线见下一节。

## 实时 FMOD 环境音与可复用区域

`Samples/INARIMechanisms/Devices/EnvironmentAudio` 新增 AmbientZone、BGMZone、ReverbZone、共享 EnvironmentAudio 和全部 224 个源设置资源。独立展厅可行走切换室内/室外参数；ArtDirectionLab 按源关卡实例化区域，跨房间保留同一 Mixer。适配器显式读取原角色碰撞层，避免独立示例的层配置漏接原玩家。

`Core/Fmod` 使用 Godot 的 C ABI 注册一个 RefCounted 原生运行时。它动态加载原 fmodstudio.dll，持有 Studio System 与事件句柄；GDScript 管理原 BGMManager 的常驻事件、部分参数覆盖、同曲不重启、换曲淡出释放及菜单重置策略。全部操作检查 FMOD 返回码；释放宿主会关闭系统并卸载 DLL。原始参数自动化、seek speed、循环和混音由实际音频引擎运行。

五个原 bank 和 DLL 都在复制目录内，清单记录来源、源码和二进制哈希。工具 `build_portable_fmod.py` 使用本机 MSVC 编译，`export_portable_environment_audio.py` 根据已核验目录生成预设。运行复制包不需要工具链或原版安装路径。当前为 Windows x64 散文件工程，已在 Godot 4.7.2 验证；PCK 内 bank 部署、其他系统原生库，以及现有 Godot 音效进入 FMOD 混响总线尚未实现。死亡与 Timeline 音频接线也不能视为已完成。

验证新增实际 FMOD 播放、224 个预设物理进出及 2,760 个参数读回、加载/一次性/保存、禁用/零层过滤、无 Stay 写入、离开保留、同曲时间轴持续推进、菜单重置和事件释放。NRT WAV 的首秒基线 RMS 为 0，启用原 Out4 环境参数后测得非零 PCM（最终复验 RMS 897.09），与单纯调用成功区分。原 demo 探针还验证源坐标接触、跨房间共享实例、初始出生点触发和宿主回收。

完整复用边界与接口见 `Samples/INARIMechanisms/README.md` 环境音章节。所有机关的总目标仍未完成；NPC/Timeline、其他触发与交互模块继续按来源核验和独立场景边界推进。

## 苦无射程区域与投掷时加成

原版 level12/9145、level28/8964 两个 ShurikenDistanceTrigger 均为可重复区域，进入增加 20 单位射程、退出写零，三个 UnityEvent 均为空。派生写入发生在基类回调后，因此加载期间也生效；无 Stay 写入，无重叠区域恢复栈。CreateShuriken 在创建时复制 AdditiveShurikenDistance 到每枚苦无，FixedUpdate 使用角色当前位置比较基础射程与该枚加成之和，严格超距才销毁；离开区域不会追溯修改已经发出的苦无。

新增 `Devices/ShurikenDistance` 的区域、共享角色状态、源预设和投射物接口；原 InariStudyPlayer 在真实投掷时记录射程，在飞行和附着期间使用它判断距离。原脚底坐标到 Unity 角色中心的换算沿用现有角色适配。`InariShurikenDistanceZones` 根据关卡 source 名称加载源矩阵与角色碰撞层。两份完整原地图尚未导入；展厅中有独立可行走/投掷的练习场地，不能把它当作原关卡复原。

导出器扫描 60 个 level/.assets 头，修复私有类型树的 MonoBehaviour 启用字段对齐，核对原字段、实际碰撞体、世界变换并逐字节回写；另核验 45 份 root/Addressables 审计，确认没有其他序列化射程区域。独立 struct 读取器再次核对两个完整二进制对象，拒绝截断/尾字节。基础 35 单位射程、16 像素换算及飞行速度/质量来自既有已校验角色配置。

两个区域与环境音区域共用新提取的 `Core/SourceTriggerArea.gd`，保持同一初始重叠、加载门控、一次性和保存逻辑。共享设置文件不直接存盘，复制后的宿主负责自己的持久化。展厅选择器同步程序选择和显示名称，避免重试/测试选择后显示错误条目。

新便携探针覆盖源预设、变换父节点、错误角色/层、初始重叠、加载期间进出、重叠退出清零、严格距离边界，以及真实移动、投掷、命中和重载释放。原角色探针对两个源坐标区域分别验证：基础射程打不到物理墙、加成苦无在离开区域后仍命中、黏附后角色离远会销毁；不伪造命中或附着结果。既有苦无淡出、手柄瞄准、瞬移、环境音与 Lab 回归通过。

整包回归还发现上轮离线音频修正仍缺少 MIX_FROM_UPDATE：只把读取和加载放在 Update 不足以保证快速输出。现按 [FMOD 官方 2.02 初始化说明](https://qa.fmod.com/t/how-to-use-fmod-wavwriter-in-unity-for-android-ios-platforms/21646/4)，在离线模式同时设置 STREAM_FROM_UPDATE 与 MIX_FROM_UPDATE；实时模式不改。连续 15 个独立进程的快速 WAV 输出均为非零环境音，原库/构建输出哈希已更新核验。
