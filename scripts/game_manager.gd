extends Node
## 全局游戏状态机：菜单 / 战斗 / 暂停 / 补给 / 结算
enum State { MENU, PLAYING, PAUSED, SHOP, VICTORY, DEFEAT }

const WEAPON_PISTOL := 0
const WEAPON_SHOTGUN := 1
const WEAPON_RIFLE := 2

const WEAPON_NAMES := ["手枪", "霰弹枪", "步枪"]
const WEAPON_PRICES := [0, 30, 50]
const HEAL_PRICE := 20
const KILL_REWARD := 10

## index = 武器 id
const WEAPONS := [
	{
		"damage": 18.0, "fire_interval": 0.28, "reload_time": 1.0,
		"mag_size": 12, "pellets": 1, "spread": 0.012, "auto": false,
	},
	{
		"damage": 9.0, "fire_interval": 0.85, "reload_time": 1.8,
		"mag_size": 6, "pellets": 7, "spread": 0.075, "auto": false,
	},
	{
		"damage": 12.0, "fire_interval": 0.1, "reload_time": 1.6,
		"mag_size": 30, "pellets": 1, "spread": 0.028, "auto": true,
	},
]

## 每一波的敌人花名册
const WAVES: Array = [
	["chaser", "chaser", "chaser", "chaser", "chaser", "chaser"],
	["chaser", "chaser", "chaser", "chaser", "chaser", "chaser", "shooter", "shooter", "shooter"],
	["chaser", "chaser", "chaser", "chaser", "chaser", "chaser", "chaser",
		"shooter", "shooter", "shooter", "heavy", "heavy"],
]

signal state_changed(state)
signal health_changed(hp)
signal gold_changed(gold)
signal ammo_changed(weapon_id, mag)
signal weapon_changed(weapon_id)
signal wave_changed(wave, remaining)
signal kills_changed(kills)
signal player_damaged
signal enemy_killed(pos)

var state: int = State.MENU
var hp: float = 100.0
const MAX_HP := 100.0
var gold: int = 0
var owned: Array[bool] = [true, false, false]
var mags: Array[int] = [12, 0, 0]
var current_weapon: int = WEAPON_PISTOL
var kills: int = 0
var wave_index: int = 0
var run_time: float = 0.0

var enemies: Array = []
## 波次运行时数据：待生成 / 存活 / 本波总数
var pending_spawns: Array = []
var alive_count: int = 0
var wave_total: int = 0
var spawn_timer: float = 0.0
const SPAWN_INTERVAL := 0.7

var main: Node = null
var player: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_inputs()


func _process(delta: float) -> void:
	if state == State.PLAYING:
		run_time += delta


# ---------- 输入映射（代码注册，避免手改 project.godot 出错） ----------
func _register_inputs() -> void:
	var km := InputMap
	for action in ["move_forward", "move_back", "move_left", "move_right",
			"sprint", "fire", "reload", "weapon_1", "weapon_2", "weapon_3",
			"pause", "interact"]:
		if not km.has_action(action):
			km.add_action(action)

	_bind_key("move_forward", [KEY_W])
	_bind_key("move_back", [KEY_S])
	_bind_key("move_left", [KEY_A])
	_bind_key("move_right", [KEY_D])
	_bind_key("sprint", [KEY_SHIFT])
	_bind_key("reload", [KEY_R])
	_bind_key("weapon_1", [KEY_1])
	_bind_key("weapon_2", [KEY_2])
	_bind_key("weapon_3", [KEY_3])
	_bind_key("pause", [KEY_ESCAPE])
	_bind_key("interact", [KEY_E, KEY_ENTER])
	# 射击：鼠标左键
	if not InputMap.action_has_event("fire", InputEventMouseButton.new()):
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", ev)


func _bind_key(action: String, keys: Array) -> void:
	for key in keys:
		var exists := false
		for e in InputMap.action_get_events(action):
			if e is InputEventKey and e.physical_keycode == key:
				exists = true
				break
		if not exists:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


# ---------- 流程控制 ----------
func start_new_run() -> void:
	# 重试前清空上一局残留的敌人与战斗状态
	if main and main.has_method("clear_world"):
		main.clear_world()
	hp = MAX_HP
	gold = 0
	owned = [true, false, false]
	mags = [12, 0, 0]
	current_weapon = WEAPON_PISTOL
	kills = 0
	wave_index = 0
	run_time = 0.0
	alive_count = 0
	pending_spawns = []
	enemies.clear()
	_enter_playing()
	wave_changed.emit(1, 0)
	health_changed.emit(hp)
	gold_changed.emit(gold)
	kills_changed.emit(kills)
	weapon_changed.emit(current_weapon)
	ammo_changed.emit(current_weapon, mags[current_weapon])
	main.start_wave(0)


