extends "res://Scripts/Simulation.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func _process(delta):
    if simulate and _net() and _net().IsActive() and !multiplayer.is_server():
        return
    var pm = _pm()
    if pm and _net() and _net().IsActive() and simulate:
        var is_day: bool = time >= 600.0 and time < 1800.0
        var mult: float = pm.GetSetting("day_rate_multiplier", 1.0) if is_day else pm.GetSetting("night_rate_multiplier", 1.0)
        if mult != 1.0:
            super(delta * mult)
            return
    super(delta)
