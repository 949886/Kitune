# Projection3D

可独立复制的Godot 4.6+ `@tool Node2D`。实例化`Projection3D.tscn`或给Node2D挂载脚本，在Inspector将`scene`设为一个Node3D根的PackedScene即可。

自动生成的透明SubViewport有独立World3D、Scene3D容器、正交Camera3D及独立Environment、方向灯；Sprite2D显示该viewport纹理。相机、画幅、场景变换、Sprite偏移/采样、环境模板和灯光均可配置。

基础节点及注入根为无owner的内部节点，不保存进外层场景。注入场景的内部owner关系保留，支持`%UniqueName`和嵌套场景。`scene_transform`作用于容器，不覆盖注入根本来的变换。

## API

- `ensure_built() -> bool`：同步、幂等构建
- `rebuild() -> bool`：释放旧实例并重建；之后重新获取节点引用
- `request_redraw()`：需要时请求一帧；配置更新尊重显式关闭渲染的策略
- 只读访问器：`viewport`、`camera`、`sprite`、`scene_container`、`scene_instance`、`light`
- 信号：`rebuilding`、`rebuilt`、`build_failed(message)`

空场景合法；无法实例化或非Node3D根会明确拒绝。树内更换scene会延迟合并重建，也可立即调用`ensure_built()`。修改投影配置不重建内容；临时直接修改访问器节点的值不会写入配置，重建会恢复配置值。

生成的世界、纹理和环境互不共享；注入场景资源遵守Godot正常规则，需逐实例修改的自定义材质/资源应启用`resource_local_to_scene`。环境模板会深复制。组件不包含平台时序、碰撞、输入或角色逻辑。
