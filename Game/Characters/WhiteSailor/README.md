# 白发水手服主角 / White Sailor

按用户提供的角色图生成：白色长直发与深色内层、紫色眼睛、白色水手服、海军蓝百褶裙、白袜和黑鞋；保持修长、小头、长腿的比例。

## 资源

| 文件 / 目录 | 用途 |
| --- | --- |
| `Sheets/` | 6 张真实 RGBA 透明图集：5 张 4 × 6 和 1 张 4 × 4；每格 320 × 320，带透明边距 |
| `Frames/` | 136 张独立透明 PNG，按源图集与帧号命名；16 张新移动帧替换旧跑步 / 空中动作，旧源帧保留 |
| `sprite_frames.res` | Godot 原生 SpriteFrames，包含 45 个原版动作名和 `BackIDLE`，保存对应播放速度与接触帧时长 |
| `appearance.json` | 动作映射、显示比例、手脚锚点类型、连击接触时刻、构建参数 |
| `frame_manifest.json` | 每帧图集矩形、包围盒、固定锚点、归一化后的骨盆 / 头部标记与源图 / 标记文件 SHA-256 |
| `Source/registration.json` | 数据驱动的源图身体标记、支撑点、模型参考身高、跑步起伏和导出锚点 |
| `CharacterPreview.tscn` | F6 打开动作预览：切换动作、播放 / 暂停、调速、翻转、时间轴、← → 逐帧、R 重播 |
| `Previews/` | 修复前后对照动图、像素检查记录、角色预览和 Forward+ 下两关实际截图 |
| `Source/` | 原始参考、最终绿幕源图和完整生成提示词；`.gdignore` 将制作源文件排除在游戏导入之外 |

所有人物绘画使用内置 **imagegen** 生成、按参考图约束身份，并用同一工具修正背景、刀刃长度和挂顶手部。
生成器最初输出了绘制的棋盘格背景，因此使用纯绿色制作源图，再由 Godot 构建工具将绿幕转为 Alpha。游戏读取 `Sheets/`，无需运行时抠图。

## 动作覆盖

| 分组 | 原画序列 |
| --- | --- |
| 移动 | 待机 4 帧、跑步 8 帧、起跳 4 帧、下落 4 帧、落地 4 帧 |
| 战斗 | 三段连击、重攻击、空中斩击、倒地死亡，各 4 帧 |
| 投掷 | 站立平投 / 上投 / 下投、空中投掷、跑动前投 / 后投，各 4 帧 |
| 攀爬 | 静止挂墙使用固定抓握姿势；上爬、挂顶、翻越墙沿、墙上投掷、挂顶投掷各 4 帧 |
| 特殊 | 冲刺、刹车、二段跳翻转、坐下、起身重生各 4 帧；跪坐待机用 4 张原画往返采样为 6 帧 |

32 条采样序列包括起跑、坐起与下爬的复用；46 个运行时状态通过配置映射到这些序列。
瞬移与弱点突进复用冲刺，部分空中 / 跑动投掷角度复用对应姿态。站立三方向使用独立原画。
这套资源不是给每个原版时间采样点各画一张：新原画按原有时间轴采样，保留输入、碰撞、位移、伤害、体力和声音事件的时机。
非致命受击沿用 INARI 的闪烁反馈，死亡采用新的倒地序列。

## 配置与重新构建

默认 `display_scale = 0.25`，站立人物约 58 个世界像素高，与原关卡的角色高度接近；仅等比缩放。
脚底、抓墙手和挂顶手分别锚定于角色的脚底、墙面和旋转后的碰撞盒顶面。挂顶原画已经竖直悬挂，因此不会再次跟随旧角色的 90° 身体旋转。

```powershell
godot --headless --path . --script res://Samples/ArtDirection/Tools/build_character_assets.gd
godot --headless --path . --editor --import
godot --headless --path . --script res://Samples/ArtDirection/Tests/WhiteSailorProbe.gd
godot --headless --path . --script res://Samples/ArtDirection/Tests/CharacterContinuityProbe.gd
```

构建工具只处理游戏导入：颜色键转 Alpha、按相连轮廓分离角色、按身体标记等比缩放与对齐、添加透明边距和导出动画。
它不绘制人物，不把蹲姿单独拉高，也不会把跨过源格子线的头发或武器裁断。
标记使用 256 × 256 的逻辑源格子坐标，允许负坐标表示越过格线的头发 / 手部；生成器输出尺寸不同但宽高比相同时，先转换到逻辑尺寸。导出格为 320 × 320。

`Source/registration.json` 中 `size_reference` 是该套原画模型伸展站立时的参考身高，不能填写当前蹲姿 / 翻滚姿态的包围盒高度。模型归一化目标是 232 素材像素；同组动作保持相同缩放，避免每帧根据头发或武器轮廓自动改变大小。骨盆和支撑点逐帧标注，头顶 / 下巴用于像素检查，不根据倾斜或遮挡的头部反推缩放。

