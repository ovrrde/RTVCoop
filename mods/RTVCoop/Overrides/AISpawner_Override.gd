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
    var variant: Dictionary = {}

    if agent.weapons && agent.weapons.get_child_count() > 0:
        var index = randi_range(0, agent.weapons.get_child_count() - 1)
        variant["weaponIndex"] = index
        variant["weaponCondition"] = randi_range(5, 50)
        var chosenWeapon = agent.weapons.get_child(index)
        if chosenWeapon && chosenWeapon.slotData && chosenWeapon.slotData.itemData:
            var magSize = chosenWeapon.slotData.itemData.magazineSize
            variant["weaponAmount"] = randi_range(1, max(1, magSize))

    variant["backpackRoll"] = randi_range(0, 100)
    if variant["backpackRoll"] < 10 && agent.backpacks && agent.backpacks.get_child_count() > 0:
        variant["backpackIndex"] = randi_range(0, agent.backpacks.get_child_count() - 1)

    if agent.clothing && agent.clothing.size() > 0:
        variant["clothingIndex"] = randi_range(0, agent.clothing.size() - 1)

    return variant


func SpawnWanderer():
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
            _pm().BroadcastAISpawn.rpc(uuid, "Wanderer", spawnPoint.get_path(), variant)

        print("AI Spawner: Agent active (Wanderer)")
    else:
        print("AI Spawner: No valid spawn points (Wanderer)")


func SpawnGuard():
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
            _pm().BroadcastAISpawn.rpc(uuid, "Guard", patrolPoint.get_path(), variant)

        print("AI Spawner: Agent active (Guard)")
    else:
        print("AI Spawner: No valid patrol points (Guard)")


func SpawnHider():
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
        _pm().BroadcastAISpawn.rpc(uuid, "Hider", hidePoint.get_path(), variant)

    print("Hider spawned")
