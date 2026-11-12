extends CanvasLayer
class_name Hud
## 全部界面：战斗 HUD、主菜单、暂停菜单、补给商店、胜负结算
## process_mode = ALWAYS：暂停时依然能响应按钮与 Esc

var font: Font
var theme: Theme

# 战斗 HUD 节点
var crosshair: Panel
var hp_label: Label
var ammo_label: Label
var weapon_label: Label
var gold_label: Label
var wave_label: Label
var enemies_label: Label
var reload_label: Label
var hint_label: Label
var banner_label: Label
var banner_timer: float = 0.0
var hit_marker: Label
var hit_marker_timer: float = 0.0
var damage_vignette: ColorRect

# 覆盖层
var menu_overlay: Control
var pause_overlay: Control
var shop_overlay: Control
var result_overlay: Control
var result_title: Label
var result_stats: Label

var test_mode: bool = false
var test_timer: float = 0.0
var test_phase: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_font()
	_build_theme()
	_build_combat_hud()
	menu_overlay = _build_menu()
	pause_overlay = _build_pause()
	shop_overlay = _build_shop()
	result_overlay = _build_result()
	_connect_signals()
	_refresh_overlay()
	test_mode = OS.has_environment("AA_TEST")
	if test_mode and OS.has_environment("AA_AUTOSTART"):
		# 仅无头自测使用：等一帧让主场景就绪后自动开局
		await get_tree().process_frame
		Game.start_new_run()
		if OS.has_environment("AA_TEST_DEFEAT"):
			# 失败路径自测：开局即把生命压到 1，等敌人一击触发 DEFEAT
			Game.hp = 1.0
			Game.health_changed.emit(Game.hp)


func _build_font() -> void:
	var loader := FontFile.new()
	# 不依赖外部字体文件：使用 Godot 内置 OpenSans 兜底，再由系统字体补 CJK
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray([
		"Microsoft YaHei", "微软雅黑", "SimHei", "黑体",
		"Noto Sans CJK SC", "PingFang SC", "Arial Unicode MS",
	])
	sys.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	font = sys


func _build_theme() -> void:
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 20

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.13, 0.15, 0.2, 0.92)
	normal.border_color = Color(0.45, 0.6, 0.85)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(10)

	var hover := normal.duplicate()
	hover.bg_color = Color(0.2, 0.26, 0.38, 0.95)
	hover.border_color = Color(0.6, 0.8, 1.0)

	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.1, 0.3, 0.45, 0.95)

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", Color(0.92, 0.95, 1.0))
	theme.set_font_size("font_size", "Button", 22)

	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = Color(0.08, 0.09, 0.13, 0.94)
	panel_box.border_color = Color(0.4, 0.5, 0.7)
	panel_box.set_border_width_all(2)
	panel_box.set_corner_radius_all(10)
	panel_box.set_content_margin_all(24)
	theme.set_stylebox("panel", "PanelContainer", panel_box)


# ---------- 战斗 HUD ----------
func _build_combat_hud() -> void:
	# 准星
	crosshair = Panel.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	crosshair.custom_minimum_size = Vector2(6, 6)
	var cross_box := StyleBoxFlat.new()
	cross_box.bg_color = Color(0.9, 0.95, 1.0, 0.9)
	cross_box.set_corner_radius_all(3)
	crosshair.add_theme_stylebox_override("panel", cross_box)
	add_child(crosshair)

	# 命中标记
	hit_marker = Label.new()
	hit_marker.set_anchors_preset(Control.PRESET_CENTER)
	hit_marker.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hit_marker.grow_vertical = Control.GROW_DIRECTION_BOTH
	hit_marker.text = "X"
	hit_marker.add_theme_font_override("font", font)
	hit_marker.add_theme_font_size_override("font_size", 26)
	hit_marker.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
	hit_marker.visible = false
	add_child(hit_marker)

	# 受伤红色暗角
	damage_vignette = ColorRect.new()
	damage_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_vignette.color = Color(0.8, 0.05, 0.05, 0.0)
	damage_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(damage_vignette)

	# 左下：生命
	hp_label = _make_label(26)
	hp_label.position = Vector2(28, 620)
	add_child(hp_label)

	# 右下：武器 + 弹匣
	ammo_label = _make_label(26)
	ammo_label.position = Vector2(960, 620)
	ammo_label.size = Vector2(300, 40)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ammo_label)

	weapon_label = _make_label(20)
	weapon_label.position = Vector2(960, 586)
	weapon_label.size = Vector2(300, 28)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(weapon_label)

	reload_label = _make_label(18)
	reload_label.position = Vector2(960, 656)
	reload_label.size = Vector2(300, 26)
	reload_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	reload_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	add_child(reload_label)

	# 顶部中央：波次 + 剩余敌人
	wave_label = _make_label(24)
	wave_label.position = Vector2(440, 18)
	wave_label.size = Vector2(400, 32)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(wave_label)

	enemies_label = _make_label(18)
	enemies_label.position = Vector2(440, 52)
	enemies_label.size = Vector2(400, 26)
	enemies_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemies_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.45))
	add_child(enemies_label)

	# 顶部左：金币
	gold_label = _make_label(24)
	gold_label.position = Vector2(28, 20)
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	add_child(gold_label)

	# 底部中央：操作提示
	hint_label = _make_label(16)
	hint_label.position = Vector2(240, 690)
	hint_label.size = Vector2(800, 24)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 0.85))
	hint_label.text = "WASD 移动  Shift 冲刺  左键射击  R 装填  1/2/3 切枪  Esc 暂停"
	add_child(hint_label)

	# 横幅（波次提示等）
	banner_label = _make_label(40)
	banner_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner_label.position = Vector2(0, 180)
	banner_label.size = Vector2(1280, 60)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.visible = false
	add_child(banner_label)


