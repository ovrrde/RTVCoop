extends "res://Scripts/AI.gd"


const RTVCoop_Ref = preload("res://mods/RTVCoopAlpha/Game/Coop.gd")

var _ai_diag_timer: float = 0.0

func _coop_log(msg: String) -> void:
    var l = Engine.get_meta("CoopLogger", null)
    if l: l.log_msg("AI_Extend", msg)

func _coop_ai_sync() -> Node:
    var coop = RTVCoop_Ref.get_instance()
    return coop.get_sync("ai") if coop else null


func Parameters(delta):
    LKL = lerp(LKL, lastKnownLocation, delta * LKLSpeed)

    var coop = RTVCoop_Ref.get_instance()
    var is_active: bool = coop != null and coop.net != null and coop.net.has_method("IsActive") and coop.net.IsActive()

    if is_active:
        var ai_sync = _coop_ai_sync()
        if ai_sync and ai_sync.has_method("GetNearestPlayerPosition"):
            playerPosition = ai_sync.GetNearestPlayerPosition(global_position)
        else:
            playerPosition = gameData.playerPosition
    else:
        playerPosition = gameData.playerPosition

    _ai_diag_timer -= delta
    if _ai_diag_timer <= 0.0 and is_active:
        _ai_diag_timer = 10.0
        var puppet_count: int = 0
        if coop and coop.players:
            puppet_count = coop.players.remote_players.size()
        var diag_sync = _coop_ai_sync()
        _coop_log("DIAG ai=%s pos=%s playerPos=%s dist=%.1f puppets=%d ai_sync=%s" % [name, str(global_position), str(playerPosition), playerDistance3D, puppet_count, str(diag_sync != null)])

    playerDistance3D = global_position.distance_to(playerPosition)
    playerDistance2D = Vector2(global_position.x, global_position.z).distance_to(Vector2(playerPosition.x, playerPosition.z))
    fireVector = (global_position - playerPosition).normalized().dot(gameData.playerVector)

    if playerDistance3D < 10 and playerVisible:
        sensorCycle = 0.05
        LKLSpeed = 4.0
    elif playerDistance3D > 10 and playerDistance3D < 50:
        sensorCycle = 0.1
        LKLSpeed = 2.0
    elif playerDistance3D > 50:
        sensorCycle = 0.5
        LKLSpeed = 1.0


func Sensor(delta):
    sensorTimer += delta

    if sensorTimer > sensorCycle:
        if playerDistance3D <= 200.0:
            var targetCamera = gameData.cameraPosition

            var coop = RTVCoop_Ref.get_instance()
            var is_active: bool = coop != null and coop.net != null and coop.net.has_method("IsActive") and coop.net.IsActive()
            if is_active:
                var ai_sync = _coop_ai_sync()
                if ai_sync and ai_sync.has_method("GetNearestPlayerCamera"):
                    targetCamera = ai_sync.GetNearestPlayerCamera(global_position)

            var directionToPlayer = (eyes.global_position - targetCamera).normalized()
            var viewDirection = -eyes.global_transform.basis.z.normalized()
            var viewRadius = viewDirection.dot(directionToPlayer)

            if viewRadius > 0.5:
                LOSCheck(targetCamera)
            else:
                playerVisible = false
        else:
            playerVisible = false

        if not playerVisible:
            Hearing()

        sensorTimer = 0.0
