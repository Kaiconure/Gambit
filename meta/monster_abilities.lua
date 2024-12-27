-- ============================================================================
-- All spells and abilities that have a dispel effect. Used to track
-- removal of buffs on mobs.
--

local meta = {
  [344] = {    -- Sticky Thread (1)
    statuses = {
      13        -- Slow
    }
  },
  [1581] = {    -- Sticky Thread (2)
    statuses = {
      13        -- Slow
    }
  },
  [439] = {    -- Petro Gaze (1)
    statuses = {
      7         -- Petrifiy
    }
  },
  [1174] = {    -- Petro Eyes (1)
    statuses = {
      7         -- Petrifiy
    }
  },
  [1184] = {    -- Petro Eyes (1)
    statuses = {
      7         -- Petrifiy
    }
  }
}

return meta