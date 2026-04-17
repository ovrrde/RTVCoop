extends "res://Scripts/Door.gd"

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
    if _net().IsActive() && !multiplayer.is_server():
        if key && locked:
            CheckKey()
            if locked:
                return
            _pm()._interactable_sync().RequestDoorUnlock.rpc_id(1, get_path())
            return
        if isOccupied:
            return
        _pm()._interactable_sync().RequestDoorToggle.rpc_id(1, get_path())
        return

    if key && locked:
        CheckKey()
        if !locked && _net().IsActive() && multiplayer.is_server():
            _pm()._interactable_sync().BroadcastDoorUnlock.rpc(get_path())
        return

    if isOccupied:
        return

    var newOpen = !isOpen
    ApplyDoorState(newOpen)

    if _net().IsActive() && multiplayer.is_server():
        _pm()._interactable_sync().BroadcastDoorState.rpc(get_path(), newOpen)


func ApplyDoorState(newOpen: bool):
    isOpen = newOpen
    animationTime += 4.0
    handleMoving = true
    if openAngle.y > 0.0: handleTarget = Vector3(0, 0, -45)
    else: handleTarget = Vector3(0, 0, 45)
    PlayDoor()


func ApplyDoorUnlock():
    locked = false
    if linked:
        linked.locked = false
    PlayUnlock()
