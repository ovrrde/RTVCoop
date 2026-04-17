extends "res://Scripts/Placer.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


var _net_last_placable_uuid: int = -1
var _net_last_furniture_fid: int = -1
var _net_sync_accumulator: float = 0.0
const _NET_SYNC_INTERVAL: float = 1.0 / 20.0


func _physics_process(delta):
    if gameData.isPlacing and (placable == null or !is_instance_valid(placable)):
        placable = null
        furniture = null
        initialWait = false
        gameData.isPlacing = false
        _net_last_placable_uuid = -1
        _net_last_furniture_fid = -1

    super(delta)
    _coop_sync_placable(delta)


func _input(event):
    # capture fid before Catalog() frees owner
    if _net() and _net().IsActive() \
            and gameData.isPlacing and gameData.decor \
            and placable and is_instance_valid(placable) and furniture \
            and Input.is_action_just_pressed("interact"):
        var fid: int = -1
        if placable.has_meta("coop_furniture_id"):
            fid = int(placable.get_meta("coop_furniture_id"))
        super(event)
        if fid >= 0:
            if multiplayer.is_server():
                _pm()._furniture_sync().BroadcastFurnitureRemove.rpc(fid)
            else:
                _pm()._furniture_sync().SubmitFurnitureRemove.rpc_id(1, fid)
            _net_last_furniture_fid = -1
            _net_sync_accumulator = 0.0
        return
    super(event)


func _coop_sync_placable(delta: float):
    if !_net() or !_net().IsActive():
        return

    if gameData.isPlacing and placable and is_instance_valid(placable):
        if placable.has_meta("network_uuid"):
            _coop_tick_pickup_sync(delta)
        elif placable.has_meta("coop_furniture_id"):
            _coop_tick_furniture_sync(delta)
        return

    if _net_last_placable_uuid >= 0:
        _coop_finalize_pickup_sync()
        _net_last_placable_uuid = -1
        _net_sync_accumulator = 0.0
    if _net_last_furniture_fid >= 0:
        _coop_finalize_furniture_sync()
        _net_last_furniture_fid = -1
        _net_sync_accumulator = 0.0


func _coop_tick_pickup_sync(delta: float):
    _net_last_placable_uuid = int(placable.get_meta("network_uuid"))
    _net_sync_accumulator += delta
    if _net_sync_accumulator < _NET_SYNC_INTERVAL:
        return
    _net_sync_accumulator = 0.0
    if multiplayer.is_server():
        _pm().BroadcastPickupMove.rpc(_net_last_placable_uuid, placable.global_position, placable.global_rotation, true)
    else:
        _pm().SubmitPickupMove.rpc_id(1, _net_last_placable_uuid, placable.global_position, placable.global_rotation, true)


func _coop_tick_furniture_sync(delta: float):
    # missing fid would int(null)→0 and move some other fid-0 furniture on remote peers
    if !placable.has_meta("coop_furniture_id"):
        return
    _net_last_furniture_fid = int(placable.get_meta("coop_furniture_id"))
    _net_sync_accumulator += delta
    if _net_sync_accumulator < _NET_SYNC_INTERVAL:
        return
    _net_sync_accumulator = 0.0
    if multiplayer.is_server():
        _pm()._furniture_sync().BroadcastFurnitureMove.rpc(_net_last_furniture_fid, placable.global_position, placable.global_rotation, placable.scale)
    else:
        _pm()._furniture_sync().SubmitFurnitureMove.rpc_id(1, _net_last_furniture_fid, placable.global_position, placable.global_rotation, placable.scale)


func _coop_finalize_pickup_sync():
    var pm = _pm()
    if !pm or !pm.worldItems.has(_net_last_placable_uuid):
        return
    var final_pickup = pm.worldItems[_net_last_placable_uuid]
    if !is_instance_valid(final_pickup):
        return
    var target_frozen: bool = final_pickup.freeze
    if multiplayer.is_server():
        pm.BroadcastPickupMove.rpc(_net_last_placable_uuid, final_pickup.global_position, final_pickup.global_rotation, target_frozen)
    else:
        pm.SubmitPickupMove.rpc_id(1, _net_last_placable_uuid, final_pickup.global_position, final_pickup.global_rotation, target_frozen)


func _coop_finalize_furniture_sync():
    var pm = _pm()
    if !pm or _net_last_furniture_fid < 0:
        return
    var final_root = pm._find_furniture_by_id(_net_last_furniture_fid)
    if !final_root:
        return
    var fs = pm._furniture_sync()
    if !fs:
        return
    if multiplayer.is_server():
        fs.BroadcastFurnitureMove.rpc(_net_last_furniture_fid, final_root.global_position, final_root.global_rotation, final_root.scale)
    else:
        fs.SubmitFurnitureMove.rpc_id(1, _net_last_furniture_fid, final_root.global_position, final_root.global_rotation, final_root.scale)
