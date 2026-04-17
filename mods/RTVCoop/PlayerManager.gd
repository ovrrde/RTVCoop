extends Node

var _net_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c


var _steam_lobby_c: Node
func _steam_lobby():
    if !_steam_lobby_c: _steam_lobby_c = get_tree().root.get_node_or_null("SteamLobby")
    return _steam_lobby_c


const BROADCAST_RATE = 20.0
const SIMULATION_BROADCAST_RATE = 1.0


var gameData = preload("res://Resources/GameData.tres")


var remotePlayers: Dictionary = {}
var peer_names: Dictionary = {}
var _container_open_bypassed: bool = false
var broadcastAccumulator: float = 0.0
var simulationAccumulator: float = 0.0
var _local_shot_count: int = 0
var _was_firing_local: bool = false
var _coop_save_timer: float = 0.0
const COOP_SAVE_INTERVAL: float = 60.0

var coopCharacterBuffer: CharacterSave = null
var sceneReady: bool = false
var _coop_loading: bool = false

# uuid -> {"pos": Vector3, "rot": Vector3, "frozen": bool}; receiver lerps toward these
var _pickup_targets: Dictionary = {}
const PICKUP_LERP_SPEED: float = 18.0

# mixed into loot seeding so containers vary per session but host/client agree within one
var coopSessionSeed: int = 0


func _ready():
    _net().disconnected.connect(_on_disconnected)
    _net().hosted.connect(_on_hosted)
    _net().joined.connect(_on_joined)
    _net().peer_joined.connect(_on_peer_joined_for_names)
    _net().peer_left.connect(_on_peer_left_for_names)
    _add_sync_module("res://mods/RTVCoop/Sync/EventSync.gd", "EventSync")
    _add_sync_module("res://mods/RTVCoop/Sync/InteractableSync.gd", "InteractableSync")
    _add_sync_module("res://mods/RTVCoop/Sync/ContainerSync.gd", "ContainerSync")
    _add_sync_module("res://mods/RTVCoop/Sync/FurnitureSync.gd", "FurnitureSync")
    _add_sync_module("res://mods/RTVCoop/Sync/AISync.gd", "AISync")
    _add_sync_module("res://mods/RTVCoop/Sync/QuestSync.gd", "QuestSync")
    _add_sync_module("res://mods/RTVCoop/Sync/WorldSync.gd", "WorldSync")
    _add_sync_module("res://mods/RTVCoop/Sync/SlotSerializer.gd", "SlotSerializer")
    _add_sync_module("res://mods/RTVCoop/Sync/PuppetManager.gd", "PuppetManager")


func _add_sync_module(path: String, node_name: String):
    var script = load(path)
    if !script:
        print("[PlayerManager] FAIL: could not load " + path)
        return
    var node = Node.new()
    node.set_script(script)
    node.name = node_name
    add_child(node)
    print("[PlayerManager] Module loaded: " + node_name)


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
    _lerp_pickup_targets(delta)


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


    if gameData.isFiring and !_was_firing_local:
        _local_shot_count += 1
    _was_firing_local = gameData.isFiring

    if !multiplayer.is_server():
        _coop_save_timer += delta
        if _coop_save_timer >= COOP_SAVE_INTERVAL:
            _coop_save_timer = 0.0
            if !gameData.isDead and !gameData.isCaching:
                SaveClientCharacterBuffer()

    broadcastAccumulator += delta

    if broadcastAccumulator < 1.0 / BROADCAST_RATE:
        return

    broadcastAccumulator = 0.0


    BroadcastLocalState()


func _puppet_manager() -> Node:
    return get_node_or_null("PuppetManager")


func ReconcilePuppets():
    var pm = _puppet_manager()
    if pm:
        pm.ReconcilePuppets()


func SpawnPuppet(peerId: int):
    var pm = _puppet_manager()
    if pm:
        pm.SpawnPuppet(peerId)


func DespawnPuppet(peerId: int):
    var pm = _puppet_manager()
    if pm:
        pm.DespawnPuppet(peerId)


func _on_disconnected():
    var scene = get_tree().current_scene
    var in_game: bool = scene != null and scene.name == "Map"

    for id in remotePlayers.keys().duplicate():
        DespawnPuppet(id)
    peer_names.clear()
    if _container_sync():
        _container_sync()._container_holders.clear()
    coopCharacterBuffer = null
    coopSessionSeed = 0
    sceneReady = false
    pendingSceneChange = ""
    pendingSpawnPosition = Vector3.ZERO
    pendingHostReady = -1.0
    pendingSecondLootSync = -1.0

    if in_game:
        Loader.Message("Coop ended — returning to menu", Color.ORANGE)
        Loader.LoadScene("Menu")


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
    print("[PlayerManager] _on_joined: invalidating lastKnownMap to force scene re-sync")
    worldItems.clear()
    worldFurniture.clear()
    worldAI.clear()
    aiTargets.clear()
    nextUuid = 0
    nextFurnitureId = 0
    if _ai_sync():
        _ai_sync()._pending_spawns.clear()
    lastKnownMap = null


func _on_peer_joined_for_names(_id: int):
    if !multiplayer.is_server():
        return
    if coopSessionSeed == 0:
        coopSessionSeed = _make_session_seed()
        print("[PlayerManager] Session seed generated on host: " + str(coopSessionSeed))
    await get_tree().create_timer(0.5, false).timeout
    SyncNameRegistry.rpc(peer_names)
    DeliverSessionSeed.rpc_id(_id, coopSessionSeed)
    if _quest_sync():
        _quest_sync().push_full_state_to(_id)

    # tell joiner which scene if host's already in one — otherwise they'd wait forever
    var map = GetMap()
    if map:
        var mapName: String = str(map.get("mapName")) if map.get("mapName") else ""
        if mapName != "":
            var controller = GetLocalController()
            var hostPos: Vector3 = controller.global_position if controller else Vector3.ZERO
            print("[PlayerManager] Sending HostSceneReady to new peer " + str(_id) + " for " + mapName)
            HostSceneReady.rpc_id(_id, mapName, hostPos, coopSessionSeed)

    _try_deliver_coop_save(_id)


