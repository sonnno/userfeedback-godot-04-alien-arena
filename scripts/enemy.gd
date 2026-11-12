extends CharacterBody3D
class_name Enemy
## 敌人基类：近战追击者 chaser / 远程射手 shooter / 重装 heavy
## 导航由 NavigationAgent3D 驱动，叠加分离转向避免完全重叠

const ENEMY_LAYER := 4
const ENEMY_MASK := 1  # 只与世界碰撞；同类之间用分离转向
const WORLD_BIT := 1
const PLAYER_BIT := 2

const STATS := {
	"chaser": {
		"hp": 36.0, "speed": 3.2, "radius": 0.45, "damage": 8.0,
		"attack_range": 1.6, "attack_cd": 0.9, "color": Color(0.85, 0.3, 0.25),
		"scale": 0.9, "coin": 10,
	},
	"shooter": {
		"hp": 30.0, "speed": 2.6, "radius": 0.45, "damage": 10.0,
		"attack_range": 16.0, "attack_cd": 2.4, "color": Color(0.35, 0.55, 0.85),
		"scale": 0.85, "coin": 10,
	},
	"heavy": {
		"hp": 140.0, "speed": 1.4, "radius": 0.85, "damage": 20.0,
		"attack_range": 2.2, "attack_cd": 1.5, "color": Color(0.5, 0.35, 0.7),
		"scale": 1.35, "coin": 10,
	},
}

var kind: String = "chaser"
var stats: Dictionary
var hp: float = 1.0
var dead: bool = false

var nav: NavigationAgent3D
var body_mi: MeshInstance3D
var body_mat: StandardMaterial3D
var repath_timer: float = 0.0
var attack_cd_left: float = 0.0
var telegraph_left: float = -1.0
var has_line_of_sight: bool = false
var los_timer: float = 0.0
var bar_fill: MeshInstance3D
var bar_mat: StandardMaterial3D
var bar_bg: MeshInstance3D
var spawn_scale: float = 1.0


func setup(enemy_kind: String) -> void:
	kind = enemy_kind
	stats = STATS[kind]
	hp = stats["hp"]
	spawn_scale = stats["scale"]


func _ready() -> void:
	collision_layer = ENEMY_LAYER
	collision_mask = ENEMY_MASK
	_build_body()
	_build_nav()
	_build_health_bar()
	# 出生缩放动画
	scale = Vector3.ONE * 0.1
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * spawn_scale, 0.35)


func _build_body() -> void:
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = stats["radius"]
	shape.height = 1.7
	col.shape = shape
	col.position = Vector3(0, 0.85, 0)
	add_child(col)

	body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = stats["color"]
	body_mat.roughness = 0.7
	body_mat.emission_enabled = true
	body_mat.emission = Color.BLACK
	body_mat.emission_energy_multiplier = 1.0

	body_mi = MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.42
	bm.height = 1.4
	bm.material = body_mat
	body_mi.mesh = bm
	body_mi.position = Vector3(0, 0.95, 0)
	add_child(body_mi)

	# 头部 + 眼睛（低模辨识）
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.3
	hm.height = 0.6
	hm.material = body_mat
	head.mesh = hm
	head.position = Vector3(0, 1.85, 0)
	add_child(head)

	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color(1.0, 0.9, 0.3)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.8, 0.2)
	eye_mat.emission_energy_multiplier = 2.0
	for sx in [-0.12, 0.12]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.06
		em.height = 0.12
		em.material = eye_mat
		eye.mesh = em
		eye.position = Vector3(sx, 1.9, 0.26)
		add_child(eye)

	# 射手的“能量核心”，重装的装甲板
	if kind == "shooter":
		var core := MeshInstance3D.new()
		var cm := SphereMesh.new()
		cm.radius = 0.16
		cm.height = 0.32
		var core_mat := StandardMaterial3D.new()
		core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		core_mat.albedo_color = Color(0.4, 0.7, 1.0)
		core_mat.emission_enabled = true
		core_mat.emission = Color(0.3, 0.6, 1.0)
		core_mat.emission_energy_multiplier = 1.5
		cm.material = core_mat
		core.mesh = cm
		core.position = Vector3(0, 1.2, 0.36)
		add_child(core)
	elif kind == "heavy":
		var plate := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(1.1, 0.9, 0.25)
		var plate_mat := StandardMaterial3D.new()
		plate_mat.albedo_color = Color(0.3, 0.22, 0.42)
		plate_mat.metallic = 0.4
		plate_mat.roughness = 0.4
		pm.material = plate_mat
		plate.mesh = pm
		plate.position = Vector3(0, 1.1, 0.42)
		add_child(plate)


