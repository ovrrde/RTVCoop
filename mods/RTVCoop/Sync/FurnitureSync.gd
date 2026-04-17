extends Node

signal furniture_token_received(token: int, fid: int)
var _next_furniture_token: int = 0

# fid -> {"pos": Vector3, "rot": Vector3, "scl": Vector3}
var _move_targets: Dictionary = {}
const FURNITURE_LERP_SPEED: float = 18.0
const FURNITURE_LERP_EPSILON: float = 0.01


func _physics_process(delta):
    if _move_targets.is_empty():
        return
    var t: float = clampf(FURNITURE_LERP_SPEED * delta, 0.0, 1.0)
    var stale: Array = []
    for fid in _move_targets:
        var root = _find_furniture_by_id(fid)
        if !root:
            stale.append(fid)
            continue
        var target: Dictionary = _move_targets[fid]
        if root.global_position.distance_to(target.pos) < FURNITURE_LERP_EPSILON:
            root.global_position = target.pos
            root.global_rotation = target.rot
            root.scale = target.scl
            stale.append(fid)
            continue
        root.global_position = root.global_position.lerp(target.pos, t)
        root.global_rotation.x = lerp_angle(root.global_rotation.x, target.rot.x, t)
        root.global_rotation.y = lerp_angle(root.global_rotation.y, target.rot.y, t)
        root.global_rotation.z = lerp_angle(root.global_rotation.z, target.rot.z, t)
        root.scale = root.scale.lerp(target.scl, t)
    for f in stale:
        _move_targets.erase(f)


func _pm():
    return get_parent()


func NextFurnitureToken() -> int:
    _next_furniture_token += 1
    return _next_furniture_token


func _find_furniture_by_id(fid: int) -> Node3D:
    var wf = _pm().worldFurniture
    if wf.has(fid):
        var cached = wf[fid]
        if is_instance_valid(cached):
            return cached
        wf.erase(fid)
    for root in _coop_iter_furniture_roots():
        if root.has_meta("coop_furniture_id") and int(root.get_meta("coop_furniture_id")) == fid:
            wf[fid] = root
            return root
    return null


func _coop_iter_furniture_roots() -> Array:
    var roots: Array = []
    var seen: Dictionary = {}
    for node in get_tree().get_nodes_in_group("Furniture"):
        var root = node.owner
        if !root or !is_instance_valid(root):
            continue
        if seen.has(root):
            continue
        seen[root] = true
        roots.append(root)
    return roots


func _coop_find_furniture_component(root: Node) -> Furniture:
    for child in root.get_children():
        if child is Furniture:
            return child
    return null


@rpc("any_peer", "reliable", "call_remote")
func RequestFurnitureSpawn(token: int, file: String, pos: Vector3, rot: Vector3, scl: Vector3):
    if !multiplayer.is_server():
        return
    var sender = multiplayer.get_remote_sender_id()
    var fid: int = _pm().GenerateFurnitureId()
    BroadcastFurnitureSpawn.rpc(fid, file, pos, rot, scl)
    DeliverFurnitureToken.rpc_id(sender, token, fid)


@rpc("authority", "reliable", "call_remote")
func DeliverFurnitureToken(token: int, fid: int):
    furniture_token_received.emit(token, fid)


@rpc("authority", "reliable", "call_local")
func BroadcastFurnitureSpawn(fid: int, file: String, pos: Vector3, rot: Vector3, scl: Vector3):
    var map = _pm().GetMap()
    if !map:
        return
    if _pm().worldFurniture.has(fid):
        var existing = _pm().worldFurniture[fid]
        if is_instance_valid(existing):
            existing.global_position = pos
            existing.global_rotation = rot
            existing.scale = scl
            return
        _pm().worldFurniture.erase(fid)
    var scene = Database.get(file)
    if !scene:
        return
    var root = scene.instantiate()
    map.add_child(root)
    root.global_position = pos
    root.global_rotation = rot
    root.scale = scl
    root.set_meta("coop_furniture_id", fid)
    _pm().worldFurniture[fid] = root
    if fid >= _pm().nextFurnitureId:
        _pm().nextFurnitureId = fid + 1
    if root is LootContainer:
        root.set_meta("coop_container_id", fid)
        if !root.is_in_group("CoopLootContainer"):
            root.add_to_group("CoopLootContainer")


@rpc("any_peer", "reliable", "call_remote")
func SubmitFurnitureMove(fid: int, pos: Vector3, rot: Vector3, scl: Vector3):
    if !multiplayer.is_server():
        return
    var sender = multiplayer.get_remote_sender_id()
    _move_targets[fid] = {"pos": pos, "rot": rot, "scl": scl}
    for peer_id in _pm().peer_names.keys():
        if peer_id == sender or peer_id == 1:
            continue
        BroadcastFurnitureMove.rpc_id(peer_id, fid, pos, rot, scl)


@rpc("authority", "reliable", "call_remote")
func BroadcastFurnitureMove(fid: int, pos: Vector3, rot: Vector3, scl: Vector3):
    _move_targets[fid] = {"pos": pos, "rot": rot, "scl": scl}


@rpc("any_peer", "reliable", "call_remote")
func SubmitFurnitureRemove(fid: int):
    if !multiplayer.is_server():
        return
    BroadcastFurnitureRemove.rpc(fid)


@rpc("authority", "reliable", "call_local")
func BroadcastFurnitureRemove(fid: int):
    var root = _find_furniture_by_id(fid)
    if root:
        root.queue_free()
    _pm().worldFurniture.erase(fid)
