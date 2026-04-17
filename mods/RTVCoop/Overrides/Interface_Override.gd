extends "res://Scripts/Interface.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


var _pending_placement_token: int = -1
var _pending_furniture_token: int = -1
var _pending_furniture_storage: Array = []


func Complete(data: Resource):
    if _net() and _net().IsActive() and data is TaskData and trader:
        _coop_complete_task(data)
        return
    super(data)


func _coop_complete_task(taskData):
    var pm = _pm()
    var qs = pm.get_node_or_null("QuestSync") if pm else null
    if !qs:
        super.Complete(taskData)
        return

    var trader_name: String = trader.traderData.name

    if multiplayer.is_server():
        if !trader.tasksCompleted.has(taskData.name):
            trader.tasksCompleted.append(taskData.name)
        trader.PlayTraderTask()
        Loader.Message("Task Completed: " + taskData.name, Color.GREEN)
        if !gameData.tutorial:
            Loader.SaveTrader(trader_name)
            Loader.UpdateProgression()
        qs.coop_trader_state[trader_name] = trader.tasksCompleted.duplicate()
        qs._persist_host()
        qs.BroadcastTaskCompletion.rpc(trader_name, taskData.name)
    else:
        if !qs.has_state_for(trader_name):
            Loader.Message("Syncing trader state… try again in a moment.", Color.ORANGE)
            return
        if qs.get_completed(trader_name).has(taskData.name):
            Loader.Message("Task already completed.", Color.ORANGE)
            return
        if !trader.tasksCompleted.has(taskData.name):
            trader.tasksCompleted.append(taskData.name)
        trader.PlayTraderTask()
        Loader.Message("Task Completed: " + taskData.name, Color.GREEN)
        qs.SubmitTaskCompletion.rpc_id(1, trader_name, taskData.name)

    UpdateTraderInfo()
    DestroyInputItems(taskData)
    GetOutputItems()
    ResetInput()


func Close():

    if itemDragged:
        Drop(itemDragged)

    if container:
        StorageContainerGrid()
        ClearContainerGrid()
        container.ContainerAudio()

        if _net().IsActive():
            _pm().SyncContainerStorage(container)
            _pm().ReleaseContainerLock(container)

            var is_death_stash = container.containerName == "Death Stash"
            var is_empty = containerGrid.get_children().size() == 0
            if is_death_stash and is_empty:
                var cid = _pm()._coop_container_id(container)
                if multiplayer.is_server():
                    _pm().BroadcastDeathStashRemove.rpc(cid)
                else:
                    _pm().SubmitDeathStashRemove.rpc_id(1, cid)

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

    if _net().IsActive() and !multiplayer.is_server():
        _pm().SaveClientCharacterBuffer()


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

    if gameData.decor:
        _coop_context_place_furniture()
        return

    if !multiplayer.is_server():
        _coop_client_context_place()
        return

    var file = Database.get(contextItem.slotData.itemData.file)
    if !file:
        print("File not found: " + contextItem.slotData.itemData.name)
        return

    var uuid: int = pm.GenerateUuid()
    var slotDict: Dictionary = pm.SerializeSlotData(contextItem.slotData)

    var initialPos: Vector3 = camera.global_position + (-camera.global_transform.basis.z * 1.0)
    pm.BroadcastPickupSpawn.rpc(uuid, slotDict, initialPos, Vector3.ZERO, Vector3.ZERO)

    if !pm.worldItems.has(uuid):
        print("[Interface] ContextPlace: pickup not in worldItems after BroadcastPickupSpawn")
        return

    var pickup = pm.worldItems[uuid]

    placer.ContextPlace(pickup)

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


