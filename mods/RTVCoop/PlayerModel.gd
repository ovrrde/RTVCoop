extends Node3D


var audioInstance3D = preload("res://Resources/AudioInstance3D.tscn")
var flashVFX = preload("res://Effects/Muzzle_Flash.tscn")


@onready var aiInstance = $AI


var currentWeaponFile: String = ""
var currentAnim: String = ""
var currentWeaponNode: Node = null
var animPlayer: AnimationPlayer = null


const RIFLE_GRIP = Transform3D(
    Vector3(-0.168531, 0.17101, 0.97075),
    Vector3(0.983905, -0.0301536, 0.176127),
    Vector3(0.0593909, 0.984808, -0.163175),
    Vector3(0.1, 0.12, 0.03)
)
const PISTOL_GRIP = Transform3D(
    Vector3(0.174912, 0.0847189, 0.980934),
    Vector3(0.982636, 0.047607, -0.179328),
    Vector3(-0.0618917, 0.995267, -0.07492),
    Vector3(0.073, 0.108, 0.01)
)


func _ready():

    if !aiInstance:
        print("[PlayerModel] No AI instance")
        return

    aiInstance.puppetMode = true

    if aiInstance.is_in_group("AI"):
        aiInstance.remove_from_group("AI")

    _coop_strip_puppet_pickups(aiInstance)

    aiInstance.show()
    aiInstance.pause = false
    aiInstance.collision_layer = 0
    aiInstance.collision_mask = 0
    aiInstance.process_mode = Node.PROCESS_MODE_INHERIT

    if aiInstance.skeleton:
        aiInstance.skeleton.process_mode = Node.PROCESS_MODE_INHERIT
        aiInstance.skeleton.show_rest_only = false
        aiInstance.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE

    if aiInstance.animator:
        aiInstance.animator.active = false

    animPlayer = aiInstance.get_node_or_null("Guard/Animations")

    if animPlayer:
        animPlayer.play("Rifle_Idle", 0.3)

    call_deferred("CaptureInitialWeaponFile")


func CaptureInitialWeaponFile():
    await get_tree().physics_frame
    await get_tree().physics_frame
    if aiInstance && aiInstance.weapon && aiInstance.weapon.slotData && aiInstance.weapon.slotData.itemData:
        currentWeaponFile = aiInstance.weapon.slotData.itemData.file


func _coop_strip_puppet_pickups(node: Node) -> void:
    if node is Pickup:
        if node.is_in_group("Item"):
            node.remove_from_group("Item")
        if node is CollisionObject3D:
            node.collision_layer = 0
            node.collision_mask = 0
        if node.has_method("Freeze"):
            node.Freeze()
    for child in node.get_children():
        _coop_strip_puppet_pickups(child)


func _pick_animation(state: Dictionary) -> String:
    var weaponType: String = state.get("weapon", "rifle")
    var prefix = "Pistol" if weaponType == "pistol" else "Rifle"
    var condition: String = state.get("animCondition", "Group")
    var blend: float = state.get("animBlend", 1.0)

    match condition:
        "Group":
            return prefix + "_Idle"
        "Guard":
            return prefix + "_Guard"
        "MovementLow":
            return prefix + "_Walk_F"
        "Movement":
            if blend >= 4.0:
                return prefix + "_Sprint_F"
            elif blend >= 2.0:
                return prefix + "_Aim_Run_F"
            else:
                return prefix + "_Aim_Walk_F"
        "Defend":
            return prefix + "_Aim_Idle"
        "Combat":
            return prefix + "_Aim_Walk_F"
        "Hunt":
            if blend >= 0.5:
                return prefix + "_Aim_Crouch_F"
            else:
                return prefix + "_Aim_Crouch_Idle"

    return prefix + "_Idle"


func ApplyAnimState(state: Dictionary):

    if !aiInstance:
        return

    if !animPlayer:
        animPlayer = aiInstance.get_node_or_null("Guard/Animations")
        if !animPlayer:
            return

    if !aiInstance.visible:
        aiInstance.show()
    if aiInstance.pause:
        aiInstance.pause = false
    if aiInstance.skeleton && aiInstance.skeleton.show_rest_only:
        aiInstance.skeleton.show_rest_only = false

    var weaponType: String = state.get("weapon", "rifle")
    var hasWeapon: bool = state.get("hasWeapon", true)


    var targetAnim = _pick_animation(state)
    if targetAnim != currentAnim:
        animPlayer.play(targetAnim, 0.3)
        currentAnim = targetAnim


    var weaponFile: String = state.get("weaponFile", "")
    if weaponFile != currentWeaponFile:
        SwapWeapon(weaponFile)
        currentWeaponFile = weaponFile

    if aiInstance.weapons:
        for child in aiInstance.weapons.get_children():
            child.visible = hasWeapon


    var shots: int = state.get("shots", 0)
    var suppressed: bool = state.get("suppressed", false)
    var fireMode: int = state.get("fireMode", 1)
    for i in shots:
        PlayPuppetFireEffect(suppressed, fireMode)

    _apply_puppet_attachments(state.get("attachments", []))
    _apply_puppet_flashlight(state.get("flashlight", false))
    _apply_puppet_spine_pitch(state.get("pitch", 0.0))
    _update_puppet_flashlight_transform()


func OnPuppetDeath():
    if !aiInstance:
        return
    if animPlayer:
        animPlayer.stop()
    if aiInstance.animator:
        aiInstance.animator.active = false
    if aiInstance.skeleton:
        aiInstance.skeleton.Activate(Vector3(0, 0, -1), 20)
        aiInstance.skeleton.simulationTime = 999.0


