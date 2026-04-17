extends "res://Scripts/FishPool.gd"


func _ready():
    var net = get_tree().root.get_node_or_null("Network")
    if net and net.has_method("IsActive") and net.IsActive():
        var pm = get_tree().root.get_node_or_null("PlayerManager")
        if pm:
            var s = await pm.CoopSeedForNode(self)
            if s != 0:
                seed(s)
    super()