所有校正直接烘焙进 `Frames/`、`Sheets/` 和原生 `SpriteFrames`。普通动作的固定根点为 `(160, 300)`，悬挂顶面为 `(160, 24)`。独立使用 `AnimatedSprite2D` 时可设 `centered = false`，普通动作 `offset = Vector2(-160, -300)`；挂顶时改用顶面锚点。游戏内由外观采样器读取这些锚点。

`appearance.json` 的 `clips.*.frame_times` 使用 0–1 归一化时间。连击接触帧对应原版 `AttackCheckStartFrame`；修改这些视觉关键帧不会修改游戏伤害判定。

## 游戏入口

实验关卡通过 `Samples/ArtDirection/Profiles/characters.json` 注册这套外观。
Godot 打开 `Samples/ArtDirection/ArtDirectionLab.tscn` 后按 F6；按 1 / 2 进入两关。
默认角色为 Shiro，可在选关页或关卡内的「角色」下拉框切换为白发水手服。
切换只更新外观，沿用当前动作时钟；原版贴图和直接创建控制器时的原版外观仍可用于独立对照测试。

## 验证记录

Godot 4.7.2 / Windows / RTX 3080：

- `WhiteSailorProbe`：136 帧 Alpha / 透明边距、全部 46 个动作、左右手脚锚点、挂顶方向、定向突进旋转、原时间轴与接触帧、可移植动画时长；逐帧比较原生 `SpriteFrames` 与 PNG 的像素一致性。
- `CharacterContinuityProbe`：从实际 PNG 中提取脸部像素，检查待机、跑步、下落的相邻帧位置与面积变化，包含末帧接首帧；旧资源会触发回归失败，新资源通过。
- `InariControllerProbe -- appearance=res://Game/Characters/WhiteSailor/appearance.json`：用新外观执行原版移动、跳跃、战斗与瞬移检查。
- `RouteProbe`：机械工厂与圆印神殿两关的三个路线目标全部完成。
- `PlayerRenderingProbe`：Forward+ 实测主角与水面倒影纹理 / 变换同步、独立灯光材质、受击透明度；10144 个像素采样，亮度比例最大误差 0。
- `capture_art_direction.gd`：Forward+ 导出两关实际画面，见 `Previews/manifest.json`。

本机沙箱限制会产生证书存储与用户缓存目录提示；测试不依赖这些目录。编辑器导入时还报告项目原有的摇杆全局类重名（`Game/UI/Joystick` 与 `addons/cherry`），上述角色和关卡运行检查均正常完成。

## 连贯性修复 / 2026-09-16

- 原版使用源格子中心作为身体中心，并把轮廓最低点、最右点作为支撑点。原画在各格的位置变化，会直接变成角色漂移；翻滚时头发在脚下面还会抬高整个角色。
- 新版按骨盆、鞋底和抓握位置注册每张原画。空中围绕骨盆运动，跑步保留小幅起伏，地面动作保持支撑点；不使用每帧的轮廓变化驱动身体位置。
- 内置 **imagegen** 补做 16 张跑步 / 上升 / 下落帧，提示词保存于 `Source/continuity_prompt.txt`。下落改为相近姿势的循环，起跑不再误用完整跳跃序列；静止挂墙不会重复迈步。
- 预览器尊重原动作的循环属性：攻击、落地、死亡等结束后停帧，按 R 重播。原先立即从终点跳回开头的预览行为已经移除。

以下是实际脸部像素中心在相邻帧之间的最大位移，单位为素材像素；游戏里按 0.25 倍显示。它反映这些循环的抖动，不代表所有肢体应该静止。

| 循环 | 修复前 | 修复后 |
| --- | ---: | ---: |
| 待机 | 40.12 | 3.72 |
| 跑步 | 38.70 | 6.93 |
| 下落 | 12.15 | 3.85 |

见 `Previews/continuity_comparison.gif`（上：旧版，下：新版，统一慢速相位对照）和 `Previews/continuity_metrics.json`。攻击等动作仍是少量关键帧组成的像素动画，未加入模糊插值或改变伤害判定时机。

生成对照时，先准备旧版的 `appearance.json`、`frame_manifest.json` 和 `Sheets/`，再运行：

```powershell
godot --path . --rendering-method gl_compatibility --script res://Samples/ArtDirection/Tools/capture_character_continuity.gd -- before=res://tmp/white-sailor-continuity/before
ffmpeg -framerate 24 -i tmp/white-sailor-continuity/capture/frame_%03d.png -vf "split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" -loop 0 Game/Characters/WhiteSailor/Previews/continuity_comparison.gif
```
