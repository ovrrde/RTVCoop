extends "res://Scripts/Loader.gd"

# WARNING: overriding methods on Loader is DEAD CODE. Loader is registered in
# project.godot as an autoload scene (*res://Resources/Loader.tscn), so the
# live autoload node is instantiated with the vanilla script before any mod
# runs. take_over_path() only updates the resource cache, not attached scripts
# on existing nodes. Any Loader.Something() call anywhere in the game hits
# vanilla. Can intercept at scene-instanced callers instead:
#
#   Loader.LoadCharacter / LoadShelter / LoadWorld  → Compiler_Override.Spawn
#   Loader.SaveCharacter / SaveShelter / SaveWorld  → Transition.gd 
#   Scene change broadcast                           → PlayerManager.ScanIfNeeded
#
# This file only exists so Main.gd's override list doesn't fail on a missing
# target. Do not add method overrides here expecting them to run.

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c
