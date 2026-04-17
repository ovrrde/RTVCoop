extends Node

const HELI_ROCKET_MATCH_RADIUS: float = 500.0
const ROCKET_EXPLODE_MATCH_RADIUS: float = 10.0
const ROCKET_CLEANUP_MATCH_RADIUS: float = 50.0
const ROCKET_EXPLOSION_SIZE: float = 20.0
const BTR_CRACK_DISTANCE_THRESHOLD: float = 50.0
const BTR_CRACK_DELAY_S: float = 0.1
const SLEEP_ENERGY_DRAIN: float = 20.0
const SLEEP_HYDRATION_DRAIN: float = 20.0
const SLEEP_MENTAL_REGEN: float = 20.0
const SLEEP_HOUR_TO_SIM_TIME: float = 100.0
const DAY_DURATION: float = 2400.0


var gameData = preload("res://Resources/GameData.tres")


func _pm():
    return get_parent()


func _physics_process(_delta):
    if _pending_events.is_empty():
        return
    var eventSystem = _find_event_system()
    if !eventSystem:
        return
    var to_process = _pending_events.duplicate()
    _pending_events.clear()
    for event in to_process:
        _apply_event(event["name"], event["params"], eventSystem)


func _find_event_system() -> Node:
    var tree = get_tree()
    if !tree:
        return null
    for g in ["EventSystem", "Events"]:
        for n in tree.get_nodes_in_group(g):
            if is_instance_valid(n):
                return n
    var roots: Array = []
    if tree.current_scene: roots.append(tree.current_scene)
    var map = tree.root.get_node_or_null("Map")
    if map and !roots.has(map): roots.append(map)
    for r in tree.root.get_children():
        if !roots.has(r): roots.append(r)
    for r in roots:
        var direct = r.get_node_or_null("EventSystem")
        if direct: return direct
        var deep = r.find_child("EventSystem", true, false)
        if deep: return deep
        var by_script = _scan_for_es(r)
        if by_script: return by_script
    return null


func _scan_for_es(n: Node) -> Node:
    if !is_instance_valid(n):
        return null
    var s = n.get_script()
    if s and str(s.resource_path).find("EventSystem") != -1:
        return n
    if n.has_method("FighterJet") and n.has_method("Airdrop") and n.has_method("Helicopter"):
        return n
    for c in n.get_children():
        var hit = _scan_for_es(c)
        if hit: return hit
    return null


var _pending_events: Array = []


@rpc("authority", "reliable", "call_remote")
func BroadcastEvent(eventName: String, params: Dictionary):
    if !_pm().sceneReady:
        _pending_events.append({"name": eventName, "params": params})
        return
    var eventSystem = _find_event_system()
    if !eventSystem:
        _pending_events.append({"name": eventName, "params": params})
        return
    _apply_event(eventName, params, eventSystem)


