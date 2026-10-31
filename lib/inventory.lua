local inventory = {}
local function equipment_view(items,confirmed,session)
    local manager=session or inventory.equipment_manager
    if manager and items then return manager:snapshot(items,confirmed) end
    return items
end

-------------------------------------------------------------------------------
-- Bags that store equippable items
local INVENTORY_BAGS_BY_ID = 
{
    [0] = { field = "inventory", usable = true, equippable = true, linkshell = true },
    [1] = { field = "safe" },
    [2] = { field = "storage" },
    [3] = { field = "locker" },
    [4] = { field = "temporary", usable = true },
    [5] = { field = "satchel", linkshell = true },
    [6] = { field = "sack", linkshell = true },
    [7] = { field = "case", linkshell = true },
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
    ["case"] = 7,
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
    ['back'] = 15,

    -- Alternate ear slot names
    ['left_ear'] = 11,
    ['right_ear'] = 12,

    -- Alternate ring slot names
    ['left_ring'] = 13,
    ['right_ring'] = 14
}

--
-- Find the id of the gear slot with the specified name
--
inventory.get_slot_id_by_name = function(slot)
    return GEAR_SLOT_IDS_BY_NAME[string.lower(slot)]
end

--
-- Find the name of the gear slot with the specified id
--
inventory.get_slot_name_by_id = function(id)
    return GEAR_SLOT_NAMES_BY_ID[id]
end

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

inventory.find_equipment_in_slot = function(slot, items, confirmed, session)
    if slot == nil then return end

    local slotId = GEAR_SLOT_IDS_BY_NAME[slot]
    if slotId == nil then return end
    local slotField = GEAR_SLOT_FIELDS_BY_ID[slotId]
    if slotField == nil then return end

    items = equipment_view(items or windower.ffxi.get_items(),confirmed,session)
    if not items or not items.equipment then return end

    -- 0 in the slot item id (local id) means nothing is equipped
    local localId = items.equipment[slotField]
    if type(localId)~='number' or localId <= 0 then return end

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
            local_id = localId,
            confirmed = confirmed
        },
        items,nil,session)
end

local function sanitize_augments(extdata)
    if
        extdata and
        type(extdata) == 'table' and
        type(extdata.augments) == 'table' and
        #extdata.augments > 0
    then
        while true do
            local found = false
            for i, augment in ipairs(extdata.augments) do
                if augment == 'none' or augment == nil then
                    found = true
                    table.remove(extdata.augments, i)
                    break
                end
            end

            if not found then
                return
            end
        end
    end
end

local function is_item_excluded(exclusion_list, bagId, localId)
    if type(exclusion_list) ~= 'table' or #exclusion_list < 1 then
        return
    end

    for i, entry in ipairs(exclusion_list) do
        if entry.bagId == bagId and entry.localId == localId then
            --writeMessage('Excluding: %s (%d / %d)':format(entry.name, entry.bagId, entry.localId))
            return true
        end
    end
end