func _on_peer_left_for_names(id: int):
    if !multiplayer.is_server():
        return
    if peer_names.has(id):
        peer_names.erase(id)
    SyncNameRegistry.rpc(peer_names)
    if _container_sync():
        _container_sync().release_holders_for_peer(id)
    var es = _event_sync()
    if es and es._sleep_ready.has(id):
        es._sleep_ready.erase(id)
        var total: int = 1 + _net().GetPeerIds().size()
        es.BroadcastSleepStatus.rpc(es._sleep_ready.keys(), total)


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


@rpc("authority", "call_remote", "reliable")
func DeliverSessionSeed(seed_value: int):
    coopSessionSeed = seed_value
    print("[PlayerManager] Session seed received: " + str(seed_value))


func _make_session_seed() -> int:
    var t = Time.get_unix_time_from_system()
    var s = int(t) ^ int(t * 1000.0) & 0x7FFFFFFF
    if s == 0:
        s = 1
    return s


# Host: if seed is 0 (fresh scene), generate + broadcast. Returns current seed.
func _ensure_session_seed() -> int:
    if coopSessionSeed != 0:
        return coopSessionSeed
    if !multiplayer.is_server():
        return 0
    coopSessionSeed = _make_session_seed()
    print("[PlayerManager] Per-scene seed generated: " + str(coopSessionSeed))
    if _net() and _net().IsActive():
        DeliverSessionSeed.rpc(coopSessionSeed)
    return coopSessionSeed


# ─── Coop client character buffer ────────────────────────────────────────────

func SaveClientCharacterBuffer():
    if multiplayer.is_server():
        return

    if _coop_loading:
        print("[PlayerManager] COOP SAVE: skipped — buffer is being restored (would clobber with partial state)")
        return

    if !sceneReady:
        print("[PlayerManager] COOP SAVE: skipped — scene not ready yet")
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

    if _net().IsActive() and !multiplayer.is_server():
        var serialized = _serialize_character(character)
        SubmitClientCharacterData.rpc_id(1, serialized)


func GiveClientStarterKit():
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

    _coop_loading = true

    await get_tree().create_timer(0.1).timeout

    var character: CharacterSave = coopCharacterBuffer
    var rigManager = get_tree().current_scene.get_node_or_null("/root/Map/Core/Camera/Manager")
    var interface = get_tree().current_scene.get_node_or_null("/root/Map/Core/UI/Interface")
    var flashlight = get_tree().current_scene.get_node_or_null("/root/Map/Core/Camera/Flashlight")
    var NVG = get_tree().current_scene.get_node_or_null("/root/Map/Core/UI/NVG")

    if !interface or !rigManager:
        print("[PlayerManager] COOP LOAD: interface/rigManager missing, skipping")
        _coop_loading = false
        return

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
        if slotData and slotData.itemData:
            interface.LoadGridItem(slotData, interface.inventoryGrid, slotData.gridPosition)

    for slotData in character.equipment:
        if slotData and slotData.itemData:
            interface.LoadSlotItem(slotData, slotData.slot)

    for slotData in character.catalog:
        if slotData and slotData.itemData:
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

    _coop_loading = false


func _serialize_character(character: CharacterSave) -> Dictionary:
    var data: Dictionary = {
        "health": character.health, "energy": character.energy,
        "hydration": character.hydration, "mental": character.mental,
        "temperature": character.temperature, "bodyStamina": character.bodyStamina,
        "armStamina": character.armStamina,
        "overweight": character.overweight, "starvation": character.starvation,
        "dehydration": character.dehydration, "bleeding": character.bleeding,
        "fracture": character.fracture, "burn": character.burn,
        "frostbite": character.frostbite, "insanity": character.insanity,
        "rupture": character.rupture, "headshot": character.headshot,
        "cat": character.cat, "catFound": character.catFound, "catDead": character.catDead,
        "primary": character.primary, "secondary": character.secondary,
        "knife": character.knife, "grenade1": character.grenade1,
        "grenade2": character.grenade2, "flashlight": character.flashlight,
        "NVG": character.NVG, "weaponPosition": character.weaponPosition,
    }
    data["inventory"] = []
    for slot in character.inventory:
        var d = SerializeSlotData(slot)
        d["gridPosition"] = slot.gridPosition
        d["gridRotated"] = slot.gridRotated
        data["inventory"].append(d)
    data["equipment"] = []
    for slot in character.equipment:
        var d = SerializeSlotData(slot)
        d["slotName"] = slot.slot
        data["equipment"].append(d)
    data["catalog"] = []
    for slot in character.catalog:
        var d = SerializeSlotData(slot)
        d["gridPosition"] = slot.gridPosition
        d["gridRotated"] = slot.gridRotated
        if slot.storage.size() > 0:
            var storage_arr: Array = []
            for s in slot.storage:
                storage_arr.append(SerializeSlotData(s))
            d["storage_data"] = storage_arr
        data["catalog"].append(d)
    return data


