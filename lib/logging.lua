VERBOSITY_NORMAL       = 0
VERBOSITY_VERBOSE      = 1
VERBOSITY_DEBUG        = 2
VERBOSITY_TRACE        = 3

--------------------------------------------------------------------------------------
-- Shift_JIS helper chacaters

CHAR_RIGHT_ARROW        = string.char(0x81, 0xA8) -- https://www.fileformat.info/info/charset/Shift_JIS/list.htm
CHAR_UP_ARROW           = string.char(0x81, 0xAA)
CHAR_BULLET             = string.char(0x81, 0x45)
CHAR_DEGREES            = string.char(0xB0)

--------------------------------------------------------------------------------------
-- Logging colors

Colors = {
    white = 1,
    green = 2,
    indigo = 3,
    magenta = 5,
    blue = 6,
    beige = 7,
    coral = 8,
    salmon = 8,
    lightgray = 16,
    cornsilk = 109,    
    darkgray = 65,
    gray = 67,
    redbrick = 68,
    gold = 69,
    slateblue = 70,
    cornflowerblue = 71,
    purple = 72,
    violet = 73,
    red = 76,
    pearl = 78,
    skyblue = 82,
    aquamarine = 83,
    lightcoral = 85,
    lightblue = 87,
    lavender = 89,
    powderblue = 92,
    lightyellow = 96,
    yellow = 104,
    pink = 105,
    khaki = 109,
    dodgerblue = 112,
    deepskyblue = 113,
}

Colors.default  = Colors.lavender
Colors.warning  = Colors.yellow
Colors.error    = Colors.red

Colors.verbose  = Colors.powderblue
Colors.debug    = Colors.gray
Colors.trace    = Colors.gray

--------------------------------------------------------------------------------------
-- Returns a color-formatted string for use with game logging
function colorize(color, message, returnColor)
    -- what is 0x1F for?

    color = color or Colors.default
    returnColor = returnColor or Colors.default

    return string.char(0x1E, tonumber(color)) 
        .. (message or '')
        .. string.char(0x1E, returnColor)
        --.. ((returnColor and string.char(0x1E, returnColor)) or '')
end

--------------------------------------------------------------------------------------
-- Text colorization helpers and semantics

function text_white(message, returnColor)
    return colorize(Colors.white, message, returnColor)
end

function text_green(message, returnColor)
    return colorize(Colors.green, message, returnColor)
end

function text_blue(message, returnColor)
    return colorize(Colors.blue, message, returnColor)
end

function text_warning(message, returnColor)
    return colorize(Colors.warning, message, returnColor)
end

function text_error(message, returnColor)
    return colorize(Colors.error, message, returnColor)
end

function text_yellow(message, returnColor)
    return colorize(Colors.yellow, message, returnColor)
end

function text_red(message, returnColor)
    return colorize(Colors.red, message, returnColor)
end

function text_redbrick(message, returnColor)
    return colorize(Colors.redbrick, message, returnColor)
end

function text_lightcoral(message, returnColor)
    return colorize(Colors.lightcoral, message, returnColor)
end

function text_gray(message, returnColor)
    return colorize(Colors.gray, message, returnColor)
end

function text_lightgray(message, returnColor)
    return colorize(Colors.lightgray, message, returnColor)
end

function text_magenta(message, returnColor)
    return colorize(Colors.magenta, message, returnColor)
end

function text_cornsilk(message, returnColor)
    return colorize(Colors.cornsilk, message, returnColor)
end

function text_gold(message, returnColor)
    return colorize(Colors.gold, message, returnColor)
end

function text_lightblue(message, returnColor)
    return colorize(Colors.lightblue, message, returnColor)
end

function text_trustset(trustSetName, returnColor)
    local colorFunc = (trustSetName == settings.trust.current and text_trustset_active or text_trustset_inactive)
    --return '[' .. colorFunc(trustSetName, returnColor) .. ']'
    return colorFunc(trustSetName, returnColor)
end

function text_gearset(gearSetName, returnColor)
    return colorize(returnColor,
        '[' .. text_magenta(gearSetName, returnColor) .. ']',
        returnColor)
end

--------------------------------------------------------------------------------------
-- Text logging

function hasVerbosity(verbosity)
    return verbosity <= VERBOSITY_NORMAL or
        verbosity <= (logging_settings and logging_settings.verbosity or 0)
end

function writeMessage(message, color, returnColor)
    windower.add_to_chat(1, 
        colorize(color or Colors.default, 
            colorize(Colors.gray, '[' .. globals.selfShortName .. '] ', color) .. (message ~= nil and message or ''), returnColor))
end

function writeWarning(message) 
    writeMessage(text_warning(message, Colors.warning), Colors.warning)
end

function writeError(message) 
    writeMessage(text_error(message))
end

function writeVerbose(message, color, returnColor)
    if hasVerbosity(VERBOSITY_VERBOSE) then
        color = color or Colors.verbose
        returnColor = returnColor or Colors.verbose
        writeMessage(
            -- string.format('%s%s',
            --     colorize(Colors.darkgray, '[verbose] ', color),
            --     message),
            message,
            color,
            returnColor
        )

        return true
    end
end

function writeDebug(message, color, returnColor)
    if hasVerbosity(VERBOSITY_DEBUG) then
        color = color or Colors.debug
        returnColor = returnColor or Colors.debug
        writeMessage(
            string.format('%s%s',
                colorize(Colors.gray, '[debug] ', color),
                message),
            color,
            returnColor
        )

        return true
    end
end

function writeTrace(message, color, returnColor)
    if hasVerbosity(VERBOSITY_TRACE) then
        color = color or Colors.trace
        returnColor = returnColor or Colors.trace
        writeMessage(
            string.format('%s%s',
                colorize(Colors.gray, '[trace] ', color),
                message),
            color,
            returnColor
        )

        return true
    end
end

function writeCommandInfo(command, ...)
    local descriptionLines = {...}

    writeMessage('  ' .. text_command(command))
    
    if isArray(descriptionLines) then
        for i = 1, #descriptionLines do
           writeMessage('    ' .. text_description(descriptionLines[i]))
        end
    end
end

--------------------------------------------------------------------------------------
-- Semantic formatting helpers

function pluralize(count, ifOne, ifOther, returnColor)
    local word = (count == 1 and ifOne or ifOther)
    --return text_number(count, returnColor) .. ' ' .. colorize(returnColor, word, returnColor)
    return text_number(count .. ' ' .. word, returnColor)
end

--------------------------------------------------------------------------------------
-- Semantic formatting references
text_player               = text_yellow
text_mount                = text_green
text_trust                = text_magenta
text_inactive             = text_gray
text_trustset_inactive    = text_inactive
text_trustset_active      = text_green
text_spell                = text_gold
text_ability              = text_blue
text_weapon_skill         = text_blue
text_item                 = text_green
text_number               = text_lightblue
text_target               = text_cornsilk
text_gearslot             = text_cornsilk
text_command              = text_green
text_description          = text_cornsilk
text_action               = text_blue
text_job                  = text_cornsilk
text_mob                  = text_lightcoral
text_target               = text_gold
text_buff                 = text_cornsilk

--------------------------------------------------------------------------------------
-- Current settings
logging_settings = {
    version = '1.0.1',
    verbosity = VERBOSITY_NORMAL
}