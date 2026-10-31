local Buffer={}
Buffer.__index=Buffer
function Buffer.new(limit,convert) return setmetatable({limit=limit,lines={},ids={},serial=0,convert=convert},Buffer) end
local function utf8Length(text,index)
    local byte=text:byte(index)
    if byte<128 then return 1 end
    local count=byte>=194 and byte<=223 and 2 or byte>=224 and byte<=239 and 3 or byte>=240 and byte<=244 and 4
    if not count or index+count-1>#text then return nil end
    for i=index+1,index+count-1 do local b=text:byte(i); if b<128 or b>191 then return nil end end
    local second=text:byte(index+1)
    if (byte==224 and second<160) or (byte==237 and second>159)
        or (byte==240 and second<144) or (byte==244 and second>143) then return nil end
    return count
end
function Buffer.isUtf8(text)
    local index=1
    while index<=#text do
        local count=utf8Length(text,index)
        if not count then return false end
        index=index+count
    end
    return true
end
function Buffer.plain(message,convert)
    local plain=tostring(message==nil and '' or message):gsub('[\30\31].',''):gsub('\r','')
    if not Buffer.isUtf8(plain) and convert then
        local ok,value=pcall(convert,plain)
        if ok and type(value)=='string' then plain=value end
    end
    return plain
end
function Buffer:add(message)
    local plain=Buffer.plain(message,self.convert)
    for line in (plain..'\n'):gmatch('(.-)\n') do
        self.serial=self.serial+1
        self.lines[#self.lines+1]=line
        self.ids[#self.ids+1]=self.serial
        if #self.lines>self.limit then table.remove(self.lines,1); table.remove(self.ids,1) end
    end
end
-- UTF-8 output: never split a code point. Legacy unconverted Shift-JIS input
-- retains safe double-byte clipping when a converter is unavailable.
local function colorToken(text,index)
    if text:byte(index)~=92 then return end
    local tail=text:sub(index)
    if tail:sub(1,3)=='\\cr' then return 3,false end
    local token,r,g,b=tail:match('^(\\cs%((%d+),(%d+),(%d+)%))')
    if token and tonumber(r)<=255 and tonumber(g)<=255 and tonumber(b)<=255 then return #token,true end
end
function Buffer.uncolored(text)
    if not text:find('\\',1,true) then return text end
    local parts,index={},1
    while index<=#text do
        local count=colorToken(text,index)
        if count then index=index+count
        else parts[#parts+1]=text:sub(index,index); index=index+1 end
    end
    return table.concat(parts)
end
function Buffer.clip(text,columns,advance)
    local index,used=1,0
    local colored=false
    local utf8=Buffer.isUtf8(text)
    while index<=#text do
        local token,active=colorToken(text,index)
        if token then
            colored=active; index=index+token
        else
        if used>=columns then break end
        local byte=text:byte(index)
        local wide=(byte>=0x81 and byte<=0x9F) or (byte>=0xE0 and byte<=0xFC)
        local count=utf8 and utf8Length(text,index) or (wide and 2 or 1)
        local width=advance and advance(text:sub(index,index+count-1)) or (utf8 and 1 or count)
        if used+width>columns then break end
        used=used+width; index=index+count
        end
    end
    return text:sub(1,index-1)..(colored and '\\cr' or '')
end
return Buffer
