extends Node

var _net_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c


var _steam_lobby_c: Node
func _steam_lobby():
    if !_steam_lobby_c: _steam_lobby_c = get_tree().root.get_node_or_null("SteamLobby")
    return _steam_lobby_c


var REMOTE_PLAYER: PackedScene = null
const BROADCAST_RATE = 20.0
const SIMULATION_BROADCAST_RATE = 1.0
const AI_BROADCAST_RATE = 20.0


var gameData = preload("res://Resources/GameData.tres")


var remotePlayers: Dictionary = {}
var peer_names: Dictionary = {}
var broadcastAccumulator: float = 0.0
var simulationAccumulator: float = 0.0
var aiAccumulator: float = 0.0

# In-memory CharacterSave snapshot for coop clients — replaces disk roundtrip.
var coopCharacterBuffer: CharacterSave = null


func _ready():
    REMOTE_PLAYER = load("res://mods/RTVCoop/Scenes/RemotePlayer.tscn")
    if !REMOTE_PLAYER:
        print("[PlayerManager] ERROR: Could not load RemotePlayer.tscn")
    else:
        print("[PlayerManager] RemotePlayer.tscn loaded OK")
    _net().disconnected.connect(_on_disconnected)
    _net().hosted.connect(_on_hosted)
    _net().joined.connect(_on_joined)
    _net().peer_joined.connect(_on_peer_joined_for_names)
    _net().peer_left.connect(_on_peer_left_for_names)


func _physics_process(delta):

    if !_net().IsActive():
        return


    if pendingSceneChange != "" && !multiplayer.is_server():
        pendingSceneTimer += delta
        if pendingSceneTimer >= SCENE_CHANGE_TIMEOUT:
            var curMap = GetMap()
            var curSceneName = ""
            if curMap:
                curSceneName = str(curMap.get("mapName")) if curMap.get("mapName") else ""
            if curSceneName == pendingSceneChange:
                print("[PlayerManager] SceneChange timeout but already in " + pendingSceneChange + " — clearing")
            else:
                print("[PlayerManager] HostSceneReady timeout (" + str(SCENE_CHANGE_TIMEOUT) + "s) — loading " + pendingSceneChange)
                SaveClientCharacterBuffer()
                Loader.LoadScene(pendingSceneChange)
            pendingSceneChange = ""
            pendingSceneTimer = 0.0


    ScanIfNeeded(delta)
    ReconcilePuppets()


    simulationAccumulator += delta
    if simulationAccumulator >= 1.0 / SIMULATION_BROADCAST_RATE:
        simulationAccumulator = 0.0
        if multiplayer.is_server() && Simulation.simulate:
            BroadcastSimulationState.rpc(
                Simulation.time,
                Simulation.day,
                Simulation.weather,
                Simulation.weatherTime,
                Simulation.season
            )


    aiAccumulator += delta
    if aiAccumulator >= 1.0 / AI_BROADCAST_RATE:
        aiAccumulator = 0.0
        if multiplayer.is_server():
            BroadcastAIPositions()


    if !multiplayer.is_server():
        for uuid in aiTargets:
            if !worldAI.has(uuid):
                continue
            var ai = worldAI[uuid]
            if !is_instance_valid(ai) || !ai.is_inside_tree():
                continue
            var target = aiTargets[uuid]
            ai.global_position = ai.global_position.lerp(target.pos, AI_LERP_SPEED * delta)
            ai.global_rotation.y = lerp_angle(ai.global_rotation.y, target.rot.y, AI_LERP_SPEED * delta)


    broadcastAccumulator += delta

    if broadcastAccumulator < 1.0 / BROADCAST_RATE:
        return

    broadcastAccumulator = 0.0


    BroadcastLocalState()


func ReconcilePuppets():

    var map = GetMap()


    if !map:

        for id in remotePlayers.keys().duplicate():
            if !is_instance_valid(remotePlayers[id]):
                remotePlayers.erase(id)
        return


    var myId = multiplayer.get_unique_id()

    # peer_names is server-authoritative and contains every active peer on
    # every player. multiplayer.get_peers() only returns the server on clients
    # due to Godot's star topology, so it misses other clients entirely.
    var knownPeers: Array = peer_names.keys()


    for peerId in knownPeers:

        if peerId == myId:
            continue


        if !remotePlayers.has(peerId) || !is_instance_valid(remotePlayers[peerId]):

            if remotePlayers.has(peerId):
                remotePlayers.erase(peerId)

            SpawnPuppet(peerId)


    var toRemove = []

    for peerId in remotePlayers.keys():
        if !(peerId in knownPeers):
            toRemove.append(peerId)


    for peerId in toRemove:
        DespawnPuppet(peerId)


const PASSTHROUGH_MAPS := ["Cabin"]


func SpawnPuppet(peerId: int):

    var map = GetMap()

    if !map:
        return


    var puppet = REMOTE_PLAYER.instantiate()
    puppet.peer_id = peerId
    puppet.name = "RemotePlayer_" + str(peerId)


    map.add_child(puppet)
    remotePlayers[peerId] = puppet


    var mapName: String = str(map.get("mapName")) if map.get("mapName") else ""
    if mapName in PASSTHROUGH_MAPS:
        var local_ctrl = GetLocalController()
        if local_ctrl and puppet is PhysicsBody3D:
            local_ctrl.add_collision_exception_with(puppet)


    print("PlayerManager: spawned puppet for peer " + str(peerId))


func DespawnPuppet(peerId: int):

    if !remotePlayers.has(peerId):
        return


    var puppet = remotePlayers[peerId]

    if is_instance_valid(puppet):
        puppet.queue_free()


    remotePlayers.erase(peerId)


    print("PlayerManager: despawned puppet for peer " + str(peerId))


func _on_disconnected():

    for id in remotePlayers.keys().duplicate():
        DespawnPuppet(id)
    peer_names.clear()
    coopCharacterBuffer = null


# ─── Display name sync ────────────────────────────────────────────────────────

func GetMyDisplayName() -> String:
    var lobby = _steam_lobby()
    if lobby and lobby.available:
        return lobby.MyName()
    return "Player " + str(multiplayer.get_unique_id())


