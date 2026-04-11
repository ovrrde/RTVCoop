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
    var shouldGenerate = _pm().ShouldGenerateLoot()

    if shouldGenerate && !custom && !locked && !furniture:
        ClearBuckets()
        FillBuckets()
        GenerateLoot()

    if shouldGenerate && custom && !force:
        ClearBuckets()
        FillBucketsCustom()
        GenerateLoot()

    if shouldGenerate && custom && force:
        for index in custom.items.size():
            CreateLoot(custom.items[index])

    if stash:
        if randi_range(0, 100) > 10:
            process_mode = ProcessMode.PROCESS_MODE_DISABLED
            hide()


func Interact():
    if !locked:
        if _net().IsActive() && !multiplayer.is_server():
            _pm().RequestContainerOpen.rpc_id(1, get_path())
            return

        var UIManager = get_tree().current_scene.get_node("/root/Map/Core/UI")
        UIManager.OpenContainer(self)
        ContainerAudio()
