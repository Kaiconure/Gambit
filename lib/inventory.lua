local inventory = {}

-------------------------------------------------------------------------------
-- Bags that store equippable items
local INVENTORY_BAGS_BY_ID = 
{
    [0] = { field = "inventory", usable = true, equippable = true },
    [1] = { field = "safe" },
    [2] = { field = "storage" },
    [3] = { field = "locker" },
    [4] = { field = "temporary", usable = true },
    [5] = { field = "satchel" },
    [6] = { field = "sack" },
    [8] = { field = "wardrobe", usable = true, equippable = true },
    [10] = { field = "wardrobe2", usable = true, equippable = true },
    [11] = { field = "wardrobe3", usable = true, equippable = true },
    [12] = { field = "wardrobe4", usable = true, equippable = true },
    [13] = { field = "wardrobe5", usable = true, equippable = true },
    [14] = { field = "wardrobe6", usable = true, equippable = true },
    [15] = { field = "wardrobe7", usable = true, equippable = true },
    [16] = { field = "wardrobe8", usable = true, equippable = true },
}

local INVENTORY_ID_BY_NAME = {
    ["inventory"] = 0,
    ["safe"] = 1,
    ["storage"] = 2,
    ["locker"] = 3,
    ["temporary"] = 4,
    ["satchel"] = 5,
    ["sack"] = 6,
    ["wardrobe"] = 8,
    ["wardrobe2"] = 10,
    ["wardrobe3"] = 11,
    ["wardrobe4"] = 12,
    ["wardrobe5"] = 13,
    ["wardrobe6"] = 14,
    ["wardrobe7"] = 15,
    ["wardrobe8"] = 16,
}

local GEAR_SLOT_INFO = 
{
	{slot = 'main', field = 'main', id = 0},
	{slot = 'range', field = 'range', id = 2},
	{slot = 'head', field = 'head', id = 4},
	{slot = 'neck', field = 'neck', id = 9},
	{slot = 'body', field = 'body', id = 5},
	{slot = 'hands', field = 'hands', id = 6},
	{slot = 'back', field = 'back', id = 15},
	{slot = 'waist', field = 'waist', id = 10},
	{slot = 'legs', field = 'legs', id = 7},
	{slot = 'feet', field = 'feet', id = 8},
    {slot = 'ear1', field = 'left_ear', id = 11},
	{slot = 'ear2', field = 'right_ear', id = 12},
    {slot = 'ring1', field = 'left_ring', id = 13},
	{slot = 'ring2', field = 'right_ring', id = 14},
	{slot = 'sub', field = 'sub', id = 1},
	{slot = 'ammo', field = 'ammo', id = 3},
}

---------------------------------------------------------------------
-- Equipment slot names by ID
local GEAR_SLOT_NAMES_BY_ID = {
    [0] = 'main',
    [1] = 'sub',
    [2] = 'range',
    [3] = 'ammo',
    [4] = 'head',
    [5] = 'body',
    [6] = 'hands',
    [7] = 'legs',
    [8] = 'feet',
    [9] = 'neck',
    [10] = 'waist',
    [11] = 'ear1',
    [12] = 'ear2',
    [13] = 'ring1',
    [14] = 'ring2',
    [15] = 'back',
}

---------------------------------------------------------------------
-- Equipment slot field names by ID
local GEAR_SLOT_FIELDS_BY_ID = {
    [0] = 'main',
    [1] = 'sub',
    [2] = 'range',
    [3] = 'ammo',
    [4] = 'head',
    [5] = 'body',
    [6] = 'hands',
    [7] = 'legs',
    [8] = 'feet',
    [9] = 'neck',
    [10] = 'waist',
    [11] = 'left_ear',
    [12] = 'right_ear',
    [13] = 'left_ring',
    [14] = 'right_ring',
    [15] = 'back',
}

