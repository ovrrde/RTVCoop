extends "res://Scripts/Instrument.gd"


var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


var _last_playing: bool = false


func _physics_process(delta):
    super(delta)
    if _net() and _net().IsActive():
        if isPlaying != _last_playing:
            _last_playing = isPlaying
            var ws = _pm()._world_sync() if _pm() else null
            if ws:
                var idx = clipOrder
                if multiplayer.is_server():
                    ws.BroadcastInstrumentState.rpc(get_path(), isPlaying, idx)
                else:
                    ws.RequestInstrumentState.rpc_id(1, get_path(), isPlaying, idx)


func _coop_remote_play(playing: bool, track_index: int):
    if playing and !isPlaying:
        isPlaying = true
        animator["parameters/conditions/End"] = false
        animator["parameters/conditions/Play"] = true
        clipOrder = track_index
        if audioClips.size() > 0:
            audioPlayer.stream = audioClips[track_index % audioClips.size()]
            audioPlayer.play()
        isLooping = true
    elif !playing and isPlaying:
        isPlaying = false
        animator["parameters/conditions/Play"] = false
        animator["parameters/conditions/End"] = true
        audioPlayer.stop()
        isLooping = false
    _last_playing = playing
