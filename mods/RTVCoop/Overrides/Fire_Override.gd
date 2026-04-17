extends "res://Scripts/Fire.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func _ready():
    var s: int = 0
    if _net() and _net().IsActive():
        s = await _pm().CoopSeedForNode(self)
        if s != 0:
            seed(s)
    super()
    if s != 0:
        randomize()


func Interact():
    if !_net() or !_net().IsActive():
        super()
        return

    if multiplayer.is_server():
        if !active:
            if MatchCheck():
                ConsumeMatch()
                active = true
                Activate()
                IgniteAudio()
                _pm()._event_sync().BroadcastFireState.rpc(get_path(), true)
        else:
            active = false
            Deactivate()
            ExtinguishAudio()
            _pm()._event_sync().BroadcastFireState.rpc(get_path(), false)
    else:
        if !active and !MatchCheck():
            return
        _pm()._event_sync().RequestFireToggle.rpc_id(1, get_path())
