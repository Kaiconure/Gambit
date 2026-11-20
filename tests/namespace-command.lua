local file=assert(io.open('lib/commands.lua'))
local source=file:read('*a'); file:close()
local handler=assert(source:match("(handlers%['namespace'%] = function.-)\nhandlers%['ns'%] = handlers%['namespace'%]"))
local selected='original'
local directories={existing=true}
local initialized={existing=true}
local warnings, errors, creates, reloads, saves={}, {}, 0, 0, 0
local receivedParent
local descriptionReports=0
local listed={'base','shortcut','sortie/a'}
local messages={}
local arrow=string.char(0x81, 0xA8)
local env=setmetatable({handlers={}, settingsPaths={
    getNamespace=function() return selected end,
    getLoadedNamespace=function() return 'battle/di' end,
    listNamespaces=function() return listed, {base=true}, {}, {shortcut='sortie/a'} end,
    validateNamespace=function(name) return name~='invalid', 'Invalid namespace' end,
    namespaceExists=function(name) return directories[name] or false end,
    isNamespaceInitialized=function(name) return directories[name] and initialized[name] or false end,
    setNamespace=function(name) selected=name; return true end,
    ensureNamespaceFolders=function(player,name,parent)
        assert(player=='Player')
        creates=creates+1; receivedParent=parent
        if name=='failure' then return false, 'Creation failed' end
        directories[name]=true; initialized[name]=true; return true
    end,
}, windower={ffxi={get_player=function() return {name='Player'} end}},
    Colors={warning=1,default=2}, CHAR_RIGHT_ARROW=arrow,
    text_namespace=function(name, returnColor)
        assert(returnColor==1 or returnColor==2, 'Namespace text must restore its enclosing color')
        return name
    end,
    text_gray=function(text, returnColor) assert(returnColor==2); return '[gray]'..text end,
    text_green=function(text) return text end,
    text_yellow=function(text, returnColor) assert(returnColor==2); return '[yellow]'..text end,
    writeWarning=function(message) warnings[#warnings+1]=message end,
    writeMessage=function(message) messages[#messages+1]=message end,
    writeError=function(message) errors[#errors+1]=message end,
    reloadSettings=function() reloads=reloads+1 end,
    saveDefaultNamespace=function() saves=saves+1 end,
    reportNamespaceDescriptions=function() descriptionReports=descriptionReports+1 end,
}, {__index=_G})
local chunk=assert(loadstring(handler)); setfenv(chunk,env); chunk()
local run=env.handlers.namespace
run({'-list'})
assert(messages[1]=='Available namespaces:' and messages[2]=='  [gray]base (abstract)'
    and messages[3]=='  [yellow]shortcut '..arrow..' sortie/a' and messages[4]=='  sortie/a')
run({})
assert(messages[#messages]=='Current namespace: battle/di')
listed={}
run({'-list'})
assert(messages[#messages]=='No namespaces with a .nsconfig file found.')
assert(selected=='original' and creates==0 and reloads==0 and saves==0)
run({'-v'})
assert(descriptionReports==1 and selected=='original' and creates==0 and reloads==0 and saves==0)
run({'-set','typo'})
assert(selected=='original' and creates==0 and reloads==0 and saves==0 and #warnings==1)
directories.unmarked=true
run({'-set','unmarked'})
assert(selected=='original' and creates==0 and reloads==0 and #warnings==2)
warnings={}
run({'-set','typo'})
run({'-set','new','-force','-parent','existing'})
assert(selected=='new' and directories.new and receivedParent=='existing' and reloads==1 and saves==1)
run({'-set','new','-parent','existing','-force'})
assert(#warnings==2 and reloads==2 and saves==2 and receivedParent=='existing')
run({'-set','existing'})
assert(selected=='existing' and #warnings==2 and reloads==3)
run({'-set','failure','-force'})
assert(selected=='existing' and #errors==1 and reloads==3 and not directories.failure)
run({'-set','invalid','-force'})
assert(selected=='existing' and #errors==2)
run({'-set','new','-force','-force'})
assert(#errors==3 and reloads==3)
run({'-clear'})
assert(selected==nil and reloads==4 and saves==4)
run({'-set','global'})
assert(selected==nil and reloads==5 and saves==5)
run({'-set','gambit'})
assert(selected==nil and reloads==6 and saves==6)
run({'-set','global','-force'})
assert(#errors==4 and reloads==6)
run({'-set','unmarked','-force'})
assert(initialized.unmarked and selected=='unmarked' and reloads==7 and saves==7)
print('PASS: namespace creation requires force, existing force warns, option ordering, failures and clear')
