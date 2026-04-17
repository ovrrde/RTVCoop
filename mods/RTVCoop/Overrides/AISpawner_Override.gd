extends "res://Scripts/AISpawner.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func _ready():
    super()


func _physics_process(delta):
    if _net().IsActive() && !multiplayer.is_server():
        return
    super(delta)


func GenerateAIVariant(agent) -> Dictionary:
    # Use content identifiers (item file paths, material resource paths)
    # rather than child-array indices. A different mod loaded on a client
    # may add or remove weapon/backpack/clothing entries on the AI prefab,
    # which shifts indices and causes clients to equip the wrong item.
    # File- and resource-path-based lookup survives those differences.
    var variant: Dictionary = {}

    if agent.weapons && agent.weapons.get_child_count() > 0:
        var index = randi_range(0, agent.weapons.get_child_count() - 1)
        var chosenWeapon = agent.weapons.get_child(index)
        variant["weaponCondition"] = randi_range(5, 50)
        if chosenWeapon && chosenWeapon.slotData && chosenWeapon.slotData.itemData:
            variant["weaponFile"] = chosenWeapon.slotData.itemData.file
            var magSize = chosenWeapon.slotData.itemData.magazineSize
            variant["weaponAmount"] = randi_range(1, max(1, magSize))

    variant["backpackRoll"] = randi_range(0, 100)
    if variant["backpackRoll"] < 10 && agent.backpacks && agent.backpacks.get_child_count() > 0:
        var bpIndex = randi_range(0, agent.backpacks.get_child_count() - 1)
        var chosenBackpack = agent.backpacks.get_child(bpIndex)
        if chosenBackpack and chosenBackpack.has_method("get") and chosenBackpack.get("slotData") and chosenBackpack.slotData.itemData:
            variant["backpackFile"] = chosenBackpack.slotData.itemData.file
        else:
            variant["backpackFile"] = chosenBackpack.name if chosenBackpack else ""

    if agent.clothing && agent.clothing.size() > 0:
        var clothIndex = randi_range(0, agent.clothing.size() - 1)
        var clothMat = agent.clothing[clothIndex]
        if clothMat and clothMat.resource_path != "":
            variant["clothingPath"] = clothMat.resource_path

    return variant


func SpawnWanderer():
    if _net().IsActive() and !multiplayer.is_server():
        return

    if APool.get_child_count() == 0:
        print("AI Spawner: APool ended (Wanderer)")
        return

    var validPoints: Array[Node3D]
    var referencePos = gameData.playerPosition
    if _net().IsActive():
        referencePos = _pm().GetNearestPlayerPosition(global_position)

    for point in spawns:
        var distanceToPlayer = point.global_position.distance_to(referencePos)
        if distanceToPlayer > spawnDistance:
            validPoints.append(point)

    if validPoints.size() != 0:
        var spawnPoint = validPoints[randi_range(0, validPoints.size() - 1)]
        var newAgent = APool.get_child(0)
        newAgent.reparent(agents)
        newAgent.global_transform = spawnPoint.global_transform
        newAgent.currentPoint = spawnPoint

        var variant: Dictionary = {}
        if _net().IsActive() && multiplayer.is_server():
            variant = GenerateAIVariant(newAgent)
        newAgent.spawnVariant = variant

        newAgent.ActivateWanderer()
        activeAgents += 1

        if _net().IsActive() && multiplayer.is_server():
            var uuid = _pm().GenerateAiUuid()
            newAgent.set_meta("network_uuid", uuid)
            _pm().worldAI[uuid] = newAgent
            _pm()._ai_sync().BroadcastAISpawn.rpc(uuid, "Wanderer", spawnPoint.global_position, spawnPoint.global_rotation, variant)

        print("AI Spawner: Agent active (Wanderer)")
    else:
        print("AI Spawner: No valid spawn points (Wanderer)")


