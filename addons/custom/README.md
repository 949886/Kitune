# Custom

项目自定义的 Godot 2D 节点及编辑器工具。插件入口为 `plugin.cfg`，已在
`project.godot` 中启用；整个目录随项目纳入 Git 管理。

## CollisionRect2D

`CollisionRect2D` 继承 `StaticBody2D`，以节点原点为中心绘制矩形，并自动创建
匹配尺寸的 `CollisionShape2D`。它统一了原先的 `SimpleSolid` 和 `Rect2D`。

- 在“添加节点”中搜索 `CollisionRect2D` 即可创建。
- `size` 同时控制绘制和碰撞，两个方向的最小尺寸均为 4。
- `fill_color`、`edge_color` 和 `edge_width` 控制外观；`edge_width = 0` 隐藏顶边。
- 碰撞层、碰撞掩码等设置沿用 `StaticBody2D` 的属性。
- 点击矩形内部即可选中节点，旋转和缩放后的图形也按实际范围选取。
- 选中节点后，可拖动八个手柄调整大小，支持旋转、缩放及撤销/重做。

碰撞子节点由组件自动维护，尺寸属性是唯一数据来源；每个节点实例使用
独立形状，避免编辑一个矩形时影响其他实例。运行时在物理查询回调中调整尺寸，
会在查询结束后更新碰撞，避免 `flushing_queries` 错误。

## 回归检查

在项目根目录执行（`godot` 替换为本机 Godot 可执行文件）：

```sh
godot --headless --path . --fixed-fps 60 --script res://addons/custom/tests/collision_rect2d_probe.gd --quit-after 600
godot --headless --editor --path . --script res://addons/custom/tests/collision_rect2d_editor_probe.gd --quit-after 600
```

分别以 `COLLISION_RECT_2D_PASS` 和 `COLLISION_RECT_EDITOR_PASS` 为成功标记。
第一项检查实际碰撞、物理回调内调整尺寸、场景保存/加载、八个手柄及教程地面；
第二项通过编辑器原生选取流程检查图形点击、旋转/缩放、场景根节点、选择切换
和实际撤销/重做历史。
