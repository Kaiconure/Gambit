-- ============================================================================
-- All spells and abilities that have a dispel effect. Used to track
-- removal of buffs on mobs.
--

local meta = {
  spells = {
    143,  -- Erase
    16,   -- Blindna
    20,   -- Cursna
    15,   -- Paralyna
    14,   -- Poisona
    17,   -- Silena
    18,   -- Stona
    19    -- Viruna

    --95,   -- Esuna* TODO: Implement later. This is AOE.
    --94   -- Sacrifice* TODO: Implement later. This transfers from party member to self.
  },
  job_abilities = {
    194   -- Healing Waltz (DNC)
  }
}

return meta