func GetPlayerName(peer_id: int) -> String:
    if peer_names.has(peer_id):
        return peer_names[peer_id]
    return "Player " + str(peer_id)


func _on_hosted():
    peer_names.clear()
    peer_names[1] = GetMyDisplayName()
    print("[PlayerManager] Host name registered: " + peer_names[1])


func _on_joined():
    var my_name = GetMyDisplayName()
    print("[PlayerManager] Reporting name to host: " + my_name)
    ReportPlayerName.rpc_id(1, my_name)


func _on_peer_joined_for_names(_id: int):
    # Server side: a new client connected. Resend the full registry to all
    # peers so the new arrival learns existing names. We delay briefly so
    # the client's own ReportPlayerName RPC has a chance to land first.
    if !multiplayer.is_server():
        return
    await get_tree().create_timer(0.5, false).timeout
    SyncNameRegistry.rpc(peer_names)


func _on_peer_left_for_names(id: int):
    if !multiplayer.is_server():
        return
    if peer_names.has(id):
        peer_names.erase(id)
    SyncNameRegistry.rpc(peer_names)


@rpc("any_peer", "call_remote", "reliable")
func ReportPlayerName(name: String):
    if !multiplayer.is_server():
        return
    var sender_id = multiplayer.get_remote_sender_id()
    peer_names[sender_id] = name
    print("[PlayerManager] Registered peer " + str(sender_id) + " as '" + name + "'")
    SyncNameRegistry.rpc(peer_names)


@rpc("authority", "call_remote", "reliable")
func SyncNameRegistry(registry: Dictionary):
    peer_names = registry.duplicate()
    print("[PlayerManager] Name registry synced (" + str(peer_names.size()) + " players)")


# ─── Coop client character buffer ────────────────────────────────────────────

func SaveClientCharacterBuffer():
    if multiplayer.is_server():
        return

    var interface = get_tree().current_scene.get_node_or_null("/root/Map/Core/UI/Interface")
    if !interface:
        return

    var character: CharacterSave = CharacterSave.new()

    character.initialSpawn = false
    character.startingKit = null

    character.health = gameData.health
    character.energy = gameData.energy
    character.hydration = gameData.hydration
    character.mental = gameData.mental
    character.temperature = gameData.temperature
    character.bodyStamina = gameData.bodyStamina
    character.armStamina = gameData.armStamina
    character.overweight = gameData.overweight
    character.starvation = gameData.starvation
    character.dehydration = gameData.dehydration
    character.bleeding = gameData.bleeding
    character.fracture = gameData.fracture
    character.burn = gameData.burn
    character.frostbite = gameData.frostbite
    character.insanity = gameData.insanity
    character.rupture = gameData.rupture
    character.headshot = gameData.headshot

    character.cat = gameData.cat
    character.catFound = gameData.catFound
    character.catDead = gameData.catDead

    character.primary = gameData.primary
    character.secondary = gameData.secondary
    character.knife = gameData.knife
    character.grenade1 = gameData.grenade1
    character.grenade2 = gameData.grenade2
    character.flashlight = gameData.flashlight
    character.NVG = gameData.NVG
    character.weaponPosition = gameData.weaponPosition

    character.inventory.clear()
    character.equipment.clear()
    character.catalog.clear()

    for item in interface.inventoryGrid.get_children():
        var newSlotData = SlotData.new()
        newSlotData.Update(item.slotData)
        newSlotData.GridSave(item.position, item.rotated)
        character.inventory.append(newSlotData)

    for equipmentSlot in interface.equipment.get_children():
        if equipmentSlot is Slot && equipmentSlot.get_child_count() != 0:
            var slotItem = equipmentSlot.get_child(0)
            var newSlotData = SlotData.new()
            newSlotData.Update(slotItem.slotData)
            newSlotData.SlotSave(equipmentSlot.name)
            character.equipment.append(newSlotData)

    for item in interface.catalogGrid.get_children():
        var newSlotData = SlotData.new()
        newSlotData.Update(item.slotData)
        newSlotData.GridSave(item.position, item.rotated)
        if item.slotData.storage.size() != 0:
            newSlotData.storage = item.slotData.storage
        character.catalog.append(newSlotData)

    coopCharacterBuffer = character
    print("[PlayerManager] COOP SAVE: Character -> buffer (" + str(character.inventory.size()) + " inv, " + str(character.equipment.size()) + " eqp, " + str(character.catalog.size()) + " cat)")


func GiveClientStarterKit():
    # Mirrors the initialSpawn path in vanilla Loader.LoadCharacter. Fires
    # on a client's first coop scene entry (buffer is null). Field access
    # on the Loader autoload works even though method overrides don't.
    if multiplayer.is_server():
        return

    await get_tree().create_timer(0.1).timeout

    var interface = get_tree().current_scene.get_node_or_null("/root/Map/Core/UI/Interface")
    if !interface:
        print("[PlayerManager] GiveClientStarterKit: no interface, skipping")
        return

    if !Loader or Loader.startingKits.size() == 0:
        print("[PlayerManager] GiveClientStarterKit: Loader.startingKits empty")
        return

    var kit: LootTable = Loader.startingKits.pick_random()
    if !kit or kit.items.size() == 0:
        print("[PlayerManager] GiveClientStarterKit: picked kit has no items")
        return

    print("[PlayerManager] Giving client starter kit: " + str(kit.items.size()) + " items")

    for item in kit.items:
        var newSlotData = SlotData.new()
        newSlotData.itemData = item
        if newSlotData.itemData.stackable:
            newSlotData.amount = newSlotData.itemData.defaultAmount
        interface.Create(newSlotData, interface.inventoryGrid, false)

    interface.UpdateStats(false)


