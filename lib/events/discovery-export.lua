-- Streaming JSON avoids building a second, capture-sized object/string in memory.
local Export={}
function Export.encode(value,write)
    local active={}
    local function stringValue(value)
        local escaped=value:gsub('[%z\1-\31\\"]',function(char)
            if char=='"' then return '\\"' end
            if char=='\\' then return '\\\\' end
            return string.format('\\u%04x',char:byte())
        end)
        write('"'); write(escaped); write('"')
    end
    local encode
    encode=function(item)
        local kind=type(item)
        if kind=='string' then stringValue(item)
        elseif kind=='number' then
            assert(item==item and item~=math.huge and item~=-math.huge,'Non-finite discovery number')
            write(tostring(item))
        elseif kind=='boolean' then write(item and 'true' or 'false')
        elseif kind=='nil' then write('null')
        elseif kind=='table' then
            assert(not active[item],'Circular discovery data')
            active[item]=true
            local count,array=0,true
            for key in pairs(item) do
                count=count+1
                if type(key)~='number' or key<1 or key%1~=0 then array=false end
            end
            array=array and count>0 and count==#item
            write(array and '[' or '{')
            if array then
                for index,child in ipairs(item) do
                    if index>1 then write(',') end
                    encode(child)
                end
            else
                local first=true
                for key,child in pairs(item) do
                    if not first then write(',') end
                    first=false;stringValue(tostring(key));write(':');encode(child)
                end
            end
            write(array and ']' or '}')
            active[item]=nil
        else error('Unsupported discovery value: '..kind) end
    end
    encode(value)
end
function Export.write(path,result)
    local partial=path..'.partial'
    local file=assert(io.open(partial,'wb'))
    local ok,err=pcall(function()
        local chunks,size={},0
        local function flush()
            if size==0 then return end
            assert(file:write(table.concat(chunks)))
            chunks={};size=0
        end
        Export.encode(result,function(chunk)
            chunks[#chunks+1]=chunk;size=size+#chunk
            if size>=4096 then flush() end
        end)
        flush()
    end)
    local closed,closeError=file:close()
    if not ok then error(err) end
    assert(closed,closeError)
    assert(os.rename(partial,path))
end
return Export