func OnPuppetRespawn():
    if !aiInstance:
        return

    if aiInstance.skeleton:
        aiInstance.skeleton.DeactivateBones()
        aiInstance.skeleton.isActive = false
        aiInstance.skeleton.simulationTimer = 0.0
        aiInstance.skeleton.show_rest_only = false
        aiInstance.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE

    # Keep the AnimationTree disabled — puppets use direct AnimationPlayer.
    if aiInstance.animator:
        aiInstance.animator.active = false

    if !animPlayer:
        animPlayer = aiInstance.get_node_or_null("Guard/Animations")
    if animPlayer:
        currentAnim = ""
        animPlayer.play("Rifle_Idle", 0.3)


func PlayPuppetFireEffect(suppressed: bool = false, fireMode: int = 1):
    if !currentWeaponNode:
        return
    var muzzleNode = currentWeaponNode.get_node_or_null("Muzzle")
    if !muzzleNode:
        return
    if !suppressed:
        var flash = flashVFX.instantiate()
        muzzleNode.add_child(flash)
        flash.Emit(true, 0.05)
    var audio = audioInstance3D.instantiate()
    muzzleNode.add_child(audio)
    if currentWeaponNode.slotData and currentWeaponNode.slotData.itemData:
        var weaponData = currentWeaponNode.slotData.itemData
        if suppressed and weaponData.get("fireSuppressed"):
            audio.PlayInstance(weaponData.fireSuppressed, 20, 200)
        elif fireMode == 2 and weaponData.get("fireAuto"):
            audio.PlayInstance(weaponData.fireAuto, 20, 200)
        elif weaponData.get("fireSemi"):
            audio.PlayInstance(weaponData.fireSemi, 20, 200)


func SwapWeapon(file: String):
    if !aiInstance || !aiInstance.weapons:
        return

    for child in aiInstance.weapons.get_children():
        child.queue_free()

    if file == "":
        return

    var scene = Database.get(file)
    if !scene:
        return

    var weapon = scene.instantiate()
    aiInstance.weapons.add_child(weapon)
    currentWeaponNode = weapon

    if weapon.is_in_group("Item"):
        weapon.remove_from_group("Item")
    weapon.collision_layer = 0
    weapon.collision_mask = 0
    weapon.freeze = true

    if weapon.slotData && weapon.slotData.itemData && weapon.slotData.itemData.weaponType == "Pistol":
        weapon.transform = PISTOL_GRIP
    else:
        weapon.transform = RIFLE_GRIP
    weapon.show()

    if weapon.slotData && weapon.slotData.itemData:
        var weaponData = weapon.slotData.itemData
        if weaponData.weaponAction != "Manual" && weaponData.compatible.size() > 0:
            if weaponData.compatible[0].subtype == "Magazine":
                var attachments = weapon.get_node_or_null("Attachments")
                if attachments:
                    var magazine = attachments.get_node_or_null(weaponData.compatible[0].file)
                    if magazine:
                        magazine.show()


var _current_attachments: Array = []
var _current_flashlight: bool = false
var _spine_bone: int = -1
var _spine_pitch: float = 0.0


func _apply_puppet_attachments(attachmentFiles: Array):
    if !currentWeaponNode or attachmentFiles == _current_attachments:
        return
    _current_attachments = attachmentFiles.duplicate()

    var attachments = currentWeaponNode.get_node_or_null("Attachments")
    if !attachments:
        return

    for child in attachments.get_children():
        child.hide()

    for file in attachmentFiles:
        var node = attachments.get_node_or_null(str(file))
        if node:
            node.show()


func _apply_puppet_spine_pitch(pitch: float):
    if !aiInstance or !aiInstance.skeleton:
        return
    if _spine_bone < 0:
        _spine_bone = aiInstance.spineData.bone if aiInstance.spineData else 12
    _spine_pitch = lerp(_spine_pitch, pitch, 0.15)
    var skel = aiInstance.skeleton
    var bonePose: Transform3D = skel.get_bone_global_pose_no_override(_spine_bone)
    bonePose.basis = bonePose.basis.rotated(bonePose.basis.x, -_spine_pitch * 0.7)
    skel.set_bone_global_pose_override(_spine_bone, bonePose, 1.0, true)


var _puppet_spotlight: SpotLight3D = null

func _apply_puppet_flashlight(on: bool):
    if on == _current_flashlight:
        return
    _current_flashlight = on

    if !aiInstance:
        return

    if on:
        if !_puppet_spotlight:
            _puppet_spotlight = SpotLight3D.new()
            _puppet_spotlight.name = "_coop_flashlight"
            _puppet_spotlight.spot_angle = 30.0
            _puppet_spotlight.spot_range = 50.0
            _puppet_spotlight.light_energy = 20.0
            _puppet_spotlight.light_color = Color.WHITE
            _puppet_spotlight.shadow_enabled = false
            aiInstance.add_child(_puppet_spotlight)
        _puppet_spotlight.visible = true
    else:
        if _puppet_spotlight:
            _puppet_spotlight.visible = false


func _update_puppet_flashlight_transform():
    if !_puppet_spotlight or !_puppet_spotlight.visible:
        return
    if aiInstance and aiInstance.eyes:
        _puppet_spotlight.global_position = aiInstance.eyes.global_position
        _puppet_spotlight.global_basis = aiInstance.eyes.global_basis * Basis(Vector3.UP, PI)