func _deserialize_character(data: Dictionary) -> CharacterSave:
    var character: CharacterSave = CharacterSave.new()
    character.initialSpawn = false
    character.startingKit = null
    character.health = data.get("health", 100.0)
    character.energy = data.get("energy", 100.0)
    character.hydration = data.get("hydration", 100.0)
    character.mental = data.get("mental", 100.0)
    character.temperature = data.get("temperature", 100.0)
    character.bodyStamina = data.get("bodyStamina", 100.0)
    character.armStamina = data.get("armStamina", 100.0)
    character.overweight = data.get("overweight", false)
    character.starvation = data.get("starvation", false)
    character.dehydration = data.get("dehydration", false)
    character.bleeding = data.get("bleeding", false)
    character.fracture = data.get("fracture", false)
    character.burn = data.get("burn", false)
    character.frostbite = data.get("frostbite", false)
    character.insanity = data.get("insanity", false)
    character.rupture = data.get("rupture", false)
    character.headshot = data.get("headshot", false)
    character.cat = data.get("cat", 100.0)
    character.catFound = data.get("catFound", false)
    character.catDead = data.get("catDead", false)
    character.primary = data.get("primary", false)
    character.secondary = data.get("secondary", false)
    character.knife = data.get("knife", false)
    character.grenade1 = data.get("grenade1", false)
    character.grenade2 = data.get("grenade2", false)
    character.flashlight = data.get("flashlight", false)
    character.NVG = data.get("NVG", false)
    character.weaponPosition = data.get("weaponPosition", 1)
    character.inventory.clear()
    for d in data.get("inventory", []):
        var slot = DeserializeSlotData(d)
        if slot:
            slot.gridPosition = d.get("gridPosition", Vector2.ZERO)
            slot.gridRotated = d.get("gridRotated", false)
            character.inventory.append(slot)
    character.equipment.clear()
    for d in data.get("equipment", []):
        var slot = DeserializeSlotData(d)
        if slot:
            slot.slot = d.get("slotName", "")
            character.equipment.append(slot)
    character.catalog.clear()
    for d in data.get("catalog", []):
        var slot = DeserializeSlotData(d)
        if slot:
            slot.gridPosition = d.get("gridPosition", Vector2.ZERO)
            slot.gridRotated = d.get("gridRotated", false)
            if d.has("storage_data"):
                for sd in d["storage_data"]:
                    var stored = DeserializeSlotData(sd)
                    if stored:
                        slot.storage.append(stored)
            character.catalog.append(slot)
    return character


func _coop_save_path(peer_id: int) -> String:
    var name_key: String = ""
    if peer_names.has(peer_id):
        name_key = peer_names[peer_id]
    if name_key == "":
        name_key = str(peer_id)
    name_key = name_key.replace(" ", "_").replace("/", "_").replace("\\", "_").replace(":", "_")
    return "user://coop_" + name_key + ".tres"


@rpc("any_peer", "reliable", "call_remote")
func SubmitClientCharacterData(data: Dictionary):
    if !multiplayer.is_server():
        return
    var sender = multiplayer.get_remote_sender_id()
    var character = _deserialize_character(data)
    var path = _coop_save_path(sender)
    ResourceSaver.save(character, path)
    print("[PlayerManager] Saved coop character for peer " + str(sender) + " to " + path)


@rpc("authority", "reliable", "call_remote")
func DeliverCoopSave(data: Dictionary):
    coopCharacterBuffer = _deserialize_character(data)
    print("[PlayerManager] Received coop save from host (" + str(coopCharacterBuffer.inventory.size()) + " inv, " + str(coopCharacterBuffer.equipment.size()) + " eqp)")


func _try_deliver_coop_save(peer_id: int):
    var path = _coop_save_path(peer_id)
    if FileAccess.file_exists(path):
        var character = load(path) as CharacterSave
        if character:
            var data = _serialize_character(character)
            DeliverCoopSave.rpc_id(peer_id, data)
            print("[PlayerManager] Delivered coop save to peer " + str(peer_id))
            return
    print("[PlayerManager] No coop save for peer " + str(peer_id) + " — they will get starter kit")


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
    var weaponSlot = null

    if rigManager:
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
    state["shots"] = _local_shot_count
    _local_shot_count = 0
    state["fireMode"] = 1
    if weaponSlot and weaponSlot.slotData:
        state["fireMode"] = weaponSlot.slotData.mode
    state["flashlight"] = gameData.flashlight
    state["nvg"] = gameData.NVG

    var attachmentFiles: Array = []
    if weaponSlot and weaponSlot.slotData:
        for nested in weaponSlot.slotData.nested:
            if nested and nested.file:
                attachmentFiles.append(nested.file)
    state["attachments"] = attachmentFiles

    var isSuppressed: bool = false
    if rigManager and rigManager.get_child_count() > 0:
        var rig = rigManager.get_child(rigManager.get_child_count() - 1)
        if rig.get("activeMuzzle") != null and rig.activeMuzzle != null:
            isSuppressed = true
    state["suppressed"] = isSuppressed

    var camera = scene.get_node_or_null("Core/Camera") if scene else null
    state["pitch"] = camera.rotation.x if camera else 0.0


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
func HostSceneReady(sceneName: String = "", hostPos: Vector3 = Vector3.ZERO, sceneSeed: int = 0):

    if sceneSeed != 0:
        coopSessionSeed = sceneSeed

    var targetScene = pendingSceneChange if pendingSceneChange != "" else sceneName

    if targetScene == "":
        return

    var currentMap = GetMap()
    var currentSceneName = ""
    if currentMap:
        currentSceneName = str(currentMap.get("mapName")) if currentMap.get("mapName") else ""
    if currentSceneName == targetScene:
        print("[PlayerManager] HostSceneReady: already in " + targetScene + " — applying spawn only, skipping reload")
        pendingSceneChange = ""
        pendingSceneTimer = 0.0
        if hostPos != Vector3.ZERO:
            _coop_apply_client_spawn(hostPos)
        return

    if hostPos != Vector3.ZERO:
        pendingSpawnPosition = hostPos
    print("[PlayerManager] Host ready in: " + targetScene + " — loading (host at " + str(pendingSpawnPosition) + ")")

    SaveClientCharacterBuffer()

    # pause stat drain across the full client transition; Compiler.Spawn clears this at the end
    gameData.isTransitioning = true

    Loader.LoadScene(targetScene)
    pendingSceneChange = ""
    pendingSceneTimer = 0.0


