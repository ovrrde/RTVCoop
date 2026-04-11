extends "res://Scripts/Compiler.gd"

# Vanilla Compiler.Spawn() calls Loader.LoadCharacter + LoadShelter + LoadWorld
# on every scene entry, all of which read the client's stale local save files
# and clobber the live coop state. Coop clients skip super() entirely and
# restore from PlayerManager.coopCharacterBuffer instead. Shelter default
# layout is preserved; container contents lazy-sync from host on interact.

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func Spawn():
    if _net() and _net().IsActive() and !_net().IsHost():
        await _coop_client_spawn()
        return
    super()


func _coop_client_spawn():
    var map = get_tree().current_scene.get_node_or_null("/root/Map")
    if !map:
        return

    var mapName: String = str(map.get("mapName")) if map.get("mapName") else ""

    if mapName == "Tutorial":
        Simulation.simulate = false
        controller.global_position = Vector3(0, 3, 12)
    else:
        Simulation.simulate = true

    if _pm().coopCharacterBuffer != null:
        await _pm().LoadClientCharacterBuffer()
    else:
        await _pm().GiveClientStarterKit()

    gameData.isTransitioning = false
    gameData.isSleeping = false
    gameData.isOccupied = false
    gameData.freeze = false

    print("[Compiler] COOP SPAWN: client entered " + mapName)