func _build_nav() -> void:
	nav = NavigationAgent3D.new()
	nav.path_desired_distance = 0.4
	nav.target_desired_distance = stats["attack_range"] * 0.7
	nav.radius = stats["radius"]
	nav.avoidance_enabled = false  # 用自定义分离转向，避免 RVO 在简单场景抖动
	add_child(nav)


func _build_health_bar() -> void:
	var bar_root := Node3D.new()
	bar_root.position = Vector3(0, 2.35 * spawn_scale, 0)
	add_child(bar_root)

	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.albedo_color = Color(0.05, 0.05, 0.06, 0.85)
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bar_bg = MeshInstance3D.new()
	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(1.05, 0.16)
	bg_mesh.material = bg_mat
	bar_bg.mesh = bg_mesh
	bar_root.add_child(bar_bg)

	bar_mat = StandardMaterial3D.new()
	bar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar_mat.albedo_color = Color(0.9, 0.2, 0.2)
	bar_mat.emission_enabled = true
	bar_mat.emission = Color(0.7, 0.1, 0.1)
	bar_mat.emission_energy_multiplier = 0.6
	bar_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bar_fill = MeshInstance3D.new()
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(1.0, 0.11)
	fill_mesh.material = bar_mat
	bar_fill.mesh = fill_mesh
	bar_fill.position = Vector3(0, 0, 0.001)
	bar_root.add_child(bar_fill)


func _physics_process(delta: float) -> void:
	if dead or Game.state != Game.State.PLAYING:
		velocity = Vector3.ZERO
		return

	attack_cd_left = max(0.0, attack_cd_left - delta)
	repath_timer -= delta
	los_timer -= delta
	if los_timer <= 0.0:
		los_timer = 0.15
		has_line_of_sight = _check_los()

	# 射手预警计时独立推进
	if telegraph_left > 0.0:
		telegraph_left -= delta
		if telegraph_left <= 0.0:
			_fire_projectile()
			telegraph_left = -1.0
		velocity = Vector3.ZERO
		return

	var player: Node3D = Game.player
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0
	var dist := to_player.length()

	if repath_timer <= 0.0:
		repath_timer = 0.4
		# 持续刷新玩家位置，避免追逐移动目标时路径过期
		nav.target_position = player.global_position

	var move_dir := Vector3.ZERO
	if not nav.is_navigation_finished():
		var next_path := nav.get_next_path_position()
		move_dir = next_path - global_position
		move_dir.y = 0
		if move_dir.length() > 0.05:
			move_dir = move_dir.normalized()

	# 射手保持距离：太近后撤
	if kind == "shooter":
		if dist < 7.0 and has_line_of_sight:
			move_dir = -to_player.normalized()
		elif dist > 15.0:
			pass  # 寻路会自然靠近
		elif has_line_of_sight and dist < stats["attack_range"]:
			# 射程内且有视线：站定攻击
			if move_dir.length() > 0 and dist < 12.0:
				move_dir = move_dir * 0.2

	# 分离转向：与附近敌人互相推开
	move_dir += _separation()
	if move_dir.length() > 1.0:
		move_dir = move_dir.normalized()

	velocity = move_dir * stats["speed"]
	# 朝玩家方向平滑转身
	if to_player.length() > 0.1:
		var target_yaw := atan2(to_player.x, to_player.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, delta * 8.0)
	move_and_slide()

	# 攻击判定
	if attack_cd_left <= 0.0:
		if kind == "shooter":
			if dist <= stats["attack_range"] and has_line_of_sight:
				_start_telegraph()
		else:
			if dist <= stats["attack_range"]:
				_melee_attack()