var worldItems: Dictionary = {}
var nextUuid: int = 0


var worldFurniture: Dictionary = {}
var nextFurnitureId: int = 0

var lastKnownMap: Node = null
var pendingSceneScan: float = -1.0

var pendingSecondScan: float = -1.0
var pendingHostReady: float = -1.0
var pendingHostSceneName: String = ""
var pendingSpawnPosition: Vector3 = Vector3.ZERO

var pendingSecondLootSync: float = -1.0


const LOOT_MANIFEST_DELAY = 2.0
const HOST_READY_BROADCAST_DELAY: float = 3.0
const CLIENT_RESYNC_DELAY: float = 4.0
var pendingLootBroadcast: float = -1.0


func ScanIfNeeded(delta: float):

    var currentMap = GetMap()


    if currentMap != lastKnownMap:

        worldItems.clear()
        worldFurniture.clear()
        worldAI.clear()
        aiTargets.clear()
        nextUuid = 0
        nextFurnitureId = 0
        pendingSecondLootSync = -1.0
        sceneReady = false
        # Host seed reset is done pre-LoadScene in Loader_Override so the
        # scene's first _ready-triggered _ensure_session_seed generates the
        # authoritative seed (same one broadcast via HostSceneReady). Resetting
        # here would fuck it and force a second, different seed.
        if _ai_sync():
            _ai_sync()._pending_spawns.clear()
        if _event_sync():
            _event_sync()._pending_events.clear()
        lastKnownMap = currentMap


        if currentMap:
            sceneReady = true
            _recover_tracked_ai()
            pendingSceneScan = 1.0
            pendingSecondScan = 5.0

            if _net().IsActive() && multiplayer.multiplayer_peer && multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
                if multiplayer.is_server():
                    pendingHostSceneName = currentMap.get("mapName") if currentMap.get("mapName") else ""
                    pendingHostReady = HOST_READY_BROADCAST_DELAY
                    # keep drain paused for the 3s broadcast-wait window (host's own Compiler.Spawn already cleared isTransitioning at this point)
                    gameData.isTransitioning = true
                    print("[PlayerManager] Host entered scene: " + pendingHostSceneName + " (broadcasting in 3s)")
                else:
                    if pendingSpawnPosition != Vector3.ZERO:
                        _coop_apply_client_spawn(pendingSpawnPosition)
                        pendingSpawnPosition = Vector3.ZERO
                    print("[PlayerManager] Client scene-change sync: requesting AI + loot manifest from host")
                    _ai_sync().RequestAISync.rpc_id(1)
                    RequestSceneLootSync.rpc_id(1)
                    _event_sync().RequestFireSync.rpc_id(1)
                    _event_sync().RequestRadioTVSync.rpc_id(1)
                    _interactable_sync().RequestDoorSync.rpc_id(1)
                    pendingSecondLootSync = CLIENT_RESYNC_DELAY


    if pendingHostReady > 0.0:
        pendingHostReady -= delta
        if pendingHostReady <= 0.0:
            var controller = GetLocalController()
            var hostPos = controller.global_position if controller else Vector3.ZERO
            _ensure_session_seed()
            print("[PlayerManager] Broadcasting HostSceneReady: " + pendingHostSceneName + " at " + str(hostPos) + " seed=" + str(coopSessionSeed))
            HostSceneReady.rpc(pendingHostSceneName, hostPos, coopSessionSeed)
            pendingHostSceneName = ""
            # broadcast-wait window ended; resume drain on host
            gameData.isTransitioning = false


    if pendingSceneScan > 0.0:

        pendingSceneScan -= delta

        if pendingSceneScan <= 0.0:
            RegisterSceneItems()
            RegisterSceneContainers()
            if multiplayer.is_server():
                pendingLootBroadcast = LOOT_MANIFEST_DELAY


    if pendingSecondScan > 0.0:

        pendingSecondScan -= delta

        if pendingSecondScan <= 0.0:
            RegisterSceneItems()
            RegisterSceneContainers()
            if multiplayer.is_server():
                pendingLootBroadcast = LOOT_MANIFEST_DELAY


    if pendingLootBroadcast > 0.0:

        pendingLootBroadcast -= delta

        if pendingLootBroadcast <= 0.0:
            _broadcast_scene_loot_manifest()


    if pendingSecondLootSync > 0.0:

        pendingSecondLootSync -= delta

        if pendingSecondLootSync <= 0.0:
            if _net().IsActive() and !multiplayer.is_server():
                RequestSceneLootSync.rpc_id(1)
                _event_sync().RequestFireSync.rpc_id(1)
                _event_sync().RequestRadioTVSync.rpc_id(1)
                _interactable_sync().RequestDoorSync.rpc_id(1)


func _recover_tracked_ai():
    var scene = get_tree().current_scene
    if !scene:
        return
    var aiSpawner = scene.get_node_or_null("AI")
    if !aiSpawner:
        return
    var agents = aiSpawner.get_node_or_null("Agents")
    if !agents:
        return
    var recovered = 0
    for agent in agents.get_children():
        if !is_instance_valid(agent):
            continue
        if !agent.has_meta("network_uuid"):
            continue
        var uuid = int(agent.get_meta("network_uuid"))
        if !worldAI.has(uuid):
            worldAI[uuid] = agent
            if uuid >= nextAiUuid:
                nextAiUuid = uuid + 1
            recovered += 1
    if recovered > 0:
        print("[PlayerManager] Recovered " + str(recovered) + " AI that were spawned before ScanIfNeeded")


