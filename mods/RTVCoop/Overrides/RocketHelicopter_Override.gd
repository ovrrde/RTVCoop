extends "res://Scripts/RocketHelicopter.gd"

const ROCKET_MAX_RANGE: float = 1000.0
const ROCKET_EXPLOSION_SIZE: float = 20.0


var _net_c: Node
var _pm_c: Node
var _exploded: bool = false
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func _ready() -> void:
    super()
    add_to_group("CoopRocket")
    if _net() and _net().IsActive() and multiplayer.is_server():
        var ws = _pm()._world_sync() if _pm() else null
        if ws:
            ws.register_rocket(self)


func _physics_process(delta: float) -> void:
    if _net() and _net().IsActive() and !multiplayer.is_server():
        return
    phase += delta
    rotate_y(deg_to_rad(sin(phase * horizontalFrequency) * deviation * delta))
    rotate_x(deg_to_rad(sin(phase * verticalFrequency + verticalOffset) * deviation * delta))
    global_position += transform.basis.z * speed * delta
    if ray.is_colliding():
        _coop_explode()
        return
    if global_position.distance_to(Vector3.ZERO) > ROCKET_MAX_RANGE:
        _coop_cleanup()


func _coop_explode():
    if _exploded:
        return
    _exploded = true
    var pos = global_position
    if _net() and _net().IsActive() and multiplayer.is_server():
        _pm()._event_sync().BroadcastRocketExplode.rpc(pos)
    var instance = load("res://Effects/Explosion.tscn").instantiate()
    get_tree().get_root().add_child(instance)
    instance.global_position = pos
    instance.size = ROCKET_EXPLOSION_SIZE
    if instance.has_method("Explode"):
        instance.Explode()
    queue_free()


func _coop_cleanup():
    if _exploded:
        return
    _exploded = true
    if _net() and _net().IsActive() and multiplayer.is_server():
        _pm()._event_sync().BroadcastRocketCleanup.rpc(global_position)
    queue_free()
