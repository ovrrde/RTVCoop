extends "res://Scripts/GrenadeRig.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func ThrowHighExecute():
    super()

    if _net().IsActive():
        var throwDirection = global_transform.basis.z
        var throwPosition = throwPoint.global_position
        var throwRotation = Vector3(0, global_rotation_degrees.y, 0)
        var throwForce = 30.0

        _pm().RequestGrenadeThrow(
            throw.resource_path,
            handle.resource_path if handle else "",
            throwPosition, throwRotation,
            throwDirection * throwForce, basis.x * 5.0
        )


func ThrowLowExecute():
    super()

    if _net().IsActive():
        var throwDirection = global_transform.basis.z
        var throwPosition = throwPoint.global_position
        var throwRotation = Vector3(0, global_rotation_degrees.y, 0)
        var throwForce = 15.0

        _pm().RequestGrenadeThrow(
            throw.resource_path,
            handle.resource_path if handle else "",
            throwPosition, throwRotation,
            throwDirection * throwForce, basis.x * 5.0
        )
