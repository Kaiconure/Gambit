local M={}
-- Both Sleep status IDs, Petrification, Stun, Bind, and Terror.
local immobilizing={[2]=true,[19]=true,[7]=true,[10]=true,[11]=true,[28]=true}
function M.active(player)
    for _,id in ipairs(player and player.buffs or {}) do
        if immobilizing[id] then return true end
    end
    return false
end
function M.current(ffxi)
    return M.active(ffxi.get_player and ffxi.get_player())
end
return M
