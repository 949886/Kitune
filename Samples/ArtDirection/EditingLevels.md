# 关卡编辑

INARI 两关的静态内容已迁入 `Scenes/Worlds/`。在 Godot 中编辑 World 场景，保存后运行
`Scenes/` 下对应的关卡入口（F6）；入口负责选关 UI、角色创建和显示视口。
运行时不会重新导出场景或覆盖已经保存的布局。

## INARI 两关

编辑 `INARI_FactoryWorld.tscn` 或 `INARI_SealWorld.tscn`，分别从
`Scenes/INARI_Factory.tscn`、`Scenes/INARI_Seal.tscn` 运行。

| 节点 | 可编辑内容 |
| --- | --- |
| `Scenery/Sprite_*`、`Scenery/Depth_*/Sprite_*` | 原版精灵的变换、显隐、Modulate、Z Index；精灵名包含源贴图名称 |
| `Terrain` | 工厂 62 个、神殿 3 个原始碰撞体，可直接修改标准碰撞形状或增加地形 |
| `Lights` | 原版灯光的位置、颜色、能量、半径、深度与源设置；运行时沿用已有灯光转换范围 |
| `EnemySpawns` | 工厂 6 个原版敌人的出生点，`Definition` 保存原始行为与动画配置 |
| `WindStations` | 工厂 2 个风力站的触发区域 |
| `Route` | 出生点、顺序目标与检查点；工厂目标下的 `KunaiAnchor` 是路线测试瞄准点 |
| `OriginalCameraRig` | 原版 INARI 相机及神殿固定跟随点；根节点 `Camera Settings` 保存镜头、阻尼和构图参数 |

编辑器直接预览基础精灵，运行后绑定完整材质、倾斜投影、灯光和水面倒影。
`Source Item` 保留精灵来源及特殊材质数据；修改这些资源字段后重新打开场景或运行即可重建其材质缓存。
`Source Animation Enabled` 可关闭该精灵的场景动画绑定。标准节点的位移、色调、显隐不会在初始化时恢复为源位置。
角色行为仍会驱动其关联精灵，完整角色模型层次和敌人预制场景尚未重构。

敌人出生标记与原版精灵分开保存；移动标记会在运行时一起偏移关联精灵。删除标记时，
相应的静态精灵仍在 `Scenery` 中，可按 `Definition / data / visuals` 中的原始 GO 标识关联清理。
改动大段地形后，原版敌人导航数据也需要同步；目前不会根据编辑后的碰撞自动重建源导航网格。

`Tools/export_inari_scenes.gd` 只在显式重新导入时读取 `Tools/inari_scene_selection.json`
来建立初始场景。正式关卡加载保存的 World 场景；源 JSON 继续作为原版动画、导航与规则档案，
不再用于重新创建静态精灵、地形、灯光位置、出生点和相机节点。

`AuthoredInariProbe` 验证保存后改过的精灵坐标及倾斜变换、色调、灯光、相机设置及新增地形；
`InariSceneEditorProbe` 在真正的 editor 模式检查精灵预览；`InariSceneMigrationProbe`
冻结动画与材质时间，对照原转换器与场景加载的相机、内容和真实渲染。
Forward+ 对照中工厂像素完全一致；神殿有 3 个像素的差异，RGB 字节误差总和为 33。
INARI 两关实际输入路线，以及 INARI 原版相机、光照、水面、敌人、门体物理和风力站动画检查均通过。
