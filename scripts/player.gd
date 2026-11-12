extends CharacterBody3D
class_name Player
## 第一人称玩家：WASD 移动、Shift 冲刺、鼠标视角、碰撞墙体

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.0
const ACCEL := 12.0
const MOUSE_SENS := 0.0025
const PLAYER_LAYER := 2
const PLAYER_MASK := 1  # 只与世界碰撞

var camera_rig: Node3D
var camera: Camera3D
var weapon: WeaponController
var yaw: float = 0.0
var pitch: float = 0.0
var base_fov := 75.0


func _init() -> void:
	collision_layer = PLAYER_LAYER
	collision_mask = PLAYER_MASK
	floor_snap_length = 0.2


func setup(rig: Node3D, cam: Camera3D, weapon_ctrl: WeaponController) -> void:
	camera_rig = rig
	camera = cam
	weapon = weapon_ctrl
	base_fov = cam.fov


func _ready() -> void:
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 1.8
	col.shape = shape
	col.position = Vector3(0, 0.9, 0)
	add_child(col)


func _physics_process(delta: float) -> void:
	if Game.state != Game.State.PLAYING:
		velocity = Vector3.ZERO
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var sprinting := Input.is_action_pressed("sprint") and direction != Vector3.ZERO
	var speed := SPRINT_SPEED if sprinting else WALK_SPEED

	var target := direction * speed
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta)
	move_and_slide()

	# 冲刺时轻微扩大视野
	var target_fov := base_fov + 6.0 if sprinting else base_fov
	camera.fov = move_toward(camera.fov, target_fov, 30.0 * delta)


func _unhandled_input(event: InputEvent) -> void:
	if Game.state != Game.State.PLAYING:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENS
		pitch = clamp(pitch - event.relative.y * MOUSE_SENS, -1.45, 1.45)
		rotation.y = yaw
		camera_rig.rotation.x = pitch


func reset_spawn(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	yaw = 0.0
	pitch = 0.0
	rotation.y = 0.0
	camera_rig.rotation.x = 0.0
	camera.fov = base_fov
