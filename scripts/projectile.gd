extends Node3D
class_name Projectile
## 射手发射的能量弹：分段射线推进，命中墙体消失，命中玩家造成伤害
## 用 Node3D + 手动射线而非 Area3D，避免高速穿模

const SPEED := 11.0
const RADIUS := 0.18
const WORLD_BIT := 1
const PLAYER_BIT := 2

var direction: Vector3 = Vector3.FORWARD
var damage: float = 10.0
var life: float = 4.0
var mesh_inst: MeshInstance3D


func setup(dir: Vector3, dmg: float) -> void:
	direction = dir.normalized()
	damage = dmg


func _ready() -> void:
	mesh_inst = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.4, 0.8, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.7, 1.0)
	mat.emission_energy_multiplier = 2.5
	sphere.material = mat
	mesh_inst.mesh = sphere
	add_child(mesh_inst)

	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 0.7, 1.0)
	light.omni_range = 3.0
	light.light_energy = 1.2
	add_child(light)


func _physics_process(delta: float) -> void:
	if Game.state != Game.State.PLAYING:
		return
	life -= delta
	if life <= 0.0:
		queue_free()
		return

	var step: Vector3 = direction * SPEED * delta
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step,
		WORLD_BIT | PLAYER_BIT)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		if hit["collider"] is Player:
			Game.damage_player(damage)
			Sfx.play("hurt", -10.0, 1.1)
		_spawn_burst()
		queue_free()
		return

	global_position += step


func _spawn_burst() -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS * 1.2
	sphere.height = RADIUS * 2.4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.5, 0.85, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.8, 1.0)
	mat.emission_energy_multiplier = 2.0
	sphere.material = mat
	mi.mesh = sphere
	get_tree().current_scene.add_child(mi)
	mi.global_position = global_position
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 2.5, 0.15)
	tw.tween_callback(mi.queue_free)
