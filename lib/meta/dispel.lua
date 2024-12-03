-- ============================================================================
-- All spells and abilities that have a dispel effect. Used to track
-- removal of buffs on mobs.
--

local meta = {
  spells = {
    260,  -- Dispel (Spell)
    360,  -- Dispelga (Spell)
    462,  -- Magic Finale (BRD)
    579,  -- Voracious Trunk (BLU)
    592,  -- Blank Gaze (BLU)
    605,  -- Geist Wall
    672   -- Osmosis
  },
  job_abilities = {
    132,  -- Dark Shot (COR)
    531   -- Lunar Roar (SMN/Fenrir)
  }
}

return meta