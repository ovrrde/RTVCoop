@tool
extends "res://Scripts/RocketGrad.gd"

const GRAD_CLEANUP_OVERSHOOT: float = 100.0


var _net_c: Node
var _pm_c: Node
var _coop_cleared: bool = false
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func ExecuteLaunch(value: bool) -> void:
    super(value)
    add_to_group("CoopRocket")
    if _net() and _net().IsActive() and multiplayer.is_server():
        var ws = _pm()._world_sync() if _pm() else null
        if ws:
            ws.register_rocket(self)


func _process(delta: float) -> void:
    if _net() and _net().IsActive() and !multiplayer.is_server():
        return
    if launched and global_position.z > abs(tracking) + GRAD_CLEANUP_OVERSHOOT and !_coop_cleared:
        _coop_cleared = true
        if _net() and _net().IsActive() and multiplayer.is_server() and _pm() and _pm()._event_sync():
            _pm()._event_sync().BroadcastRocketCleanup.rpc(global_position)
    super(delta)
