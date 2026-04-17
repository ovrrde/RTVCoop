extends "res://Scripts/Loader.gd"

var _net_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c


func _is_coop_client() -> bool:
    return _net() != null and _net().IsActive() and !_net().IsHost()


func SaveCharacter():
    if _is_coop_client():
        return
    super()


func SaveWorld():
    if _is_coop_client():
        return
    super()


func SaveShelter(targetShelter):
    if _is_coop_client():
        return
    super(targetShelter)


func SaveTrader(trader: String):
    if _is_coop_client():
        return
    super(trader)


func LoadScene(sceneName: String):
    # Host must reset the session seed BEFORE the new scene loads. The first
    # CoopSeedForNode call from inside the new scene's _ready cascade (Layouts,
    # LootContainer, Fire, etc.) will then generate the seed via
    # _ensure_session_seed, which also broadcasts it to clients. ScanIfNeeded
    # later sees the already-generated seed and won't clobber it.
    if _net() and _net().IsActive() and multiplayer.is_server():
        var pm = get_tree().root.get_node_or_null("PlayerManager")
        if pm:
            pm.coopSessionSeed = 0
    super(sceneName)


func LoadTrader(trader: String):
    # local user://Traders.tres would clobber our QuestSync-synced list with the client's solo save
    if _is_coop_client():
        var pm = get_tree().root.get_node_or_null("PlayerManager")
        var qs = pm.get_node_or_null("QuestSync") if pm else null
        var interface = get_tree().current_scene.get_node_or_null("/root/Map/Core/UI/Interface")
        if qs and interface and interface.get("trader") != null and interface.trader:
            interface.trader.tasksCompleted.clear()
            for task_name in qs.get_completed(trader):
                interface.trader.tasksCompleted.append(task_name)
            qs.RequestTraderState.rpc_id(1, trader)
        return
    super(trader)
