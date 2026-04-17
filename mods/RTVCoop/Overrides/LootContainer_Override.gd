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

    var loot_mult_f: float = 1.0
    if is_coop:
        var pm = _pm()
        if pm:
            loot_mult_f = pm.GetSetting("loot_multiplier", 1.0)

    if !custom && !locked && !furniture:
        ClearBuckets()
        FillBuckets()
        _generate_loot_scaled(loot_mult_f)

    if custom && !force:
        ClearBuckets()
        FillBucketsCustom()
        _generate_loot_scaled(loot_mult_f)

    if custom && force:
        for index in custom.items.size():
            CreateLoot(custom.items[index])

    if stash:
        if randi_range(0, 100) > 10:
            process_mode = ProcessMode.PROCESS_MODE_DISABLED
            hide()

    if is_coop:
        randomize()


func _generate_loot_scaled(mult: float):
    var full_passes: int = int(mult)
    var frac: float = mult - float(full_passes)
    for _i in full_passes:
        GenerateLoot()
    if frac > 0.0 and randf() < frac:
        GenerateLoot()


func Interact():
    if locked:
        return
    _pm().TryOpenContainer(self)
