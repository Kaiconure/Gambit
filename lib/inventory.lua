local inventory = {}

-------------------------------------------------------------------------------
-- Bags that store equipable items
local EQUIPMENT_BAGS_BY_ID = 
{
    [0] = { field = "inventory" },
    [8] = { field = "wardrobe" },
    [10] = { field = "wardrobe2" },
    [11] = { field = "wardrobe3" },
    [12] = { field = "wardrobe4" },
    [13] = { field = "wardrobe5" },
    [14] = { field = "wardrobe6" },
    [15] = { field = "wardrobe7" },
    [16] = { field = "wardrobe8" },
}

--
-- Find the actual item resource represented by the specified bag location.
--
inventory.get_item_from_bag = function (items, bagId, localId)
    if localId <= 0 then
        return
    end
    
    -- Find the containing bag
    local bagInfo = EQUIPMENT_BAGS_BY_ID[bagId]
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

inventory.find_item = function(item)
    item = findItem(item)
    
    if item == nil then return end

    for bagId, entry in pairs(EQUIPMENT_BAGS_BY_ID) do
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

        if bagItem then
            local data = extdata.decode(bagItem)

            if true then -- item.category == 'Usable' or extdata.usable then        
                return {
                    bagId = bagId,
                    bagName = entry.field,
                    localId = bagItem.slot,
                    id = bagItem.id,
                    item = item,
                    name = item.name,
                    count = bagItem.count,
                    status = bagItem.status,
                    extdata = extdatadata
                }
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