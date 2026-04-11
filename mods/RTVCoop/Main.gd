extends Node


func _ready():

    print("[RTVCoop] Creating autoloads at /root/...")

    _try_load_steam_extension()

    var overlay_script = load("res://mods/RTVCoop/DebugOverlay.gd")
    if overlay_script:
        var overlay = CanvasLayer.new()
        overlay.set_script(overlay_script)
        overlay.name = "CoopDebug"
        get_tree().root.add_child(overlay)
        print("[RTVCoop] Debug overlay OK")


    var lobby_steam_script = load("res://mods/RTVCoop/SteamLobby.gd")
    if lobby_steam_script:
        var lobby_steam = Node.new()
        lobby_steam.set_script(lobby_steam_script)
        lobby_steam.name = "SteamLobby"
        get_tree().root.add_child(lobby_steam)
        print("[RTVCoop] SteamLobby OK")


    var net_script = load("res://mods/RTVCoop/Network.gd")
    if net_script:
        var net = Node.new()
        net.set_script(net_script)
        net.name = "Network"
        get_tree().root.add_child(net)
        print("[RTVCoop] Network OK")

    var pm_script = load("res://mods/RTVCoop/PlayerManager.gd")
    if pm_script:
        var pm = Node.new()
        pm.set_script(pm_script)
        pm.name = "PlayerManager"
        get_tree().root.add_child(pm)
        print("[RTVCoop] PlayerManager OK")

    var lobby_script = load("res://mods/RTVCoop/LobbyUI.gd")
    if lobby_script:
        var lobby = CanvasLayer.new()
        lobby.set_script(lobby_script)
        lobby.name = "CoopLobby"
        get_tree().root.add_child(lobby)
        print("[RTVCoop] Lobby UI OK")

    print("[RTVCoop] Registering overrides...")

    _override("res://mods/RTVCoop/Overrides/AI_Override.gd", "res://Scripts/AI.gd")
    _override("res://mods/RTVCoop/Overrides/AISpawner_Override.gd", "res://Scripts/AISpawner.gd")
    _override("res://mods/RTVCoop/Overrides/Character_Override.gd", "res://Scripts/Character.gd")
    _override("res://mods/RTVCoop/Overrides/Compiler_Override.gd", "res://Scripts/Compiler.gd")
    _override("res://mods/RTVCoop/Overrides/Door_Override.gd", "res://Scripts/Door.gd")
    _override("res://mods/RTVCoop/Overrides/Switch_Override.gd", "res://Scripts/Switch.gd")
    _override("res://mods/RTVCoop/Overrides/Loader_Override.gd", "res://Scripts/Loader.gd")
    _override("res://mods/RTVCoop/Overrides/Pickup_Override.gd", "res://Scripts/Pickup.gd")
    _override("res://mods/RTVCoop/Overrides/LootContainer_Override.gd", "res://Scripts/LootContainer.gd")
    _override("res://mods/RTVCoop/Overrides/Interface_Override.gd", "res://Scripts/Interface.gd")
    _override("res://mods/RTVCoop/Overrides/Interactor_Override.gd", "res://Scripts/Interactor.gd")
    _override("res://mods/RTVCoop/Overrides/Simulation_Override.gd", "res://Scripts/Simulation.gd")
    _override("res://mods/RTVCoop/Overrides/Explosion_Override.gd", "res://Scripts/Explosion.gd")
    _override("res://mods/RTVCoop/Overrides/GrenadeRig_Override.gd", "res://Scripts/GrenadeRig.gd")
    _override("res://mods/RTVCoop/Overrides/LootSimulation_Override.gd", "res://Scripts/LootSimulation.gd")

    print("[RTVCoop] Done.")
    queue_free()


func _override(modPath: String, gamePath: String):
    var script = load(modPath)
    if !script:
        print("[RTVCoop] FAIL load: " + modPath)
        return
    script.reload()
    script.take_over_path(gamePath)
    print("[RTVCoop] OK: " + gamePath + " -> " + modPath)


func _try_load_steam_extension():
    var ext_path = "res://addons/godotsteam/godotsteam.gdextension"
    if !FileAccess.file_exists(ext_path):
        print("[RTVCoop] GodotSteam .gdextension not found at " + ext_path + " — skipping (direct IP only)")
        return
    if GDExtensionManager.is_extension_loaded(ext_path):
        print("[RTVCoop] GodotSteam already loaded")
        return
    var status = GDExtensionManager.load_extension(ext_path)
    match status:
        GDExtensionManager.LOAD_STATUS_OK:
            print("[RTVCoop] GodotSteam extension loaded OK")
        GDExtensionManager.LOAD_STATUS_ALREADY_LOADED:
            print("[RTVCoop] GodotSteam extension already loaded")
        GDExtensionManager.LOAD_STATUS_FAILED:
            print("[RTVCoop] GodotSteam extension FAILED to load (status=FAILED)")
        GDExtensionManager.LOAD_STATUS_NOT_LOADED:
            print("[RTVCoop] GodotSteam extension NOT loaded (status=NOT_LOADED)")
        GDExtensionManager.LOAD_STATUS_NEEDS_RESTART:
            print("[RTVCoop] GodotSteam extension needs editor restart (status=NEEDS_RESTART)")
        _:
            print("[RTVCoop] GodotSteam extension load returned unknown status: " + str(status))
