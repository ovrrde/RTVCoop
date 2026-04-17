extends Node


var itemDataCache: Dictionary = {}


func _pm():
    return get_parent()


func SerializeSlotData(slot: SlotData) -> Dictionary:
    if !slot || !slot.itemData:
        return {}
    var nestedFiles: Array = []
    for item in slot.nested:
        if item:
            nestedFiles.append(item.file)
    return {
        "file": slot.itemData.file,
        "amount": slot.amount,
        "condition": slot.condition,
        "state": slot.state,
        "rotated": slot.gridRotated,
        "gridPosition": slot.gridPosition,
        "position": slot.position,
        "mode": slot.mode,
        "zoom": slot.zoom,
        "chamber": slot.chamber,
        "casing": slot.casing,
        "nested": nestedFiles,
    }


func DeserializeSlotData(dict: Dictionary) -> SlotData:
    var slot = SlotData.new()
    var file = dict.get("file", "")
    if file == "":
        return null
    slot.itemData = LookupItemData(file)
    if !slot.itemData:
        return null
    slot.amount = dict.get("amount", 0)
    slot.condition = dict.get("condition", 100)
    slot.state = dict.get("state", "")
    slot.gridRotated = dict.get("rotated", false)
    slot.gridPosition = dict.get("gridPosition", Vector2.ZERO)
    slot.position = dict.get("position", 0)
    slot.mode = dict.get("mode", 1)
    slot.zoom = dict.get("zoom", 1)
    slot.chamber = dict.get("chamber", false)
    slot.casing = dict.get("casing", false)
    for nestedFile in dict.get("nested", []):
        var nestedData = LookupItemData(nestedFile)
        if nestedData:
            slot.nested.append(nestedData)
    return slot


func LookupItemData(file: String) -> ItemData:
    if file == "":
        return null
    if itemDataCache.has(file):
        return itemDataCache[file]
    var scene = Database.get(file)
    if !scene:
        push_warning("[SlotSerializer] Unknown item file: " + file + " — peer may be missing a mod")
        return null
    var temp = scene.instantiate()
    var data = null
    if "slotData" in temp && temp.slotData && temp.slotData.itemData:
        data = temp.slotData.itemData
    temp.queue_free()
    if data:
        itemDataCache[file] = data
    return data


func ApplySlotDictToPickup(pickup, slotDict: Dictionary):
    if !pickup or !pickup.slotData:
        return
    pickup.slotData.amount = slotDict.get("amount", pickup.slotData.amount)
    pickup.slotData.condition = slotDict.get("condition", pickup.slotData.condition)
    pickup.slotData.state = slotDict.get("state", pickup.slotData.state)
    pickup.slotData.chamber = slotDict.get("chamber", pickup.slotData.chamber)
    pickup.slotData.casing = slotDict.get("casing", pickup.slotData.casing)
    pickup.slotData.mode = slotDict.get("mode", pickup.slotData.mode)
    pickup.slotData.zoom = slotDict.get("zoom", pickup.slotData.zoom)
    pickup.slotData.position = slotDict.get("position", pickup.slotData.position)
    pickup.slotData.nested.clear()
    for nestedFile in slotDict.get("nested", []):
        var nestedData = LookupItemData(nestedFile)
        if nestedData:
            pickup.slotData.nested.append(nestedData)
    if pickup.has_method("UpdateAttachments"):
        pickup.UpdateAttachments()
