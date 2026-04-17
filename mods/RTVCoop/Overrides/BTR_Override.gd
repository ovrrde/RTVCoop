extends "res://Scripts/BTR.gd"


var _net_c: Node
var _pm_c: Node
var _coop_remote_fire: bool = false
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
        else:
            freeze = true


func _physics_process(delta):
    if _net() and _net().IsActive() and !multiplayer.is_server():
        Tires(delta)
        Suspension(delta)
        return
    super(delta)


func Muzzle():
    if _coop_remote_fire:
        _coop_remote_fire = false
        super()
        return
    super()
    if _net() and _net().IsActive() and multiplayer.is_server():
        _pm()._event_sync().BroadcastBTRFire.rpc(name, fullAuto)