func LoadClientCharacterBuffer():
    if multiplayer.is_server():
        return
    if coopCharacterBuffer == null:
        return

    await get_tree().create_timer(0.1).timeout

    var character: CharacterSave = coopCharacterBuffer
    var rigManager = get_tree().current_scene.get_node_or_null("/root/Map/Core/Camera/Manager")
    var interface = get_tree().current_scene.get_node_or_null("/root/Map/Core/UI/Interface")
    var flashlight = get_tree().current_scene.get_node_or_null("/root/Map/Core/Camera/Flashlight")
    var NVG = get_tree().current_scene.get_node_or_null("/root/Map/Core/UI/NVG")

    if !interface or !rigManager:
        print("[PlayerManager] COOP LOAD: interface/rigManager missing, skipping")
        return

    # Wipe any existing interface/rig state before rebuilding from the buffer.
    # ClearRig() also resets gameData.primary/secondary/knife flags.
    for child in interface.inventoryGrid.get_children():
        interface.inventoryGrid.remove_child(child)
        child.queue_free()
    for child in interface.catalogGrid.get_children():
        interface.catalogGrid.remove_child(child)
        child.queue_free()
    for equipmentSlot in interface.equipment.get_children():
        if equipmentSlot is Slot:
            for child in equipmentSlot.get_children():
                equipmentSlot.remove_child(child)
                child.queue_free()
    rigManager.ClearRig()

    await get_tree().process_frame

    for slotData in character.inventory:
        interface.LoadGridItem(slotData, interface.inventoryGrid, slotData.gridPosition)

    for slotData in character.equipment:
        interface.LoadSlotItem(slotData, slotData.slot)

    for slotData in character.catalog:
        interface.LoadGridItem(slotData, interface.catalogGrid, slotData.gridPosition)

    interface.UpdateStats(false)

    gameData.health = character.health
    gameData.energy = character.energy
    gameData.hydration = character.hydration
    gameData.mental = character.mental
    gameData.temperature = character.temperature
    gameData.bodyStamina = character.bodyStamina
    gameData.armStamina = character.armStamina
    gameData.overweight = character.overweight
    gameData.starvation = character.starvation
    gameData.dehydration = character.dehydration
    gameData.bleeding = character.bleeding
    gameData.fracture = character.fracture
    gameData.burn = character.burn
    gameData.frostbite = character.frostbite
    gameData.insanity = character.insanity
    gameData.rupture = character.rupture
    gameData.headshot = character.headshot

    gameData.cat = character.cat
    gameData.catFound = character.catFound
    gameData.catDead = character.catDead

    gameData.primary = character.primary
    gameData.secondary = character.secondary
    gameData.knife = character.knife
    gameData.grenade1 = character.grenade1
    gameData.grenade2 = character.grenade2
    gameData.flashlight = character.flashlight
    gameData.NVG = character.NVG

    if gameData.primary:
        rigManager.LoadPrimary()
        gameData.weaponPosition = character.weaponPosition
    elif gameData.secondary:
        rigManager.LoadSecondary()
        gameData.weaponPosition = character.weaponPosition
    elif gameData.knife:
        rigManager.LoadKnife()
    elif gameData.grenade1:
        rigManager.LoadGrenade1()
    elif gameData.grenade2:
        rigManager.LoadGrenade2()

    if gameData.flashlight && flashlight:
        flashlight.Load()
    if gameData.NVG && NVG:
        NVG.Load()

    print("[PlayerManager] COOP LOAD: Character <- buffer (" + str(character.inventory.size()) + " inv, " + str(character.equipment.size()) + " eqp, " + str(character.catalog.size()) + " cat)")


func BroadcastLocalState():

    var controller = GetLocalController()

    if !controller:
        return


    var state = GatherLocalAnimState(controller)


    if multiplayer.is_server():
        ApplyState.rpc(multiplayer.get_unique_id(), state)
    else:
        SubmitState.rpc_id(1, state)


func GatherLocalAnimState(controller: Node3D) -> Dictionary:

    var state := {
        "pos": controller.global_position,
        "rot": controller.global_rotation,
        "animCondition": "Guard",
        "animBlend": 0.0,
        "weapon": "rifle",
        "hasWeapon": false,
        "weaponFile": "",
    }


    if gameData.isCrouching:
        state["animCondition"] = "Hunt"
        if gameData.isMoving:
            state["animBlend"] = 1.0
        else:
            state["animBlend"] = 0.0

    elif gameData.isAiming && gameData.isMoving:
        state["animCondition"] = "Combat"
        state["animBlend"] = 1.0

    elif gameData.isAiming:
        state["animCondition"] = "Defend"
        state["animBlend"] = 0.0

    elif gameData.isMoving && gameData.weaponPosition == 1:
        state["animCondition"] = "MovementLow"
        if gameData.isRunning:
            state["animBlend"] = 2.0
        else:
            state["animBlend"] = 1.0

    elif gameData.isMoving:
        state["animCondition"] = "Movement"
        if gameData.isRunning:
            state["animBlend"] = 5.0
        elif gameData.isWalking:
            state["animBlend"] = 1.0
        else:
            state["animBlend"] = 1.0

    elif gameData.weaponPosition == 2:
        state["animCondition"] = "Defend"
        state["animBlend"] = 0.0

    else:
        state["animCondition"] = "Group"
        state["animBlend"] = 1.0


    state["weaponFile"] = ""
    state["weapon"] = "rifle"
    state["hasWeapon"] = false

    var scene = get_tree().current_scene
    var rigManager = scene.get_node_or_null("Core/Camera/Manager") if scene else null

    if rigManager:
        var weaponSlot = null
        if gameData.primary && rigManager.primarySlot && rigManager.primarySlot.get_child_count() > 0:
            weaponSlot = rigManager.primarySlot.get_child(0)
        elif gameData.secondary && rigManager.secondarySlot && rigManager.secondarySlot.get_child_count() > 0:
            weaponSlot = rigManager.secondarySlot.get_child(0)

        if weaponSlot && weaponSlot.slotData && weaponSlot.slotData.itemData:
            state["weaponFile"] = weaponSlot.slotData.itemData.file
            state["hasWeapon"] = true
            if weaponSlot.slotData.itemData.weaponType == "Pistol":
                state["weapon"] = "pistol"
            else:
                state["weapon"] = "rifle"

        elif gameData.knife && rigManager.knifeSlot && rigManager.knifeSlot.get_child_count() > 0:
            var knifeItem = rigManager.knifeSlot.get_child(0)
            if knifeItem.slotData && knifeItem.slotData.itemData:
                state["weaponFile"] = knifeItem.slotData.itemData.file
    state["isFiring"] = gameData.isFiring


    return state


