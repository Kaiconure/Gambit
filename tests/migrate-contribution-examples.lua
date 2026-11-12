-- One-time, formatting-preserving migration. Pass a JSON array of file paths.
-- Only contribution objects are rewritten; unrelated JSON/Markdown is retained.
local json=require('./lib/jsonlua')
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local function skip(s,i)local _,last=s:find('^%s*',i);return (last or i-1)+1 end
local function quoted(s,i)
 i=i+1
 while i<=#s do
  local c=s:sub(i,i)
  if c=='\\' then i=i+2 elseif c=='"' then return i+1 else i=i+1 end
 end
 error('Unclosed string')
end
local function valueEnd(s,i)
 local c=s:sub(i,i)
 if c=='"' then return quoted(s,i) end
 if c=='{' or c=='[' then
  local depth=1;i=i+1
  while depth>0 do
   c=s:sub(i,i);assert(c~='','Unclosed value')
   if c=='"' then i=quoted(s,i)
   else
    if c=='{' or c=='[' then depth=depth+1 elseif c=='}' or c==']' then depth=depth-1 end
    i=i+1
   end
  end
  return i
 end
 local last=s:find('[,%]}%s]',i)
 return last or #s+1
end
local function fields(s,start)
 local result={};local i=skip(s,start+1)
 while s:sub(i,i)~='}' do
  assert(s:sub(i,i)=='"','Expected object key')
  local keyEnd=quoted(s,i)
  local key=s:sub(i,keyEnd-1)
  local indent=#(s:sub(1,i-1):match('\n( *)[^\n]*$') or '')
  i=skip(s,keyEnd);assert(s:sub(i,i)==':');i=skip(s,i+1)
  local last=valueEnd(s,i)
  result[#result+1]={key=key,value=s:sub(i,last-1),indent=indent,start=i}
  i=skip(s,last)
  if s:sub(i,i)==',' then i=skip(s,i+1) else assert(s:sub(i,i)=='}') end
 end
 return result,i+1
end
local function shift(value,amount)
 if amount>=0 then return value:gsub('\n', '\n'..string.rep(' ',amount)) end
 return value:gsub('\n'..string.rep(' ',-amount),'\n')
end
local count=0
for _,path in ipairs(json.parse(read(assert(arg[1])))) do
 local original=read(path)
 local s=original:gsub('\r\n','\n')
 local from=1
 while true do
  local first,last=s:find('"contributions"%s*:%s*{',from)
  if not first then break end
  local base=#(s:sub(1,first-1):match('\n( *)$') or '')
  local entries,finish=fields(s,last)
  for index=#entries,1,-1 do
   if entries[index].value=='null' then table.remove(entries,index) end
  end
  local out={'['}
  for index,entry in ipairs(entries) do
   out[#out+1]='\n'..string.rep(' ',base+2)..'{\n'..string.rep(' ',base+4)..'"slot": '..entry.key
   local properties
   if entry.value:sub(1,1)=='{' then properties=fields(s,entry.start)
   else properties={{key='"actions"',value=entry.value,indent=entry.indent}} end
   for _,property in ipairs(properties) do
    out[#out+1]=',\n'..string.rep(' ',base+4)..property.key..': '..shift(property.value,base+4-property.indent)
   end
   out[#out+1]='\n'..string.rep(' ',base+2)..'}'..(index<#entries and ',' or '')
  end
  out[#out+1]='\n'..string.rep(' ',base)..']'
  local replacement=table.concat(out)
  s=s:sub(1,last-1)..replacement..s:sub(finish)
  from=last+#replacement
 end
 if original:find('\r\n',1,true) then s=s:gsub('\n','\r\n') end
 if s~=original then
  if path:match('%.json$') then assert(json.parse(s)) end
  local f=assert(io.open(path,'wb'));f:write(s);f:close();count=count+1
 end
end
print('Migrated '..count..' files')
