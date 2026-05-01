extends "res://mods/RTVCoopAlpha/HookKit/BaseHook.gd"



const CoopAuthority = preload("res://mods/RTVCoopAlpha/Framework/CoopAuthority.gd")

var gameData: Resource = preload("res://Resources/GameData.tres")
const COOP_DOOR_OPEN_RANGE: float = 40.0
const COOP_RETARGET_INTERVAL: float = 0.25

func _setup_hooks() -> void:
	CoopHook.register_replace_or_post(self,
		"ai-_physics_process",
		_replace_ai_physics_process,
		_post_ai_physics_process)
	CoopHook.register_replace_or_post(self,
		"ai-death",
		_replace_ai_death,
		_post_ai_death)
	CoopHook.register_replace_or_post(self,
		"ai-initialize",
		_replace_ai_initialize,
		_post_ai_initialize)
	CoopHook.register_replace_or_post(self, "ai-playfire", _replace_sound_fire, _post_sound)
	CoopHook.register_replace_or_post(self, "ai-playtail", _replace_sound_tail, _post_sound)
	CoopHook.register_replace_or_post(self, "ai-playidle", _replace_sound_idle, _post_sound)
	CoopHook.register_replace_or_post(self, "ai-playcombat", _replace_sound_combat, _post_sound)
	CoopHook.register_replace_or_post(self, "ai-playdamage", _replace_sound_damage, _post_sound)
	CoopHook.register_replace_or_post(self, "ai-playdeath", _replace_sound_death, _post_sound)


func _replace_ai_physics_process(delta: float) -> void:
	var a := CoopHook.caller()
	if a == null:
		return
	if not CoopAuthority.is_active():
		return
	if a.get_meta("coop_puppet_mode", false):
		CoopHook.skip_super()
		return
	if not CoopAuthority.is_host():
		_client_animate(a, delta)
		CoopHook.skip_super()
		return
	# Multi-player AI retarget: vanilla Sensor + Parameters read
	# gameData.playerPosition / gameData.cameraPosition (host's view). Swap
	# them here to nearest puppet so vanilla physics naturally retargets,
	# restore in _post_ai_physics_process.
	if a.dead or not a.sensorActive:
		return
	if ai == null or not ai.has_method("GetNearestPlayerPosition"):
		return
	var t: float = float(a.get_meta("_coop_retarget_t", 0.0)) - delta
	var pos_cache: Vector3 = a.get_meta("_coop_retarget_pos", Vector3.ZERO)
	var cam_cache: Vector3 = a.get_meta("_coop_retarget_cam", Vector3.ZERO)
	if t <= 0.0 or pos_cache == Vector3.ZERO:
		pos_cache = ai.GetNearestPlayerPosition(a.global_position)
		cam_cache = ai.GetNearestPlayerCamera(a.global_position)
		a.set_meta("_coop_retarget_pos", pos_cache)
		a.set_meta("_coop_retarget_cam", cam_cache)
		a.set_meta("_coop_retarget_t", COOP_RETARGET_INTERVAL)
	else:
		a.set_meta("_coop_retarget_t", t)
	if pos_cache == Vector3.ZERO:
		return
	var gd: Resource = a.gameData
	a.set_meta("_coop_saved_pp", gd.playerPosition)
	a.set_meta("_coop_saved_cp", gd.cameraPosition)
	gd.playerPosition = pos_cache
	gd.cameraPosition = cam_cache


func _post_ai_physics_process(_delta: float) -> void:
	var a := CoopHook.caller()
	if a == null or not a.has_meta("_coop_saved_pp"):
		return
	var gd: Resource = a.gameData
	gd.playerPosition = a.get_meta("_coop_saved_pp")
	gd.cameraPosition = a.get_meta("_coop_saved_cp")
	a.remove_meta("_coop_saved_pp")
	a.remove_meta("_coop_saved_cp")


