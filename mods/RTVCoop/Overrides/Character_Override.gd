extends "res://Scripts/Character.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func Death():
    if _net().IsActive():
        CoopRespawn()
        return

    super()


func CoopRespawn():

    _pm().NotifyPlayerDeath(multiplayer.get_unique_id())

    var deathPos: Vector3 = get_parent().global_position

    PlayDeathAudio()
    audio.breathing.stop()
    audio.heartbeat.stop()
    gameData.health = 0
    gameData.isDead = true
    gameData.freeze = true

    var iface = _pm().GetLocalInterface()

    var deathItems: Array = []
    if iface:
        for item in iface.inventoryGrid.get_children():
            var d = _pm().SerializeSlotData(item.slotData)
            deathItems.append(d)
        for item in iface.inventoryGrid.get_children():
            iface.inventoryGrid.Pick(item)
            item.queue_free()

        for equipmentSlot in iface.equipment.get_children():
            if equipmentSlot is Slot and equipmentSlot.get_child_count() != 0:
                var slotItem = equipmentSlot.get_child(0)
                var d = _pm().SerializeSlotData(slotItem.slotData)
                deathItems.append(d)
                slotItem.queue_free()
                equipmentSlot.hint.show()

        for item in iface.catalogGrid.get_children():
            var d = _pm().SerializeSlotData(item.slotData)
            deathItems.append(d)
        for item in iface.catalogGrid.get_children():
            iface.catalogGrid.Pick(item)
            item.queue_free()

        iface.UpdateStats(false)

        if iface.activeProgress and is_instance_valid(iface.activeProgress):
            iface.activeProgress.queue_free()
        iface.activeProgress = null
        iface.isCrafting = false

    rigManager.ClearRig()

    if deathItems.size() > 0:
        if multiplayer.is_server():
            _pm().SpawnDeathContainer.rpc(deathPos, deathItems)
        else:
            _pm().SubmitDeathContainer.rpc_id(1, deathPos, deathItems)

    Loader.FadeIn()

    await get_tree().create_timer(5.0).timeout

    var controller = get_parent()
    var respawnPos = controller.global_position + Vector3(0, 1, 0)

    var transitions = get_tree().get_nodes_in_group("Transition")
    var bestTransition = null
    var bestDist = INF
    for transition in transitions:
        if !transition.owner or !transition.owner.get("spawn"):
            continue
        var d = controller.global_position.distance_squared_to(transition.owner.global_position)
        if d < bestDist:
            bestDist = d
            bestTransition = transition.owner

    if bestTransition and bestTransition.spawn:
        respawnPos = bestTransition.spawn.global_position + Vector3(0, 0.5, 0)

    controller.global_position = respawnPos
    controller.velocity = Vector3.ZERO

    gameData.health = 100
    gameData.bodyStamina = 100
    gameData.armStamina = 100
    gameData.oxygen = 100

    gameData.energy = clampf(gameData.energy, 25.0, 100.0)
    gameData.hydration = clampf(gameData.hydration, 25.0, 100.0)
    gameData.mental = clampf(gameData.mental, 25.0, 100.0)
    gameData.temperature = clampf(gameData.temperature, 25.0, 100.0)

    gameData.bleeding = false
    gameData.fracture = false
    gameData.burn = false
    gameData.frostbite = false
    gameData.insanity = false
    gameData.rupture = false
    gameData.headshot = false
    gameData.starvation = false
    gameData.dehydration = false
    gameData.overweight = false
    gameData.poisoning = false

    gameData.isDead = false
    gameData.freeze = false
    gameData.damage = false
    gameData.impact = false

    # Coop respawns in-place; vanilla resets these via scene reload.
    gameData.isOccupied = false
    gameData.isPlacing = false
    gameData.isInserting = false
    gameData.isInspecting = false
    gameData.isReloading = false
    gameData.isChecking = false
    gameData.isClearing = false
    gameData.isDrawing = false
    gameData.isFiring = false
    gameData.isAiming = false
    gameData.isScoped = false
    gameData.isTransitioning = false
    gameData.isCaching = false
    gameData.isSleeping = false
    gameData.isCrafting = false
    gameData.jammed = false
    gameData.interaction = false
    gameData.transition = false

    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
    Loader.FadeOut()

    _pm().NotifyPlayerRespawn(multiplayer.get_unique_id())

    print("DEATH: Coop Respawn at " + str(respawnPos))