func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.93, 0.96, 1.0))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


# ---------- 覆盖层工厂 ----------
func _make_overlay(dim: bool) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	if dim:
		var bg := ColorRect.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.color = Color(0.03, 0.04, 0.07, 0.75)
		c.add_child(bg)
	add_child(c)
	return c


func _make_panel(c: Control) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	pc.custom_minimum_size = Vector2(560, 0)
	pc.theme = theme
	c.add_child(pc)
	return pc


func _make_title(text: String, size: int = 38) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	return l


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = theme
	b.custom_minimum_size = Vector2(0, 52)
	return b


func _build_menu() -> Control:
	var c := _make_overlay(true)
	var pc := _make_panel(c)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	pc.add_child(vbox)
	vbox.add_child(_make_title("异形训练场"))
	var sub := _make_label(18)
	sub.text = "单人波次射击 · 击败三波异形，赢取金币武装自己"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)
	var start := _make_button("开始游戏")
	start.pressed.connect(func() -> void: Game.start_new_run())
	vbox.add_child(start)
	var controls := _make_label(17)
	controls.text = "鼠标视角  WASD 移动  Shift 冲刺\n左键射击  R 装填  1/2/3 切换武器  Esc 暂停"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(controls)
	var quit := _make_button("退出游戏")
	quit.pressed.connect(func() -> void: get_tree().quit())
	vbox.add_child(quit)
	return c


func _build_pause() -> Control:
	var c := _make_overlay(true)
	var pc := _make_panel(c)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	pc.add_child(vbox)
	vbox.add_child(_make_title("已暂停", 34))
	var resume := _make_button("继续游戏")
	resume.pressed.connect(func() -> void: Game.resume_game())
	vbox.add_child(resume)
	var restart := _make_button("重新开始")
	restart.pressed.connect(func() -> void: Game.start_new_run())
	vbox.add_child(restart)
	var menu := _make_button("返回主菜单")
	menu.pressed.connect(func() -> void: Game.return_to_menu())
	vbox.add_child(menu)
	return c


var shop_gold_label: Label
var shop_status_label: Label
var shop_buttons: Array[Button] = []


func _build_shop() -> Control:
	var c := _make_overlay(true)
	var pc := _make_panel(c)
	pc.custom_minimum_size = Vector2(640, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	pc.add_child(vbox)
	vbox.add_child(_make_title("补给站", 34))
	var info := _make_label(19)
	info.text = "波次间隙 · 敌人不会来袭"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)
	shop_gold_label = _make_label(24)
	shop_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vbox.add_child(shop_gold_label)

	var data := [
		["购买霰弹枪（30 金币）· 7 弹丸近距离爆发", 1],
		["购买步枪（50 金币）· 全自动高射速", 2],
		["回满生命（20 金币）", -1],
	]
	for entry in data:
		var b := _make_button(entry[0])
		var id: int = entry[1]
		b.pressed.connect(_on_shop_button.bind(id))
		vbox.add_child(b)
		shop_buttons.append(b)

	shop_status_label = _make_label(17)
	shop_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_status_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.4))
	vbox.add_child(shop_status_label)

	var continue_btn := _make_button("确认并开始下一波")
	continue_btn.pressed.connect(func() -> void: Game.close_shop_and_next_wave())
	vbox.add_child(continue_btn)
	return c