@rpc("any_peer", "unreliable", "call_remote")
func SubmitState(state: Dictionary):

    if !multiplayer.is_server():
        return


    var sender = multiplayer.get_remote_sender_id()
    ApplyState.rpc(sender, state)


@rpc("authority", "unreliable", "call_local")
func ApplyState(peerId: int, state: Dictionary):

    if peerId == multiplayer.get_unique_id():
        return


    if !remotePlayers.has(peerId) || !is_instance_valid(remotePlayers.get(peerId)):
        return


    var puppet = remotePlayers[peerId]


    if !puppet.is_inside_tree():
        return


    if puppet.has_method("SetTarget"):
        puppet.SetTarget(state.get("pos", puppet.global_position), state.get("rot", puppet.global_rotation))
    else:
        puppet.global_position = state.get("pos", puppet.global_position)
        puppet.global_rotation = state.get("rot", puppet.global_rotation)


    if puppet.has_method("ApplyAnimState"):
        puppet.ApplyAnimState(state)


func RequestPlayerDamage(targetPeerId: int, damage: int, penetration: int = 0):

    if !_net().IsActive():
        return


    if multiplayer.is_server():

        ApplyPlayerDamage.rpc(targetPeerId, damage, penetration)


    else:

        SubmitPlayerDamage.rpc_id(1, targetPeerId, damage, penetration)


@rpc("any_peer", "reliable", "call_remote")
func SubmitPlayerDamage(targetPeerId: int, damage: int, penetration: int):

    if !multiplayer.is_server():
        return


    ApplyPlayerDamage.rpc(targetPeerId, damage, penetration)


@rpc("authority", "reliable", "call_local")
func ApplyPlayerDamage(targetPeerId: int, damage: int, penetration: int):

    if targetPeerId != multiplayer.get_unique_id():
        return


    var character = GetLocalCharacter()

    if !character:
        print("PlayerManager: ApplyPlayerDamage but no local Character found")
        return


    print("PlayerManager: taking " + str(damage) + " damage from network (pen " + str(penetration) + ")")


    character.WeaponDamage(damage, penetration)


func GetLocalController() -> Node3D:


    var scene = get_tree().current_scene

    if !scene:
        return null

    return scene.get_node_or_null("Core/Controller")


func GetLocalCharacter() -> Node:

    var scene = get_tree().current_scene

    if !scene:
        return null

    return scene.get_node_or_null("Core/Controller/Character")


func GetMap() -> Node:

    var scene = get_tree().current_scene

    if scene && scene.name == "Map":
        return scene

    return null


@rpc("authority", "reliable", "call_remote")
func ApplySceneChange(scene: String):

    pendingSceneChange = scene
    pendingSceneTimer = 0.0
    print("PlayerManager: host changing to " + scene + " — waiting for ready signal (timeout " + str(SCENE_CHANGE_TIMEOUT) + "s)")


@rpc("authority", "reliable", "call_remote")
func HostSceneReady(sceneName: String = "", hostPos: Vector3 = Vector3.ZERO):

    var targetScene = pendingSceneChange if pendingSceneChange != "" else sceneName

    if targetScene == "":
        return

    # Already-in-scene guard — prevents a double Loader.LoadScene if the
    # fallback timeout path fired first, or HostSceneReady arrived twice.
    var currentMap = GetMap()
    var currentSceneName = ""
    if currentMap:
        currentSceneName = str(currentMap.get("mapName")) if currentMap.get("mapName") else ""
    if currentSceneName == targetScene:
        print("[PlayerManager] HostSceneReady: already in " + targetScene + " — applying spawn only, skipping reload")
        pendingSceneChange = ""
        pendingSceneTimer = 0.0
        if hostPos != Vector3.ZERO:
            var peerId = multiplayer.get_unique_id()
            var offset = Vector3(fmod(float(peerId), 4.0) - 2.0, 0, fmod(float(peerId), 3.0) - 1.5)
            var controller = GetLocalController()
            if controller:
                controller.global_position = hostPos + offset
        return

    if hostPos != Vector3.ZERO:
        var peerId = multiplayer.get_unique_id()
        var offset = Vector3(fmod(float(peerId), 4.0) - 2.0, 0, fmod(float(peerId), 3.0) - 1.5)
        pendingSpawnPosition = hostPos + offset
    print("[PlayerManager] Host ready in: " + targetScene + " — loading (spawn at " + str(pendingSpawnPosition) + ")")

    # Must run BEFORE Loader.LoadScene so the buffer is populated while the
    # old Interface still exists.
    SaveClientCharacterBuffer()

    Loader.LoadScene(targetScene)
    pendingSceneChange = ""
    pendingSceneTimer = 0.0


@rpc("any_peer", "reliable", "call_remote")
func RequestDoorToggle(doorPath: NodePath):

    if !multiplayer.is_server():
        return


    var door = get_node_or_null(doorPath)

    if !door || !(door is Door):
        return


    if door.locked || door.isOccupied:
        return


    var newOpen = !door.isOpen
    door.ApplyDoorState(newOpen)


    BroadcastDoorState.rpc(doorPath, newOpen)


@rpc("authority", "reliable", "call_remote")
func BroadcastDoorState(doorPath: NodePath, newOpen: bool):

    var door = get_node_or_null(doorPath)

    if !door || !(door is Door):
        return


    door.ApplyDoorState(newOpen)


@rpc("any_peer", "reliable", "call_remote")
func RequestDoorUnlock(doorPath: NodePath):

    if !multiplayer.is_server():
        return


    var door = get_node_or_null(doorPath)

    if !door || !(door is Door):
        return


    door.ApplyDoorUnlock()
    BroadcastDoorUnlock.rpc(doorPath)


@rpc("authority", "reliable", "call_remote")
func BroadcastDoorUnlock(doorPath: NodePath):

    var door = get_node_or_null(doorPath)

    if !door || !(door is Door):
        return


    door.ApplyDoorUnlock()


