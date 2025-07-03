local party_info = {
    p_by_id = {},
    a1_by_id = {},
    a2_by_id = {},
    player = nil,
    refresh_interval = 3,
    last_refreshed = 0
}

local _p_symbols    = {'p0', 'p1', 'p2', 'p3', 'p4', 'p5'}
local _a1_symbols   = {'a10', 'a11', 'a12', 'a13', 'a14', 'a15' }
local _a2_symbols   = {'a20', 'a21', 'a22', 'a23', 'a24', 'a25' }

party_info.refresh = function(self, player, party, force)
    if 
        force or 
        ((os.clock() - self.last_refreshed) >= self.refresh_interval) 
    then
        player = player or windower.ffxi.get_player()
        party = party or windower.ffxi.get_party()

        self.player = player

        local p_by_id = {}
        local a1_by_id = {}
        local a2_by_id = {}

        for i = 0, 5 do
            local p   = party['p' .. i]
            local a1  = party['a1' .. i]
            local a2  = party['a2' .. i]

            if p and p.mob and p.mob.id then p_by_id[p.mob.id] = p end
            if a1 and a1.mob and a1.mob.id then a1_by_id[a1.mob.id] = a1 end
            if a2 and a2.mob and a2.mob.id then a2_by_id[a2.mob.id] = a2 end
        end

        self.p_by_id = p_by_id
        self.a1_by_id = a1_by_id
        self.a2_by_id = a2_by_id

        self.last_refreshed = os.clock()
    end
end

party_info.isParty = function(self, id)
    return id and (self.p_by_id[id] or (self.player and self.player.id == id))
end

party_info.isAlliance1 = function(self, id)
    return id and self.a1_by_id[id]
end

party_info.isAlliance2 = function(self, id)
    return id and self.a2_by_id[id]
end

party_info.isMember = function(self, id)
    return self:isParty(id) or self:isAlliance1(id) or self:isAlliance2(id)
end

party_info.canShareClaim = function(self, id)
    return self:isMember(id) or hasBuff(player, BUFF_ELVORSEAL) or hasBuff(player, BUFF_BATTLEFIELD)
end

return party_info