func _apply_event(eventName: String, params: Dictionary, eventSystem: Node):
    var cname: String = params.get("_cname", "")
    match eventName:
        "FighterJet":
            var ev = load("res://Assets/Fighter_Jet/Fighter_Jet.tscn").instantiate()
            if cname != "": ev.name = cname
            eventSystem.add_child(ev)
            ev.global_position = params.get("pos", ev.global_position)
            ev.global_rotation = params.get("rot", ev.global_rotation)

        "Airdrop":
            var ev = load("res://Assets/CASA/CASA.tscn").instantiate()
            if cname != "": ev.name = cname
            eventSystem.add_child(ev)
            ev.global_position = params.get("pos", ev.global_position)
            ev.global_rotation = params.get("rot", ev.global_rotation)
            if params.has("dropThreshold"):
                ev.dropThreshold = params["dropThreshold"]

        "Helicopter":
            var ev = load("res://Assets/Helicopter/Helicopter.tscn").instantiate()
            if cname != "": ev.name = cname
            eventSystem.add_child(ev)
            ev.global_position = params.get("pos", ev.global_position)
            ev.global_rotation = params.get("rot", ev.global_rotation)

        "Police":
            var paths_node = eventSystem.get_node_or_null("Paths")
            if !paths_node:
                return
            var pathIndex: int = int(params.get("pathIndex", 0))
            if pathIndex >= paths_node.get_child_count():
                return
            var selectedPath = paths_node.get_child(pathIndex)
            var inversePath: bool = params.get("inverse", false)
            var waypoint = selectedPath.get_child(selectedPath.get_child_count() - 1) if inversePath else selectedPath.get_child(0)
            var ev = load("res://Assets/Police/Police.tscn").instantiate()
            if cname != "": ev.name = cname
            eventSystem.add_child(ev)
            ev.selectedPath = selectedPath
            ev.inversePath = inversePath
            ev.global_transform = waypoint.global_transform

        "BTR":
            var paths_node = eventSystem.get_node_or_null("Paths")
            if !paths_node:
                return
            var pathIndex: int = int(params.get("pathIndex", 0))
            if pathIndex >= paths_node.get_child_count():
                return
            var selectedPath = paths_node.get_child(pathIndex)
            var inversePath: bool = params.get("inverse", false)
            var waypoint = selectedPath.get_child(selectedPath.get_child_count() - 1) if inversePath else selectedPath.get_child(0)
            var ev = load("res://Assets/BTR/BTR.tscn").instantiate()
            if cname != "": ev.name = cname
            eventSystem.add_child(ev)
            ev.selectedPath = selectedPath
            ev.inversePath = inversePath
            ev.global_transform = waypoint.global_transform

        "CrashSite":
            var crashes_node = eventSystem.get_node_or_null("Crashes")
            if !crashes_node:
                return
            var crashIndex: int = int(params.get("crashIndex", 0))
            if crashIndex >= crashes_node.get_child_count():
                return
            var randomCrash = crashes_node.get_child(crashIndex)
            var ev = load("res://Assets/Helicopter/Helicopter_Crash.tscn").instantiate()
            randomCrash.add_child(ev)
            ev.global_transform = randomCrash.global_transform

        "Cat":
            if gameData.catFound or gameData.catDead:
                return
            var wells = get_tree().get_nodes_in_group("Well")
            if wells.size() == 0:
                return
            var wellIndex: int = int(params.get("wellIndex", 0))
            if wellIndex >= wells.size():
                return
            var randomWell: Node3D = wells[wellIndex]
            var wellBottom = randomWell.get_node_or_null("Bottom")
            if !wellBottom:
                return
            var catScene = load("res://Items/Lore/Cat/Cat.tscn")
            var rescueScene = load("res://Items/Lore/Cat/Rescue.tscn")
            var catInstance = catScene.instantiate()
            wellBottom.add_child(catInstance)
            catInstance.global_transform = wellBottom.global_transform
            var catSystem = catInstance.get_child(0)
            catSystem.currentState = catSystem.State.Rescue
            var rescueInstance = rescueScene.instantiate()
            wellBottom.add_child(rescueInstance)
            rescueInstance.global_transform = wellBottom.global_transform
            rescueInstance.cat = catInstance
            rescueInstance.position.y = 3.0

        "Transmission":
            var radios = get_tree().get_nodes_in_group("Radio")
            for radio in radios:
                radio.Transmission()


@rpc("authority", "reliable", "call_remote")
func BroadcastHelicopterRockets(heliPath: String, heliPos: Vector3, heliRot: Vector3):
    var es = _find_event_system()
    if !es:
        return
    var heli = es.get_node_or_null(heliPath)
    if !heli:
        for child in es.get_children():
            if child.has_method("FireRockets") and child.global_position.distance_to(heliPos) < HELI_ROCKET_MATCH_RADIUS:
                heli = child
                break
    if heli and heli.has_method("FireRockets"):
        heli.global_position = heliPos
        heli.global_rotation = heliRot
        if heli.get("_coop_remote_fire") != null:
            heli._coop_remote_fire = true
        heli.FireRockets()


