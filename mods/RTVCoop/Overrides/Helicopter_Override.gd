extends "res://Scripts/Helicopter.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func _ready():
    super()
    if _net() and _net().IsActive():
        if multiplayer.is_server():
            var ws = _pm()._world_sync() if _pm() else null
            if ws:
                ws.register_vehicle(self)


func _physics_process(delta):
    if _net() and _net().IsActive() and !multiplayer.is_server():
        RotorBlades(delta)
        return
    super(delta)


var _coop_remote_fire: bool = false

func FireRockets():
    if _net() and _net().IsActive() and !multiplayer.is_server() and !_coop_remote_fire:
        return
    _coop_remote_fire = false
    super()
    if _net() and _net().IsActive() and multiplayer.is_server():
        _pm()._event_sync().BroadcastHelicopterRockets.rpc(name, global_position, global_rotation)


func Spotted():
    if _net().IsActive() and !multiplayer.is_server():
        return
    if _net().IsActive() and multiplayer.is_server():
        _pm()._event_sync().BroadcastHelicopterSpotted.rpc()
    super()


func Sensor(delta):
    if _net().IsActive() and !multiplayer.is_server():
        return
    super(delta)
