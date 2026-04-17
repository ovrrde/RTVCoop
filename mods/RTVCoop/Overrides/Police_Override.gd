extends "res://Scripts/Police.gd"


var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


var _client_prev_pos: Vector3

func _ready():
    super()
    if _net() and _net().IsActive():
        if multiplayer.is_server():
            var ws = _pm()._world_sync() if _pm() else null
            if ws:
                ws.register_vehicle(self)
        else:
            freeze = true
            _client_prev_pos = global_position


func _physics_process(delta):
    if _net() and _net().IsActive() and !multiplayer.is_server():
        var vel = (global_position - _client_prev_pos) / max(delta, 0.001)
        _client_prev_pos = global_position
        var fwd = vel.dot(global_transform.basis.z)
        Tire_FL.rotation.y = lerp_angle(Tire_FL.rotation.y, 0.0, delta * steerSmoothness)
        Tire_FR.rotation.y = lerp_angle(Tire_FR.rotation.y, 0.0, delta * steerSmoothness)
        Tire_FL.rotation.x += fwd * delta
        Tire_FR.rotation.x += fwd * delta
        Tire_RL.rotation.x += fwd * delta
        Tire_RR.rotation.x += fwd * delta
        Suspension(delta)
        Wobble(delta)
        Audio(delta)
        if currentState == State.Boss:
            police.rotation.y += delta * 20.0
        return
    super(delta)
