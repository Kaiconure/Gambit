ux = ux or {}

local PANEL_WIDTH   = 800
local PANEL_HEIGHT  = 104

local TEXT_STYLE =
{
    --font = 'Consolas',
    font = 'Lucida Console',
    size = 21,
    color = {
        r = 255,
        g = 255,
        b = 255,
        a = 255
    },
    stroke = {
        r = 0,
        g = 0,
        b = 0,
        a = 255,
        w = 2
    }    
}

local function setup_image(image, path)
    image:path(path)
    image:repeat_xy(1, 1)
    image:draggable(false)
    image:fit(true)
end

local function setup_text(text, settings, overrides)
    text:bg_alpha(0)
    text:bg_visible(false)
    
    text:font(settings.font)
    text:size(settings.size)
    
    text:color(
        overrides and overrides.color and overrides.color.r or settings.color.r,
        overrides and overrides.color and overrides.color.g or settings.color.g,
        overrides and overrides.color and overrides.color.b or settings.color.b)
    text:alpha(settings.color.a)
    
    text:stroke_color(
        overrides and overrides.stroke and overrides.stroke.r or settings.stroke.r,
        overrides and overrides.stroke and overrides.stroke.g or settings.stroke.g,
        overrides and overrides.stroke and overrides.stroke.b or settings.stroke.b)
    text:stroke_transparency(settings.stroke.a)
    text:stroke_width(settings.stroke.w)
end

local PanelUI = {}
PanelUI.__index = PanelUI

function PanelUI.new(settings)
    local self = setmetatable({}, PanelUI)

    local windower_settings = windower.get_windower_settings()

    self.t_start = 0
    self.t_tick = 0

    self:configure(settings)

    self.background = images.new()
    self.background:transparency(192)
    self.background:size(PANEL_WIDTH, PANEL_HEIGHT)
    self.background:pos(
        (windower_settings.ui_x_res - PANEL_WIDTH) / 2.0,
        self.settings.top
    )
    setup_image(self.background, windower.addon_path .. 'content/ffvii-short-md.png')

    self.textbox = texts.new('')
    setup_text(self.textbox, TEXT_STYLE)

    self:hide()

    return self
end

function PanelUI:configure(settings)
    self.settings = json.parse(
        json.stringify(settings or { enabled = true, duration = 3, top = 100 })
    )
end

function PanelUI:enabled(f)
    if type(f) ~= 'boolean' then
        return self.settings.enabled
    end

    self.settings.enabled = f

    self:hide()
end

function PanelUI:tick()
    if self.t_start > 0 then
        self.t_tick = os.clock()

        local age = self.t_tick - self.t_start
        if age > self.settings.duration then
            self:hide()
        end
    end
end

function PanelUI:setText(text)
    if not text then
        self:hide()
        return
    end

    local windower_settings = windower.get_windower_settings()

    self.textbox:text(text)
    setup_text(self.textbox, TEXT_STYLE)

    local tb_size = ux.core.MeasureTextElement(self.textbox)
    self.textbox:pos(
        (windower_settings.ui_x_res - tb_size.w) / 2.0,         -- Horizontal center
        self.settings.top + ((PANEL_HEIGHT - tb_size.h) / 2)    -- Vertical center
    )

    self:show()
end

function PanelUI:hide()
    self.t_start = 0
    self.t_tick = 0

    self.textbox:hide()
    self.background:hide()
end

function PanelUI:show()
    self.t_start = os.clock()
    self.t_tick = self.t_start

    self.background:show()
    self.textbox:show()
end

ux.cloud_panel = PanelUI