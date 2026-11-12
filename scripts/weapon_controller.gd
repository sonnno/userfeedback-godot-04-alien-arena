extends Node3D
class_name WeaponController
## 三把武器的射击 / 装填 / 切换逻辑，含第一人称简易枪模与弹道反馈

const ENEMY_LAYER := 4
const WORLD_LAYER := 1
const SHOOT_MASK := WORLD_LAYER | ENEMY_LAYER

var camera: Camera3D
var rig_root: Node3D
var view_models: Array[Node3D] = []
var muzzles: Array[Marker3D] = []

var cooldown: float = 0.0
var reload_left: float = -1.0
var reload_duration: float = 0.0
var reloading_id: int = -1
var recoil_pitch: float = 0.0
var muzzle_flash: OmniLight3D
var muzzle_timer: float = 0.0

var sfx_names := ["pistol", "shotgun", "rifle"]
var model_colors := [
	Color(0.42, 0.45, 0.52),
	Color(0.32, 0.2, 0.13),
	Color(0.18, 0.2, 0.24),
]


func setup(cam: Camera3D, rig: Node3D) -> void:
	camera = cam
	rig_root = rig
	_build_view_models()
	muzzle_flash = OmniLight3D.new()
	muzzle_flash.light_color = Color(1.0, 0.75, 0.35)
	muzzle_flash.light_energy = 0.0
	muzzle_flash.omni_range = 5.0
	muzzle_flash.position = Vector3(0.25, -0.2, -0.8)
	rig_root.add_child(muzzle_flash)
	Game.weapon_changed.connect(_on_weapon_changed)
	Game.ammo_changed.connect(_on_ammo_changed)
	_refresh_view_model()


func _build_view_models() -> void:
	for id in Game.WEAPONS.size():
		var vm := Node3D.new()
		var is_shotgun: bool = id == 1
		var is_rifle: bool = id == 2
		# 枪身：窄(X)、扁(Y)、长(Z)，长轴沿视野方向（-Z 朝屏幕内）
		var body_mi := MeshInstance3D.new()
		var body_mesh := BoxMesh.new()
		body_mesh.size = Vector3(0.07, 0.09, 0.42) if not is_shotgun else Vector3(0.09, 0.11, 0.5)
		body_mesh.material = _vm_material(model_colors[id])
		body_mi.mesh = body_mesh
		vm.add_child(body_mi)
		# 握把：枪身下方靠后（+Z 靠近玩家），竖直向下
		var grip := MeshInstance3D.new()
		var grip_mesh := BoxMesh.new()
		grip_mesh.size = Vector3(0.06, 0.16, 0.08)
		grip_mesh.material = _vm_material(Color(0.12, 0.12, 0.15))
		grip.mesh = grip_mesh
		grip.position = Vector3(0, -0.11, 0.12)
		grip.rotation_degrees.x = -12
		vm.add_child(grip)
		# 枪管：沿 Z 轴的细圆柱，朝屏幕内延伸
		var barrel := MeshInstance3D.new()
		var barrel_mesh := CylinderMesh.new()
		barrel_mesh.top_radius = 0.022
		barrel_mesh.bottom_radius = 0.022
		barrel_mesh.height = 0.28 if is_rifle else 0.2
		barrel_mesh.material = _vm_material(Color(0.08, 0.08, 0.1))
		barrel.mesh = barrel_mesh
		# 圆柱默认沿 Y，绕 X 转 90° 后沿 Z
		barrel.rotation_degrees.x = 90
		barrel.position = Vector3(0, 0.02, -0.32)
		vm.add_child(barrel)
		# 步枪加一个弹匣盒，霰弹枪加泵管，增强辨识度
		if is_rifle:
			var mag := MeshInstance3D.new()
			var mag_mesh := BoxMesh.new()
			mag_mesh.size = Vector3(0.05, 0.13, 0.07)
			mag_mesh.material = _vm_material(Color(0.1, 0.1, 0.12))
			mag.mesh = mag_mesh
			mag.position = Vector3(0, -0.11, -0.02)
			vm.add_child(mag)
		elif is_shotgun:
			var pump := MeshInstance3D.new()
			var pump_mesh := CylinderMesh.new()
			pump_mesh.top_radius = 0.03
			pump_mesh.bottom_radius = 0.03
			pump_mesh.height = 0.14
			pump_mesh.material = _vm_material(Color(0.35, 0.22, 0.14))
			pump.mesh = pump_mesh
			pump.rotation_degrees.x = 90
			pump.position = Vector3(0, -0.05, -0.18)
			vm.add_child(pump)
		# 枪口标记
		var muzzle := Marker3D.new()
		muzzle.position = Vector3(0, 0.02, -0.5)
		vm.add_child(muzzle)
		muzzles.append(muzzle)

		# 持握位置：屏幕右下方，整体缩小并推远，枪口斜指屏幕中央
		vm.position = Vector3(0.15, -0.17, -0.55)
		vm.rotation_degrees.x = -55.0
		vm.scale = Vector3.ONE * 0.62
		vm.visible = false
		rig_root.add_child(vm)
		view_models.append(vm)


func _vm_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	# 视图模型用无光照，避免被场景灯光过曝发白，颜色保持稳定
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _process(delta: float) -> void:
	if Game.state != Game.State.PLAYING:
		return
	cooldown = max(0.0, cooldown - delta)

	# 装填推进
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			Game.refill_mag(reloading_id)
			reloading_id = -1
			reload_left = -1.0

	# 后坐力恢复
	recoil_pitch = move_toward(recoil_pitch, 0.0, delta * 1.8)
	rig_root.rotation.x = recoil_pitch
	# 装填时把枪沉下去一点
	var target_pos := Vector3(0.15, -0.3, -0.48) if reload_left > 0.0 else Vector3(0.15, -0.17, -0.55)
	var vm: Node3D = view_models[Game.current_weapon]
	vm.position = vm.position.lerp(target_pos, delta * 10.0)

	# 枪口灯光衰减
	if muzzle_timer > 0.0:
		muzzle_timer -= delta
		muzzle_flash.light_energy = max(0.0, muzzle_timer * 40.0)

	_handle_input()


