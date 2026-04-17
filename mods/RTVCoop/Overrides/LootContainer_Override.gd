extends "res://Scripts/LootContainer.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func _ready():
    add_to_group("CoopLootContainer")

    var is_coop = _net() and _net().IsActive()

    var seed_val: int = 0
    if is_coop:
        seed_val = await _pm().CoopSeedForNode(self)
        if seed_val != 0:
            seed(seed_val)

    if !custom && !locked && !furniture:
        ClearBuckets()
        FillBuckets()
        GenerateLoot()

    if custom && !force:
        ClearBuckets()
        FillBucketsCustom()
        GenerateLoot()

    if custom && force:
        for index in custom.items.size():
            CreateLoot(custom.items[index])

    if stash:
        if randi_range(0, 100) > 10:
            process_mode = ProcessMode.PROCESS_MODE_DISABLED
            hide()

    if is_coop:
        randomize()


func Interact():
    if locked:
        return
    _pm().TryOpenContainer(self)
