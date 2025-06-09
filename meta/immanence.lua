local meta = {
    ['categories'] = {
        ['thunder'] = {
            'thunder',
            'thunder ii',
            'thunder iii',
            'thunder iv',
            'thunder v',
            'thunder vi'
        },
        ['blizzard'] = {
            'blizzard',
            'blizzard ii',
            'blizzard iii',
            'blizzard iv',
            'blizzard v',
            'blizzard vi'
        },
        ['fire'] = {
            'fire',
            'fire ii',
            'fire iii',
            'fire iv',
            'fire v',
            'fire vi'
        },
        ['aero'] = {
            'aero',
            'aero ii',
            'aero iii',
            'aero iv',
            'aero v',
            'aero vi'
        },
        ['water'] = {
            'water',
            'water ii',
            'water iii',
            'water iv',
            'water v',
            'water vi'
        },
        ['stone'] = {
            'stone',
            'stone ii',
            'stone iii',
            'stone iv',
            'stone v',
            'stone vi'
        }
    },
    ['spells'] = {
        ['thunder vi'] = 'thunder',
        ['thunder v'] = 'thunder',
        ['thunder iv'] = 'thunder',
        ['thunder iii'] = 'thunder',
        ['thunder ii'] = 'thunder',
        ['thunder'] = 'thunder',

        ['blizzard vi'] = 'blizzard',
        ['blizzard v'] = 'blizzard',
        ['blizzard iv'] = 'blizzard',
        ['blizzard iii'] = 'blizzard',
        ['blizzard ii'] = 'blizzard',
        ['blizzard'] = 'blizzard',

        ['fire vi'] = 'fire',
        ['fire v'] = 'fire',
        ['fire iv'] = 'fire',
        ['fire iii'] = 'fire',
        ['fire ii'] = 'fire',
        ['fire'] = 'fire',

        ['aero vi'] = 'aero',
        ['aero v'] = 'aero',
        ['aero iv'] = 'aero',
        ['aero iii'] = 'aero',
        ['aero ii'] = 'aero',
        ['aero'] = 'aero',

        ['water vi'] = 'water',
        ['water v'] = 'water',
        ['water iv'] = 'water',
        ['water iii'] = 'water',
        ['water ii'] = 'water',
        ['water'] = 'water',

        ['stone vi'] = 'stone',
        ['stone v'] = 'stone',
        ['stone iv'] = 'stone',
        ['stone iii'] = 'stone',
        ['stone ii'] = 'stone',
        ['stone'] = 'stone',
    }
}

-----------------------------------------------------------------------------------------
-- Determine the immanence category of the specified spell
meta.category_of = function(self, spell)
    spell = tostring(spell)
    if spell then
        return meta.spells[string.lower(spell)]
    end
end

return meta