func _replace_ai_death(direction, force) -> void:
	var a := CoopHook.caller()
	if a == null or not CoopAuthority.is_active():
		return
	if a.get_meta("coop_puppet_mode", false):
		return
	if a.get_meta("_coop_death_from_broadcast", false):
		a.remove_meta("_coop_death_from_broadcast")
		return
	if a.dead:
		CoopHook.skip_super()
		return
	if not CoopAuthority.is_host():
		CoopHook.skip_super()
		return
	if not a.has_meta("network_uuid"):
		return
	var uuid: int = int(a.get_meta("network_uuid"))
	a.set_meta("_coop_death_broadcasted", true)
	var ss: Node = coop.get_sync("slot_serializer") if coop else null
	var container_loot: Array = []
	var lc: Node = ai._get_ai_loot_container(a) if ai else null
	if ss and lc:
		for s in lc.loot:
			container_loot.append(ss.SerializeSlotData(s))
	var weapon_dict: Dictionary = ss.SerializeSlotData(a.weapon.slotData) if ss and a.weapon and a.weapon.slotData else {}
	var backpack_dict: Dictionary = ss.SerializeSlotData(a.backpack.slotData) if ss and a.backpack and a.backpack.slotData else {}
	var secondary_dict: Dictionary = ss.SerializeSlotData(a.secondary.slotData) if ss and a.secondary and a.secondary.slotData else {}
	var _corpse_cid: int = players.nextContainerId if players else -1
	if players:
		players.nextContainerId += 1
	if lc and _corpse_cid >= 0:
		if not lc.is_in_group("CoopLootContainer"):
			lc.add_to_group("CoopLootContainer")
		lc.set_meta("coop_container_id", _corpse_cid)
	ai.BroadcastAIDeath.rpc(uuid, direction, force, container_loot, weapon_dict, backpack_dict, secondary_dict, _corpse_cid)
	if players:
		if a.weapon:
			var w_uuid: int = uuid * 10 + 1
			a.weapon.set_meta("network_uuid", w_uuid)
			players.worldItems[w_uuid] = a.weapon
			if w_uuid >= players.nextUuid:
				players.nextUuid = w_uuid + 1
		if a.backpack:
			var b_uuid: int = uuid * 10 + 2
			a.backpack.set_meta("network_uuid", b_uuid)
			players.worldItems[b_uuid] = a.backpack
			if b_uuid >= players.nextUuid:
				players.nextUuid = b_uuid + 1
		if a.secondary:
			var s_uuid: int = uuid * 10 + 3
			a.secondary.set_meta("network_uuid", s_uuid)
			players.worldItems[s_uuid] = a.secondary
			if s_uuid >= players.nextUuid:
				players.nextUuid = s_uuid + 1
		players.world_ai.erase(uuid)
		players.ai_targets.erase(uuid)


func _post_ai_death(direction, force) -> void:
	pass


func _replace_ai_initialize() -> void:
	var a := CoopHook.caller()
	if a == null or not CoopAuthority.is_active():
		return
	if a.get_meta("coop_puppet_mode", false):
		CoopHook.skip_super()
		return
	if not CoopAuthority.is_host():
		CoopHook.skip_super()


func _post_ai_initialize() -> void:
	pass




func _coop_sound(a: Node, sound_type: int, extra_bool: bool = false) -> bool:
	if a.get_meta("_coop_force_local_play", false):
		return true
	if not CoopAuthority.is_active():
		return true
	if not CoopAuthority.is_host():
		return false
	if a.has_meta("network_uuid") and ai:
		ai.BroadcastAISound.rpc(int(a.get_meta("network_uuid")), sound_type, extra_bool)
	return true


func _replace_sound_fire() -> void:
	var a := CoopHook.caller()
	if a == null or a.get_meta("coop_puppet_mode", false):
		return
	if not _coop_sound(a, 0, a.fullAuto if "fullAuto" in a else false):
		CoopHook.skip_super()

func _replace_sound_tail() -> void:
	var a := CoopHook.caller()
	if a == null or a.get_meta("coop_puppet_mode", false):
		return
	if not _coop_sound(a, 1):
		CoopHook.skip_super()

func _replace_sound_idle() -> void:
	var a := CoopHook.caller()
	if a == null or a.get_meta("coop_puppet_mode", false):
		return
	if not _coop_sound(a, 2):
		CoopHook.skip_super()

func _replace_sound_combat() -> void:
	var a := CoopHook.caller()
	if a == null or a.get_meta("coop_puppet_mode", false):
		return
	if not _coop_sound(a, 3):
		CoopHook.skip_super()

func _replace_sound_damage() -> void:
	var a := CoopHook.caller()
	if a == null or a.get_meta("coop_puppet_mode", false):
		return
	if not _coop_sound(a, 4):
		CoopHook.skip_super()

func _replace_sound_death() -> void:
	var a := CoopHook.caller()
	if a == null or a.get_meta("coop_puppet_mode", false):
		return
	if not _coop_sound(a, 5):
		CoopHook.skip_super()

func _post_sound() -> void:
	pass


func _client_animate(a: Node, delta: float) -> void:
	var animator: AnimationMixer = a.animator if "animator" in a else null
	var skeleton: Skeleton3D = a.skeleton if "skeleton" in a else null
	if animator == null or skeleton == null:
		return

	if not a.get_meta("coop_client_anim_ready", false):
		animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
		animator.active = true
		skeleton.show_rest_only = false
		a.set_meta("coop_client_anim_ready", true)

	var speed: float = a.speed if "speed" in a else 0.0
	var movement_speed: float = a.movementSpeed if "movementSpeed" in a else 0.0
	movement_speed = move_toward(movement_speed, speed, delta * 5.0)
	if "movementSpeed" in a:
		a.movementSpeed = movement_speed
	animator["parameters/Rifle/Movement/blend_position"] = movement_speed
	animator["parameters/Pistol/Movement/blend_position"] = movement_speed

	animator.advance(delta)
	skeleton.advance(delta)