func _coop_context_place_furniture():
    var pm = _pm()
    var filename: String = contextItem.slotData.itemData.file
    var scene = Database.get(filename)
    if !scene:
        print("File not found: " + contextItem.slotData.itemData.name)
        return

    var initialPos: Vector3 = camera.global_position + (-camera.global_transform.basis.z * 2.0)
    var initialRot: Vector3 = Vector3.ZERO
    var initialScale: Vector3 = Vector3.ONE

    if multiplayer.is_server():
        var fs = pm._furniture_sync()
        var fid: int = pm.GenerateFurnitureId()
        fs.BroadcastFurnitureSpawn.rpc(fid, filename, initialPos, initialRot, initialScale)

        var root = pm._find_furniture_by_id(fid)
        if !root:
            print("[Interface] ContextPlace decor: furniture " + str(fid) + " not in worldFurniture after spawn")
            return

        # Preserve container storage if the player was placing a stored
        # cabinet, then sync to every other peer.
        if root is LootContainer and contextItem.slotData.storage.size() != 0:
            root.storage = contextItem.slotData.storage
            root.storaged = true
            pm.SyncContainerStorage(root)

        placer.ContextPlace(root)
    else:
        var fs = pm._furniture_sync()
        if _pending_furniture_token != -1 and fs.furniture_token_received.is_connected(_on_furniture_token_received):
            fs.furniture_token_received.disconnect(_on_furniture_token_received)

        _pending_furniture_token = pm.NextFurnitureToken()
        _pending_furniture_storage = contextItem.slotData.storage.duplicate() if contextItem.slotData.storage.size() > 0 else []
        fs.furniture_token_received.connect(_on_furniture_token_received)
        fs.RequestFurnitureSpawn.rpc_id(1, _pending_furniture_token, filename, initialPos, initialRot, initialScale)

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


func _on_furniture_token_received(token: int, fid: int):
    if token != _pending_furniture_token:
        return

    _pending_furniture_token = -1
    var pm = _pm()
    var fs = pm._furniture_sync() if pm else null
    if fs and fs.furniture_token_received.is_connected(_on_furniture_token_received):
        fs.furniture_token_received.disconnect(_on_furniture_token_received)

    if !pm:
        _pending_furniture_storage = []
        return

    var root = pm._find_furniture_by_id(fid)
    if !root:
        print("[Interface] furniture_token_received: fid " + str(fid) + " not in worldFurniture")
        _pending_furniture_storage = []
        return

    if root is LootContainer and _pending_furniture_storage.size() > 0:
        root.storage = _pending_furniture_storage
        root.storaged = true
        pm.SyncContainerStorage(root)
    _pending_furniture_storage = []

    placer.ContextPlace(root)


func _coop_client_context_place():
    var pm = _pm()
    var file = Database.get(contextItem.slotData.itemData.file)
    if !file:
        print("File not found: " + contextItem.slotData.itemData.name)
        return

    var slotDict: Dictionary = pm.SerializeSlotData(contextItem.slotData)
    var initialPos: Vector3 = camera.global_position + (-camera.global_transform.basis.z * 1.0)

    if _pending_placement_token != -1 and pm.placement_token_received.is_connected(_on_placement_token_received):
        pm.placement_token_received.disconnect(_on_placement_token_received)

    _pending_placement_token = pm.NextPlacementToken()
    pm.placement_token_received.connect(_on_placement_token_received)
    pm.RequestPlacementSpawn.rpc_id(1, _pending_placement_token, slotDict, initialPos)

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


func _on_placement_token_received(token: int, uuid: int):
    if token != _pending_placement_token:
        return

    _pending_placement_token = -1
    var pm = _pm()
    if pm and pm.placement_token_received.is_connected(_on_placement_token_received):
        pm.placement_token_received.disconnect(_on_placement_token_received)

    if !pm or !pm.worldItems.has(uuid):
        print("[Interface] placement_token_received: uuid " + str(uuid) + " not in worldItems")
        return

    var pickup = pm.worldItems[uuid]
    if !is_instance_valid(pickup):
        return

    placer.ContextPlace(pickup)
