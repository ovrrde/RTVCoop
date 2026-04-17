extends "res://Scripts/AI.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


var puppetMode: bool = false
var spawnVariant: Dictionary = {}

var _client_anim_ready: bool = false
var _client_last_state: int = -1

var _coop_force_local_play: bool = false


func _physics_process(delta):
    if pause || dead:
        return

    if puppetMode:
        return

    if _net().IsActive() && !multiplayer.is_server():
        _client_animate(delta)
        return

    super(delta)


func _client_animate(delta):
    if !animator or !skeleton:
        return

    if !_client_anim_ready:
        animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
        skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
        animator.active = true
        skeleton.show_rest_only = false
        _reset_client_animator_conditions()
        _client_last_state = -1
        _client_anim_ready = true

    if currentState != _client_last_state:
        _apply_client_animator_conditions(currentState)
        _client_last_state = currentState

    movementSpeed = move_toward(movementSpeed, speed, delta * 5.0)
    animator["parameters/Rifle/Movement/blend_position"] = movementSpeed
    animator["parameters/Pistol/Movement/blend_position"] = movementSpeed

    animator.advance(delta)
    skeleton.advance(delta)


func _reset_client_animator_conditions():
    if !animator:
        return
    animator["parameters/Rifle/conditions/Movement"] = false
    animator["parameters/Pistol/conditions/Movement"] = false
    animator["parameters/Rifle/conditions/Combat"] = false
    animator["parameters/Pistol/conditions/Combat"] = false
    animator["parameters/Rifle/conditions/Guard"] = false
    animator["parameters/Pistol/conditions/Guard"] = false
    animator["parameters/Rifle/conditions/Defend"] = false
    animator["parameters/Pistol/conditions/Defend"] = false
    animator["parameters/Rifle/conditions/Hunt"] = false
    animator["parameters/Pistol/conditions/Hunt"] = false
    animator["parameters/Rifle/conditions/Group"] = false
    animator["parameters/Pistol/conditions/Group"] = false


func _apply_client_animator_conditions(state: int):
    if !animator:
        return
    _reset_client_animator_conditions()
    match state:
        State.Idle, State.Guard:
            animator["parameters/Rifle/conditions/Guard"] = true
            animator["parameters/Pistol/conditions/Guard"] = true
        State.Wander, State.Patrol, State.Hide, State.Cover, \
        State.Shift, State.Attack, State.Vantage, State.Return:
            animator["parameters/Rifle/conditions/Movement"] = true
            animator["parameters/Pistol/conditions/Movement"] = true
        State.Defend:
            animator["parameters/Rifle/conditions/Defend"] = true
            animator["parameters/Pistol/conditions/Defend"] = true
        State.Combat:
            animator["parameters/Rifle/conditions/Combat"] = true
            animator["parameters/Pistol/conditions/Combat"] = true
        State.Hunt, State.Ambush:
            animator["parameters/Rifle/conditions/Hunt"] = true
            animator["parameters/Pistol/conditions/Hunt"] = true


func Initialize():
    await get_tree().physics_frame

    if puppetMode:
        DeactivateEquipment()
        DeactivateContainer()
        EquipmentSetup()
        HideGizmos()
        return

    navigationMap = get_world_3d().get_navigation_map()
    map = get_tree().current_scene.get_node_or_null("/root/Map")
    AISpawner = get_tree().current_scene.get_node_or_null("/root/Map/AI")

    if boss: health = 300.0
    else: health = 100.0

    DeactivateEquipment()
    DeactivateContainer()
    HideGizmos()

    if _net().IsActive() and !multiplayer.is_server():
        return

    await get_tree().create_timer(10.0, false).timeout;
    voiceCycle = randf_range(10.0, 60.0)
    sensorActive = true


func EquipmentSetup():
    SelectWeapon()
    if allowBackpacks: SelectBackpack()
    if allowClothing: SelectClothing()


func Parameters(delta):
    LKL = lerp(LKL, lastKnownLocation, delta * LKLSpeed)

    if _net().IsActive():
        playerPosition = _pm().GetNearestPlayerPosition(global_position)
    else:
        playerPosition = gameData.playerPosition

    playerDistance3D = global_position.distance_to(playerPosition)
    playerDistance2D = Vector2(global_position.x, global_position.z).distance_to(Vector2(playerPosition.x, playerPosition.z))
    fireVector = (global_position - playerPosition).normalized().dot(gameData.playerVector)

    if playerDistance3D < 10 && playerVisible:
        sensorCycle = 0.05
        LKLSpeed = 4.0
    elif playerDistance3D > 10 && playerDistance3D < 50:
        sensorCycle = 0.1
        LKLSpeed = 2.0
    elif playerDistance3D > 50:
        sensorCycle = 0.5
        LKLSpeed = 1.0