func SpawnGuard():
    if _net().IsActive() and !multiplayer.is_server():
        return

    if APool.get_child_count() == 0:
        print("AI Spawner: APool ended (Guard)")
        return

    if patrols.size() != 0:
        var patrolPoint = patrols[randi_range(0, patrols.size() - 1)]
        var newAgent = APool.get_child(0)
        newAgent.reparent(agents)
        newAgent.global_transform = patrolPoint.global_transform
        newAgent.currentPoint = patrolPoint

        var variant: Dictionary = {}
        if _net().IsActive() && multiplayer.is_server():
            variant = GenerateAIVariant(newAgent)
        newAgent.spawnVariant = variant

        newAgent.ActivateGuard()
        activeAgents += 1

        if _net().IsActive() && multiplayer.is_server():
            var uuid = _pm().GenerateAiUuid()
            newAgent.set_meta("network_uuid", uuid)
            _pm().worldAI[uuid] = newAgent
            _pm()._ai_sync().BroadcastAISpawn.rpc(uuid, "Guard", patrolPoint.global_position, patrolPoint.global_rotation, variant)

        print("AI Spawner: Agent active (Guard)")
    else:
        print("AI Spawner: No valid patrol points (Guard)")


func SpawnHider():
    if _net().IsActive() and !multiplayer.is_server():
        return

    if APool.get_child_count() == 0:
        print("Spawn blocked (Hider): APool ended")
        return

    var randomIndex = randi_range(0, hides.size() - 1)
    var hidePoint = hides[randomIndex]
    var newAgent = APool.get_child(0)
    newAgent.reparent(agents)
    newAgent.global_transform = hidePoint.global_transform
    newAgent.currentPoint = hidePoint

    var variant: Dictionary = {}
    if _net().IsActive() && multiplayer.is_server():
        variant = GenerateAIVariant(newAgent)
    newAgent.spawnVariant = variant

    newAgent.ActivateHider()
    activeAgents += 1

    if _net().IsActive() && multiplayer.is_server():
        var uuid = _pm().GenerateAiUuid()
        newAgent.set_meta("network_uuid", uuid)
        _pm().worldAI[uuid] = newAgent
        _pm()._ai_sync().BroadcastAISpawn.rpc(uuid, "Hider", hidePoint.global_position, hidePoint.global_rotation, variant)

    print("Hider spawned")


func SpawnMinion(spawnPosition):
    if _net().IsActive() and !multiplayer.is_server():
        return

    if APool.get_child_count() == 0:
        return

    var newAgent = APool.get_child(0)
    newAgent.reparent(agents)
    newAgent.global_position = spawnPosition
    newAgent.currentPoint = waypoints.pick_random()
    newAgent.lastKnownLocation = gameData.playerPosition

    var variant: Dictionary = {}
    if _net().IsActive() and multiplayer.is_server():
        variant = GenerateAIVariant(newAgent)
    newAgent.spawnVariant = variant

    newAgent.ActivateMinion()
    activeAgents += 1

    if _net().IsActive() and multiplayer.is_server():
        var uuid = _pm().GenerateAiUuid()
        newAgent.set_meta("network_uuid", uuid)
        _pm().worldAI[uuid] = newAgent
        _pm()._ai_sync().BroadcastAISpawn.rpc(uuid, "Minion", spawnPosition, Vector3.ZERO, variant)

    print("AI Spawner: Agent active (Minion)")


func SpawnBoss(spawnPosition):
    if _net().IsActive() and !multiplayer.is_server():
        return

    if BPool.get_child_count() == 0:
        return

    var newBoss = BPool.get_child(0)
    newBoss.reparent(agents)
    newBoss.global_position = spawnPosition
    newBoss.currentPoint = waypoints.pick_random()
    newBoss.lastKnownLocation = gameData.playerPosition

    var variant: Dictionary = {}
    if _net().IsActive() and multiplayer.is_server():
        variant = GenerateAIVariant(newBoss)
    newBoss.spawnVariant = variant

    newBoss.ActivateBoss()
    activeAgents += 1

    if _net().IsActive() and multiplayer.is_server():
        var uuid = _pm().GenerateAiUuid()
        newBoss.set_meta("network_uuid", uuid)
        _pm().worldAI[uuid] = newBoss
        _pm()._ai_sync().BroadcastAISpawn.rpc(uuid, "Boss", spawnPosition, Vector3.ZERO, variant)

    print("AI Spawner: Agent active (Boss)")