@rpc("any_peer", "reliable", "call_remote")
func RequestSwitchToggle(switchPath: NodePath):

    if !multiplayer.is_server():
        return


    var sw = get_node_or_null(switchPath)

    if !sw || !sw.has_method("ApplySwitchState"):
        return


    var newActive = !sw.active
    sw.ApplySwitchState(newActive)


    BroadcastSwitchState.rpc(switchPath, newActive)


@rpc("authority", "reliable", "call_remote")
func BroadcastSwitchState(switchPath: NodePath, newActive: bool):

    var sw = get_node_or_null(switchPath)

    if !sw || !sw.has_method("ApplySwitchState"):
        return


    sw.ApplySwitchState(newActive)


var worldItems: Dictionary = {}
var nextUuid: int = 0

var lastKnownMap: Node = null
var pendingSceneScan: float = -1.0
var pendingHostReady: float = -1.0
var pendingHostSceneName: String = ""
var pendingSpawnPosition: Vector3 = Vector3.ZERO


func ScanIfNeeded(delta: float):

    var currentMap = GetMap()


    if currentMap != lastKnownMap:

        worldItems.clear()
        aiTargets.clear()
        nextUuid = 0
        lastKnownMap = currentMap


        if currentMap:
            pendingSceneScan = 1.0

            if _net().IsActive() && multiplayer.multiplayer_peer && multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
                if multiplayer.is_server():
                    pendingHostSceneName = currentMap.get("mapName") if currentMap.get("mapName") else ""
                    pendingHostReady = 3.0
                    print("[PlayerManager] Host entered scene: " + pendingHostSceneName + " (broadcasting in 3s)")
                else:
                    if pendingSpawnPosition != Vector3.ZERO:
                        var controller = GetLocalController()
                        if controller:
                            controller.global_position = pendingSpawnPosition
                            print("[PlayerManager] Client spawned near host at " + str(pendingSpawnPosition))
                        pendingSpawnPosition = Vector3.ZERO
                    RequestAISync.rpc_id(1)


    if pendingHostReady > 0.0:
        pendingHostReady -= delta
        if pendingHostReady <= 0.0:
            var controller = GetLocalController()
            var hostPos = controller.global_position if controller else Vector3.ZERO
            print("[PlayerManager] Broadcasting HostSceneReady: " + pendingHostSceneName + " at " + str(hostPos))
            HostSceneReady.rpc(pendingHostSceneName, hostPos)
            pendingHostSceneName = ""


    if pendingSceneScan > 0.0:

        pendingSceneScan -= delta

        if pendingSceneScan <= 0.0:
            RegisterSceneItems()


func RegisterSceneItems():

    var items = get_tree().get_nodes_in_group("Item")


    items.sort_custom(func(a, b): return str(a.get_path()) < str(b.get_path()))


    var uuid = 0

    for item in items:
        if item is Pickup:
            item.set_meta("network_uuid", uuid)
            worldItems[uuid] = item
            uuid += 1


    nextUuid = uuid


    print("PlayerManager: registered " + str(uuid) + " scene items")


func GenerateUuid() -> int:
    var u = nextUuid
    nextUuid += 1
    return u


func RequestPickup(uuid: int):

    if !_net().IsActive():
        return


    if multiplayer.is_server():

        if !worldItems.has(uuid):
            return


        var pickup = worldItems[uuid]

        if !is_instance_valid(pickup):
            worldItems.erase(uuid)
            return


        BroadcastPickupTake.rpc(uuid, multiplayer.get_unique_id())


    else:

        RequestPickupTake.rpc_id(1, uuid, multiplayer.get_unique_id())


@rpc("any_peer", "reliable", "call_remote")
func RequestPickupTake(uuid: int, peerId: int):

    if !multiplayer.is_server():
        return


    if !worldItems.has(uuid):
        return


    var pickup = worldItems[uuid]

    if !is_instance_valid(pickup):
        worldItems.erase(uuid)
        return


    BroadcastPickupTake.rpc(uuid, peerId)


@rpc("authority", "reliable", "call_local")
func BroadcastPickupTake(uuid: int, peerId: int):

    if !worldItems.has(uuid):
        return


    var pickup = worldItems[uuid]

    if !is_instance_valid(pickup):
        worldItems.erase(uuid)
        return


    if peerId == multiplayer.get_unique_id():

        var iface = GetLocalInterface()

        if iface:

            if !iface.AutoStack(pickup.slotData, iface.inventoryGrid):
                iface.Create(pickup.slotData, iface.inventoryGrid, false)

            iface.UpdateStats(false)


            if pickup.has_method("PlayPickup"):
                pickup.PlayPickup()


    worldItems.erase(uuid)
    pickup.queue_free()


func RequestPickupSpawn(slotDict: Dictionary, pos: Vector3, rotDeg: Vector3, vel: Vector3):

    if !_net().IsActive():
        return


    if multiplayer.is_server():
        var uuid = GenerateUuid()
        BroadcastPickupSpawn.rpc(uuid, slotDict, pos, rotDeg, vel)
    else:
        SubmitPickupSpawn.rpc_id(1, slotDict, pos, rotDeg, vel)


@rpc("any_peer", "reliable", "call_remote")
func SubmitPickupSpawn(slotDict: Dictionary, pos: Vector3, rotDeg: Vector3, vel: Vector3):

    if !multiplayer.is_server():
        return


    var uuid = GenerateUuid()
    BroadcastPickupSpawn.rpc(uuid, slotDict, pos, rotDeg, vel)


