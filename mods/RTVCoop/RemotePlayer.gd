extends CharacterBody3D

var _pm_c: Node
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


var peer_id: int = 0
var isDead: bool = false


@onready var playerModel = get_node_or_null("PlayerModel")


var targetPosition: Vector3 = Vector3.ZERO
var targetRotation: Vector3 = Vector3.ZERO
var hasTarget: bool = false

const LERP_SPEED = 18.0


func _ready():
    pass


func _physics_process(delta):
    if hasTarget:
        global_position = global_position.lerp(targetPosition, LERP_SPEED * delta)
        global_rotation.y = lerp_angle(global_rotation.y, targetRotation.y, LERP_SPEED * delta)


func SetTarget(pos: Vector3, rot: Vector3):
    targetPosition = pos
    targetRotation = rot
    if !hasTarget:
        global_position = pos
        global_rotation = rot
        hasTarget = true


func ApplyAnimState(state: Dictionary):
    if isDead:
        return
    if playerModel && playerModel.has_method("ApplyAnimState"):
        playerModel.ApplyAnimState(state)


func OnDeath():
    isDead = true
    if playerModel and playerModel.has_method("OnPuppetDeath"):
        playerModel.OnPuppetDeath()


func OnRespawn():
    isDead = false
    if playerModel and playerModel.has_method("OnPuppetRespawn"):
        playerModel.OnPuppetRespawn()


func WeaponDamage(_type: String, finalDamage: float):
    _pm().RequestPlayerDamage(peer_id, int(finalDamage), 0)