func _handle_input() -> void:
	# 切枪（取消未完成的装填）
	var wanted := -1
	if Input.is_action_just_pressed("weapon_1"):
		wanted = 0
	elif Input.is_action_just_pressed("weapon_2"):
		wanted = 1
	elif Input.is_action_just_pressed("weapon_3"):
		wanted = 2
	if wanted >= 0 and Game.owned[wanted]:
		if wanted != Game.current_weapon:
			_cancel_reload()
			Game.switch_weapon(wanted)
			Sfx.play("reload", -14.0, 1.4)

	if Input.is_action_just_pressed("reload"):
		_try_reload()

	var id: int = Game.current_weapon
	var is_auto: bool = Game.WEAPONS[id]["auto"]
	var firing := Input.is_action_pressed("fire") if is_auto else Input.is_action_just_pressed("fire")
	if firing:
		_try_fire()


func _cancel_reload() -> void:
	if reload_left > 0.0:
		reload_left = -1.0
		reloading_id = -1


func _try_reload() -> void:
	var id: int = Game.current_weapon
	var data: Dictionary = Game.WEAPONS[id]
	if reload_left > 0.0 or Game.mags[id] >= data["mag_size"]:
		return
	reload_left = data["reload_time"]
	reload_duration = data["reload_time"]
	reloading_id = id
	Sfx.play("reload", -8.0)


func _try_fire() -> void:
	var id: int = Game.current_weapon
	var data: Dictionary = Game.WEAPONS[id]
	if cooldown > 0.0 or reload_left > 0.0:
		return
	cooldown = data["fire_interval"]

	if Game.mags[id] <= 0:
		# 空仓不能造成伤害，只给干击反馈
		Sfx.play("empty", -10.0)
		return

	Game.consume_ammo(id)
	Sfx.play(sfx_names[id], -7.0, randf_range(0.95, 1.05))
	muzzle_timer = 0.07
	_spawn_muzzle_flash(id)
	recoil_pitch += 0.04 if id != 1 else 0.07

	var pellets: int = data["pellets"]
	var spread: float = data["spread"]
	var damage: float = data["damage"]
	for p in pellets:
		_fire_ray(damage, spread)

	# 自动打空后提示装填
	if Game.mags[id] == 0:
		Game.ammo_changed.emit(id, 0)


func _fire_ray(damage: float, spread: float) -> void:
	var space := get_world_3d().direct_space_state
	var origin := camera.global_position
	var dir: Vector3 = -camera.global_transform.basis.z
	dir = (dir + Vector3(
		randf_range(-spread, spread),
		randf_range(-spread, spread),
		randf_range(-spread, spread))).normalized()

	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 100.0, SHOOT_MASK)
	query.collide_with_areas = true
	var hit := space.intersect_ray(query)

	var end_pos: Vector3 = origin + dir * 100.0
	if not hit.is_empty():
		end_pos = hit["position"]
		var collider = hit["collider"]
		if collider is Enemy:
			collider.take_damage(damage, hit["position"])
			Sfx.play("hit", -12.0, randf_range(0.95, 1.1))
			Game.main.hud.show_hit_marker(collider.is_dead())
			_spawn_spark(end_pos, Color(1.0, 0.3, 0.2))
		else:
			_spawn_spark(end_pos, Color(1.0, 0.85, 0.4))
	_spawn_tracer(origin + Vector3(0, -0.15, 0), end_pos)


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	# 用标准 BoxMesh 代替 ImmediateMesh，避免 GL 后端高频即时构建几何
	var length: float = from.distance_to(to)
	if length < 0.01:
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.025, 0.025, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.25)
	mat.emission_energy_multiplier = 2.0
	box.material = mat
	mi.mesh = box
	get_tree().current_scene.add_child(mi)
	# 盒体长轴沿 Z，look_at 让 -Z 指向终点（盒体对称，朝向正负无影响）
	mi.global_position = from.lerp(to, 0.5)
	mi.look_at(to, Vector3.UP)
	# 短暂保留后移除，保证至少渲染一帧
	var tw := create_tween()
	tw.tween_interval(0.06)
	tw.tween_callback(mi.queue_free)


func _spawn_spark(pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	sphere.material = mat
	mi.mesh = sphere
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 2.2, 0.12)
	tw.tween_callback(mi.queue_free)


func _spawn_muzzle_flash(id: int) -> void:
	var muzzle: Marker3D = muzzles[id]
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.65, 0.2)
	mat.emission_energy_multiplier = 3.0
	sphere.material = mat
	mi.mesh = sphere
	muzzle.add_child(mi)
	var tw := create_tween()
	tw.tween_interval(0.05)
	tw.tween_callback(mi.queue_free)


func reload_progress() -> float:
	if reload_left <= 0.0:
		return 1.0
	return 1.0 - reload_left / reload_duration


func is_reloading() -> bool:
	return reload_left > 0.0


func _on_weapon_changed(_id: int) -> void:
	_refresh_view_model()


func _on_ammo_changed(id: int, _mag: int) -> void:
	if id == Game.current_weapon:
		_refresh_view_model()


func _refresh_view_model() -> void:
	for i in view_models.size():
		view_models[i].visible = (i == Game.current_weapon and Game.owned[i])
