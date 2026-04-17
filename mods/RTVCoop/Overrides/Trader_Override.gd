extends "res://Scripts/Trader.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func _ready():
    super()
    if _net() and _net().IsActive():
        _coop_apply_shared_state()


func _coop_apply_shared_state():
    var pm = _pm()
    if !pm:
        return
    var qs = pm.get_node_or_null("QuestSync")
    if !qs:
        return
    if multiplayer.is_server():
        var completed: Array = qs.get_completed(traderData.name)
        tasksCompleted.clear()
        for task_name in completed:
            tasksCompleted.append(task_name)
    else:
        tasksCompleted.clear()
        if qs.has_state_for(traderData.name):
            for task_name in qs.get_completed(traderData.name):
                tasksCompleted.append(task_name)
        qs.RequestTraderState.rpc_id(1, traderData.name)


func CompleteTask(taskData):
    if _net() and _net().IsActive():
        var pm = _pm()
        var qs = pm.get_node_or_null("QuestSync") if pm else null
        if qs:
            if multiplayer.is_server():
                super(taskData)
                qs.coop_trader_state[traderData.name] = tasksCompleted.duplicate()
                qs._persist_host()
                qs.BroadcastTaskCompletion.rpc(traderData.name, taskData.name)
                return
            else:
                if !qs.has_state_for(traderData.name):
                    Loader.Message("Syncing trader state… try again in a moment.", Color.ORANGE)
                    return
                if qs.get_completed(traderData.name).has(taskData.name):
                    Loader.Message("Task already completed.", Color.ORANGE)
                    return
                PlayTraderTask()
                Loader.Message("Task Completed: " + taskData.name, Color.GREEN)
                qs.SubmitTaskCompletion.rpc_id(1, traderData.name, taskData.name)
                return
    super(taskData)