@rpc("authority", "reliable", "call_local")
func BroadcastPickupSpawn(uuid: int, slotDict: Dictionary, pos: Vector3, rotDeg: Vector3, vel: Vector3):

    var file = slotDict.get("file", "")

    if file == "":
        return


    var scene = Database.get(file)

    if !scene:
        print("PlayerManager: no Database entry for " + file)
        return


    var map = GetMap()

    if !map:
        return


    var pickup = scene.instantiate()
    map.add_child(pickup)


    pickup.position = pos
    pickup.rotation_degrees = rotDeg
    pickup.linear_velocity = vel
    pickup.Unfreeze()


    pickup.slotData.amount = slotDict.get("amount", pickup.slotData.amount)
    pickup.slotData.condition = slotDict.get("condition", pickup.slotData.condition)
    pickup.slotData.state = slotDict.get("state", pickup.slotData.state)
    pickup.slotData.chamber = slotDict.get("chamber", pickup.slotData.chamber)
    pickup.slotData.casing = slotDict.get("casing", pickup.slotData.casing)
    pickup.slotData.mode = slotDict.get("mode", pickup.slotData.mode)
    pickup.slotData.zoom = slotDict.get("zoom", pickup.slotData.zoom)
    pickup.slotData.position = slotDict.get("position", pickup.slotData.position)


    pickup.slotData.nested.clear()
    for nestedFile in slotDict.get("nested", []):
        var nestedData = LookupItemData(nestedFile)
        if nestedData:
            pickup.slotData.nested.append(nestedData)


    pickup.UpdateAttachments()


    pickup.set_meta("network_uuid", uuid)
    worldItems[uuid] = pickup


    if uuid >= nextUuid:
        nextUuid = uuid + 1


func ShouldGenerateLoot() -> bool:
    if !_net().IsActive():
        return true
    return multiplayer.is_server()


@rpc("any_peer", "reliable", "call_remote")
func RequestContainerOpen(containerPath: NodePath):

    if !multiplayer.is_server():
        return


    var container = get_node_or_null(containerPath)

    if !container || !(container is LootContainer):
        return


    var sender = multiplayer.get_remote_sender_id()
    var serialized: Array = []


    var source = container.storage if container.storaged else container.loot

    for slot in source:
        serialized.append(SerializeSlotData(slot))


    DeliverContainerLoot.rpc_id(sender, containerPath, serialized, container.storaged)


@rpc("authority", "reliable", "call_remote")
func DeliverContainerLoot(containerPath: NodePath, serialized: Array, isStoraged: bool):

    var container = get_node_or_null(containerPath)

    if !container || !(container is LootContainer):
        return


    if isStoraged:
        container.storage.clear()
        for dict in serialized:
            container.storage.append(DeserializeSlotData(dict))
        container.storaged = true
    else:
        container.loot.clear()
        for dict in serialized:
            container.loot.append(DeserializeSlotData(dict))


    var UIManager = get_tree().current_scene.get_node_or_null("Core/UI")

    if UIManager:
        UIManager.OpenContainer(container)
        container.ContainerAudio()


func SyncContainerStorage(container: LootContainer):

    if !_net().IsActive():
        return


    if !container:
        return


    var serialized: Array = []

    for slot in container.storage:
        serialized.append(SerializeSlotData(slot))


    var path = container.get_path()


    if multiplayer.is_server():
        BroadcastContainerStorage.rpc(path, serialized)
    else:
        SubmitContainerStorage.rpc_id(1, path, serialized)


@rpc("any_peer", "reliable", "call_remote")
func SubmitContainerStorage(containerPath: NodePath, serialized: Array):

    if !multiplayer.is_server():
        return


    var container = get_node_or_null(containerPath)

    if !container || !(container is LootContainer):
        return


    container.storage.clear()

    for dict in serialized:
        container.storage.append(DeserializeSlotData(dict))

    container.storaged = true


    BroadcastContainerStorage.rpc(containerPath, serialized)


@rpc("authority", "reliable", "call_remote")
func BroadcastContainerStorage(containerPath: NodePath, serialized: Array):

    var container = get_node_or_null(containerPath)

    if !container || !(container is LootContainer):
        return


    container.storage.clear()

    for dict in serialized:
        container.storage.append(DeserializeSlotData(dict))

    container.storaged = true


func SerializeSlotData(slot: SlotData) -> Dictionary:

    if !slot || !slot.itemData:
        return {}


    var nestedFiles: Array = []
    for item in slot.nested:
        if item:
            nestedFiles.append(item.file)


    return {
        "file": slot.itemData.file,
        "amount": slot.amount,
        "condition": slot.condition,
        "state": slot.state,
        "rotated": slot.gridRotated,
        "gridPosition": slot.gridPosition,
        "position": slot.position,
        "mode": slot.mode,
        "zoom": slot.zoom,
        "chamber": slot.chamber,
        "casing": slot.casing,
        "nested": nestedFiles,
    }


func DeserializeSlotData(dict: Dictionary) -> SlotData:

    var slot = SlotData.new()
    var file = dict.get("file", "")


    if file == "":
        return slot


    slot.itemData = LookupItemData(file)
    slot.amount = dict.get("amount", 0)
    slot.condition = dict.get("condition", 100)
    slot.state = dict.get("state", "")
    slot.gridRotated = dict.get("rotated", false)
    slot.gridPosition = dict.get("gridPosition", Vector2.ZERO)
    slot.position = dict.get("position", 0)
    slot.mode = dict.get("mode", 1)
    slot.zoom = dict.get("zoom", 1)
    slot.chamber = dict.get("chamber", false)
    slot.casing = dict.get("casing", false)


    for nestedFile in dict.get("nested", []):
        var nestedData = LookupItemData(nestedFile)
        if nestedData:
            slot.nested.append(nestedData)


    return slot


var itemDataCache: Dictionary = {}


func LookupItemData(file: String) -> ItemData:

    if file == "":
        return null


    if itemDataCache.has(file):
        return itemDataCache[file]


    var scene = Database.get(file)

    if !scene:
        return null


    var temp = scene.instantiate()
    var data = null


    if "slotData" in temp && temp.slotData && temp.slotData.itemData:
        data = temp.slotData.itemData


    temp.queue_free()


    if data:
        itemDataCache[file] = data


    return data


@rpc("authority", "unreliable", "call_remote")
func BroadcastSimulationState(time: float, day: int, weather: String, weatherTime: float, season: int):

    var dayChanged = (Simulation.day != day)


    Simulation.time = time
    Simulation.day = day
    Simulation.weather = weather
    Simulation.weatherTime = weatherTime
    Simulation.season = season


    if dayChanged:
        var scene = get_tree().current_scene
        if scene && scene.name == "Map":
            Loader.UpdateProgression()


var worldAI: Dictionary = {}
var nextAiUuid: int = 0
var aiTargets: Dictionary = {}  # uuid → {pos: Vector3, rot: Vector3}
const AI_LERP_SPEED = 18.0