@rpc("authority", "unreliable", "call_remote")
func BroadcastAirdropPose(casaName: String, airdropPos: Vector3, airdropRot: Vector3, isReleased: bool):
    var es = _find_event_system()
    if !es:
        return
    var casa_node = es.get_node_or_null(casaName)
    if !casa_node:
        return
    var ad = casa_node.get_node_or_null("Airdrop")
    if !ad:
        var map = _pm().GetMap()
        if map:
            for child in map.get_children():
                if child.name.begins_with("Airdrop") and child is RigidBody3D:
                    ad = child
                    break
    if !ad:
        return
    ad.global_position = airdropPos
    ad.global_rotation = airdropRot
    if casa_node:
        if !casa_node.dropped:
            casa_node.dropped = true
            ad.show()
        if isReleased and !casa_node.released:
            casa_node.released = true
    if isReleased and ad.get_parent() != null and ad.get_parent() != _pm().GetMap():
        var map = _pm().GetMap()
        if map:
            ad.reparent(map)
            ad.show()
            ad.freeze = true


@rpc("authority", "reliable", "call_local")
func BroadcastAirdropLanding(pos: Vector3, rot: Vector3):
    var ad = _find_airdrop()
    if !ad:
        return
    ad.global_position = pos
    ad.global_rotation = rot
    if ad is RigidBody3D:
        ad.freeze = true
        ad.linear_velocity = Vector3.ZERO
        ad.angular_velocity = Vector3.ZERO
    _reseed_airdrop_loot(ad, pos)


func _find_airdrop() -> Node:
    var map = _pm().GetMap()
    if map:
        for child in map.get_children():
            if child.name.begins_with("Airdrop") and child is RigidBody3D:
                return child
    var es = _find_event_system()
    if es:
        for casa in es.get_children():
            var ad = casa.get_node_or_null("Airdrop")
            if ad:
                return ad
    return null


func _reseed_airdrop_loot(container: Node, landing_pos: Vector3):
    if !container.has_method("GenerateLoot"):
        return
    if container.get("loot") != null:
        container.loot.clear()
    if container.get("storage") != null:
        container.storage.clear()
    if container.get("storaged") != null:
        container.storaged = false
    for c in container.get_children():
        if c.is_in_group("Item"):
            c.queue_free()
    seed(_pm().CoopPosHash(landing_pos) ^ _pm()._ensure_session_seed())
    if container.get("custom") and container.get("force"):
        for index in container.custom.items.size():
            container.CreateLoot(container.custom.items[index])
    elif container.get("custom"):
        container.ClearBuckets()
        if container.has_method("FillBucketsCustom"):
            container.FillBucketsCustom()
        else:
            container.FillBuckets()
        container.GenerateLoot()
    else:
        container.ClearBuckets()
        container.FillBuckets()
        container.GenerateLoot()
    randomize()


@rpc("authority", "reliable", "call_remote")
func BroadcastBTRFire(btrName: String, fullAuto: bool):
    var es = _find_event_system()
    if !es:
        return
    var btr = es.get_node_or_null(btrName)
    if !btr:
        return
    btr.fullAuto = fullAuto
    btr.playerDistance = btr.global_position.distance_to(gameData.playerPosition)
    btr._coop_remote_fire = true
    btr.Muzzle()
    btr.PlayFire()
    btr.PlayTail()
    if btr.playerDistance > BTR_CRACK_DISTANCE_THRESHOLD:
        await get_tree().create_timer(BTR_CRACK_DELAY_S, false).timeout
        btr.PlayCrack()


@rpc("authority", "reliable", "call_remote")
func BroadcastRocketExplode(pos: Vector3):
    var best = null
    var best_dist = ROCKET_EXPLODE_MATCH_RADIUS
    for rocket in get_tree().get_nodes_in_group("CoopRocket"):
        if !is_instance_valid(rocket):
            continue
        var d = rocket.global_position.distance_to(pos)
        if d < best_dist:
            best_dist = d
            best = rocket
    if best:
        best.queue_free()
    var explosion_scene = load("res://Effects/Explosion.tscn")
    if explosion_scene:
        var instance = explosion_scene.instantiate()
        get_tree().get_root().add_child(instance)
        instance.global_position = pos
        instance.size = ROCKET_EXPLOSION_SIZE
        if instance.has_method("Explode"):
            instance.Explode()


@rpc("authority", "reliable", "call_remote")
func BroadcastRocketCleanup(pos: Vector3):
    var best = null
    var best_dist = ROCKET_CLEANUP_MATCH_RADIUS
    for rocket in get_tree().get_nodes_in_group("CoopRocket"):
        if !is_instance_valid(rocket):
            continue
        var d = rocket.global_position.distance_to(pos)
        if d < best_dist:
            best_dist = d
            best = rocket
    if best:
        best.queue_free()


