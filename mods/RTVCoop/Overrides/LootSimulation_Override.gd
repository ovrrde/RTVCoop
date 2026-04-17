extends "res://Scripts/LootSimulation.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func _ready():
    get_child(0).queue_free()
    if _net().IsActive() and !multiplayer.is_server():
        return

    if !custom:
        ClearBuckets()
        FillBuckets()
        GenerateLoot()
        SpawnItems()

    if custom && !force:
        ClearBuckets()
        FillBucketsCustom()
        GenerateLoot()

    if custom && force:
        for index in custom.items.size():
            loot.append(custom.items[index])
            SpawnItems()
