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

    PlayDeathAudio()
    audio.breathing.stop()
    audio.heartbeat.stop()
    gameData.health = 0
    gameData.isDead = true
    gameData.freeze = true
    rigManager.ClearRig()

    Loader.FadeIn()

    await get_tree().create_timer(5.0).timeout

    var controller = get_parent()
    var respawnPos = controller.global_position + Vector3(0, 1, 0)

    var spawnPoints = get_tree().get_nodes_in_group("AI_SP")
    if spawnPoints.size() > 0:
        var point = spawnPoints[randi_range(0, spawnPoints.size() - 1)]
        respawnPos = point.global_position + Vector3(0, 0.5, 0)

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

    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
    Loader.FadeOut()

    _pm().NotifyPlayerRespawn(multiplayer.get_unique_id())

    print("DEATH: Coop Respawn at " + str(respawnPos))
