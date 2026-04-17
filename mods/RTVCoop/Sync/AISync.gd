extends Node

var gameData = preload("res://Resources/GameData.tres")

const AI_BROADCAST_RATE = 20.0
const AI_LERP_SPEED = 18.0
const AI_SOUND_FIRE = 0
const AI_SOUND_TAIL = 1
const AI_SOUND_IDLE = 2
const AI_SOUND_COMBAT = 3
const AI_SOUND_DAMAGE = 4
const AI_SOUND_DEATH = 5

var aiAccumulator: float = 0.0
var _pending_spawns: Array = []
const SPAWN_RETRY_INTERVAL = 0.5
const SPAWN_RETRY_MAX = 10

const MANIFEST_CHECK_INTERVAL: float = 60.0
var _manifest_timer: float = 0.0


func _pm():
    return get_parent()


func _physics_process(delta):
    if !_pm()._net().IsActive():
        return

    if multiplayer.is_server():
        aiAccumulator += delta
        if aiAccumulator >= 1.0 / AI_BROADCAST_RATE:
            aiAccumulator = 0.0
            BroadcastAIPositions()
    else:
        for uuid in _pm().aiTargets:
            if !_pm().worldAI.has(uuid):
                continue
            var ai = _pm().worldAI[uuid]
            if !is_instance_valid(ai) or !ai.is_inside_tree():
                continue
            var target = _pm().aiTargets[uuid]
            ai.global_position = ai.global_position.lerp(target["pos"], AI_LERP_SPEED * delta)
            ai.global_rotation.y = lerp_angle(ai.global_rotation.y, target["rot"].y, AI_LERP_SPEED * delta)
            if !ai.visible and !ai.dead:
                ai.show()
                ai.pause = false
                ai.process_mode = Node.PROCESS_MODE_INHERIT
                if ai.skeleton:
                    ai.skeleton.process_mode = Node.PROCESS_MODE_INHERIT
                    ai.skeleton.show_rest_only = false

    _process_pending_spawns()

    if !multiplayer.is_server() and _pm().sceneReady:
        _manifest_timer += delta
        if _manifest_timer >= MANIFEST_CHECK_INTERVAL:
            _manifest_timer = 0.0
            RequestAIManifest.rpc_id(1)


func _process_pending_spawns():
    if _pending_spawns.is_empty():
        return
    if !_pm().sceneReady:
        return
    var still_pending: Array = []
    for entry in _pending_spawns:
        if entry["timer"] > 0.0:
            entry["timer"] -= get_physics_process_delta_time()
            still_pending.append(entry)
            continue
        var success = _try_spawn_agent(entry)
        if !success:
            entry["retries"] += 1
            if entry["retries"] > SPAWN_RETRY_MAX:
                print("AISync: giving up on pending spawn uuid=" + str(entry["uuid"]) + " after " + str(SPAWN_RETRY_MAX) + " retries (pool exhausted)")
                continue
            entry["timer"] = SPAWN_RETRY_INTERVAL
            still_pending.append(entry)
    _pending_spawns = still_pending


func _get_ai_spawner():
    var scene = get_tree().current_scene
    if !scene:
        return null
    return scene.get_node_or_null("AI")


func _try_spawn_agent(entry: Dictionary) -> bool:
    var uuid: int = entry["uuid"]
    if _pm().worldAI.has(uuid):
        return true

    if !_pm().sceneReady:
        return false

    var aiSpawner = _get_ai_spawner()
    if !aiSpawner:
        return false

    var spawnType: String = entry.get("spawnType", "")
    var pool = aiSpawner.BPool if spawnType == "Boss" else aiSpawner.APool
    if pool.get_child_count() == 0:
        return false

    var newAgent = pool.get_child(0)
    newAgent.reparent(aiSpawner.agents)
    newAgent.global_position = entry["pos"]
    newAgent.global_rotation = entry["rot"]
    newAgent.set_meta("network_uuid", uuid)
    newAgent.spawnVariant = entry.get("variant", {})
    _pm().worldAI[uuid] = newAgent
    if entry.has("aiTarget"):
        _pm().aiTargets[uuid] = entry["aiTarget"]
    aiSpawner.activeAgents += 1
    if uuid >= _pm().nextAiUuid:
        _pm().nextAiUuid = uuid + 1

    _deferred_activate(newAgent, spawnType, entry.get("isSync", false))

    if !newAgent.has_method("_client_animate"):
        print("[AISync] WARNING: AI_Override NOT loaded on agent — vanilla AI.gd running. take_over_path failed for class_name script.")
    return true


