extends Node

var _container_holders: Dictionary = {}


func _pm():
    return get_parent()


func _find_container_by_id(cid: int) -> LootContainer:
    for container in get_tree().get_nodes_in_group("CoopLootContainer"):
        if !is_instance_valid(container):
            continue
        if _pm()._coop_container_id(container) == cid:
            return container
    for collider in get_tree().get_nodes_in_group("Interactable"):
        if !is_instance_valid(collider):
            continue
        var node: Node = collider
        while node:
            if node is LootContainer:
                if _pm()._coop_container_id(node) == cid:
                    if !node.is_in_group("CoopLootContainer"):
                        node.add_to_group("CoopLootContainer")
                    return node
                break
            node = node.get_parent()
    return null


func SyncContainerStorage(container: LootContainer):
    if !_pm()._net().IsActive():
        return
    if !container:
        return
    var serialized: Array = []
    for slot in container.storage:
        serialized.append(_pm().SerializeSlotData(slot))
    var cid = _pm()._coop_container_id(container)
    if multiplayer.is_server():
        BroadcastContainerStorage.rpc(cid, serialized)
    else:
        SubmitContainerStorage.rpc_id(1, cid, serialized)


@rpc("any_peer", "reliable", "call_remote")
func SubmitContainerStorage(cid: int, serialized: Array):
    if !multiplayer.is_server():
        return
    var container = _find_container_by_id(cid)
    if !container:
        return
    container.storage.clear()
    for dict in serialized:
        container.storage.append(_pm().DeserializeSlotData(dict))
    container.storaged = true
    BroadcastContainerStorage.rpc(cid, serialized)


@rpc("authority", "reliable", "call_remote")
func BroadcastContainerStorage(cid: int, serialized: Array):
    var container = _find_container_by_id(cid)
    if !container:
        return
    container.storage.clear()
    for dict in serialized:
        container.storage.append(_pm().DeserializeSlotData(dict))
    container.storaged = true


func TryOpenContainer(container) -> void:
    if !container:
        return
    var cid: int = _pm()._coop_container_id(container)
    if !_pm()._net() or !_pm()._net().IsActive():
        _coop_open_container_ui(container)
        return
    if multiplayer.is_server():
        if _container_holders.has(cid) and _container_holders[cid] != 1:
            _coop_play_local_error()
            return
        _container_holders[cid] = 1
        _coop_open_container_ui(container)
        return
    RequestContainerOpen.rpc_id(1, cid)


func ReleaseContainerLock(container) -> void:
    if !container:
        return
    if !_pm()._net() or !_pm()._net().IsActive():
        return
    var cid: int = _pm()._coop_container_id(container)
    if multiplayer.is_server():
        if _container_holders.has(cid) and _container_holders[cid] == 1:
            _container_holders.erase(cid)
        return
    ReleaseContainer.rpc_id(1, cid)


func _coop_open_container_ui(container) -> void:
    var ui_root = get_tree().current_scene.get_node_or_null("/root/Map/Core/UI")
    if ui_root and ui_root.has_method("OpenContainer"):
        _pm()._container_open_bypassed = true
        ui_root.OpenContainer(container)
        _pm()._container_open_bypassed = false
    if container.has_method("ContainerAudio"):
        container.ContainerAudio()


func _coop_play_local_error() -> void:
    var iface = _pm().GetLocalInterface()
    if iface and iface.has_method("PlayError"):
        iface.PlayError()


func release_holders_for_peer(peer_id: int):
    for cid in _container_holders.keys().duplicate():
        if _container_holders[cid] == peer_id:
            _container_holders.erase(cid)


@rpc("any_peer", "reliable", "call_remote")
func RequestContainerOpen(cid: int):
    if !multiplayer.is_server():
        return
    var sender_id: int = multiplayer.get_remote_sender_id()
    if _container_holders.has(cid) and _container_holders[cid] != sender_id:
        DenyContainerOpen.rpc_id(sender_id, cid)
        return
    _container_holders[cid] = sender_id
    GrantContainerOpen.rpc_id(sender_id, cid)


@rpc("authority", "reliable", "call_remote")
func GrantContainerOpen(cid: int):
    var container = _find_container_by_id(cid)
    if !container:
        return
    _coop_open_container_ui(container)


@rpc("authority", "reliable", "call_remote")
func DenyContainerOpen(_cid: int):
    _coop_play_local_error()


@rpc("any_peer", "reliable", "call_remote")
func ReleaseContainer(cid: int):
    if !multiplayer.is_server():
        return
    var sender_id: int = multiplayer.get_remote_sender_id()
    if _container_holders.has(cid) and _container_holders[cid] == sender_id:
        _container_holders.erase(cid)