func _on_shop_button(id: int) -> void:
	if id == -1:
		if Game.heal_full():
			Sfx.play("buy")
			shop_status_label.text = "生命已回满"
		else:
			shop_status_label.text = "金币不足或生命已满"
	else:
		if Game.try_buy_weapon(id):
			Sfx.play("buy")
			shop_status_label.text = "已购买：%s" % Game.WEAPON_NAMES[id]
		else:
			shop_status_label.text = "已拥有或金币不足"
	_refresh_shop()


func _refresh_shop() -> void:
	shop_gold_label.text = "金币：%d" % Game.gold
	# 按钮顺序：霰弹枪 / 步枪 / 治疗 / 继续
	shop_buttons[0].disabled = Game.owned[1] or Game.gold < 30
	shop_buttons[1].disabled = Game.owned[2] or Game.gold < 50
	shop_buttons[2].disabled = Game.gold < 20 or Game.hp >= Game.MAX_HP
	if Game.owned[1]:
		shop_buttons[0].text = "霰弹枪已拥有"
	if Game.owned[2]:
		shop_buttons[1].text = "步枪已拥有"


func _build_result() -> Control:
	var c := _make_overlay(true)
	var pc := _make_panel(c)
	pc.custom_minimum_size = Vector2(560, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	pc.add_child(vbox)
	var title := _make_title("", 40)
	result_title = title
	vbox.add_child(title)
	var stats := _make_label(24)
	result_stats = stats
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats)
	var retry := _make_button("再来一局")
	retry.pressed.connect(func() -> void: Game.start_new_run())
	vbox.add_child(retry)
	var menu := _make_button("返回主菜单")
	menu.pressed.connect(func() -> void: Game.return_to_menu())
	vbox.add_child(menu)
	return c


# ---------- 信号与刷新 ----------
func _connect_signals() -> void:
	Game.state_changed.connect(func(_s: int) -> void: _refresh_overlay())
	Game.health_changed.connect(_on_health)
	Game.gold_changed.connect(func(_g: int) -> void:
		gold_label.text = "金币：%d" % Game.gold
		_refresh_shop())
	Game.ammo_changed.connect(_on_ammo)
	Game.weapon_changed.connect(_on_weapon)
	Game.wave_changed.connect(_on_wave)
	Game.kills_changed.connect(func(_k: int) -> void: pass)
	Game.player_damaged.connect(_on_player_damaged)


func _refresh_overlay() -> void:
	menu_overlay.visible = Game.state == Game.State.MENU
	pause_overlay.visible = Game.state == Game.State.PAUSED
	shop_overlay.visible = Game.state == Game.State.SHOP
	result_overlay.visible = Game.state in [Game.State.VICTORY, Game.State.DEFEAT]
	var combat_visible: bool = Game.state in [Game.State.PLAYING, Game.State.PAUSED]
	for n in [hp_label, ammo_label, weapon_label, gold_label, wave_label,
			enemies_label, hint_label, crosshair]:
		n.visible = combat_visible
	if Game.state == Game.State.SHOP:
		shop_status_label.text = ""
		_refresh_shop()
	if Game.state in [Game.State.VICTORY, Game.State.DEFEAT]:
		_fill_result()


func _fill_result() -> void:
	var title: Label = result_title
	var stats: Label = result_stats
	if Game.state == Game.State.VICTORY:
		title.text = "胜利！"
		title.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55))
	else:
		title.text = "任务失败"
		title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
	stats.text = "击杀数：%d\n用时：%s" % [Game.kills, Game.format_time()]


func _on_health(hp: float) -> void:
	hp_label.text = "生命：%d" % int(ceil(hp))
	if hp < 35:
		hp_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	elif hp < 70:
		hp_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.35))
	else:
		hp_label.add_theme_color_override("font_color", Color(0.93, 0.96, 1.0))


func _on_ammo(id: int, mag: int) -> void:
	if id != Game.current_weapon:
		return
	var data: Dictionary = Game.WEAPONS[id]
	ammo_label.text = "%d / ∞" % mag
	if mag == 0:
		ammo_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	else:
		ammo_label.add_theme_color_override("font_color", Color(0.93, 0.96, 1.0))


func _on_weapon(id: int) -> void:
	weapon_label.text = "%s（按 %d 切换）" % [Game.WEAPON_NAMES[id], id + 1]
	_on_ammo(id, Game.mags[id])


func _on_wave(wave: int, remaining: int) -> void:
	wave_label.text = "第 %d / 3 波" % wave
	enemies_label.text = "剩余敌人：%d" % remaining


func _on_player_damaged() -> void:
	damage_vignette.color = Color(0.8, 0.05, 0.05, 0.35)
	var tw := create_tween()
	tw.tween_property(damage_vignette, "color:a", 0.0, 0.5)


