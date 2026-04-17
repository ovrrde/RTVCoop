extends Node


const VEHICLE_BROADCAST_RATE: float = 20.0
const ROCKET_BROADCAST_RATE: float = 15.0
const VEHICLE_LERP_SPEED: float = 12.0
const ROCKET_LERP_SPEED: float = 20.0

var _vehicle_accum: float = 0.0
var _rocket_accum: float = 0.0
var _vehicles: Array = []    # host-tracked BTR/Police nodes
var _rockets: Array = []     # host-tracked rockets in flight

# NodePath -> {"pos": Vector3, "rot": Vector3}; client-side lerp targets
var _vehicle_targets: Dictionary = {}
var _rocket_targets: Dictionary = {}


func _pm():
    return get_parent()


func _physics_process(delta):
    if !_pm()._net().IsActive():
        return

    if multiplayer.is_server():
        _vehicle_accum += delta
        if _vehicle_accum >= 1.0 / VEHICLE_BROADCAST_RATE:
            _vehicle_accum = 0.0
            _broadcast_vehicles()

        _rocket_accum += delta
        if _rocket_accum >= 1.0 / ROCKET_BROADCAST_RATE:
            _rocket_accum = 0.0
            _broadcast_rockets()
    else:
        _lerp_targets(_vehicle_targets, VEHICLE_LERP_SPEED, delta)
        _lerp_targets(_rocket_targets, ROCKET_LERP_SPEED, delta)


func _lerp_targets(targets: Dictionary, speed: float, delta: float):
    if targets.is_empty():
        return
    var t: float = clampf(speed * delta, 0.0, 1.0)
    var stale: Array = []
    for path in targets:
        var node = get_node_or_null(path)
        if !node or !is_instance_valid(node):
            stale.append(path)
            continue
        var target: Dictionary = targets[path]
        node.global_position = node.global_position.lerp(target.pos, t)
        node.global_rotation.x = lerp_angle(node.global_rotation.x, target.rot.x, t)
        node.global_rotation.y = lerp_angle(node.global_rotation.y, target.rot.y, t)
        node.global_rotation.z = lerp_angle(node.global_rotation.z, target.rot.z, t)
    for p in stale:
        targets.erase(p)


# ─── Vehicles (BTR / Police) ──────────────────────────────────────────────

func register_vehicle(node: Node3D):
    if !_vehicles.has(node):
        _vehicles.append(node)


func _broadcast_vehicles():
    var alive: Array = []
    for v in _vehicles:
        if !is_instance_valid(v) or !v.is_inside_tree():
            continue
        alive.append(v)
        BroadcastVehiclePose.rpc(v.get_path(), v.global_position, v.global_rotation)
    _vehicles = alive


@rpc("authority", "unreliable", "call_remote")
func BroadcastVehiclePose(path: NodePath, pos: Vector3, rot: Vector3):
    _vehicle_targets[path] = {"pos": pos, "rot": rot}


# ─── Rockets (RocketGrad / RocketHelicopter) ──────────────────────────────

func register_rocket(node: Node3D):
    if !_rockets.has(node):
        _rockets.append(node)


func _broadcast_rockets():
    var alive: Array = []
    for r in _rockets:
        if !is_instance_valid(r) or !r.is_inside_tree():
            continue
        alive.append(r)
        BroadcastRocketPose.rpc(r.get_path(), r.global_position, r.global_rotation)
    _rockets = alive


@rpc("authority", "unreliable", "call_remote")
func BroadcastRocketPose(path: NodePath, pos: Vector3, rot: Vector3):
    _rocket_targets[path] = {"pos": pos, "rot": rot}


# ─── Simple Interact-state (Radio / Television) ───────────────────────────

func CoopRouteInteractToggle(path: NodePath) -> bool:
    var net = _pm()._net()
    if !net or !net.IsActive():
        return false
    if multiplayer.is_server():
        BroadcastInteractToggle.rpc(path)
    else:
        RequestInteractToggle.rpc_id(1, path)
    return true


@rpc("any_peer", "reliable", "call_remote")
func RequestInteractToggle(path: NodePath):
    if !multiplayer.is_server():
        return
    BroadcastInteractToggle.rpc(path)


@rpc("authority", "reliable", "call_local")
func BroadcastInteractToggle(path: NodePath):
    var node = get_node_or_null(path)
    if !node or !node.has_method("_coop_remote_interact"):
        return
    node._coop_remote_interact()


# ─── Instrument (play / stop) ─────────────────────────────────────────────

@rpc("any_peer", "reliable", "call_remote")
func RequestInstrumentState(path: NodePath, playing: bool, track_index: int):
    if !multiplayer.is_server():
        return
    BroadcastInstrumentState.rpc(path, playing, track_index)


@rpc("authority", "reliable", "call_local")
func BroadcastInstrumentState(path: NodePath, playing: bool, track_index: int):
    var node = get_node_or_null(path)
    if !node or !node.has_method("_coop_remote_play"):
        return
    node._coop_remote_play(playing, track_index)


# ─── Missile spawner ──────────────────────────────────────────────────────

@rpc("authority", "reliable", "call_remote")
func BroadcastMissilePrepare(spawner_path: NodePath):
    var spawner = get_node_or_null(spawner_path)
    if !spawner or !spawner.has_method("ExecutePrepareMissiles"):
        return
    var existing = spawner.get_children().filter(func(n): return n.has_method("ExecuteLaunch"))
    if existing.is_empty():
        spawner.ExecutePrepareMissiles(true)


@rpc("authority", "reliable", "call_remote")
func BroadcastMissileLaunch(spawner_path: NodePath, child_index: int):
    var spawner = get_node_or_null(spawner_path)
    if !spawner:
        return
    if child_index < 0 or child_index >= spawner.get_child_count():
        return
    var child = spawner.get_child(child_index)
    if !child or !child.has_method("ExecuteLaunch"):
        return
    spawner.launched = true
    child.visible = true
    child.ExecuteLaunch(true)


# ─── Cat quest ────────────────────────────────────────────────────────────

@rpc("any_peer", "reliable", "call_remote")
func RequestCatState(cat_found: bool, cat_dead: bool, cat_hydration: float):
    if !multiplayer.is_server():
        return
    BroadcastCatState.rpc(cat_found, cat_dead, cat_hydration)


@rpc("authority", "reliable", "call_local")
func BroadcastCatState(cat_found: bool, cat_dead: bool, cat_hydration: float):
    var gd = load("res://Resources/GameData.tres")
    if !gd:
        return
    if cat_found: gd.catFound = true
    if cat_dead: gd.catDead = true
    gd.cat = cat_hydration