@rpc("authority", "reliable", "call_remote")
func BroadcastHelicopterSpotted():
    Loader.Message("You have been spotted!", Color.RED)


var _sleep_ready: Dictionary = {}
var _sleep_in_progress: bool = false


@rpc("any_peer", "reliable", "call_remote")
func RequestSleepReady(hours: int):
    if !multiplayer.is_server():
        return
    HostToggleSleepReady(multiplayer.get_remote_sender_id(), hours)


func HostToggleSleepReady(peer_id: int, hours: int):
    if !multiplayer.is_server() or _sleep_in_progress:
        return
    if _sleep_ready.has(peer_id):
        _sleep_ready.erase(peer_id)
    else:
        _sleep_ready[peer_id] = hours
    var total: int = 1 + _pm()._net().GetPeerIds().size()
    var ready_ids: Array = _sleep_ready.keys()
    BroadcastSleepStatus.rpc(ready_ids, total)
    if _sleep_ready.size() >= total:
        var max_hours: int = 0
        for id in _sleep_ready:
            if int(_sleep_ready[id]) > max_hours:
                max_hours = int(_sleep_ready[id])
        _sleep_in_progress = true
        _sleep_ready.clear()
        BroadcastSleepStatus.rpc([], total)
        BroadcastSleep.rpc(max_hours)


@rpc("authority", "reliable", "call_local")
func BroadcastSleepStatus(ready_ids: Array, total: int):
    _pm().set_meta("coop_sleep_ready_ids", ready_ids)
    _pm().set_meta("coop_sleep_total", total)


@rpc("any_peer", "reliable", "call_remote")
func RequestSleep():
    if !multiplayer.is_server():
        return
    var beds = get_tree().get_nodes_in_group("Interactable")
    for collider in beds:
        var node = collider
        while node:
            if node.has_method("Interact") and node.get("canSleep") != null:
                if node.canSleep:
                    BroadcastSleep.rpc(node.randomSleep)
                return
            node = node.get_parent()


@rpc("authority", "reliable", "call_local")
func BroadcastSleep(sleepHours: int):
    gameData.isSleeping = true
    gameData.freeze = true
    Simulation.simulate = false

    var sleepTime = sleepHours * SLEEP_HOUR_TO_SIM_TIME
    var currentTime = Simulation.time
    var combinedTime = currentTime + sleepTime
    if combinedTime >= DAY_DURATION:
        Simulation.day += 1
        Simulation.time = combinedTime - DAY_DURATION
        Simulation.weatherTime -= sleepTime
    else:
        Simulation.time = combinedTime
        Simulation.weatherTime -= sleepTime

    gameData.energy -= SLEEP_ENERGY_DRAIN
    gameData.hydration -= SLEEP_HYDRATION_DRAIN
    gameData.mental += SLEEP_MENTAL_REGEN

    Loader.Message("You slept " + str(sleepHours) + " hours", Color.GREEN)

    await get_tree().create_timer(float(sleepHours), false).timeout

    Simulation.simulate = true
    gameData.isSleeping = false
    gameData.freeze = false
    _sleep_in_progress = false

    for collider in get_tree().get_nodes_in_group("Interactable"):
        var node = collider
        while node:
            if node.get("canSleep") != null:
                node.canSleep = false
                break
            node = node.get_parent()


@rpc("any_peer", "reliable", "call_remote")
func RequestFireSync():
    if !multiplayer.is_server():
        return
    var sender = multiplayer.get_remote_sender_id()
    var fires: Array = []
    for fire in _all_fires():
        fires.append({"path": fire.get_path(), "active": bool(fire.active)})
    print("[EventSync] Sending fire manifest to peer " + str(sender) + ": " + str(fires.size()) + " fires")
    ApplyFireManifest.rpc_id(sender, fires)


@rpc("authority", "reliable", "call_remote")
func ApplyFireManifest(fires: Array):
    print("[EventSync] Received fire manifest: " + str(fires.size()) + " fires")
    for entry in fires:
        var fire = get_node_or_null(entry.get("path", NodePath()))
        if !fire or !fire.has_method("Activate"):
            continue
        var desired: bool = bool(entry.get("active", false))
        if fire.active == desired:
            continue
        fire.active = desired
        if desired:
            fire.Activate()
        else:
            fire.Deactivate()