inventory.equip_many = function(pieces, all_items, simulate, changes, session)
    -- Set-level metadata belongs to callers, not slot resolution.
    if pieces.meta~=nil then
        local equipment={}
        for slot,piece in pairs(pieces) do
            if slot~='meta' then equipment[slot]=piece end
        end
        pieces=equipment
    end
    all_items = equipment_view(all_items or windower.ffxi.get_items(),false,session)
    
    if type(changes) == 'table' then
        changes.removed = {}
        changes.equipped = {}
    else
        changes = nil
    end

    local exclusion_list = { }
    local bags_to_search = INVENTORY_BAGS_BY_ID

    -- Equipment structure:
    --  - string: equipment | item | gear
    --  - string: slot
    --  - (Note: Will add augment filters at some point)

    local flags = { equippable = true, equipped = false }
    local swaps = { }

    -- Resolve in slot order as well as sending in slot order. Candidate copies
    -- reserved by one slot cannot be reused by a later slot in this request.
    local ordered={}
    for slot,piece in pairs(pieces) do
        local id=type(slot)=='string' and inventory.get_slot_id_by_name(slot)
        if id then ordered[id]={slot=slot,piece=piece} end
    end
    for _,info in ipairs(GEAR_SLOT_INFO) do
        local entry=ordered[info.id]
        if entry then
            local slot,piece=entry.slot,entry.piece
            local nested=type(piece)=='table' and (piece.equipment or piece.item or piece.gear or piece.name)
            local choices=type(piece)=='table' and #piece>0 and piece
                or type(nested)=='table' and nested or {piece}
            local equipped=inventory.find_equipment_in_slot(slot,all_items,false,session)
            local selected
            for _,choice in ipairs(choices) do
                if type(choice)=='string' then choice={name=choice} end
                assert(type(choice)=='table','Equipment candidates must be item names or tables')
                local name=choice.equipment or choice.item or choice.gear or choice.name
                local augments=choice.augments or choice.aug or {}
                if type(name)=='string' then
                    local resource=findItem(name)
                    -- Equipped/queued copies are eligible, and win over other
                    -- physical copies of this candidate. Unspecified augments
                    -- do not require an unnecessary change to another copy.
                    if equipped and resource and equipped.id==resource.id
                        and not is_item_excluded(exclusion_list,equipped.bagId,equipped.localId)
                        and inventory.has_all_augments(equipped,augments) then
                        selected=equipped
                    elseif resource then
                        local excluded={}
                        for _,item in ipairs(exclusion_list) do excluded[#excluded+1]=item end
                        while true do
                            local candidate=inventory.find_item({id=resource.id,name=name,augments=augments,slot=slot},flags,all_items,excluded,session)
                            if not candidate then break end
                            excluded[#excluded+1]=candidate
                            if candidate.raw_slots[info.id] then selected=candidate; break end
                        end
                    end
                    if selected then break end
                end
            end
            if selected then
                exclusion_list[#exclusion_list+1]=selected
                if selected~=equipped then
                    swaps[#swaps+1]={slot_id=info.id,slot=slot,item=selected,augments=selected.matched_augments}
                end
            end
        end
    end

    local rank={}
    for index,info in ipairs(GEAR_SLOT_INFO) do rank[info.id]=index end
    table.sort(swaps,function(a,b) return rank[a.slot_id]<rank[b.slot_id] end)
    local operations={}
    -- Now we will go through all of the processed swaps, and equip the gear
    if not simulate then
        -- if inventory.printDebug then
        --     inventory.printDebug('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>')
        -- end

        for i, swap in ipairs(swaps) do

            -- If we're tracking changes, store those changes now
            if changes then
                -- If an item is already in this slot, fetch it and store it in the removed list
                local removed = inventory.find_equipment_in_slot(swap.slot, all_items,false,session)
                if removed then
                    changes.removed[swap.slot] = {
                        name = removed.name,
                        augments = removed.augments,
                        id = removed.id,
                        localId = removed.localId,
                        bagId = removed.bagId
                    }
                else
                    changes.removed[swap.slot] = {empty=true}
                end

                -- Store the item we are swapping in
                changes.equipped[swap.slot] = {
                    name = swap.item.name,
                    augments = swap.augments
                }
            end

            -- If a debugging callback was provided, log the specific changes we're making
            -- if inventory.printDebug then
            --     if changes and changes.removed[swap.slot] then
            --         inventory.printDebug('Equipping %s: [%s]>>[%s]':format(
            --             swap.slot,
            --             changes.removed[swap.slot].name,
            --             swap.item.name
            --         ))
            --     else                    
            --         inventory.printDebug('Equipping %s: [%s]':format(
            --             swap.slot,
            --             swap.item.name
            --         ))
            --     end
            -- end

            operations[#operations+1]={slot=swap.slot_id,item={id=swap.item.id,
                localId=swap.item.localId,bagId=swap.item.bagId},
                after=swap.slot_id==1 and 0 or swap.slot_id==3 and 2 or nil}
        end
        local manager=session or inventory.equipment_manager
        if manager then
            manager:submit(operations)
        else
            for _,op in ipairs(operations) do windower.ffxi.set_equip(op.item.localId,op.slot,op.item.bagId) end
        end
    end

    return #swaps
end

-- Restoration must not depend on the asynchronous equipped-status cache.
-- A quick failed action may reach post before its pre equipment update arrives.
inventory.snapshot_equipment = function(session)
    local items=equipment_view(windower.ffxi.get_items(),false,session)
    assert(items and items.equipment,'Equipment state is unavailable for snapshot')
    local saved={}
    for _,info in ipairs(GEAR_SLOT_INFO) do
        local index=items.equipment[info.field]
        if index==0 then saved[info.slot]={empty=true}
        elseif type(index)=='number' and index>0 then
            local bag=items.equipment[info.field..'_bag']
            local item=inventory.get_item_from_bag(items,bag,index)
            assert(item,'Equipment item metadata is unavailable for snapshot: '..info.slot)
            saved[info.slot]={id=item.id,name=item.name,localId=index,bagId=bag}
        end
        -- Unknown slots are not assumed empty and must never be unequipped on pop.
    end
    return saved
end

inventory.restore_equipment = function(removed,session)
    local items=windower.ffxi.get_items()
    if not items then return 0 end
    local count=0
    local operations={}
    local legacy={}
    for slot,saved in pairs(removed or {}) do
        local slotId=inventory.get_slot_id_by_name(slot)
        if slotId~=nil then
            if saved.empty then
                operations[#operations+1]={slot=slotId,item={localId=0,bagId=0,id=0}}
                count=count+1
            elseif type(saved.localId)=='number' and type(saved.bagId)=='number' then
                local item=inventory.get_item_from_bag(items,saved.bagId,saved.localId)
                -- Never equip an unrelated item if a bag slot has been reused.
                if item and item.id==saved.id then
                    operations[#operations+1]={slot=slotId,item={localId=saved.localId,bagId=saved.bagId,id=saved.id},
                        after=slotId==1 and 0 or slotId==3 and 2 or nil}
                    count=count+1
                end
            else legacy[slot]=saved end
        end
    end
    local rank={}
    for index,info in ipairs(GEAR_SLOT_INFO) do rank[info.id]=index end
    table.sort(operations,function(a,b) return rank[a.slot]<rank[b.slot] end)
    local manager=session or inventory.equipment_manager
    if manager then manager:submit(operations)
    else
        for _,op in ipairs(operations) do windower.ffxi.set_equip(op.item.localId,op.slot,op.item.bagId) end
    end
    if next(legacy) then count=count+inventory.equip_many(legacy,nil,false,nil,session) end
    return count
end

inventory.find_equipped_linkshells = function(player, items)
    local result = {}

    player = player or windower.ffxi.get_player()
    if player then
        items = items or windower.ffxi.get_items()

        if items then
            local primary_linkshell = nil
            local secondary_linkshell = nil

            local primary_linkshell_name = player.linkshell

            for bagId, bagInfo in pairs(INVENTORY_BAGS_BY_ID) do
                -- Only search bags that allow linkshell equipping
                if bagInfo and bagInfo.linkshell then
                    local bag = items[bagInfo.field]

                    -- Only search bags that are enabled
                    if bag.enabled then
                        for localId, bagItem in pairs(bag) do

                            -- Only look at equipped linkshells
                            if type(bagItem) == 'table' and bagItem.status == 19 then
                                local ext = extdata.decode(bagItem)
                                if ext then
                                    local info = {
                                        bagId = bagId,
                                        localId = localId,
                                        linkshellId = ext.linkshell_id,
                                        name = ext.name,
                                        type = ext.status
                                    }

                                    table.insert(result, info)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return result
end

inventory.find_item = function(item, flags, items, exclusion_list, session)
    flags = flags or default_find_item_flags

    local only_usable = flags.usable
    local only_equippable = flags.equippable
    local only_inventory = flags.inventory

    local augments = (type(item) == 'table' and (item.augments or item.aug)) or nil

    -- If the flags don't specify a specific bag local id, we'll just look up the item directly from metadata
    if not flags.local_id then
        item = findItem(item)
        if item == nil then 
            return 
        end
    end

    -- Search all bags by default
    local bags_to_search = INVENTORY_BAGS_BY_ID

    -- If the flags specify a bag id that is valid, we'll search only that bag
    if flags.bag_id and INVENTORY_BAGS_BY_ID[flags.bag_id] then
        bags_to_search =
        {
            [flags.bag_id] = INVENTORY_BAGS_BY_ID[flags.bag_id]
        }
    end

    local empty = { }

    -- If we're only looking at the main inventory, limit our bag search to that
    if only_inventory then
        local inventory_id = INVENTORY_ID_BY_NAME['inventory']
        bags_to_search = {
            [inventory_id] = INVENTORY_BAGS_BY_ID[inventory_id]
        }
    end

    items = items or windower.ffxi.get_items()
    if not flags.usable then items=equipment_view(items,flags.confirmed,session) end

    for bagId, bagInfo in pairs(bags_to_search) do
        local bag_is_usable = bagInfo.usable
        local bag_is_equippable = bagInfo.equippable

        if 
            (bag_is_usable or not only_usable) and
            (bag_is_equippable or not only_equippable)
        then
            local bag = items[bagInfo.field]
            local bagItems = nil

            if flags.local_id then
                -- If a specific local id was specified, use that directly. We'll also
                -- update the underlying item to match this one.
                local bagItem = bag[flags.local_id]
                if bagItem then
                    item = findItem(bagItem.id)
                    bagItems = { bagItem }
                else
                    bagItems = empty
                end
            else
                bagItems = tableAll(bag, function (_i)
                    return type(_i) == 'table' and _i.id == item.id 
                end)
            end

            -- Bag item structure
            -- count: int,
            -- status: int,
            -- id: int, [item id]
            -- slot: int, [local id]
            -- bazaar: int,
            -- extdata: string,

            --Item statuses: 
            --  0: None
            --  5: Equipped
            --  19: Linkshell Equipped
            --  25: In Bazaar
            
            for _i, bagItem in ipairs(bagItems) do
                if 
                    bagItem and
                    item and
                    not is_item_excluded(exclusion_list, bagId, bagItem.slot)
                then
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

                        -- Strip out non-augments from the list so that we only have legitimate augments remaining
                        sanitize_augments(ext)
                    end
                    
                    local isUsableItem = 
                        -- Note: Temporarily skipping the usable item check; let's assume people know
                        -- what they're asking for at that level.
                        --(item.category == 'Usable' or (ext and (ext.usable or ext.type == 'Enchanted Equipment'))) and

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
                    if (session or inventory.equipment_manager) and not flags.usable and bagInfo.equippable then
                        isEquipped=false
                        for _,field in pairs(GEAR_SLOT_FIELDS_BY_ID) do
                                if items.equipment and items.equipment[field]==bagItem.slot and items.equipment[field..'_bag']==bagId then
                                isEquipped=true; break
                            end
                        end
                    end

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
                                        if not slot then
                                            slot = slotName
                                        end
                                    end
                                end
                            end
                        end
                    end

                    --print('item: %s, augments: %s':format(item.name, augments and tostring(#augments) or 'none'))

                    if 
                        (isUsableItem or not flags.usable) and          -- Usable flag
                        (isEquippableItem or not flags.equippable) and  -- Equippable flag
                        (
                            flags.equipped == nil or                    -- Equipped flag
                            (flags.equipped and isEquipped) or
                            (not flags.equipped and not isEquipped)
                        ) and 
                        inventory.has_all_augments(ext, augments)       -- Augments match
                    then
                        if slots then
                            if slots[1] == 'main' or slots[2] == 'main' then
                                slot = 'main'
                            end
                        end
                        return {
                            bagId = bagId,
                            bagName = bagInfo.field,
                            localId = bagItem.slot,
                            id = item.id,
                            item = item,
                            name = item.name,
                            count = bagItem.count,
                            status = bagItem.status,
                            extdata = ext,
                            item_type = item.type,
                            ext_type = ext and ext.type,
                            is_equipped = isEquipped,
                            is_bazaar = bagItem.status == 25,
                            augments = ext.augments or {},  -- The augments this item has
                            matched_augments = augments,    -- The augments we searched for and were matched on
                            charges_remaining = charges,
                            seconds_until_reuse = secondsUntilReuse,
                            seconds_until_activation = secondsUntilActivation,
                            can_use = isUsableItem,
                            slot = slot or (slots and slots[1]), -- Save the current slot, or first valid slot, for easy access (equipment only)
                            slots = slots, -- Save all slots (equipment only)
                            raw_slots = item.slots or {}
                        }
                    end
                end
            end
        end
    end
end

--
-- Determine if appropriate ranged attack gear is equipped. Note that this will NOT register 
-- for consumable thrown items (i.e. it will not let you throw your Rare/Ex sachet).
--
inventory.get_ranged_equipment = function (session)
    local items = equipment_view(windower.ffxi.get_items(),false,session)
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

--
-- Determine if the specified item contains ALL of the specified required augments.
--
inventory.has_all_augments = function(item_or_extdata, required_augments)

    local extdata = item_or_extdata
    if type(item_or_extdata) == 'table' and type(item_or_extdata.extdata) == 'table' then
        extdata = item_or_extdata.extdata
    end

    local matches = 0
    local num_required = (type(required_augments) == 'table' and #required_augments) or 0

    if 
        num_required > 0 and
        type(extdata) == 'table' and
        type(extdata.augments) == 'table' and
        #extdata.augments > 0 
    then
        for i, required_augment in ipairs(required_augments) do
            for j, contained_augment in ipairs(extdata.augments) do
                if required_augment == contained_augment then
                    found = true
                    matches = matches + 1
                    break
                end
            end
        end
    end

    return matches >= num_required
end

-- Same API, explicitly bound to a context's collector; never a global mode flag.
function inventory.bind_equipment(session)
    return setmetatable({
        equip_many=function(pieces,items,simulate,changes) return inventory.equip_many(pieces,items,simulate,changes,session) end,
        restore_equipment=function(removed) return inventory.restore_equipment(removed,session) end,
        snapshot_equipment=function() return inventory.snapshot_equipment(session) end,
        find_equipment_in_slot=function(slot,items,confirmed) return inventory.find_equipment_in_slot(slot,items,confirmed,session) end,
        find_item=function(item,flags,items,excluded) return inventory.find_item(item,flags,items,excluded,session) end,
        get_ranged_equipment=function() return inventory.get_ranged_equipment(session) end,
    },{__index=inventory})
end
return inventory
