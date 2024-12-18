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

-- Value	Location
-- 0	Inventory
-- 1	Mog Safe
-- 2	Storage
-- 3	Mog Locker
-- 4	Temp Items
-- 5	Satchel
-- 6	Sack

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

inventory.find_item = function(item, flags)
    flags = flags or default_find_item_flags

    local only_usable = flags.usable
    local only_equippable = flags.equippable

    item = findItem(item)
    
    if item == nil then return end

    for bagId, bagInfo in pairs(INVENTORY_BAGS_BY_ID) do
        local bag_is_usable = bagInfo.usable
        local bag_is_equippable = bagInfo.equippable

        if 
            (bag_is_usable or not only_usable) and
            (bag_is_equippable or not only_equippable)
        then
            local bag = windower.ffxi.get_items(bagId)
            local bagItem = tableFirst(bag, function (_i) 
                return type(_i) == 'table' and _i.id == item.id 
            end)

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

            if bagItem then
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

                -- writeMessage('item: %s: isUsableItem=%s, isEquippableItem=%s':format(
                --     item.name,
                --     tostring(isUsableItem),
                --     tostring(isEquippableItem)
                -- ))
                -- coroutine.sleep(1)

                -- writeJsonToFile('./data/%s.json':format(item.name), item)
                -- writeJsonToFile('/data/%s.extdata.json':format(item.name), ext)

                if 
                    (isUsableItem or not flags.usable) and
                    (isEquippableItem or not flags.equippable)
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
                        is_equipped = bagItem.status == 5 or bagItem.status == 19,
                        is_bazaar = bagItem.status == 25,
                        charges_remaining = charges,
                        seconds_until_reuse = secondsUntilReuse,
                        seconds_until_activation = secondsUntilActivation,
                        can_use = isUsableItem
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