var pendingSceneChange: String = ""
var pendingSceneTimer: float = 0.0
# Long enough to accommodate load times. Firing earlier
# would race the host's HostSceneReady RPC and cause a double scene-load.
const SCENE_CHANGE_TIMEOUT = 90.0


func GenerateAiUuid() -> int:
    var u = nextAiUuid
    nextAiUuid += 1
    return u


func GetNearestPlayerPosition(from: Vector3) -> Vector3:

    var nearest = Vector3.ZERO
    var bestDist = INF
    var found = false


    var localCtrl = GetLocalController()
    if localCtrl && localCtrl.is_inside_tree():
        var d = from.distance_squared_to(localCtrl.global_position)
        if d < bestDist:
            bestDist = d
            nearest = localCtrl.global_position
            found = true


    for id in remotePlayers:
        var puppet = remotePlayers[id]
        if !is_instance_valid(puppet) || !puppet.is_inside_tree():
            continue
        var d = from.distance_squared_to(puppet.global_position)
        if d < bestDist:
            bestDist = d
            nearest = puppet.global_position
            found = true


    return nearest if found else Vector3.ZERO


func GetNearestPlayerCamera(from: Vector3) -> Vector3:

    var nearestCam = Vector3.ZERO
    var bestDist = INF
    var found = false


    var localCtrl = GetLocalController()
    if localCtrl && localCtrl.is_inside_tree():
        var d = from.distance_squared_to(localCtrl.global_position)
        if d < bestDist:
            bestDist = d
            nearestCam = gameData.cameraPosition
            found = true


    for id in remotePlayers:
        var puppet = remotePlayers[id]
        if !is_instance_valid(puppet) || !puppet.is_inside_tree():
            continue
        var d = from.distance_squared_to(puppet.global_position)
        if d < bestDist:
            bestDist = d
            nearestCam = puppet.global_position + Vector3(0, 1.6, 0)
            found = true


    return nearestCam if found else Vector3.ZERO


func BroadcastAIPositions():

    if worldAI.is_empty():
        return


    var uuids: Array = []
    var positions: PackedVector3Array = PackedVector3Array()
    var rotations: PackedVector3Array = PackedVector3Array()
    var speeds: PackedFloat32Array = PackedFloat32Array()
    var aiStates: PackedInt32Array = PackedInt32Array()


    for uuid in worldAI:
        var ai = worldAI[uuid]
        if !is_instance_valid(ai) || !ai.is_inside_tree():
            continue
        uuids.append(uuid)
        positions.append(ai.global_position)
        rotations.append(ai.global_rotation)
        speeds.append(ai.speed)
        aiStates.append(ai.currentState)


    if uuids.size() == 0:
        return


    BroadcastAIStates.rpc(uuids, positions, rotations, speeds, aiStates)


@rpc("authority", "unreliable", "call_remote")
func BroadcastAIStates(uuids: Array, positions: PackedVector3Array, rotations: PackedVector3Array, speeds: PackedFloat32Array, states: PackedInt32Array):

    for i in uuids.size():
        var uuid = uuids[i]
        if !worldAI.has(uuid):
            continue
        var ai = worldAI[uuid]
        if !is_instance_valid(ai) || !ai.is_inside_tree():
            continue
        aiTargets[uuid] = {"pos": positions[i], "rot": rotations[i]}
        ai.speed = speeds[i]
        ai.currentState = states[i]


@rpc("authority", "reliable", "call_remote")
func BroadcastAISpawn(uuid: int, spawnType: String, spawnPointPath: NodePath, variant: Dictionary):

    var scene = get_tree().current_scene
    if !scene:
        return


    var aiSpawner = scene.get_node_or_null("AI")
    if !aiSpawner:
        print("PlayerManager: BroadcastAISpawn but no AI spawner in scene")
        return


    var spawnPoint = get_node_or_null(spawnPointPath)
    if !spawnPoint:
        print("PlayerManager: BroadcastAISpawn but spawn point missing: " + str(spawnPointPath))
        return


    if aiSpawner.APool.get_child_count() == 0:
        print("PlayerManager: BroadcastAISpawn but client APool empty")
        return


    var newAgent = aiSpawner.APool.get_child(0)
    newAgent.reparent(aiSpawner.agents)
    newAgent.global_transform = spawnPoint.global_transform
    newAgent.currentPoint = spawnPoint
    newAgent.set_meta("network_uuid", uuid)


    newAgent.spawnVariant = variant


    worldAI[uuid] = newAgent
    aiSpawner.activeAgents += 1


    if spawnType == "Wanderer":
        newAgent.ActivateWanderer()
    elif spawnType == "Guard":
        newAgent.ActivateGuard()
    elif spawnType == "Hider":
        newAgent.ActivateHider()


    if uuid >= nextAiUuid:
        nextAiUuid = uuid + 1


@rpc("any_peer", "reliable", "call_remote")
func RequestAISync():

    if !multiplayer.is_server():
        return


    var sender = multiplayer.get_remote_sender_id()

    print("PlayerManager: AI sync requested by peer " + str(sender) + " — sending " + str(worldAI.size()) + " AI")


    for uuid in worldAI:
        var ai = worldAI[uuid]
        if !is_instance_valid(ai) || !ai.is_inside_tree():
            continue
        SyncSingleAI.rpc_id(sender, uuid, ai.global_position, ai.global_rotation, ai.spawnVariant)


@rpc("authority", "reliable", "call_remote")
func SyncSingleAI(uuid: int, pos: Vector3, rot: Vector3, variant: Dictionary):

    if worldAI.has(uuid):
        return


    var scene = get_tree().current_scene
    if !scene:
        return


    var aiSpawner = scene.get_node_or_null("AI")
    if !aiSpawner:
        return


    if aiSpawner.APool.get_child_count() == 0:
        print("PlayerManager: SyncSingleAI but client APool empty")
        return


    var newAgent = aiSpawner.APool.get_child(0)
    newAgent.reparent(aiSpawner.agents)
    newAgent.global_position = pos
    newAgent.global_rotation = rot
    newAgent.spawnVariant = variant
    newAgent.set_meta("network_uuid", uuid)
    worldAI[uuid] = newAgent
    aiTargets[uuid] = {"pos": pos, "rot": rot}
    aiSpawner.activeAgents += 1


    newAgent.EquipmentSetup()
    newAgent.Activate()


    if uuid >= nextAiUuid:
        nextAiUuid = uuid + 1


    print("PlayerManager: synced AI uuid " + str(uuid))


