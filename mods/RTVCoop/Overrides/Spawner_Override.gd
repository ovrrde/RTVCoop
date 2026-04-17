@tool
extends "res://Scripts/Spawner.gd"

func _ready() -> void:
    var should_restore: bool = false
    if !Engine.is_editor_hint():
        var sceneData = data as SpawnerSceneData
        if sceneData and sceneData.runtime:
            seed(hash(str(get_path())))
            should_restore = true
    super()
    if should_restore:
        randomize()