func return_to_menu() -> void:
	_set_state(State.MENU)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false


func _enter_playing() -> void:
	_set_state(State.PLAYING)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func pause_game() -> void:
	if state != State.PLAYING:
		return
	_set_state(State.PAUSED)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume_game() -> void:
	if state != State.PAUSED:
		return
	_enter_playing()


func open_shop() -> void:
	_set_state(State.SHOP)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_shop_and_next_wave() -> void:
	wave_index += 1
	_enter_playing()
	main.start_wave(wave_index)


func win_game() -> void:
	_set_state(State.VICTORY)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func lose_game() -> void:
	if state == State.DEFEAT:
		return
	_set_state(State.DEFEAT)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _set_state(s: int) -> void:
	state = s
	print("[Game] state -> ", ["MENU", "PLAYING", "PAUSED", "SHOP", "VICTORY", "DEFEAT"][s])
	state_changed.emit(s)


# ---------- 波次 ----------
func begin_wave(roster: Array) -> void:
	pending_spawns = roster.duplicate()
	# 打乱出生顺序，避免敌人全部从同一个入口出现
	pending_spawns.shuffle()
	wave_total = roster.size()
	alive_count = 0
	spawn_timer = 0.0
	print("[Game] wave %d start, total=%d" % [wave_index + 1, wave_total])
	wave_changed.emit(wave_index + 1, wave_total)


func register_spawned(enemy: Node) -> void:
	enemies.append(enemy)
	alive_count += 1
	wave_changed.emit(wave_index + 1, remaining_enemies())


func register_dead(enemy: Node) -> void:
	enemies.erase(enemy)
	alive_count -= 1
	kills += 1
	gold += KILL_REWARD
	kills_changed.emit(kills)
	gold_changed.emit(gold)
	enemy_killed.emit(enemy.global_position)
	wave_changed.emit(wave_index + 1, remaining_enemies())
	print("[Game] kill #%d (%s), alive=%d, pending=%d, gold=%d" % [kills, enemy.kind, alive_count, pending_spawns.size(), gold])
	if state == State.PLAYING and alive_count == 0 and pending_spawns.is_empty():
		main.on_wave_cleared()


func remaining_enemies() -> int:
	return alive_count + pending_spawns.size()


# ---------- 玩家 ----------
func damage_player(amount: float) -> void:
	if state != State.PLAYING:
		return
	hp = max(0.0, hp - amount)
	health_changed.emit(hp)
	player_damaged.emit()
	if hp <= 0.0:
		lose_game()


func heal_full() -> bool:
	if gold < HEAL_PRICE or hp >= MAX_HP:
		return false
	gold -= HEAL_PRICE
	hp = MAX_HP
	gold_changed.emit(gold)
	health_changed.emit(hp)
	return true


# ---------- 武器 / 弹药 ----------
func try_buy_weapon(weapon_id: int) -> bool:
	if owned[weapon_id] or gold < WEAPON_PRICES[weapon_id]:
		return false
	gold -= WEAPON_PRICES[weapon_id]
	owned[weapon_id] = true
	mags[weapon_id] = WEAPONS[weapon_id]["mag_size"]
	gold_changed.emit(gold)
	return true


func consume_ammo(weapon_id: int) -> void:
	mags[weapon_id] = max(0, mags[weapon_id] - 1)
	ammo_changed.emit(weapon_id, mags[weapon_id])


func refill_mag(weapon_id: int) -> void:
	# 备用弹药无限：装填即补满弹匣
	mags[weapon_id] = WEAPONS[weapon_id]["mag_size"]
	ammo_changed.emit(weapon_id, mags[weapon_id])


func switch_weapon(weapon_id: int) -> void:
	if not owned[weapon_id] or weapon_id == current_weapon:
		return
	current_weapon = weapon_id
	weapon_changed.emit(current_weapon)
	ammo_changed.emit(current_weapon, mags[current_weapon])


func format_time() -> String:
	var total := int(run_time)
	return "%02d:%02d" % [total / 60, total % 60]
