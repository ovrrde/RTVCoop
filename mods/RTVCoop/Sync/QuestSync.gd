extends Node


var coop_trader_state: Dictionary = {}  # trader_name -> Array[String]
var _loaded_from_disk: bool = false
# blocks client completions until host's authoritative state arrives, else first-open race lets client re-complete host's quests
var state_received: Dictionary = {}


func _pm():
    return get_parent()


func _ready():
    call_deferred("_init_from_disk_if_host")


func _init_from_disk_if_host():
    if !multiplayer.is_server():
        return
    if _loaded_from_disk:
        return
    if !FileAccess.file_exists("user://Traders.tres"):
        _ensure_defaults()
        _loaded_from_disk = true
        return
    var traders = load("user://Traders.tres")
    if !traders:
        _ensure_defaults()
        _loaded_from_disk = true
        return
    coop_trader_state["Generalist"] = traders.generalist.duplicate() if traders.generalist else []
    coop_trader_state["Doctor"] = traders.doctor.duplicate() if traders.doctor else []
    coop_trader_state["Gunsmith"] = traders.gunsmith.duplicate() if traders.gunsmith else []
    coop_trader_state["Grandma"] = traders.grandma.duplicate() if traders.grandma else []
    _loaded_from_disk = true
    var totals = str(coop_trader_state["Generalist"].size()) + "/" \
        + str(coop_trader_state["Doctor"].size()) + "/" \
        + str(coop_trader_state["Gunsmith"].size()) + "/" \
        + str(coop_trader_state["Grandma"].size())
    print("[QuestSync] Host loaded trader state (G/D/Gu/Gr): " + totals)


func _ensure_defaults():
    for name in ["Generalist", "Doctor", "Gunsmith", "Grandma"]:
        if !coop_trader_state.has(name):
            coop_trader_state[name] = []


func get_completed(trader_name: String) -> Array:
    if !coop_trader_state.has(trader_name):
        coop_trader_state[trader_name] = []
    return coop_trader_state[trader_name]


func apply_completion_local(trader_name: String, task_name: String):
    var completed: Array = get_completed(trader_name)
    if !completed.has(task_name):
        completed.append(task_name)
    var trader = _find_active_trader(trader_name)
    if trader and !trader.tasksCompleted.has(task_name):
        trader.tasksCompleted.append(task_name)


func _find_active_trader(trader_name: String) -> Node:
    var interface = get_tree().current_scene.get_node_or_null("/root/Map/Core/UI/Interface")
    if interface and interface.get("trader") != null:
        var t = interface.trader
        if is_instance_valid(t) and t.traderData and t.traderData.name == trader_name:
            return t
    for node in get_tree().get_nodes_in_group("Trader"):
        if is_instance_valid(node) and node.traderData and node.traderData.name == trader_name:
            return node
    return null


func _persist_host():
    if !multiplayer.is_server():
        return
    var traders = null
    if FileAccess.file_exists("user://Traders.tres"):
        traders = load("user://Traders.tres")
    if !traders:
        var TraderSaveScript = load("res://Scripts/TraderSave.gd")
        if !TraderSaveScript:
            return
        traders = TraderSaveScript.new()
    traders.generalist = get_completed("Generalist").duplicate()
    traders.doctor = get_completed("Doctor").duplicate()
    traders.gunsmith = get_completed("Gunsmith").duplicate()
    traders.grandma = get_completed("Grandma").duplicate()
    ResourceSaver.save(traders, "user://Traders.tres")


@rpc("any_peer", "reliable", "call_remote")
func RequestTraderState(trader_name: String):
    if !multiplayer.is_server():
        return
    var sender = multiplayer.get_remote_sender_id()
    var completed: Array = get_completed(trader_name)
    DeliverTraderState.rpc_id(sender, trader_name, completed)


@rpc("authority", "reliable", "call_remote")
func DeliverTraderState(trader_name: String, completed: Array):
    coop_trader_state[trader_name] = completed.duplicate()
    state_received[trader_name] = true
    var trader = _find_active_trader(trader_name)
    if trader:
        trader.tasksCompleted.clear()
        for task_name in completed:
            trader.tasksCompleted.append(task_name)
        print("[QuestSync] Client applied " + str(completed.size()) + " completed tasks for " + trader_name)


func has_state_for(trader_name: String) -> bool:
    if multiplayer.is_server():
        return true
    return state_received.get(trader_name, false)


func push_full_state_to(peer_id: int):
    if !multiplayer.is_server():
        return
    for name in ["Generalist", "Doctor", "Gunsmith", "Grandma"]:
        DeliverTraderState.rpc_id(peer_id, name, get_completed(name))


@rpc("any_peer", "reliable", "call_remote")
func SubmitTaskCompletion(trader_name: String, task_name: String):
    if !multiplayer.is_server():
        return
    var completed: Array = get_completed(trader_name)
    if completed.has(task_name):
        return
    completed.append(task_name)
    _persist_host()
    BroadcastTaskCompletion.rpc(trader_name, task_name)


@rpc("authority", "reliable", "call_local")
func BroadcastTaskCompletion(trader_name: String, task_name: String):
    apply_completion_local(trader_name, task_name)
    print("[QuestSync] Task completed — " + trader_name + "/" + task_name)
