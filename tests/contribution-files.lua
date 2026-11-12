-- Validate migrated repository configurations from the migration file manifest.
local json=require('./lib/jsonlua')
local entries=require('./lib/contribution-entries')
local function read(path)local f=assert(io.open(path));local s=f:read('*a');f:close();return s end
local count=0
for _,path in ipairs(json.parse(read(assert(arg[1],'file manifest required')))) do
 if path:match('%.json$') then
  local document=json.parse(read(path))
  if document.contributions then
   local ok,result=pcall(entries.read,document.contributions,function()return true end)
   assert(ok,path..': '..tostring(result))
   for key in pairs(document.contributions) do assert(type(key)=='number',path..': legacy contribution object remains') end
   count=count+1
  end
 end
end
print('PASS: '..count..' migrated contribution documents have explicit slot/actions entries')