func _is_trader_display_item(node: Node) -> bool:
    if !node:
        return false
    var parent: Node = node.get_parent()
    while parent:
        var script = parent.get_script()
        if script and str(script.resource_path).ends_with("TraderDisplay.gd"):
            return true
        parent = parent.get_parent()
    return false


func RegisterSceneItems():

    var items = get_tree().get_nodes_in_group("Item")


    items.sort_custom(func(a, b): return str(a.get_path()) < str(b.get_path()))


    var registered = 0

    for item in items:
        if item is Pickup:
            if item.has_meta("network_uuid"):
                continue
            if _is_trader_display_item(item):
                continue
            item.set_meta("network_uuid", nextUuid)
            worldItems[nextUuid] = item
            nextUuid += 1
            registered += 1


    print("PlayerManager: registered " + str(registered) + " new scene items (total " + str(worldItems.size()) + ")")


func RegisterSceneContainers():
    var seen: Dictionary = {}
    var added: int = 0
    for collider in get_tree().get_nodes_in_group("Interactable"):
        if !is_instance_valid(collider):
            continue
        var node: Node = collider
        var root: LootContainer = null
        while node:
            if node is LootContainer:
                root = node
                break
            node = node.get_parent()
        if !root or seen.has(root):
            continue
        seen[root] = true
        if !root.is_in_group("CoopLootContainer"):
            root.add_to_group("CoopLootContainer")
            added += 1
    print("PlayerManager: registered " + str(seen.size()) + " containers (" + str(added) + " newly added to group)")


func _coop_apply_client_spawn(host_pos: Vector3) -> void:
    var controller = GetLocalController()
    if !controller:
        return
    controller.global_position = host_pos
    controller.velocity = Vector3.ZERO
    print("[PlayerManager] Client spawn: host=" + str(host_pos))


# ─── Scene loot manifest ─────────────────────────────────────────────────────

func _broadcast_scene_loot_manifest():
    if !multiplayer.is_server():
        return
    var map = GetMap()
    if !map:
        return
    var mapName: String = str(map.get("mapName")) if map.get("mapName") else ""
    var manifest = _build_scene_loot_manifest()
    print("[PlayerManager] Broadcasting scene loot manifest for " + mapName + ": " + str(manifest.items.size()) + " items, " + str(manifest.containers.size()) + " containers, " + str(manifest.furniture.size()) + " furniture")
    ApplySceneLootManifest.rpc(mapName, manifest.items, manifest.containers, manifest.furniture)


func _build_scene_loot_manifest() -> Dictionary:
    var items: Array = []
    for uuid in worldItems:
        var pickup = worldItems[uuid]
        if !is_instance_valid(pickup):
            continue
        if !pickup.slotData or !pickup.slotData.itemData:
            continue
        if _is_inside_skeleton(pickup):
            continue
        items.append({
            "uuid": uuid,
            "file": pickup.slotData.itemData.file,
            "pos": pickup.global_position,
            "rot": pickup.global_rotation,
            "slotDict": SerializeSlotData(pickup.slotData),
        })

    var furniture: Array = []
    for root in _coop_iter_furniture_roots():
        var component = _coop_find_furniture_component(root)
        if !component or !component.itemData:
            continue
        var fid: int
        if root.has_meta("coop_furniture_id"):
            fid = int(root.get_meta("coop_furniture_id"))
        else:
            fid = nextFurnitureId
            nextFurnitureId += 1
            root.set_meta("coop_furniture_id", fid)
            worldFurniture[fid] = root
            if root is LootContainer:
                root.set_meta("coop_container_id", fid)
        furniture.append({
            "fid": fid,
            "file": component.itemData.file,
            "pos": root.global_position,
            "rot": root.global_rotation,
            "scale": root.scale,
        })

    var container_set: Dictionary = {}
    for container in get_tree().get_nodes_in_group("CoopLootContainer"):
        if !is_instance_valid(container):
            continue
        if container.containerName == "Corpse":
            continue
        container_set[_coop_container_id(container)] = container

    for collider in get_tree().get_nodes_in_group("Interactable"):
        if !is_instance_valid(collider):
            continue
        var node: Node = collider
        while node:
            if node is LootContainer:
                var cid = _coop_container_id(node)
                if !container_set.has(cid) and node.containerName != "Corpse":
                    container_set[cid] = node
                    if !node.is_in_group("CoopLootContainer"):
                        node.add_to_group("CoopLootContainer")
                break
            node = node.get_parent()

    var containers: Array = []
    for cid in container_set:
        var container = container_set[cid]
        var content = container.storage if container.storaged else container.loot
        var serialized: Array = []
        for slot in content:
            serialized.append(SerializeSlotData(slot))
        containers.append({
            "id": cid,
            "loot": serialized,
            "storaged": container.storaged,
            "visible": container.visible,
            "disabled": container.process_mode == Node.PROCESS_MODE_DISABLED,
        })

    print("[PlayerManager] Manifest built: " + str(items.size()) + " items, " + str(containers.size()) + " containers, " + str(furniture.size()) + " furniture (fids=" + str(furniture.map(func(f): return f.fid)) + ")")
    return {"items": items, "containers": containers, "furniture": furniture}


func _coop_iter_furniture_roots() -> Array:
    return _furniture_sync()._coop_iter_furniture_roots()

func _coop_find_furniture_component(root: Node) -> Furniture:
    return _furniture_sync()._coop_find_furniture_component(root)

func _find_furniture_by_id(fid: int) -> Node3D:
    return _furniture_sync()._find_furniture_by_id(fid)


const COOP_POS_HASH_SNAP: float = 0.1


func CoopPosHash(pos: Vector3) -> int:
    return hash(Vector3(
        snappedf(pos.x, COOP_POS_HASH_SNAP),
        snappedf(pos.y, COOP_POS_HASH_SNAP),
        snappedf(pos.z, COOP_POS_HASH_SNAP)
    ))