---------------------------------------------------------------------
-- Equipment slot ID's by name
local GEAR_SLOT_IDS_BY_NAME = {
    ['main'] = 0,
    ['sub'] = 1,
    ['range'] = 2,
    ['ammo'] = 3,
    ['head'] = 4,
    ['body'] = 5,
    ['hands'] = 6,
    ['legs'] = 7,
    ['feet'] = 8,
    ['neck'] = 9,
    ['waist'] = 10,
    ['ear1'] = 11,
    ['ear2'] = 12,
    ['ring1'] = 13,
    ['ring2'] = 14,
    ['back'] = 15
}



--
-- Find the actual item resource represented by the specified bag location.
--
inventory.get_item_from_bag = function (items, bagId, localId)
    if localId <= 0 then
        return
    end
    
    -- Find the containing bag
    local bagInfo = INVENTORY_BAGS_BY_ID[bagId]
    if bagInfo == nil then
        return
    end

    -- Find the item in the bag
    local bagName = bagInfo.field
    local bagItem = items[bagName] and items[bagName][localId]
    if bagItem == nil then
        return
    end

    -- Find the actual item info
    return resources.items[bagItem.id]    
end

-- flags:
--  - usable
--  - equippable

local default_find_item_flags = {
    usable = false,
    equippable = false
}

inventory.find_equipment_in_slot = function(slot, items)
    if slot == nil then return end

    local slotId = GEAR_SLOT_IDS_BY_NAME[slot]
    if slotId == nil then return end
    local slotField = GEAR_SLOT_FIELDS_BY_ID[slotId]
    if slotField == nil then return end

    items = items or windower.ffxi.get_items()
    if not items then return end

    -- 0 in the slot item id (local id) means nothing is equipped
    local localId = items.equipment[slotField]
    if localId <= 0 then return end

    local bagId = items.equipment[slotField .. '_bag']
    if bagId < 0 then return end

    local bagInfo = INVENTORY_BAGS_BY_ID[bagId]
    local bag = items[bagInfo.field]

    if not bag then return end

    -- Get the item entry from the bag
    local bagItem = bag[localId]
    if not bagItem then return end

    return inventory.find_item(nil,
        {
            equippable = true,
            bag_id = bagId,
            local_id = localId
        },
        items)
end

