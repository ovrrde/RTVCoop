extends "res://Scripts/Explosion.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func CheckOverlap():
    if _net().IsActive() && !multiplayer.is_server():
        return
    super()


func CheckLOS(target):
    var headPos = target.global_position + Vector3(0, 1.5, 0)
    if target.get("head") && target.head:
        headPos = target.head.global_position

    LOS.look_at(headPos, Vector3.UP, true)
    LOS.force_raycast_update()

    if LOS.is_colliding():
        if LOS.get_collider().is_in_group("AI"):
            target.ExplosionDamage(LOS.global_basis.z)
        if LOS.get_collider().is_in_group("Player"):
            target.get_child(0).ExplosionDamage()


func CheckAlert():
    if _net().IsActive() && !multiplayer.is_server():
        return
    super()