func Sensor(delta):
    sensorTimer += delta

    if sensorTimer > sensorCycle:
        if playerDistance3D <= 200.0:
            var targetCamera = gameData.cameraPosition
            if _net().IsActive():
                targetCamera = _pm().GetNearestPlayerCamera(global_position)

            var directionToPlayer = (eyes.global_position - targetCamera).normalized()
            var viewDirection = - eyes.global_transform.basis.z.normalized()
            var viewRadius = viewDirection.dot(directionToPlayer)

            if viewRadius > 0.5:
                LOSCheck(targetCamera)
            else:
                playerVisible = false
        else:
            playerVisible = false

        if !playerVisible:
            Hearing()

        sensorTimer = 0.0


func SelectWeapon():
    if weapons.get_child_count() != 0:
        var weaponFile: String = spawnVariant.get("weaponFile", "")
        var weaponIndex = -1
        if weaponFile != "":
            for i in weapons.get_child_count():
                var child = weapons.get_child(i)
                if child.slotData and child.slotData.itemData and child.slotData.itemData.file == weaponFile:
                    weaponIndex = i
                    break
        if weaponIndex < 0:
            weaponIndex = randi_range(0, weapons.get_child_count() - 1)

        weapon = weapons.get_child(weaponIndex)
        weaponData = weapon.slotData.itemData
        weapon.show()

        for child in weapons.get_children():
            if child != weapon:
                child.queue_free()

        muzzle = weapon.get_node("Muzzle")

        var LOD0: MeshInstance3D = weapon.get_node_or_null("LOD0")
        var LOD1: MeshInstance3D = weapon.get_node_or_null("LOD1")
        if LOD0 && LOD1:
            LOD0.visibility_range_end = 10.0
            LOD1.visibility_range_begin = 9.0
            LOD1.visibility_range_end = 200.0
        else:
            print("AI: Weapon visibility failed")

        var newSlotData = SlotData.new()
        newSlotData.itemData = weapon.slotData.itemData
        newSlotData.condition = spawnVariant.get("weaponCondition", randi_range(5, 50))
        newSlotData.amount = spawnVariant.get("weaponAmount", randi_range(1, newSlotData.itemData.magazineSize))
        newSlotData.chamber = true
        weapon.slotData = newSlotData

        if newSlotData.itemData.weaponType == "Pistol":
            animator["parameters/conditions/Pistol"] = true
            animator["parameters/conditions/Rifle"] = false
        else:
            animator["parameters/conditions/Pistol"] = false
            animator["parameters/conditions/Rifle"] = true

        if weaponData.weaponAction != "Manual":
            if weaponData.compatible.size() != 0:
                if weaponData.compatible[0].subtype == "Magazine":
                    var magazine = weapon.get_node_or_null("Attachments").get_node_or_null(weaponData.compatible[0].file)
                    var magazineLOD0: MeshInstance3D = magazine.get_node_or_null("LOD0")
                    var magazineLOD1: MeshInstance3D = magazine.get_node_or_null("LOD1")
                    if magazine && magazineLOD0 && magazineLOD1:
                        magazine.show()
                        magazineLOD0.visibility_range_end = 10.0
                        magazineLOD1.visibility_range_begin = 9.0
                        magazineLOD1.visibility_range_end = 200.0
                    else:
                        print("AI: Magazine visibility failed")
                    weapon.slotData.nested.append(weaponData.compatible[0])


func SelectBackpack():
    if backpacks.get_child_count() != 0:
        var backpackRoll = spawnVariant.get("backpackRoll", randi_range(0, 100))
        if backpackRoll < 10:
            var backpackFile: String = spawnVariant.get("backpackFile", "")
            var backpackIndex = -1
            if backpackFile != "":
                for i in backpacks.get_child_count():
                    var child = backpacks.get_child(i)
                    if child.get("slotData") and child.slotData.itemData and child.slotData.itemData.file == backpackFile:
                        backpackIndex = i
                        break
                    if backpackIndex < 0 and child.name == backpackFile:
                        backpackIndex = i
                        break
            if backpackIndex < 0:
                backpackIndex = randi_range(0, backpacks.get_child_count() - 1)
            backpack = backpacks.get_child(backpackIndex)

            for child in backpacks.get_children():
                if child != backpack:
                    child.queue_free()

            var backpackMesh: MeshInstance3D = backpack.get_node_or_null("Mesh")
            if backpack && backpackMesh:
                backpack.show()
                backpackMesh.visibility_range_end = 400.0
            else:
                print("AI: Backpack visibility failed")

            var chestCollider: CollisionShape3D = chest.get_child(0)
            chestCollider.shape.size.z = 0.4
            chestCollider.position.z -= 0.05
        else:
            for child in backpacks.get_children():
                child.queue_free()


func SelectClothing():
    if clothing.size() != 0:
        var clothingPath: String = spawnVariant.get("clothingPath", "")
        var clothingIndex = -1
        if clothingPath != "":
            for i in clothing.size():
                if clothing[i] and clothing[i].resource_path == clothingPath:
                    clothingIndex = i
                    break
        if clothingIndex < 0:
            clothingIndex = randi_range(0, clothing.size() - 1)
        var clothingMaterial = clothing[clothingIndex]
        mesh.set_surface_override_material(0, clothingMaterial)


