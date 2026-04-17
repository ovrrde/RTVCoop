extends Node


func _pm():
    return get_parent()


func _ready():
    get_tree().get_root().child_entered_tree.connect(_on_root_child_added)


func _on_root_child_added(node: Node):
    if !(node is Grenade):
        return
    if node.has_meta("_coop_remote"):
        return
    if !_pm()._net().IsActive():
        return
    _broadcast_grenade_spawn(node)


func _broadcast_grenade_spawn(grenade: Node):
    await get_tree().physics_frame
    if !is_instance_valid(grenade) or !grenade.is_inside_tree():
        return

    var throwPath: String = grenade.scene_file_path
    var handlePath: String = ""
    if grenade.handle and is_instance_valid(grenade.handle):
        handlePath = grenade.handle.scene_file_path


    if multiplayer.is_server():
        BroadcastGrenadeThrow.rpc(
            multiplayer.get_unique_id(),
            throwPath, handlePath,
            grenade.global_position, grenade.rotation_degrees,
            grenade.linear_velocity, grenade.angular_velocity
        )
    else:
        SubmitGrenadeThrow.rpc_id(1,
            throwPath, handlePath,
            grenade.global_position, grenade.rotation_degrees,
            grenade.linear_velocity, grenade.angular_velocity
        )


func _find_mine_by_id(mine_id: int) -> Node3D:
    for mine in get_tree().get_nodes_in_group("CoopMine"):
        if !is_instance_valid(mine):
            continue
        if _pm()._coop_container_id(mine) == mine_id:
            return mine
    return null


@rpc("any_peer", "reliable", "call_remote")
func RequestDoorSync():
    if !multiplayer.is_server():
        return
    var sender = multiplayer.get_remote_sender_id()
    var doors: Array = []
    var scene = get_tree().current_scene
    if scene:
        _scan_doors(scene, doors)
    print("[InteractableSync] Sending door manifest to peer " + str(sender) + ": " + str(doors.size()) + " doors")
    ApplyDoorManifest.rpc_id(sender, doors)


@rpc("authority", "reliable", "call_remote")
func ApplyDoorManifest(doors: Array):
    print("[InteractableSync] Received door manifest: " + str(doors.size()) + " doors")
    for entry in doors:
        var door = get_node_or_null(entry.get("path", NodePath()))
        if !door or !(door is Door):
            continue
        var desired_open: bool = bool(entry.get("isOpen", false))
        var desired_locked: bool = bool(entry.get("locked", false))
        if !desired_locked and door.locked:
            door.locked = false
            if door.linked:
                door.linked.locked = false
        if door.isOpen != desired_open:
            door.isOpen = desired_open
            if desired_open:
                door.position = door.openOffset + door.defaultPosition
                door.rotation_degrees = door.openAngle + door.defaultRotation
            else:
                door.position = door.defaultPosition
                door.rotation_degrees = door.defaultRotation
            door.animationTime = 0.0


func _scan_doors(n: Node, out: Array):
    _pm()._event_sync().CoopWalk(n, func(node):
        if node is Door:
            out.append({
                "path": node.get_path(),
                "isOpen": bool(node.isOpen),
                "locked": bool(node.locked),
            })
        return false
    )


@rpc("any_peer", "reliable", "call_remote")
func RequestDoorToggle(doorPath: NodePath):
    if !multiplayer.is_server():
        return
    var door = get_node_or_null(doorPath)
    if !door or !(door is Door):
        return
    if door.locked or door.isOccupied:
        return
    var newOpen = !door.isOpen
    door.ApplyDoorState(newOpen)
    BroadcastDoorState.rpc(doorPath, newOpen)


@rpc("authority", "reliable", "call_remote")
func BroadcastDoorState(doorPath: NodePath, newOpen: bool):
    var door = get_node_or_null(doorPath)
    if !door or !(door is Door):
        return
    door.ApplyDoorState(newOpen)


@rpc("any_peer", "reliable", "call_remote")
func RequestDoorUnlock(doorPath: NodePath):
    if !multiplayer.is_server():
        return
    var door = get_node_or_null(doorPath)
    if !door or !(door is Door):
        return
    door.ApplyDoorUnlock()
    BroadcastDoorUnlock.rpc(doorPath)


@rpc("authority", "reliable", "call_remote")
func BroadcastDoorUnlock(doorPath: NodePath):
    var door = get_node_or_null(doorPath)
    if !door or !(door is Door):
        return
    door.ApplyDoorUnlock()


@rpc("any_peer", "reliable", "call_remote")
func RequestSwitchToggle(switchPath: NodePath):
    if !multiplayer.is_server():
        return
    var sw = get_node_or_null(switchPath)
    if !sw or !sw.has_method("ApplySwitchState"):
        return
    var newActive = !sw.active
    sw.ApplySwitchState(newActive)
    BroadcastSwitchState.rpc(switchPath, newActive)