func _deferred_activate(agent, spawnType: String, isSync: bool):
    if !is_instance_valid(agent) or !agent.is_inside_tree():
        return
    if isSync:
        if agent.has_method("EquipmentSetup"):
            agent.EquipmentSetup()
        agent.Activate()
    else:
        match spawnType:
            "Wanderer": agent.ActivateWanderer()
            "Guard": agent.ActivateGuard()
            "Hider": agent.ActivateHider()
            "Minion": agent.ActivateMinion()
            "Boss": agent.ActivateBoss()
    _ensure_ai_visible(agent)


func GenerateAiUuid() -> int:
    var u = _pm().nextAiUuid
    _pm().nextAiUuid += 1
    return u


func GetNearestPlayerPosition(from: Vector3) -> Vector3:
    var nearest = Vector3.ZERO
    var bestDist = INF
    var found = false
    var localCtrl = _pm().GetLocalController()
    if localCtrl and localCtrl.is_inside_tree():
        var d = from.distance_squared_to(localCtrl.global_position)
        if d < bestDist:
            bestDist = d
            nearest = localCtrl.global_position
            found = true
    for id in _pm().remotePlayers:
        var puppet = _pm().remotePlayers[id]
        if !is_instance_valid(puppet) or !puppet.is_inside_tree():
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
    var localCtrl = _pm().GetLocalController()
    if localCtrl and localCtrl.is_inside_tree():
        var d = from.distance_squared_to(localCtrl.global_position)
        if d < bestDist:
            bestDist = d
            nearestCam = gameData.cameraPosition
            found = true
    for id in _pm().remotePlayers:
        var puppet = _pm().remotePlayers[id]
        if !is_instance_valid(puppet) or !puppet.is_inside_tree():
            continue
        var d = from.distance_squared_to(puppet.global_position)
        if d < bestDist:
            bestDist = d
            nearestCam = puppet.global_position + Vector3(0, 1.6, 0)
            found = true
    return nearestCam if found else Vector3.ZERO


func BroadcastAIPositions():
    if _pm().worldAI.is_empty():
        return
    var uuids: Array = []
    var positions: PackedVector3Array = PackedVector3Array()
    var rotations: PackedVector3Array = PackedVector3Array()
    var speeds: PackedFloat32Array = PackedFloat32Array()
    var aiStates: PackedInt32Array = PackedInt32Array()
    for uuid in _pm().worldAI:
        var ai = _pm().worldAI[uuid]
        if !is_instance_valid(ai) or !ai.is_inside_tree():
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
        if !_pm().worldAI.has(uuid):
            continue
        var ai = _pm().worldAI[uuid]
        if !is_instance_valid(ai) or !ai.is_inside_tree():
            continue
        _pm().aiTargets[uuid] = {"pos": positions[i], "rot": rotations[i]}
        ai.speed = speeds[i]
        ai.currentState = states[i]


@rpc("authority", "reliable", "call_remote")
func BroadcastAISpawn(uuid: int, spawnType: String, spawnPos: Vector3, spawnRot: Vector3, variant: Dictionary):
    if _pm().worldAI.has(uuid):
        return
    var entry = {
        "uuid": uuid,
        "spawnType": spawnType,
        "pos": spawnPos,
        "rot": spawnRot,
        "variant": variant,
        "isSync": false,
        "retries": 0,
        "timer": 0.0,
    }
    if !_try_spawn_agent(entry):
        _pending_spawns.append(entry)


@rpc("any_peer", "reliable", "call_remote")
func RequestAISync():
    if !multiplayer.is_server():
        return
    var sender = multiplayer.get_remote_sender_id()
    print("AISync: AI sync requested by peer " + str(sender) + " — sending " + str(_pm().worldAI.size()) + " AI")
    for uuid in _pm().worldAI:
        var ai = _pm().worldAI[uuid]
        if !is_instance_valid(ai) or !ai.is_inside_tree():
            continue
        SyncSingleAI.rpc_id(sender, uuid, ai.global_position, ai.global_rotation, ai.spawnVariant)


@rpc("authority", "reliable", "call_remote")
func SyncSingleAI(uuid: int, pos: Vector3, rot: Vector3, variant: Dictionary):
    if _pm().worldAI.has(uuid):
        return
    var entry = {
        "uuid": uuid,
        "spawnType": "",
        "pos": pos,
        "rot": rot,
        "variant": variant,
        "isSync": true,
        "aiTarget": {"pos": pos, "rot": rot},
        "retries": 0,
        "timer": 0.0,
    }
    if !_try_spawn_agent(entry):
        _pending_spawns.append(entry)


func _ensure_ai_visible(agent):
    if !is_instance_valid(agent):
        return
    agent.show()
    agent.pause = false
    agent.process_mode = Node.PROCESS_MODE_INHERIT
    if agent.skeleton:
        agent.skeleton.show_rest_only = false
        agent.skeleton.process_mode = Node.PROCESS_MODE_INHERIT
        agent.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
    if agent.animator:
        agent.animator.active = true
        agent.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
    if agent.get("_client_anim_ready") != null:
        agent._client_anim_ready = false


