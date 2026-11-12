extends Node3D
## 主控：搭建竞技场与导航、生成玩家、调度三波敌人、判定波次结束

const PLAYER_SPAWN := Vector3(0, 0.1, 18)

var arena: ArenaBuilder
var nav_region: NavigationRegion3D
var hud: Hud
var player: Player
var enemies_root: Node3D

# 仅 AA_SHOT 环境变量触发的视口截图（视觉验证用，正常游戏不生效）
var shot_enabled: bool = false
var shot_clock: float = 0.0
var shots_taken: int = 0
var shot_times: Array[float] = [2.0, 6.0, 11.0]


func _ready() -> void:
	Game.main = self
	arena = ArenaBuilder.new()
	arena.name = "Arena"
	add_child(arena)
	arena.build(self)

	await _build_navigation()
	_spawn_player()
	_build_hud()

	Game.state_changed.connect(_on_state_changed)
	Game.enemy_killed.connect(_on_enemy_killed)
	shot_enabled = OS.has_environment("AA_SHOT")


func _build_navigation() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	var nav_mesh := NavigationMesh.new()
	# cell_size 与默认导航地图一致（0.25），避免栅格化警告
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_height = 2.0
	nav_mesh.agent_max_climb = 0.25
	nav_mesh.agent_max_slope = 45.0
	# 用静态碰撞体烘焙：导航区域下所有子节点的墙体、掩体、地面全部纳入
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = 1
	nav_region.navigation_mesh = nav_mesh
	add_child(nav_region)
	# 把静态几何挂到导航区域下，作为烘焙源
	arena.geometry_root.reparent(nav_region)
	# 主线程烘焙并等待完成信号（headless 下直接取结果会拿到空网格）
	nav_region.bake_navigation_mesh(false)
	if nav_mesh.get_vertices().is_empty():
		await nav_region.bake_finished
	var verts := nav_region.navigation_mesh.get_vertices().size()
	print("[Main] navmesh baked, vertices=", verts, ", spawn_points=", arena.spawn_points.size())
	if verts == 0:
		push_error("[Main] navigation mesh is empty — enemies will not navigate")


func _spawn_player() -> void:
	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.position = Vector3(0, 1.65, 0)

	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.fov = 75.0
	cam.near = 0.05
	rig.add_child(cam)

	var weapon_rig := Node3D.new()
	weapon_rig.name = "WeaponRig"
	rig.add_child(weapon_rig)

	player = Player.new()
	player.name = "Player"
	player.add_child(rig)
	add_child(player)

	var weapon := WeaponController.new()
	weapon.name = "WeaponController"
	weapon_rig.add_child(weapon)
	weapon.setup(cam, weapon_rig)

	player.setup(rig, cam, weapon)
	player.reset_spawn(PLAYER_SPAWN)
	Game.player = player

	enemies_root = Node3D.new()
	enemies_root.name = "Enemies"
	add_child(enemies_root)


func _build_hud() -> void:
	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)


# ---------- 波次调度 ----------
func start_wave(index: int) -> void:
	Game.begin_wave(Game.WAVES[index])
	hud._on_wave(index + 1, Game.remaining_enemies())
	hud.show_banner("第 %d 波来袭！" % (index + 1))


func _process(delta: float) -> void:
	_maybe_capture_shot(delta)
	if Game.state != Game.State.PLAYING:
		return
	if Game.pending_spawns.is_empty():
		return
	Game.spawn_timer -= delta
	if Game.spawn_timer <= 0.0:
		Game.spawn_timer = Game.SPAWN_INTERVAL
		_spawn_next()


## 视觉验证：在指定时刻保存视口截图，截完即退出
func _maybe_capture_shot(delta: float) -> void:
	if not shot_enabled:
		return
	shot_clock += delta
	if shots_taken < shot_times.size() and shot_clock >= shot_times[shots_taken]:
		var img := get_viewport().get_texture().get_image()
		var path := "user://aa_shot_%d.png" % shots_taken
		img.save_png(path)
		print("[Shot] saved ", path, " size=", img.get_size())
		shots_taken += 1
		if shots_taken >= shot_times.size():
			get_tree().quit(0)


func _spawn_next() -> void:
	if Game.pending_spawns.is_empty():
		return
	var kind: String = Game.pending_spawns.pop_front()
	var pos := _pick_spawn_point()
	var enemy := Enemy.new()
	enemy.setup(kind)
	enemy.position = pos
	enemies_root.add_child(enemy)
	# 等节点就绪后再注册导航目标
	Game.register_spawned(enemy)
	if is_instance_valid(enemy.nav):
		enemy.nav.target_position = player.global_position


func _pick_spawn_point() -> Vector3:
	# 避开玩家：优先选择距离玩家最远的入口，带少量随机偏移
	var candidates: Array[Vector3] = arena.spawn_points.duplicate()
	candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.distance_to(player.global_position) > b.distance_to(player.global_position))
	# 70% 概率取最远入口，30% 随机取，保证“从不同入口出现”但不机械
	var base: Vector3
	if randf() < 0.7:
		base = candidates[0]
	else:
		base = candidates[randi() % candidates.size()]
	return base + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))


func on_wave_cleared() -> void:
	if Game.wave_index >= Game.WAVES.size() - 1:
		hud.show_banner("最后一波已清剿！")
		# 留出短暂庆祝时间再弹胜利结算
		await get_tree().create_timer(1.2).timeout
		if Game.state == Game.State.PLAYING:
			Game.win_game()
		return
	hud.show_banner("第 %d 波清剿完毕，前往补给站" % (Game.wave_index + 1))
	await get_tree().create_timer(1.0).timeout
	if Game.state == Game.State.PLAYING:
		Game.open_shop()


func _on_enemy_killed(pos: Vector3) -> void:
	_spawn_coin_pop(pos)


func _spawn_coin_pop(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.22, 0.22)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.2)
	mat.emission_energy_multiplier = 1.8
	bm.material = mat
	mi.mesh = bm
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos + Vector3(0, 1.2, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "global_position", pos + Vector3(0, 2.4, 0), 0.5)
	tw.tween_property(mi, "scale", Vector3.ONE * 0.1, 0.5)
	tw.chain().tween_callback(mi.queue_free)


func _on_state_changed(state: int) -> void:
	if state == Game.State.MENU:
		clear_world()


## 清空一局的所有战斗产物：敌人、投射物、波次计数（重试 / 回菜单时调用）
func clear_world() -> void:
	for e in Game.enemies.duplicate():
		if is_instance_valid(e):
			e.queue_free()
	Game.enemies.clear()
	for child in enemies_root.get_children():
		child.queue_free()
	# 清理残留投射物与特效
	for node in get_tree().current_scene.get_children():
		if node is Projectile:
			node.queue_free()
	Game.alive_count = 0
	Game.pending_spawns.clear()
	if is_instance_valid(player):
		player.reset_spawn(PLAYER_SPAWN)