func CoopSeedForNode(node: Node3D) -> int:
    if !multiplayer.is_server():
        while coopSessionSeed == 0:
            if !_net() or !_net().IsActive():
                return 0
            await get_tree().process_frame
    return CoopPosHash(node.global_position) ^ _ensure_session_seed()


func _coop_container_id(container) -> int:
    if container.has_meta("coop_container_id"):
        return int(container.get_meta("coop_container_id"))
    return CoopPosHash(container.global_position)


func _is_inside_skeleton(node: Node) -> bool:
    var parent = node.get_parent()
    while parent:
        if parent is Skeleton3D:
            return true
        parent = parent.get_parent()
    return false


@rpc("any_peer", "reliable", "call_remote")
func RequestSceneLootSync():
    if !multiplayer.is_server():
        return
    var map = GetMap()
    if !map:
        return
    var mapName: String = str(map.get("mapName")) if map.get("mapName") else ""
    var sender = multiplayer.get_remote_sender_id()
    var manifest = _build_scene_loot_manifest()
    print("[PlayerManager] Sending scene loot manifest to peer " + str(sender) + " for " + mapName + ": " + str(manifest.items.size()) + " items, " + str(manifest.containers.size()) + " containers, " + str(manifest.furniture.size()) + " furniture")
    ApplySceneLootManifest.rpc_id(sender, mapName, manifest.items, manifest.containers, manifest.furniture)


@rpc("authority", "reliable", "call_remote")
func ApplySceneLootManifest(sceneName: String, items: Array, containers: Array, furniture: Array = []):
    print("[PlayerManager] Received loot manifest for " + sceneName + ": " + str(items.size()) + " items, " + str(containers.size()) + " containers, " + str(furniture.size()) + " furniture")
    var map = GetMap()
    if !map:
        print("[PlayerManager] Ignoring loot manifest — no map loaded")
        return
    var currentSceneName: String = str(map.get("mapName")) if map.get("mapName") else ""
    if currentSceneName != sceneName:
        print("[PlayerManager] Ignoring loot manifest for " + sceneName + " (currently in " + currentSceneName + ")")
        return

    var manifest_uuids: Dictionary = {}
    for item_data in items:
        manifest_uuids[int(item_data.get("uuid", -1))] = true

    for pickup in get_tree().get_nodes_in_group("Item"):
        if !(pickup is Pickup):
            continue
        if _is_inside_skeleton(pickup):
            continue
        if _is_trader_display_item(pickup):
            continue
        var keep: bool = false
        if pickup.has_meta("network_uuid"):
            var existing_uuid: int = int(pickup.get_meta("network_uuid"))
            if manifest_uuids.has(existing_uuid):
                keep = true
        if !keep:
            pickup.queue_free()

    var manifest_fids: Dictionary = {}
    for entry in furniture:
        manifest_fids[int(entry.get("fid", -1))] = true

    if furniture.size() > 0:
        for root in _coop_iter_furniture_roots():
            var keep: bool = false
            if root.has_meta("coop_furniture_id"):
                var existing_fid: int = int(root.get_meta("coop_furniture_id"))
                if manifest_fids.has(existing_fid):
                    keep = true
            if !keep:
                root.queue_free()
        for fid in worldFurniture.keys().duplicate():
            if !manifest_fids.has(fid) or !is_instance_valid(worldFurniture[fid]):
                worldFurniture.erase(fid)

    await get_tree().process_frame

    for uuid in worldItems.keys().duplicate():
        var existing = worldItems[uuid]
        if !is_instance_valid(existing):
            worldItems.erase(uuid)

    for item_data in items:
        _spawn_manifest_item(map, item_data)

    for furniture_entry in furniture:
        _spawn_manifest_furniture(map, furniture_entry)

    var container_lookup: Dictionary = {}
    for container in get_tree().get_nodes_in_group("CoopLootContainer"):
        if !is_instance_valid(container):
            continue
        if container.containerName == "Corpse":
            continue
        container_lookup[_coop_container_id(container)] = container

    # Also walk Interactable group for containers not yet in CoopLootContainer - fixes bullshittery
    for collider in get_tree().get_nodes_in_group("Interactable"):
        if !is_instance_valid(collider):
            continue
        var node: Node = collider
        while node:
            if node is LootContainer:
                var cid = _coop_container_id(node)
                if !container_lookup.has(cid) and node.containerName != "Corpse":
                    container_lookup[cid] = node
                    if !node.is_in_group("CoopLootContainer"):
                        node.add_to_group("CoopLootContainer")
                break
            node = node.get_parent()

    var matched_containers = 0
    for container_data in containers:
        var cid: int = container_data.get("id", 0)
        if !container_lookup.has(cid):
            continue
        var container = container_lookup[cid]
        var serialized: Array = container_data.get("loot", [])
        var storaged: bool = container_data.get("storaged", false)
        if storaged:
            container.storage.clear()
            for dict in serialized:
                var slot = DeserializeSlotData(dict)
                if slot:
                    container.storage.append(slot)
            container.storaged = true
        else:
            container.loot.clear()
            for dict in serialized:
                var slot = DeserializeSlotData(dict)
                if slot:
                    container.loot.append(slot)
        if container_data.has("visible"):
            container.visible = bool(container_data.get("visible", true))
        if container_data.has("disabled"):
            var should_disable: bool = bool(container_data.get("disabled", false))
            container.process_mode = Node.PROCESS_MODE_DISABLED if should_disable else Node.PROCESS_MODE_INHERIT
        matched_containers += 1

    print("[PlayerManager] Applied scene loot manifest: " + str(items.size()) + " items, " + str(matched_containers) + "/" + str(containers.size()) + " containers, " + str(furniture.size()) + " furniture")