func _separation() -> Vector3:
	var push := Vector3.ZERO
	var r: float = stats["radius"]
	for other in Game.enemies:
		if other == self or other.dead:
			continue
		var diff: Vector3 = global_position - other.global_position
		diff.y = 0
		var d := diff.length()
		var min_d: float = r + other.stats["radius"] + 0.2
		if d > 0.001 and d < min_d:
			push += diff.normalized() * (min_d - d) / min_d
	return push * 1.4


func _check_los() -> bool:
	var player: Node3D = Game.player
	var from := global_position + Vector3(0, 1.4, 0)
	var to: Vector3 = player.global_position + Vector3(0, 1.2, 0)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_BIT | PLAYER_BIT)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	return hit["collider"] is Player


func _start_telegraph() -> void:
	telegraph_left = 0.55
	attack_cd_left = stats["attack_cd"]
	body_mat.emission = Color(1.0, 0.3, 0.15)
	body_mat.emission_energy_multiplier = 1.2
	Sfx.play("shooter_telegraph", -12.0)


func _fire_projectile() -> void:
	body_mat.emission = Color.BLACK
	body_mat.emission_energy_multiplier = 1.0
	var proj := Projectile.new()
	proj.setup((Game.player.global_position + Vector3(0, 1.1, 0)) - (global_position + Vector3(0, 1.4, 0)),
		stats["damage"])
	get_tree().current_scene.add_child(proj)
	proj.global_position = global_position + Vector3(0, 1.4, 0)


func _melee_attack() -> void:
	attack_cd_left = stats["attack_cd"]
	Game.damage_player(stats["damage"])
	Sfx.play("hurt", -10.0, 0.8)
	# 攻击前冲小动画
	var tw := create_tween()
	var start_x := body_mi.position.x
	tw.tween_property(body_mi, "position", body_mi.position + Vector3(0, 0, 0.25), 0.08)
	tw.tween_property(body_mi, "position", Vector3(start_x, 0.95, 0), 0.12)


func take_damage(amount: float, _hit_pos: Vector3) -> void:
	if dead:
		return
	hp -= amount
	_update_health_bar()
	# 受击闪白
	body_mat.emission = Color(1.0, 1.0, 1.0)
	body_mat.emission_energy_multiplier = 0.9
	var tw := create_tween()
	tw.tween_interval(0.08)
	tw.tween_callback(func() -> void:
		if not dead and telegraph_left <= 0.0:
			body_mat.emission = Color.BLACK
			body_mat.emission_energy_multiplier = 1.0
	)
	if hp <= 0.0:
		_die()


func _update_health_bar() -> void:
	var ratio: float = clamp(hp / stats["hp"], 0.0, 1.0)
	bar_fill.scale.x = max(ratio, 0.001)
	# 从左侧收缩
	bar_fill.position.x = -(1.0 - ratio) * 0.5
	if ratio > 0.5:
		bar_mat.albedo_color = Color(0.3, 0.85, 0.3)
		bar_mat.emission = Color(0.2, 0.6, 0.2)
	elif ratio > 0.25:
		bar_mat.albedo_color = Color(0.95, 0.75, 0.2)
		bar_mat.emission = Color(0.7, 0.5, 0.1)
	else:
		bar_mat.albedo_color = Color(0.9, 0.2, 0.2)
		bar_mat.emission = Color(0.7, 0.1, 0.1)


func _die() -> void:
	dead = true
	Sfx.play("enemy_die", -9.0)
	Game.register_dead(self)
	# 死亡动画：倒下下沉后销毁
	set_physics_process(false)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "rotation:z", PI / 2.0, 0.3)
	tw.tween_property(self, "scale", Vector3.ONE * spawn_scale * 0.6, 0.35)
	tw.chain().tween_callback(queue_free)
	bar_bg.visible = false
	bar_fill.visible = false


func is_dead() -> bool:
	return dead