inventory.find_item = function(item, flags, items)
    flags = flags or default_find_item_flags

    local only_usable = flags.usable
    local only_equippable = flags.equippable

    if not flags.local_id then
        item = findItem(item)    
        if item == nil then return end
    end

    items = items or windower.ffxi.get_items()

    local bags_to_search = (flags.bag_id and { INVENTORY_BAGS_BY_ID[flags.bag_id] }) or INVENTORY_BAGS_BY_ID

    for bagId, bagInfo in pairs(bags_to_search) do
        local bag_is_usable = bagInfo.usable
        local bag_is_equippable = bagInfo.equippable

        if 
            (bag_is_usable or not only_usable) and
            (bag_is_equippable or not only_equippable)
        then
            local bag = items[bagInfo.field]
            local bagItem = nil

            if flags.local_id then
                -- If a specific local id was specified, use that directly. We'll also
                -- update the underlying item to match this one.
                bagItem = bag[flags.local_id]
                if bagItem then
                    item = findItem(bagItem.id)
                end
            else
                -- Otherwise, find the first item whose ID matches the item provided
                bagItem = tableFirst(bag, function (_i) 
                    return type(_i) == 'table' and _i.id == item.id 
                end)
            end

            -- Bag item structure
            -- count: int,
            -- status: int,
            -- id: int,
            -- slot: int,
            -- bazaar: int,
            -- extdata: string,

            --Item statuses: 
            --  0: None
            --  5: Equipped
            --  19: Linkshell Equipped
            --  25: In Bazaar

            if bagItem and item then
                local ext = extdata.decode(bagItem)

                local chargesRemaining = 1
                local secondsUntilReuse = nil
                local secondsUntilActivation = nil

                if ext then
                    if type(ext.charges_remaining) == 'number' then
                        chargesRemaining = ext.charges_remaining
                    end

                    -- Countdown to when it can be equipped and used (ex: 15 minutes on Capacity Ring)
                    if type(ext.next_use_time) == 'number' then
                        secondsUntilReuse = ext.next_use_time + 18000 - os.time()
                    end
                    
                    -- Countdown to use once it's been equiped (ex: 5 seconds on Capacity Ring).
                    -- It will be negative if the item is not equipped.
                    if type(ext.activation_time) == 'number' then
                        secondsUntilActivation = ext.activation_time + 18000 - os.time()
                    end
                end
                
                local isUsableItem = 
                    (item.category == 'Usable' or (ext and (ext.usable or ext.type == 'Enchanted Equipment'))) and
                    bagInfo.usable and
                    bag.enabled and
                    bagItem.status ~= 25 and
                    (secondsUntilReuse == nil or secondsUntilReuse <= 0) and
                    chargesRemaining > 0

                local isEquippableItem = 
                    (item.flags and item.flags.Equippable) and 
                    bagInfo.equippable and
                    bagItem.status ~= 25

                local isEquipped = bagItem.status == 5 or bagItem.status == 19

                local slots = {}
                local slot = nil
                if type(item.slots) == 'table' then
                    for slotId, validSlot in pairs(item.slots) do
                        local slotName = GEAR_SLOT_NAMES_BY_ID[slotId]
                        if validSlot and slotName then
                            slots[#slots + 1] = slotName
                        end

                        if items.equipment then
                            local slotField = GEAR_SLOT_FIELDS_BY_ID[slotId]
                            if slotField then
                                local slotEquipment = items.equipment[slotField]
                                local slotEquipmentBag = items.equipment[slotField .. '_bag']

                                if 
                                    slotEquipment == bagItem.slot and
                                    slotEquipmentBag == bagId
                                then
                                    slot = slotName
                                end
                            end
                        end
                    end
                end

                if 
                    (isUsableItem or not flags.usable) and          -- Usable flag
                    (isEquippableItem or not flags.equippable) and  -- Equippable flag
                    (
                        flags.equipped == nil or                    -- Equipped flag
                        (flags.equipped ~= false and isEquipped) or
                        (flags.equipped == false and not isEquipped)
                    )
                then
                    return {
                        bagId = bagId,
                        bagName = bagInfo.field,
                        localId = bagItem.slot,
                        id = bagItem.id,
                        item = item,
                        name = item.name,
                        count = bagItem.count,
                        status = bagItem.status,
                        extdata = ext,
                        item_type = item.type,
                        ext_type = ext and ext.type,
                        is_equipped = isEquipped,
                        is_bazaar = bagItem.status == 25,
                        charges_remaining = charges,
                        seconds_until_reuse = secondsUntilReuse,
                        seconds_until_activation = secondsUntilActivation,
                        can_use = isUsableItem,
                        slot = slot or (slots and slots[1]), -- Save the current slot, or first valid slot, for easy access (equipment only)
                        slots = slots -- Save all slots (equipment only)
                    }
                end
            end
        end
    end
end

--
-- Determine if appropriate ranged attack gear is equipped. Note that this will NOT register 
-- for consumable thrown items (i.e. it will not let you throw your Rare/Ex sachet).
--
inventory.get_ranged_equipment = function ()
    local items = windower.ffxi.get_items()
    if items then
        local range = inventory.get_item_from_bag(items, items.equipment.range_bag, items.equipment.range)
        local ammo = inventory.get_item_from_bag(items, items.equipment.ammo_bag, items.equipment.ammo)

        -- Can't do anything if there's no ranged weapon equipped
        if range == nil then return end

        local category = range.category
        local valid = false
        if category == 'Weapon' then
            local range_type = range.range_type
            local ammo_type = ammo and ammo.ammo_type
            if range_type == 'Bow' and ammo_type == 'Arrow' then
                valid = true
            elseif range_type == 'Crossbow' and ammo_type == 'Bolt' then
                valid = true
            elseif range_type == 'Gun' and ammo_type == 'Bullet' then
                valid = true
            elseif range_type == nil then
                -- It seems that throwing weapons have no range type...maybe they used to be ammo.
                -- This includes boomerangs and chakrams
                valid = true
            end

            return {
                weapon = range,
                ammo = ammo,
                valid = valid
            }
        end
    end
end

return inventory