func _spawn_manifest_item(map: Node, item_data: Dictionary):
    var file: String = item_data.get("file", "")
    if file == "":
        return
    var uuid: int = item_data.get("uuid", -1)
    if uuid >= 0 and worldItems.has(uuid) and is_instance_valid(worldItems[uuid]):
        var existing = worldItems[uuid]
        existing.global_position = item_data.get("pos", existing.global_position)
        existing.global_rotation = item_data.get("rot", existing.global_rotation)
        var slotDictExisting: Dictionary = item_data.get("slotDict", {})
        if slotDictExisting.size() > 0:
            _apply_slot_dict_to_pickup(existing, slotDictExisting)
        return
    var scene = Database.get(file)
    if !scene:
        push_warning("[PlayerManager] Manifest item not in Database: " + file + " — peer may be missing a mod")
        return

    var pickup = scene.instantiate()
    map.add_child(pickup)
    pickup.global_position = item_data.get("pos", Vector3.ZERO)
    pickup.global_rotation = item_data.get("rot", Vector3.ZERO)

    var slotDict: Dictionary = item_data.get("slotDict", {})
    if slotDict.size() > 0:
        _apply_slot_dict_to_pickup(pickup, slotDict)

    pickup.freeze = true

    if uuid >= 0:
        pickup.set_meta("network_uuid", uuid)
        worldItems[uuid] = pickup
        if uuid >= nextUuid:
            nextUuid = uuid + 1


func _spawn_manifest_furniture(_map: Node, entry: Dictionary):
    var fid: int = int(entry.get("fid", -1))
    if fid < 0:
        return
    var file: String = entry.get("file", "")
    if Database.get(file) == null:
        push_warning("[PlayerManager] Manifest furniture not in Database: " + file + " — peer may be missing a mod")
        return
    _furniture_sync().BroadcastFurnitureSpawn(
        fid,
        file,
        entry.get("pos", Vector3.ZERO),
        entry.get("rot", Vector3.ZERO),
        entry.get("scale", Vector3.ONE)
    )


func GenerateUuid() -> int:
    var u = nextUuid
    nextUuid += 1
    return u


func GenerateFurnitureId() -> int:
    var f = nextFurnitureId
    nextFurnitureId += 1
    return f

func NextFurnitureToken() -> int:
    return _furniture_sync().NextFurnitureToken()


func RequestPickup(uuid: int):

    if !_net().IsActive():
        return

    if !worldItems.has(uuid):
        return

    var pickup = worldItems[uuid]
    if !is_instance_valid(pickup):
        worldItems.erase(uuid)
        return

    var iface = GetLocalInterface()
    if !iface:
        return

    var added: bool = false
    if iface.AutoStack(pickup.slotData, iface.inventoryGrid):
        added = true
    elif iface.Create(pickup.slotData, iface.inventoryGrid, false):
        added = true

    if !added:
        if iface.has_method("PlayError"):
            iface.PlayError()
        return

    iface.UpdateStats(false)
    if pickup.has_method("PlayPickup"):
        pickup.PlayPickup()

    worldItems.erase(uuid)
    pickup.queue_free()

    if multiplayer.is_server():
        BroadcastPickupRemove.rpc(uuid)
    else:
        SubmitPickupRemove.rpc_id(1, uuid)


@rpc("any_peer", "reliable", "call_remote")
func SubmitPickupRemove(uuid: int):
    if !multiplayer.is_server():
        return
    BroadcastPickupRemove.rpc(uuid)


@rpc("authority", "reliable", "call_local")
func BroadcastPickupRemove(uuid: int):
    if !worldItems.has(uuid):
        return
    var pickup = worldItems[uuid]
    if is_instance_valid(pickup):
        pickup.queue_free()
    worldItems.erase(uuid)


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


signal placement_token_received(token: int, uuid: int)
var _next_placement_token: int = 0


func NextPlacementToken() -> int:
    _next_placement_token += 1
    return _next_placement_token


@rpc("authority", "reliable", "call_remote")
func BroadcastPickupMove(uuid: int, pos: Vector3, rot: Vector3, frozen: bool = true):
    _pickup_targets[uuid] = {"pos": pos, "rot": rot, "frozen": frozen}


@rpc("any_peer", "reliable", "call_remote")
func SubmitPickupMove(uuid: int, pos: Vector3, rot: Vector3, frozen: bool = true):
    if !multiplayer.is_server():
        return
    _pickup_targets[uuid] = {"pos": pos, "rot": rot, "frozen": frozen}
    BroadcastPickupMove.rpc(uuid, pos, rot, frozen)


const PICKUP_LERP_EPSILON: float = 0.01


func _lerp_pickup_targets(delta: float):
    if _pickup_targets.is_empty():
        return
    var t: float = clampf(PICKUP_LERP_SPEED * delta, 0.0, 1.0)
    var stale: Array = []
    for uuid in _pickup_targets:
        if !worldItems.has(uuid):
            stale.append(uuid)
            continue
        var pickup = worldItems[uuid]
        if !is_instance_valid(pickup):
            stale.append(uuid)
            continue
        var target: Dictionary = _pickup_targets[uuid]
        if target.frozen and pickup.global_position.distance_to(target.pos) < PICKUP_LERP_EPSILON:
            pickup.global_position = target.pos
            pickup.global_rotation = target.rot
            pickup.freeze = true
            stale.append(uuid)
            continue
        pickup.global_position = pickup.global_position.lerp(target.pos, t)
        pickup.global_rotation.x = lerp_angle(pickup.global_rotation.x, target.rot.x, t)
        pickup.global_rotation.y = lerp_angle(pickup.global_rotation.y, target.rot.y, t)
        pickup.global_rotation.z = lerp_angle(pickup.global_rotation.z, target.rot.z, t)
        if target.frozen:
            pickup.freeze = true
        else:
            if pickup.has_method("Unfreeze"):
                pickup.Unfreeze()
            else:
                pickup.freeze = false
    for u in stale:
        _pickup_targets.erase(u)


