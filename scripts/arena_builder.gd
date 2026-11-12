extends Node3D
class_name ArenaBuilder
## 代码化搭建低多边形竞技场：地面、四入口外墙、中央障碍、侧翼掩体与通道
## 所有静态体放在 world 碰撞层（layer 1），供射线检测与运行时导航烘焙使用

const WALL_LAYER := 1
const ARENA_HALF := 25.0
const WALL_HEIGHT := 4.5
const ENTRANCE_HALF_WIDTH := 3.0

var spawn_points: Array[Vector3] = []
var geometry_root: Node3D


func build(root: Node3D) -> void:
	geometry_root = Node3D.new()
	geometry_root.name = "StaticGeometry"
	root.add_child(geometry_root)

	_make_floor()
	_make_outer_walls()
	_make_central_obstacles()
	_make_inner_walls()
	_make_cover_blocks()
	_make_spawn_pads()
	_make_lighting(root)


func _mat(color: Color, emission: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	m.metallic = 0.0
	m.vertex_color_use_as_albedo = false
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m


func _add_box(pos: Vector3, size: Vector3, color: Color,
		emission: Color = Color.BLACK, emission_energy: float = 0.0) -> Node3D:
	var body := StaticBody3D.new()
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	body.position = pos

	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mat(color, emission, emission_energy)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	geometry_root.add_child(body)
	return body


func _make_floor() -> void:
	# 地板延伸到入口出生平台之外（58×58），保证导航网格覆盖四个入口
	var body := StaticBody3D.new()
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	var mi := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(58, 0.4, 58)
	plane.material = _mat(Color(0.16, 0.17, 0.2))
	mi.mesh = plane
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(58, 0.4, 58)
	col.shape = shape
	body.add_child(col)
	body.position = Vector3(0, -0.2, 0)
	geometry_root.add_child(body)

	# 网格装饰线（细的发光条，帮助辨认空间）
	var grid_mat := _mat(Color(0.24, 0.27, 0.33))
	for i in range(-20, 21, 5):
		for axis in [0, 2]:
			var strip := MeshInstance3D.new()
			var bm := BoxMesh.new()
			if axis == 0:
				bm.size = Vector3(49.0, 0.02, 0.12)
				strip.position = Vector3(0, 0.02, i)
			else:
				bm.size = Vector3(0.12, 0.02, 49.0)
				strip.position = Vector3(i, 0.02, 0)
			bm.material = grid_mat
			strip.mesh = bm
			geometry_root.add_child(strip)


func _make_outer_walls() -> void:
	var wall_color := Color(0.32, 0.34, 0.4)
	var h := WALL_HEIGHT
	var seg := (50.0 - ENTRANCE_HALF_WIDTH * 2.0) / 2.0  # 每侧两段墙的长度 = 22
	var off := ENTRANCE_HALF_WIDTH + seg / 2.0            # 墙段中心偏移 = 14
	# 南北墙（沿 X），入口在中央
	for sign in [-1.0, 1.0]:
		var z: float = sign * ARENA_HALF
		_add_box(Vector3(-off, h / 2.0, z), Vector3(seg, h, 1.0), wall_color)
		_add_box(Vector3(off, h / 2.0, z), Vector3(seg, h, 1.0), wall_color)
	# 东西墙（沿 Z）
	for sign in [-1.0, 1.0]:
		var x: float = sign * ARENA_HALF
		_add_box(Vector3(x, h / 2.0, -off), Vector3(1.0, h, seg), wall_color)
		_add_box(Vector3(x, h / 2.0, off), Vector3(1.0, h, seg), wall_color)


func _make_central_obstacles() -> void:
	# 十字形中央障碍：玩家与敌人都需要绕行
	var c := Color(0.45, 0.3, 0.22)
	_add_box(Vector3(0, 1.5, 0), Vector3(10, 3, 2.4), c)
	_add_box(Vector3(0, 1.5, 0), Vector3(2.4, 3, 10), c)
	# 中央顶部亮色标记，便于辨认
	_add_box(Vector3(0, 3.05, 0), Vector3(2.6, 0.15, 2.6),
		Color(0.9, 0.55, 0.2), Color(1.0, 0.5, 0.15), 0.8)


func _make_inner_walls() -> void:
	# 四段内墙围成方框通道，开口朝向四个入口方向
	var c := Color(0.28, 0.4, 0.42)
	_add_box(Vector3(-7, 1.25, 0), Vector3(6, 2.5, 1.2), c)
	_add_box(Vector3(7, 1.25, 0), Vector3(6, 2.5, 1.2), c)
	_add_box(Vector3(0, 1.25, -7), Vector3(1.2, 2.5, 6), c)
	_add_box(Vector3(0, 1.25, 7), Vector3(1.2, 2.5, 6), c)


func _make_cover_blocks() -> void:
	# 侧翼矮掩体：四个象限各两块，留出绕行路线
	var c := Color(0.36, 0.42, 0.3)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_box(Vector3(sx * 15, 1.0, sz * 10), Vector3(3, 2, 3), c)
			_add_box(Vector3(sx * 10, 1.0, sz * 16), Vector3(3, 2, 3), c)


func _make_spawn_pads() -> void:
	# 入口外侧的发光平台 = 敌人入口；同时记录出生点
	var pad_color := Color(0.5, 0.15, 0.15)
	var pad_emit := Color(1.0, 0.2, 0.15)
	var pad_z := ARENA_HALF + 2.5
	var pad_x := ARENA_HALF + 2.5
	var pads := [
		[Vector3(0, 0.06, -pad_z), Vector3(0, 0, -pad_z - 1.0)],
		[Vector3(0, 0.06, pad_z), Vector3(0, 0, pad_z + 1.0)],
		[Vector3(-pad_x, 0.06, 0), Vector3(-pad_x - 1.0, 0, 0)],
		[Vector3(pad_x, 0.06, 0), Vector3(pad_x + 1.0, 0, 0)],
	]
	for p in pads:
		_add_box(p[0], Vector3(4.5, 0.12, 4.5), pad_color, pad_emit, 0.9)
		spawn_points.append(p[1])


func _make_lighting(root: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.52, 0.6)
	e.ambient_light_energy = 0.7
	env.environment = e
	root.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, -40, 0)
	key.light_energy = 1.1
	key.shadow_enabled = true
	root.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 130, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.6, 0.7, 1.0)
	root.add_child(fill)
