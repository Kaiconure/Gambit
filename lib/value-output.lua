local output = {}

local function formatValue(value)
    local kind = type(value)
    if kind == 'boolean' then
        return value and text_green('true') or text_red('false')
    elseif kind == 'string' then
        return text_yellow(string.format('"%s"', value))
    elseif kind == 'number' then
        return text_number(tostring(value))
    end
    return text_gray(tostring(value))
end

-- Match varget's shallow display; nested/cyclic tables are not traversed.
function output.write(name, value, label)
    writeMessage(text_gray(string.format('%s %s value:', label or 'Variable',
        text_yellow(type(value), Colors.gray))))
    if type(value) ~= 'table' then
        writeMessage(string.format('  %s: %s', text_blue(name), formatValue(value)))
    elseif #value > 0 then
        writeMessage(string.format('  %s %s:', text_blue(name), text_yellow('array')))
        for i, item in ipairs(value) do
            writeMessage(string.format('    %s: %s', text_number(i), formatValue(item)))
        end
    else
        writeMessage(string.format('  %s %s:', text_blue(name), text_yellow('table')))
        for key, item in pairs(value) do
            writeMessage(string.format('    %s: %s', text_yellow(tostring(key)), formatValue(item)))
        end
    end
end

return output