func show_hit_marker(killed: bool) -> void:
	hit_marker.text = "X" if not killed else "✕ 击杀"
	hit_marker.add_theme_color_override("font_color",
		Color(1.0, 0.25, 0.2) if killed else Color(1.0, 0.9, 0.5))
	hit_marker.visible = true
	hit_marker_timer = 0.15


func show_banner(text: String) -> void:
	banner_label.text = text
	banner_label.visible = true
	banner_timer = 2.2
	Sfx.play("wave")


func _process(delta: float) -> void:
	# 暂停键：任何非菜单/结算状态都可切换
	if Input.is_action_just_pressed("pause"):
		if Game.state == Game.State.PLAYING:
			Game.pause_game()
		elif Game.state == Game.State.PAUSED:
			Game.resume_game()

	if hit_marker_timer > 0.0:
		hit_marker_timer -= delta
		if hit_marker_timer <= 0.0:
			hit_marker.visible = false

	if banner_timer > 0.0:
		banner_timer -= delta
		if banner_timer <= 0.0:
			banner_label.visible = false

	# 装填进度提示
	if Game.state == Game.State.PLAYING:
		var w: WeaponController = Game.player.weapon
		if w.is_reloading():
			reload_label.text = "装填中… %d%%" % int(w.reload_progress() * 100.0)
		else:
			reload_label.text = ""

	_run_test(delta)
	if test_mode and Game.state == Game.State.SHOP:
		# 无头自测：自动购买可负担的补给后立即进入下一波
		Game.try_buy_weapon(1)
		Game.try_buy_weapon(2)
		if Game.hp < Game.MAX_HP:
			Game.heal_full()
		Game.close_shop_and_next_wave()
	if test_mode and Game.state in [Game.State.VICTORY, Game.State.DEFEAT]:
		test_phase += 1
		if test_phase > 120:  # 约 2 秒后退出
			print("[Test] final state = ", Game.state, " kills=", Game.kills, " time=", Game.format_time())
			get_tree().quit(0 if Game.state == Game.State.VICTORY else 2)


# ---------- 无头自动化测试：AA_TEST 环境变量开启 ----------
func _run_test(delta: float) -> void:
	if not test_mode or Game.state != Game.State.PLAYING:
		test_timer = 0.0
		return
	test_timer += delta
	# 失败路径自测：玩家不反击，静止等敌人击杀
	if OS.has_environment("AA_TEST_DEFEAT"):
		return
	_auto_aim_nearest()
	# AA_SHOT_VIEW：视觉验证模式只瞄准不开火，让敌人活着进入视野
	if OS.has_environment("AA_SHOT_VIEW"):
		return
	# 每 0.18 秒尝试射击 + 定期装填/切枪，模拟真实操作节奏
	if fmod(test_timer, 0.18) < delta:
		var w: WeaponController = Game.player.weapon
		w._try_fire()
	if fmod(test_timer, 1.6) < delta:
		var w: WeaponController = Game.player.weapon
		w._try_reload()
	if fmod(test_timer, 6.0) < delta:
		# 测试中用击杀奖励购买全部武器并轮流使用
		for id in [1, 2]:
			if not Game.owned[id]:
				Game.try_buy_weapon(id)
		var next_id := (int(test_timer / 6.0) % 3)
		if Game.owned[next_id]:
			Game.switch_weapon(next_id)
	# 兜底：若残余敌人卡住（20 秒无击杀），直接清理最近敌人，保证流程可跑完
	if fmod(test_timer, 20.0) < delta and Game.alive_count > 0:
		var nearest: Enemy = null
		var nd := 9999.0
		for e in Game.enemies:
			if e.dead:
				continue
			var d: float = e.global_position.distance_to(Game.player.global_position)
			if d < nd:
				nd = d
				nearest = e
		if nearest:
			nearest.take_damage(9999.0, nearest.global_position)


## 自测专用：把视角锁向最近敌人，验证射击/命中/击杀链路（正常游戏不调用）
func _auto_aim_nearest() -> void:
	var nearest: Enemy = null
	var nd := 9999.0
	for e in Game.enemies:
		if e.dead:
			continue
		var d: float = e.global_position.distance_to(Game.player.global_position)
		if d < nd:
			nd = d
			nearest = e
	if nearest == null:
		return
	var p: Player = Game.player
	var offset: Vector3 = nearest.global_position - p.global_position
	p.yaw = atan2(-offset.x, -offset.z)
	p.rotation.y = p.yaw
	var flat := Vector2(offset.x, offset.z).length()
	p.pitch = clamp(atan2(nearest.global_position.y + 1.2 - (p.global_position.y + 1.65), flat), -1.45, 1.45)
	p.camera_rig.rotation.x = p.pitch