@rpc("authority", "reliable", "call_remote")
func BroadcastSwitchState(switchPath: NodePath, newActive: bool):
    var sw = get_node_or_null(switchPath)
    if !sw or !sw.has_method("ApplySwitchState"):
        return
    sw.ApplySwitchState(newActive)


@rpc("any_peer", "reliable", "call_remote")
func SubmitMineDetonate(mine_id: int):
    if !multiplayer.is_server():
        return
    var mine = _find_mine_by_id(mine_id)
    if !mine or mine.isDetonated:
        return
    mine.Detonate()


@rpc("authority", "reliable", "call_remote")
func BroadcastMineDetonate(mine_id: int):
    var mine = _find_mine_by_id(mine_id)
    if !mine or mine.isDetonated:
        return
    mine._coop_detonate_suppressed = true
    mine.Detonate()
    mine._coop_detonate_suppressed = false


@rpc("any_peer", "reliable", "call_remote")
func SubmitMineInstantDetonate(mine_id: int):
    if !multiplayer.is_server():
        return
    var mine = _find_mine_by_id(mine_id)
    if !mine or mine.isDetonated or mine.is_queued_for_deletion():
        return
    mine.InstantDetonate()


@rpc("authority", "reliable", "call_remote")
func BroadcastMineInstantDetonate(mine_id: int):
    var mine = _find_mine_by_id(mine_id)
    if !mine or mine.isDetonated or mine.is_queued_for_deletion():
        return
    mine._coop_detonate_suppressed = true
    mine.InstantDetonate()
    mine._coop_detonate_suppressed = false


func RequestGrenadeThrow(throwPath: String, handlePath: String, pos: Vector3, rotDeg: Vector3, vel: Vector3, angVel: Vector3):
    if !_pm()._net().IsActive():
        return
    var origin_id = multiplayer.get_unique_id()
    if multiplayer.is_server():
        BroadcastGrenadeThrow.rpc(origin_id, throwPath, handlePath, pos, rotDeg, vel, angVel)
    else:
        SubmitGrenadeThrow.rpc_id(1, throwPath, handlePath, pos, rotDeg, vel, angVel)


@rpc("any_peer", "reliable", "call_remote")
func SubmitGrenadeThrow(throwPath: String, handlePath: String, pos: Vector3, rotDeg: Vector3, vel: Vector3, angVel: Vector3):
    if !multiplayer.is_server():
        return
    var origin_id = multiplayer.get_remote_sender_id()
    _spawn_grenade_locally(throwPath, handlePath, pos, rotDeg, vel, angVel)
    BroadcastGrenadeThrow.rpc(origin_id, throwPath, handlePath, pos, rotDeg, vel, angVel)


@rpc("authority", "reliable", "call_remote")
func BroadcastGrenadeThrow(origin_id: int, throwPath: String, handlePath: String, pos: Vector3, rotDeg: Vector3, vel: Vector3, angVel: Vector3):
    if multiplayer.get_unique_id() == origin_id:
        return
    _spawn_grenade_locally(throwPath, handlePath, pos, rotDeg, vel, angVel)


func _spawn_grenade_locally(throwPath: String, handlePath: String, pos: Vector3, rotDeg: Vector3, vel: Vector3, angVel: Vector3):
    var throwScene = load(throwPath)
    if !throwScene:
        print("[InteractableSync] Failed to load grenade scene: " + throwPath)
        return
    var throwGrenade = throwScene.instantiate()
    throwGrenade.set_meta("_coop_remote", true)
    get_tree().get_root().add_child(throwGrenade)
    throwGrenade.position = pos
    throwGrenade.rotation_degrees = rotDeg
    throwGrenade.linear_velocity = vel
    throwGrenade.angular_velocity = angVel
    if handlePath != "":
        var handleScene = load(handlePath)
        if handleScene:
            var throwHandle = handleScene.instantiate()
            get_tree().get_root().add_child(throwHandle)
            throwGrenade.handle = throwHandle
            throwHandle.position = pos
            throwHandle.rotation_degrees = rotDeg
            throwHandle.linear_velocity = vel / 2.0
            throwHandle.angular_velocity = -angVel


@rpc("authority", "reliable", "call_remote")
func BroadcastTransitionDrain(energy: float, hydration: float):
    var gd = load("res://Resources/GameData.tres")
    if !gd:
        return
    gd.energy -= energy
    gd.hydration -= hydration


func RequestPlayerExplosionDamage(targetPeerId: int):
    if !_pm()._net().IsActive():
        return
    ApplyPlayerExplosionDamage.rpc(targetPeerId)


@rpc("authority", "reliable", "call_local")
func ApplyPlayerExplosionDamage(targetPeerId: int):
    if targetPeerId != multiplayer.get_unique_id():
        return
    var character = _pm().GetLocalCharacter()
    if character:
        character.ExplosionDamage()