@rpc("authority", "reliable", "call_remote")
func BroadcastAISound(uuid: int, sound_type: int, fullAuto: bool = false):
    if !_pm().worldAI.has(uuid):
        return
    var ai = _pm().worldAI[uuid]
    if !is_instance_valid(ai):
        return
    ai._coop_force_local_play = true
    match sound_type:
        AI_SOUND_FIRE:
            ai.fullAuto = fullAuto
            ai.PlayFire()
        AI_SOUND_TAIL: ai.PlayTail()
        AI_SOUND_IDLE: ai.PlayIdle()
        AI_SOUND_COMBAT: ai.PlayCombat()
        AI_SOUND_DAMAGE: ai.PlayDamage()
        AI_SOUND_DEATH: ai.PlayDeath()
    ai._coop_force_local_play = false


@rpc("authority", "reliable", "call_remote")
func BroadcastAIDeath(uuid: int, direction: Vector3, force: float, container_loot: Array = [], weapon_dict: Dictionary = {}, backpack_dict: Dictionary = {}, secondary_dict: Dictionary = {}):
    if !_pm().worldAI.has(uuid):
        return
    var ai = _pm().worldAI[uuid]
    if !is_instance_valid(ai):
        _pm().worldAI.erase(uuid)
        return
    if container_loot.size() > 0 and ai.container and ai.container is LootContainer:
        ai.container.loot.clear()
        for dict in container_loot:
            var slot = _pm().DeserializeSlotData(dict)
            if slot:
                ai.container.loot.append(slot)
    if weapon_dict.size() > 0 and ai.weapon and ai.weapon.slotData:
        _pm()._apply_slot_dict_to_pickup(ai.weapon, weapon_dict)
    if backpack_dict.size() > 0 and ai.backpack and ai.backpack.slotData:
        _pm()._apply_slot_dict_to_pickup(ai.backpack, backpack_dict)
    if secondary_dict.size() > 0 and ai.secondary and ai.secondary.slotData:
        _pm()._apply_slot_dict_to_pickup(ai.secondary, secondary_dict)
    ai.Death(direction, force)
    _pm().worldAI.erase(uuid)
    if ai.container and ai.container is LootContainer:
        if !ai.container.is_in_group("CoopLootContainer"):
            ai.container.add_to_group("CoopLootContainer")
        ai.container.set_meta("coop_container_id", uuid)


@rpc("any_peer", "reliable", "call_remote")
func RequestAIManifest():
    if !multiplayer.is_server():
        return
    var sender = multiplayer.get_remote_sender_id()
    var uuids: PackedInt32Array = PackedInt32Array()
    for uuid in _pm().worldAI:
        var ai = _pm().worldAI[uuid]
        if !is_instance_valid(ai) or !ai.is_inside_tree():
            continue
        uuids.append(int(uuid))
    DeliverAIManifest.rpc_id(sender, uuids)


@rpc("authority", "reliable", "call_remote")
func DeliverAIManifest(host_uuids: PackedInt32Array):
    var host_set: Dictionary = {}
    for u in host_uuids:
        host_set[int(u)] = true
    var client_set: Dictionary = {}
    for u in _pm().worldAI:
        client_set[int(u)] = true

    var missing_on_client: Array = []
    var extra_on_client: Array = []
    for u in host_set:
        if !client_set.has(u):
            missing_on_client.append(u)
    for u in client_set:
        if !host_set.has(u):
            extra_on_client.append(u)

    if missing_on_client.is_empty() and extra_on_client.is_empty():
        return

    print("[AISync] Manifest drift — host=" + str(host_uuids.size()) + " client=" + str(_pm().worldAI.size())
        + " missing=" + str(missing_on_client.size()) + " extra=" + str(extra_on_client.size())
        + " — requesting full resync")

    # dead AI must keep their corpse node — only free if still alive-on-client but gone-on-host
    for u in extra_on_client:
        var ai = _pm().worldAI.get(u)
        if is_instance_valid(ai) and !ai.dead:
            ai.queue_free()
        _pm().worldAI.erase(u)
        _pm().aiTargets.erase(u)

    if !missing_on_client.is_empty():
        RequestAISync.rpc_id(1)


@rpc("any_peer", "reliable", "call_remote")
func RequestAIDamage(uuid: int, hitbox: String, damage: float):
    if !multiplayer.is_server():
        return
    if !_pm().worldAI.has(uuid):
        return
    var ai = _pm().worldAI[uuid]
    if !is_instance_valid(ai):
        _pm().worldAI.erase(uuid)
        return
    ai.WeaponDamage(hitbox, damage)