@rpc("any_peer", "reliable", "call_remote")
func RequestPlacementSpawn(token: int, slotDict: Dictionary, initialPos: Vector3):
    if !multiplayer.is_server():
        return
    var sender = multiplayer.get_remote_sender_id()
    var uuid = GenerateUuid()
    BroadcastPickupSpawn.rpc(uuid, slotDict, initialPos, Vector3.ZERO, Vector3.ZERO)
    DeliverPlacementToken.rpc_id(sender, token, uuid)


@rpc("authority", "reliable", "call_remote")
func DeliverPlacementToken(token: int, uuid: int):
    placement_token_received.emit(token, uuid)


@rpc("authority", "reliable", "call_local")
func BroadcastPickupSpawn(uuid: int, slotDict: Dictionary, pos: Vector3, rotDeg: Vector3, vel: Vector3):

    var file = slotDict.get("file", "")

    if file == "":
        return


    var scene = Database.get(file)

    if !scene:
        push_warning("[PlayerManager] Pickup not in Database: " + file + " — peer may be missing a mod")
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


    _apply_slot_dict_to_pickup(pickup, slotDict)


    pickup.set_meta("network_uuid", uuid)
    worldItems[uuid] = pickup


    if uuid >= nextUuid:
        nextUuid = uuid + 1


func ShouldGenerateLoot() -> bool:
    if !_net().IsActive():
        return true
    return multiplayer.is_server()


func _find_container_by_id(cid: int) -> LootContainer:
    return _container_sync()._find_container_by_id(cid)

func SyncContainerStorage(container: LootContainer):
    _container_sync().SyncContainerStorage(container)

func TryOpenContainer(container) -> void:
    _container_sync().TryOpenContainer(container)

func ReleaseContainerLock(container) -> void:
    _container_sync().ReleaseContainerLock(container)


func _slot_serializer() -> Node:
    return get_node_or_null("SlotSerializer")


func SerializeSlotData(slot: SlotData) -> Dictionary:
    return _slot_serializer().SerializeSlotData(slot)


func DeserializeSlotData(dict: Dictionary) -> SlotData:
    return _slot_serializer().DeserializeSlotData(dict)


func LookupItemData(file: String) -> ItemData:
    return _slot_serializer().LookupItemData(file)


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
var aiTargets: Dictionary = {}


var pendingSceneChange: String = ""
var pendingSceneTimer: float = 0.0
const SCENE_CHANGE_TIMEOUT = 90.0


func GenerateAiUuid() -> int:
    return _ai_sync().GenerateAiUuid()

func GetNearestPlayerPosition(from: Vector3) -> Vector3:
    return _ai_sync().GetNearestPlayerPosition(from)

func GetNearestPlayerCamera(from: Vector3) -> Vector3:
    return _ai_sync().GetNearestPlayerCamera(from)


# ─── Sync module forwarders ──────────────────────────────────────────────────

func _event_sync() -> Node:
    return get_node_or_null("EventSync")

func _interactable_sync() -> Node:
    return get_node_or_null("InteractableSync")

func _container_sync() -> Node:
    return get_node_or_null("ContainerSync")

func _furniture_sync() -> Node:
    return get_node_or_null("FurnitureSync")

func _ai_sync() -> Node:
    return get_node_or_null("AISync")

func _quest_sync() -> Node:
    return get_node_or_null("QuestSync")

func _world_sync() -> Node:
    return get_node_or_null("WorldSync")


func _apply_slot_dict_to_pickup(pickup, slotDict: Dictionary):
    _slot_serializer().ApplySlotDictToPickup(pickup, slotDict)


@rpc("any_peer", "reliable", "call_remote")
func SubmitDeathContainer(pos: Vector3, items: Array):
    if !multiplayer.is_server():
        return
    SpawnDeathContainer.rpc(pos, items)


@rpc("authority", "reliable", "call_local")
func SpawnDeathContainer(pos: Vector3, items: Array):
    var map = GetMap()
    if !map:
        return
    var scene = Database.get("Crate_Military")
    if !scene:
        return
    var container = scene.instantiate()
    map.add_child(container)
    container.global_position = pos + Vector3(0, 0.5, 0)

    container.containerSize = Vector2(16, 16)
    container.loot.clear()
    container.storage.clear()
    for dict in items:
        var slot = DeserializeSlotData(dict)
        if slot and slot.itemData:
            container.loot.append(slot)
    container.storaged = false
    container.containerName = "Death Stash"

    var mesh = container.get_node_or_null("Mesh")
    if mesh:
        mesh.hide()

    var backpack_scene = Database.get("Duffel_Retro")
    if backpack_scene:
        var visual = backpack_scene.instantiate()
        visual.collision_layer = 0
        visual.collision_mask = 0
        visual.freeze = true
        if visual.is_in_group("Item"):
            visual.remove_from_group("Item")
        container.add_child(visual)

    if !container.is_in_group("CoopLootContainer"):
        container.add_to_group("CoopLootContainer")

    print("[PlayerManager] Death container spawned at " + str(pos) + " with " + str(items.size()) + " items")


@rpc("any_peer", "reliable", "call_remote")
func SubmitDeathStashRemove(cid: int):
    if !multiplayer.is_server():
        return
    BroadcastDeathStashRemove.rpc(cid)


@rpc("authority", "reliable", "call_local")
func BroadcastDeathStashRemove(cid: int):
    var container = _find_container_by_id(cid)
    if container and container.containerName == "Death Stash":
        container.queue_free()


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