func ActivateWanderer():
    EquipmentSetup()
    super()
    HideGizmos()

func ActivateHider():
    EquipmentSetup()
    super()
    HideGizmos()

func ActivateGuard():
    EquipmentSetup()
    super()
    HideGizmos()

func ActivateMinion():
    EquipmentSetup()
    super()
    HideGizmos()

func ActivateBoss():
    EquipmentSetup()
    super()
    HideGizmos()


func _coop_sound(sound_type: int, extra_bool: bool = false):
    if _coop_force_local_play:
        return true
    if _net().IsActive() and !multiplayer.is_server():
        return false
    if _net().IsActive() and multiplayer.is_server() and has_meta("network_uuid"):
        _pm()._ai_sync().BroadcastAISound.rpc(get_meta("network_uuid"), sound_type, extra_bool)
    return true

func PlayFire():
    if _coop_sound(0, fullAuto): super()
func PlayTail():
    if _coop_sound(1): super()
func PlayIdle():
    if _coop_sound(2): super()
func PlayCombat():
    if _coop_sound(3): super()
func PlayDamage():
    if _coop_sound(4): super()
func PlayDeath():
    if _coop_sound(5): super()


func WeaponDamage(hitbox: String, damage: float):
    if dead:
        return

    if puppetMode:
        var node = get_parent()
        while node:
            if "peer_id" in node:
                _pm().RequestPlayerDamage(node.peer_id, int(damage), 0)
                return
            node = node.get_parent()
        return

    if _net().IsActive() && !multiplayer.is_server():
        if has_meta("network_uuid"):
            _pm()._ai_sync().RequestAIDamage.rpc_id(1, get_meta("network_uuid"), hitbox, damage)
        return

    super(hitbox, damage)


func Death(direction, force):
    if dead:
        return

    if puppetMode:
        return

    if _net().IsActive() && multiplayer.is_server() && has_meta("network_uuid"):
        var container_loot: Array = []
        if container and container is LootContainer:
            for slot in container.loot:
                container_loot.append(_pm().SerializeSlotData(slot))

        var weapon_dict: Dictionary = {}
        if weapon and weapon.slotData:
            weapon_dict = _pm().SerializeSlotData(weapon.slotData)

        var backpack_dict: Dictionary = {}
        if backpack and backpack.slotData:
            backpack_dict = _pm().SerializeSlotData(backpack.slotData)

        var secondary_dict: Dictionary = {}
        if secondary and secondary.slotData:
            secondary_dict = _pm().SerializeSlotData(secondary.slotData)

        var dying_uuid = get_meta("network_uuid")
        _pm()._ai_sync().BroadcastAIDeath.rpc(
            dying_uuid,
            direction,
            force,
            container_loot,
            weapon_dict,
            backpack_dict,
            secondary_dict
        )
        # BroadcastAIDeath is call_remote so host must erase locally
        _pm().worldAI.erase(dying_uuid)
        _pm().aiTargets.erase(dying_uuid)

    var aiUuid = get_meta("network_uuid") if has_meta("network_uuid") else -1

    dead = true
    flash.Reset()
    detector.monitoring = false
    LOS.enabled = false
    fire.enabled = false
    below.enabled = false
    forward.enabled = false
    animator.active = false
    collision.disabled = true
    agent.velocity = Vector3.ZERO
    ActivateContainer()

    if aiUuid >= 0 and container and container is LootContainer:
        if !container.is_in_group("CoopLootContainer"):
            container.add_to_group("CoopLootContainer")
        container.set_meta("coop_container_id", aiUuid)

    if weapon:
        weapon.collision.disabled = false
        weapon.process_mode = Node.PROCESS_MODE_INHERIT
        if aiUuid >= 0 && _net().IsActive():
            var wUuid = aiUuid * 10 + 1
            weapon.set_meta("network_uuid", wUuid)
            _pm().worldItems[wUuid] = weapon

    if backpack:
        backpack.collision.disabled = false
        backpack.process_mode = Node.PROCESS_MODE_INHERIT
        if aiUuid >= 0 && _net().IsActive():
            var bUuid = aiUuid * 10 + 2
            backpack.set_meta("network_uuid", bUuid)
            _pm().worldItems[bUuid] = backpack

    if secondary:
        secondary.collision.disabled = false
        secondary.process_mode = Node.PROCESS_MODE_INHERIT
        if aiUuid >= 0 && _net().IsActive():
            var sUuid = aiUuid * 10 + 3
            secondary.set_meta("network_uuid", sUuid)
            _pm().worldItems[sUuid] = secondary

    skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
    skeleton.Activate(direction, force)
    skeleton.set_bone_global_pose_override(spineData.bone, skeleton.get_bone_pose(spineData.bone), 0.0, true)
    AISpawner.activeAgents -= 1
    HideGizmos()
