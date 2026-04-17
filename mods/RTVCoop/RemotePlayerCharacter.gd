extends Node3D

var _pm_c: Node
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func WeaponDamage(damage: int, penetration: int):

    var puppet = owner

    if !puppet:
        return


    if !("peer_id" in puppet):
        return


    _pm().RequestPlayerDamage(puppet.peer_id, damage, penetration)


func ExplosionDamage():

    var puppet = owner

    if !puppet:
        return


    if !("peer_id" in puppet):
        return


    _pm()._interactable_sync().RequestPlayerExplosionDamage(puppet.peer_id)