@rpc("authority", "reliable", "call_remote")
func BroadcastAIDeath(uuid: int, direction: Vector3, force: float, container_loot: Array = [], weapon_dict: Dictionary = {}, backpack_dict: Dictionary = {}, secondary_dict: Dictionary = {}):

    if !worldAI.has(uuid):
        return


    var ai = worldAI[uuid]
    if !is_instance_valid(ai):
        worldAI.erase(uuid)
        return


    # Apply the host's authoritative loot to the client AI before ragdoll.
    if container_loot.size() > 0 and ai.container and ai.container.get_child_count() > 0:
        var ai_container = ai.container.get_child(0)
        if ai_container and ai_container is LootContainer:
            ai_container.loot.clear()
            for dict in container_loot:
                ai_container.loot.append(DeserializeSlotData(dict))

    if weapon_dict.size() > 0 and ai.weapon and ai.weapon.slotData:
        _apply_slot_dict_to_pickup(ai.weapon, weapon_dict)

    if backpack_dict.size() > 0 and ai.backpack and ai.backpack.slotData:
        _apply_slot_dict_to_pickup(ai.backpack, backpack_dict)

    if secondary_dict.size() > 0 and ai.secondary and ai.secondary.slotData:
        _apply_slot_dict_to_pickup(ai.secondary, secondary_dict)

    ai.Death(direction, force)
    worldAI.erase(uuid)


func _apply_slot_dict_to_pickup(pickup, slotDict: Dictionary):
    if !pickup or !pickup.slotData:
        return
    pickup.slotData.amount = slotDict.get("amount", pickup.slotData.amount)
    pickup.slotData.condition = slotDict.get("condition", pickup.slotData.condition)
    pickup.slotData.state = slotDict.get("state", pickup.slotData.state)
    pickup.slotData.chamber = slotDict.get("chamber", pickup.slotData.chamber)
    pickup.slotData.casing = slotDict.get("casing", pickup.slotData.casing)
    pickup.slotData.mode = slotDict.get("mode", pickup.slotData.mode)
    pickup.slotData.zoom = slotDict.get("zoom", pickup.slotData.zoom)
    pickup.slotData.position = slotDict.get("position", pickup.slotData.position)
    pickup.slotData.nested.clear()
    for nestedFile in slotDict.get("nested", []):
        var nestedData = LookupItemData(nestedFile)
        if nestedData:
            pickup.slotData.nested.append(nestedData)


@rpc("any_peer", "reliable", "call_remote")
func RequestAIDamage(uuid: int, hitbox: String, damage: float):

    if !multiplayer.is_server():
        return


    if !worldAI.has(uuid):
        return


    var ai = worldAI[uuid]

    if !is_instance_valid(ai):
        worldAI.erase(uuid)
        return


    ai.WeaponDamage(hitbox, damage)


func RequestGrenadeThrow(throwPath: String, handlePath: String, pos: Vector3, rotDeg: Vector3, vel: Vector3, angVel: Vector3):

    if !_net().IsActive():
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

    # The originator already spawned via super() in their local GrenadeRig.
    if multiplayer.get_unique_id() == origin_id:
        return

    _spawn_grenade_locally(throwPath, handlePath, pos, rotDeg, vel, angVel)


func _spawn_grenade_locally(throwPath: String, handlePath: String, pos: Vector3, rotDeg: Vector3, vel: Vector3, angVel: Vector3):

    var throwScene = load(throwPath)
    if !throwScene:
        return


    var throwGrenade = throwScene.instantiate()
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


func RequestPlayerExplosionDamage(targetPeerId: int):

    if !_net().IsActive():
        return


    ApplyPlayerExplosionDamage.rpc(targetPeerId)


@rpc("authority", "reliable", "call_local")
func ApplyPlayerExplosionDamage(targetPeerId: int):

    if targetPeerId != multiplayer.get_unique_id():
        return


    var character = GetLocalCharacter()
    if character:
        character.ExplosionDamage()


func NotifyPlayerDeath(peerId: int):

    if !_net().IsActive():
        return


    if multiplayer.is_server():
        BroadcastPlayerDeath.rpc(peerId)
    else:
        SubmitPlayerDeath.rpc_id(1, peerId)


@rpc("any_peer", "reliable", "call_remote")
func SubmitPlayerDeath(peerId: int):
    if !multiplayer.is_server():
        return
    BroadcastPlayerDeath.rpc(peerId)


@rpc("authority", "reliable", "call_local")
func BroadcastPlayerDeath(peerId: int):

    if peerId == multiplayer.get_unique_id():
        return


    if !remotePlayers.has(peerId):
        return


    var puppet = remotePlayers[peerId]
    if is_instance_valid(puppet) && puppet.has_method("OnDeath"):
        puppet.OnDeath()


func NotifyPlayerRespawn(peerId: int):

    if !_net().IsActive():
        return


    if multiplayer.is_server():
        BroadcastPlayerRespawn.rpc(peerId)
    else:
        SubmitPlayerRespawn.rpc_id(1, peerId)


@rpc("any_peer", "reliable", "call_remote")
func SubmitPlayerRespawn(peerId: int):
    if !multiplayer.is_server():
        return
    BroadcastPlayerRespawn.rpc(peerId)


@rpc("authority", "reliable", "call_local")
func BroadcastPlayerRespawn(peerId: int):

    if peerId == multiplayer.get_unique_id():
        return


    if !remotePlayers.has(peerId):
        return


    var puppet = remotePlayers[peerId]
    if is_instance_valid(puppet) && puppet.has_method("OnRespawn"):
        puppet.OnRespawn()


func GetLocalInterface() -> Node:

    var scene = get_tree().current_scene

    if !scene:
        return null


    return scene.get_node_or_null("Core/UI/Interface")
