extends "res://Scripts/Interface.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func Close():

    if itemDragged:
        Drop(itemDragged)

    if container:
        StorageContainerGrid()
        ClearContainerGrid()
        container.ContainerAudio()

        if _net().IsActive():
            _pm().SyncContainerStorage(container)

        container = null

    if trader:
        if !gameData.tutorial:
            Loader.SaveTrader(trader.traderData.name)
        ResetTrading()
        ClearSupplyGrid()
        trader.PlayTraderEnd()
        trader = null

    Reset()
    ResetInput()
    HideAllUI()
    UpdateStats(false)
    tooltip.hide()
    highlight.hide()


func Drop(target):

    var map = get_tree().current_scene.get_node("/root/Map")
    var file = Database.get(target.slotData.itemData.file)

    if !file:
        print("File not found: " + target.slotData.itemData.name)
        target.queue_free()
        PlayDrop()
        return

    var dropDirection
    var dropPosition
    var dropRotation
    var dropForce = 2.5

    if trader:
        if hoverGrid == null:
            dropDirection = trader.global_transform.basis.z
            dropPosition = (trader.global_position + Vector3(0, 1.0, 0)) + dropDirection / 2
            dropRotation = Vector3(-25, trader.rotation_degrees.y + 180 + randf_range(-45, 45), 45)
    else:
        if hoverGrid == null:
            dropDirection = - camera.global_transform.basis.z
            dropPosition = (camera.global_position + Vector3(0, -0.25, 0)) + dropDirection / 2
            dropRotation = Vector3(-25, camera.rotation_degrees.y + 180 + randf_range(-45, 45), 45)
        elif hoverGrid.get_parent().name == "Inventory":
            dropDirection = - camera.global_transform.basis.z
            dropPosition = (camera.global_position + Vector3(0, -0.25, 0)) + dropDirection / 2
            dropRotation = Vector3(-25, camera.rotation_degrees.y + 180 + randf_range(-45, 45), 45)
        elif hoverGrid.get_parent().name == "Container":
            dropDirection = container.global_transform.basis.z
            dropPosition = (container.global_position + Vector3(0, 0.5, 0)) + dropDirection / 2
            dropRotation = Vector3(-25, container.rotation_degrees.y + 180 + randf_range(-45, 45), 45)


    if target.slotData.itemData.stackable:
        var boxSize = target.slotData.itemData.defaultAmount
        var boxesNeeded = ceil(float(target.slotData.amount) / float(boxSize))
        var amountLeft = target.slotData.amount

        for box in boxesNeeded:

            var amountForBox: int
            if amountLeft > boxSize:
                amountLeft -= boxSize
                amountForBox = boxSize
            else:
                amountForBox = amountLeft

            if _net().IsActive():
                var slotDict = {
                    "file": target.slotData.itemData.file,
                    "amount": amountForBox,
                    "condition": target.slotData.condition,
                    "state": target.slotData.state,
                }
                _pm().RequestPickupSpawn(slotDict, dropPosition, dropRotation, dropDirection * dropForce)
            else:
                var pickup = file.instantiate()
                map.add_child(pickup)
                pickup.position = dropPosition
                pickup.rotation_degrees = dropRotation
                pickup.linear_velocity = dropDirection * dropForce
                pickup.Unfreeze()
                var newSlotData = SlotData.new()
                newSlotData.itemData = target.slotData.itemData
                newSlotData.amount = amountForBox
                pickup.slotData.Update(newSlotData)

    else:

        if _net().IsActive():
            var slotDict = _pm().SerializeSlotData(target.slotData)
            _pm().RequestPickupSpawn(slotDict, dropPosition, dropRotation, dropDirection * dropForce)
        else:
            var pickup = file.instantiate()
            map.add_child(pickup)
            pickup.position = dropPosition
            pickup.rotation_degrees = dropRotation
            pickup.linear_velocity = dropDirection * dropForce
            pickup.Unfreeze()
            pickup.slotData.Update(target.slotData)
            pickup.UpdateAttachments()

    target.reparent(self)
    target.queue_free()
    PlayDrop()
    UpdateStats(true)


func ContextPlace():

    var net = _net()
    var pm = _pm()

    if !net || !net.IsActive():
        super()
        return

    var file = Database.get(contextItem.slotData.itemData.file)
    if !file:
        print("File not found: " + contextItem.slotData.itemData.name)
        return

    var dropDirection = - camera.global_transform.basis.z
    var dropPosition = (camera.global_position + Vector3(0, -0.25, 0)) + dropDirection / 2
    var dropRotation = Vector3(-25, camera.rotation_degrees.y + 180 + randf_range(-45, 45), 45)
    var dropForce = 1.0

    var slotDict = pm.SerializeSlotData(contextItem.slotData)
    pm.RequestPickupSpawn(slotDict, dropPosition, dropRotation, dropDirection * dropForce)

    if contextGrid:
        contextGrid.Pick(contextItem)

    contextItem.reparent(self)
    contextItem.queue_free()

    if contextSlot:
        rigManager.UpdateRig(false)
        contextSlot.hint.show()

    Reset()
    HideContext()
    PlayClick()
    UIManager.ToggleInterface()