func _all_fires() -> Array:
    var out: Array = []
    var scene = get_tree().current_scene
    if !scene:
        return out
    _scan_fires(scene, out)
    return out


func _scan_fires(n: Node, out: Array):
    CoopWalk(n, func(node):
        if node.has_method("Activate") and node.has_method("Deactivate") and node.get("active") != null and node.get("force") != null:
            var s = node.get_script()
            if s and str(s.resource_path).find("Fire") != -1:
                out.append(node)
                return true
        return false
    )


static func CoopWalk(n: Node, visitor: Callable) -> void:
    if !is_instance_valid(n):
        return
    if visitor.call(n):
        return
    for c in n.get_children():
        CoopWalk(c, visitor)


@rpc("any_peer", "reliable", "call_remote")
func RequestRadioTVSync():
    if !multiplayer.is_server():
        return
    var sender = multiplayer.get_remote_sender_id()
    var radios: Array = []
    var tvs: Array = []
    var scene = get_tree().current_scene
    if scene:
        _scan_radios_tvs(scene, radios, tvs)
    print("[EventSync] Sending radio/TV manifest to peer " + str(sender) + ": " + str(radios.size()) + " radios, " + str(tvs.size()) + " TVs")
    ApplyRadioTVManifest.rpc_id(sender, radios, tvs)


@rpc("authority", "reliable", "call_remote")
func ApplyRadioTVManifest(radios: Array, tvs: Array):
    print("[EventSync] Received radio/TV manifest: " + str(radios.size()) + " radios, " + str(tvs.size()) + " TVs")
    for entry in radios:
        var r = get_node_or_null(entry.get("path", NodePath()))
        if !r:
            continue
        if r.get("transmission") != null:
            r.transmission = bool(entry.get("transmission", false))
        var desired: bool = bool(entry.get("active", false))
        if r.active == desired:
            continue
        r.active = desired
        if desired:
            if r.has_method("GetRandomTuningClip") and r.get("tuning") != null:
                r.tuning.stream = r.GetRandomTuningClip()
                r.tuning.play()
                r.isTuning = true
        else:
            if r.get("audio") != null:
                r.audio.stop()
            if r.get("tuning") != null:
                r.tuning.stop()
            r.isTuning = false
    for entry in tvs:
        var tv = get_node_or_null(entry.get("path", NodePath()))
        if !tv or !tv.has_method("Activate"):
            continue
        var desired: bool = bool(entry.get("active", false))
        if tv.active == desired:
            continue
        tv.active = desired
        if desired:
            tv.Activate()
        else:
            tv.Deactivate()


func _scan_radios_tvs(n: Node, radios: Array, tvs: Array):
    CoopWalk(n, func(node):
        var s = node.get_script()
        if s:
            var p = str(s.resource_path)
            if p.find("Radio.gd") != -1:
                radios.append({
                    "path": node.get_path(),
                    "active": bool(node.active),
                    "transmission": bool(node.get("transmission")) if node.get("transmission") != null else false,
                })
            elif p.find("Television.gd") != -1:
                tvs.append({"path": node.get_path(), "active": bool(node.active)})
        return false
    )


@rpc("any_peer", "reliable", "call_remote")
func RequestFireToggle(firePath: NodePath):
    if !multiplayer.is_server():
        return
    var fire = get_node_or_null(firePath)
    if !fire or !fire.has_method("Activate"):
        return
    if !fire.active:
        fire.active = true
        fire.Activate()
        fire.IgniteAudio()
    else:
        fire.active = false
        fire.Deactivate()
        fire.ExtinguishAudio()
    BroadcastFireState.rpc(firePath, fire.active)


@rpc("authority", "reliable", "call_remote")
func BroadcastFireState(firePath: NodePath, isActive: bool):
    var fire = get_node_or_null(firePath)
    if !fire or !fire.has_method("Activate"):
        return
    fire.active = isActive
    if isActive:
        fire.Activate()
        fire.IgniteAudio()
    else:
        fire.Deactivate()
        fire.ExtinguishAudio()
