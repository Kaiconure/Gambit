local exceptions = dofile('meta/offensive-magic-exceptions.lua')
local file = assert(io.open('lib/action-context.lua'))
local source = file:read('*a'); file:close()
local expression = assert(source:match('local suppress = (context.vars.__suppress_offensive_magic.-)\n%s*if not suppress then'))
local check = assert(loadstring('return ' .. expression))
local context = {vars={__suppress_offensive_magic=1}}
local spell = {targets={Enemy=true}}
setfenv(check, {context=context,spell=spell,offensiveMagicExceptions=exceptions})
for id, entry in pairs(exceptions) do
    assert(type(id)=='number' and type(entry)=='table' and type(entry.en)=='string')
    spell.id=id;spell.name='Localized name'
    assert(not check())
end
for _, id in ipairs({23,24,25,26,27,33,34,35,36,37,56,58,59,79,80,112,
    230,231,232,233,234,245,246,247,248,254,276,841,842,843,844,880,881,882,883}) do
    assert(exceptions[id] and exceptions[id].en)
end
for _, id in ipairs({799,144,220,99999}) do
    spell.id=id;spell.name='Geo-Frailty'
    assert(check()) -- Names never grant an exception, nor do unrelated spells.
end
context.vars.__suppress_offensive_magic=false
assert(not check())
context.vars.__suppress_offensive_magic=1
spell.targets={Self=true};assert(not check())
print('PASS: spell-ID exceptions, non-exempt spells, localization and existing target rules')
