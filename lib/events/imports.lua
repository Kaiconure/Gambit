-- Explicit composition; import names resolve through event directories only.
return function(candidates,read,entryName)
    local directories,seenDirectories={},{}
    for _,path in ipairs(candidates) do
        local directory=path:match('^(.*)/[^/]+$')
        if directory and not seenDirectories[directory] then
            seenDirectories[directory]=true
            directories[#directories+1]=directory
        end
    end
    local documents,seen,visiting,chain={},{},{},{}
    local function reference(value,path)
        assert(type(value)=='string' and value:match('%S'),path..': imports require nonempty strings')
        value=value:gsub('\\','/')
        assert(not value:find(':',1,true) and value:sub(1,1)~='/',path..': invalid event import '..value)
        for part in (value..'/'):gmatch('(.-)/') do
            assert(part~='' and part~='.' and part~='..',path..': invalid event import '..value)
        end
        if not value:match('%.json$') then value=value..'.json' end
        return value
    end
    local visit
    visit=function(path,document)
        local identity=path:lower()
        assert(not visiting[identity],'Event import cycle: '..table.concat(chain,' -> ')..' -> '..path)
        if seen[identity] then return end
        assert(#chain<64,'Event import depth exceeded: '..table.concat(chain,' -> '))
        assert(type(document)=='table',path..': expected an object')
        visiting[identity]=true; chain[#chain+1]=path
        local imports=document.imports
        if imports==nil then imports={} end
        assert(type(imports)=='table',path..': imports must be an array')
        for key in pairs(imports) do
            assert(type(key)=='number' and key>=1 and key%1==0 and key<=#imports,path..': imports must be a dense array')
        end
        for _,name in ipairs(imports) do
            local relative=reference(name,path)
            local found
            for _,directory in ipairs(directories) do
                local candidate=directory..'/'..relative
                local value=read(candidate)
                if value~=nil then found=true; visit(candidate,value); break end
            end
            assert(found,'Missing event import '..relative..': '..table.concat(chain,' -> '))
        end
        chain[#chain]=nil; visiting[identity]=nil; seen[identity]=true
        documents[#documents+1]={path=path,document=document}
    end
    if entryName then
        local relative=reference(entryName,'Event entry point')
        for _,directory in ipairs(directories) do
            local path=directory..'/'..relative
            local document=read(path)
            if document~=nil then visit(path,document); return documents,path end
        end
        error('Event entry point not found: '..relative)
    end
    for _,path in ipairs(candidates) do
        local document=read(path)
        if document~=nil then visit(path,document); return documents,path end
    end
    return documents
end
