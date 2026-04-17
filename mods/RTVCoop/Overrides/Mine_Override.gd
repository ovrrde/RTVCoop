extends "res://Scripts/Mine.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


var _coop_detonate_suppressed: bool = false


func _ready() -> void:
    super()
    add_to_group("CoopMine")


func Detonate():
    if isDetonated:
        return
    super()

    if _coop_detonate_suppressed:
        return
    if !_net() or !_net().IsActive():
        return

    var mine_id: int = _pm()._coop_container_id(self)
    if multiplayer.is_server():
        _pm()._interactable_sync().BroadcastMineDetonate.rpc(mine_id)
    else:
        _pm()._interactable_sync().SubmitMineDetonate.rpc_id(1, mine_id)


func InstantDetonate():
    if isDetonated or is_queued_for_deletion():
        return
    super()

    if _coop_detonate_suppressed:
        return
    if !_net() or !_net().IsActive():
        return

    var mine_id: int = _pm()._coop_container_id(self)
    if multiplayer.is_server():
        _pm()._interactable_sync().BroadcastMineInstantDetonate.rpc(mine_id)
    else:
        _pm()._interactable_sync().SubmitMineInstantDetonate.rpc_id(1, mine_id)
