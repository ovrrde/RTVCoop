extends "res://Scripts/CASA.gd"

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
        else:
            if airdrop:
                airdrop.freeze = true
                airdrop.sleeping = true


func _physics_process(delta):
    if _net() and _net().IsActive() and !multiplayer.is_server():
        leftPropeller.rotation.z += delta * 20.0
        rightPropeller.rotation.z += delta * 20.0
        Parachute(delta)
        return
    super(delta)
    if _net().IsActive() and multiplayer.is_server() and dropped and airdrop and is_instance_valid(airdrop) and airdrop.is_inside_tree():
        _pm()._event_sync().BroadcastAirdropPose.rpc(name, airdrop.global_position, airdrop.global_rotation, released)


func Collided(body: Node3D):
    if _net() and _net().IsActive() and !multiplayer.is_server():
        return
    super(body)
    if _net().IsActive() and multiplayer.is_server():
        _pm()._event_sync().BroadcastAirdropLanding.rpc(airdrop.global_position, airdrop.global_rotation)
