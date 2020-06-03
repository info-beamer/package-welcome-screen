-- Copyright (c) 2014-2020 Florian Wesch <fw@dividuum.de>
-- All rights reserved. No warranty, explicit or implicit, provided.

local has_branding, branding, brand_video

util.no_globals()
node.alias "root"

if CONTENTS['branding.jpg'] then
    has_branding, branding = pcall(resource.load_image, 'branding.jpg')
    brand_video = false
elseif CONTENTS['branding.mp4'] then
    has_branding, branding = pcall(resource.load_video, {
        file = 'branding.mp4',
        looped = true,
        audio = true,
        raw = true,
    })
    brand_video = true
end

local logo = resource.load_image{
    file = "iblogo.png",
    fastload = true,
}

local branding_settings = {
    ["register-url"] = "https://info-beamer.com/register",
    ["acknowledge-info-beamer"] = true,
    ["branding-action-centered"] = false,
    ["branding-state-centered"] = false,
    ["branding-wifi-template"] = 'Configuration WiFi %s active',
}
util.json_watch("branding.json", function(settings)
    for k, v in pairs(settings) do
        branding_settings[k] = v
    end
end)

local font = resource.load_font "font.ttf"
local white = resource.create_colored_texture(1, 1, 1, 1)
local black = resource.create_colored_texture(0, 0, 0, 1)
local dot = white

local serial = sys.get_env "SERIAL"
local channel = sys.get_env "CHANNEL"
local status = "Loading"
local connect_info = "Loading"
local connect_pin = ""
local wifi_name = ""
local network_info = ""
local updating = false
local update_progress = 0
local target_update_progress = 0

local state_shader = resource.create_shader[[
    uniform sampler2D Texture;
    varying vec2 TexCoord;
    uniform vec4 Color;

    void main() {
        vec4 tex = texture2D(Texture, TexCoord);
        float alpha = tex.a * (1.0 - tex.r);
        gl_FragColor = mix(
            vec4(0.5, 0.5, 0.5, 0.5 * alpha),
            vec4(0.3, 0.9, 0.3, 0.5 * alpha),
            Color.a
        );
    }
]]

-- dual display support
local function setup_displays()
  local displays = sys.displays
  WIDTH = displays[1].x2 - displays[1].x1
  HEIGHT = displays[1].y2 - displays[1].y1
  return {
      primary = function()
          gl.ortho()
          gl.translate(displays[1].x1, displays[1].y1)
      end,
      secondary = function()
          gl.ortho()
          gl.translate(displays[2].x1, displays[2].y1)
      end,
      overlap = (
          #displays == 2 and
          displays[1].x1+1 < displays[2].x2-1 and
          displays[1].x2-1 > displays[2].x1+1 and
          displays[1].y1+1 < displays[2].y2-1 and
          displays[1].y2-1 > displays[2].y1+1
      ),
      has_secondary = #displays == 2,
  }
end

gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)
local displays = setup_displays()

local function States(names)
    local success = {}
    local icons = {}
    local active = {}

    for idx = 1, #names do
        icons[idx] = resource.load_image("state-" .. names[idx] .. ".png")
        success[names[idx]] = false
        active[idx] = 0
    end

    local function draw(x, y, size, alpha)
        size = size or 32
        state_shader:use()
        for idx = #names, 1, -1 do
            local name = names[idx]
            if success[name] then
                active[idx] = math.min(1, active[idx] + 0.01)
            else
                active[idx] = math.max(0, active[idx] - 0.01)
            end
            icons[idx]:draw(x-size, y-size, x, y, active[idx] * alpha)
            x = x - (size*1.25)
        end
        state_shader:deactivate()
    end

    local function set(name, value)
        success[name] = value
    end

    return {
        set = set;
        draw = draw;
    }
end

local states = States{
    "time", "dns", "connectivity", "sync"
}

util.data_mapper{
    ["sys/syncer/progress"] = function(progress)
        updating = true
        target_update_progress = tonumber(progress)
    end;

    ["sys/syncer/updating"] = function(active)
        updating = active == "1"
        if updating then
            update_progress = 0
            target_update_progress = 0
        end
    end;

    ["sys/syncer/status"] = function(new_status)
        status = new_status
    end;

    ["sys/uplink/status"] = function(status)
        states.set("connectivity", status == "connected")
    end;

    ["sys/connect/pin"] = function(pin)
        connect_pin = pin:upper()
    end;

    ["sys/connect/info"] = function(info)
        connect_info = info
        status = info
    end;

    ["sys/wifi_name"] = function(name)
        wifi_name = name
    end;

    ["sys/state/(.*)"] = function(state, success)
        states.set(state, success == "true")
    end;

    ["sys/network/info"] = function(new_network_info)
        network_info = new_network_info
    end;
}

local start = sys.now()

local function centered(font, y, text, size, r,g,b,a, dots)
    local x = math.floor((WIDTH-font:width(text, size))/2)
    gl.pushMatrix()
    gl.translate(x, y)
    text = text..(dots and ("."):rep((sys.now() * 3) % 4) or '')
    local offset = size > 20 and 2 or 1
    font:write(offset, offset, text, size, 0, 0, 0, 0.8*a)
    local w = font:write(0, 0, text, size, r,g,b,a)
    gl.popMatrix()
    return w
end

local function draw_display_corner_dots(alpha)
    local dot_size = 2
    dot:draw(0,0,dot_size,dot_size,                      0.5*alpha)
    dot:draw(WIDTH,0,WIDTH-dot_size,dot_size,            0.5*alpha)
    dot:draw(0,HEIGHT,dot_size,HEIGHT-dot_size,          0.5*alpha)
    dot:draw(WIDTH,HEIGHT,WIDTH-dot_size,HEIGHT-dot_size,0.5*alpha)
end

local function eased(defer, d)
    local t = math.min(math.max(0, sys.now() - start - defer), d) / d
    t = t * 2
    if t < 1 then
        return 0.5 * t * t
    else
        t = t - 1
        return -0.5 * (t * (t - 2) - 1)
    end
end

local function vanilla(alpha)
    displays.primary()

    local blend1 = eased(2.5, 2)
    local blend2 = 1 - eased(4, 5)
    local blend3 = 1 - eased(2, 1)
    local blend4 = 1 + eased(2, 1)
    local center_y = HEIGHT / 2

    local background = resource.render_child("background", false)
    background:draw(0, 0, WIDTH, HEIGHT, alpha)

    gl.pushMatrix()
        gl.translate(WIDTH/2, HEIGHT/2)
        gl.scale(blend4*blend4, blend4*blend4)
        util.draw_correct(logo, -WIDTH/2, -HEIGHT/2+40, WIDTH/2, HEIGHT/2-40, blend3*alpha)
    gl.popMatrix()

    local title = "info-beamer"
    local title_w
    local title_bottom
    if WIDTH >= 1600 then
        title_w = centered(font, center_y - 255, title, 200, 1,1,1,blend1)
        title_bottom = center_y - 75
    elseif WIDTH >= 1024 then
        title_w = centered(font, center_y - 180, title, 130, 1,1,1,blend1)
        title_bottom = center_y - 60
    else 
        title_w = centered(font, center_y - 150, title, 90, 1,1,1,blend1)
        title_bottom = center_y - 65
    end

    local function channel_message(message, r,g,b)
        local width = font:width(message, 15)
        local x = (WIDTH+title_w) / 2 - width
        font:write(x + 60 - 60*blend1, title_bottom, message, 15, r,g,b,blend1*0.5)
    end

    if channel == "testing" then
        channel_message("Testing Channel", 1,.65,0)
    elseif channel == "bleeding" then
        channel_message("Bleeding Channel (DO NOT USE IN PRODUCTION!)", 1,.65,0)
    end

    local y = center_y + 120
    if HEIGHT < 1024 then
        y = center_y + 50
    end

    if wifi_name ~= "" then
        centered(font, y,    "Connect to the new WiFi network", 30, 1,1,1,(1-blend2)/2)
        centered(font, y+30, wifi_name, 30, 1,1,0,(1-blend2))
        centered(font, y+60, "to configure this device.", 30, 1,1,1,(1-blend2)/2)
    elseif connect_pin ~= "" then
        centered(font, y,    "Use the following PIN to add", 30, 1,1,1,(1-blend2)/2)
        centered(font, y+30, "this screen to your account", 30, 1,1,1,(1-blend2)/2)
        centered(font, y+65, connect_pin, 90, 1,1,1,(1-blend2))
    elseif updating then
        centered(font, y, "Fetching content", 30, 1,1,1,(1-blend2)/2*math.abs(math.sin(sys.now())), true)
    else
        centered(font, y, "Waiting for content", 30, 1,1,1,(1-blend2)/2*math.abs(math.sin(sys.now())), true)
    end

    black:draw(0, HEIGHT-32, WIDTH, HEIGHT, 0.3*blend1)

    font:write(5, HEIGHT - 16 - 8, status, 16, 1,1,1,0.5)

    if connect_pin ~= "" then
        draw_display_corner_dots(alpha)
    elseif updating then
        update_progress = (target_update_progress - update_progress) * 0.05 + update_progress
        white:draw(0, HEIGHT - 5, (WIDTH-100) * update_progress, HEIGHT, 0.6)
    end

    local network_info_width = font:width(network_info, 16)
    local x = WIDTH-6+ (1-blend1)*250
    if WIDTH >= 800 then
        font:write(x - network_info_width - 5 - 110, HEIGHT - 16 - 8, network_info, 16, 1,1,1,0.5*blend1)
    end
    states.draw(x, HEIGHT-6, 20, blend1)

    if displays.has_secondary then
        if connect_pin ~= "" then
            font:write(WIDTH-60, 3, "HDMI0", 18, 1,1,1,alpha*0.3)
        end
        displays.secondary()
        local center_y = HEIGHT / 2
        if not displays.overlap then
            background:draw(0, 0, WIDTH, HEIGHT, alpha)
        end
        if connect_pin ~= "" then
            font:write(WIDTH-60, 3, "HDMI1", 18, 1,1,1,alpha*0.3)
            draw_display_corner_dots(alpha)
        end
    end
    background:dispose()
end

local function branded_main()
    displays.primary()
    local now = sys.now()

    local fadein = eased(0, 3)
    local fade_bottom = eased(1, 3) / 2
    local blend1 = eased(4, 1) / 2
    local blend2 = eased(3, 1) / 1.3
    local ib_out = eased(3, 1)
    local state_in = eased(4, 1)

    if brand_video then
        gl.clear(0,0,0,0)
        branding:place(0, 0, WIDTH, HEIGHT):alpha(fadein):layer(-1)
    else
        branding:draw(0, 0, WIDTH, HEIGHT, fadein)
    end
    black:draw(0, HEIGHT - 20, WIDTH, HEIGHT, fade_bottom)

    if branding_settings['acknowledge-info-beamer'] then
       font:write(WIDTH-180, HEIGHT-18, "powered by info-beamer", 16, 1,1,1, fade_bottom*2 - ib_out)
    end

    local y = HEIGHT-18
    local size = 18
    if branding_settings['branding-action-centered'] then
        y = HEIGHT / 2 - 20
        size = 26
    end

    if wifi_name ~= "" then
        centered(font, y, string.format(
            branding_settings['branding-wifi-template'], wifi_name
        ), size, 1,1,1,blend2)
    elseif connect_pin ~= "" then
        centered(font, y, "Connect using PIN " .. connect_pin, size, 1,1,1,blend2)
    else
        centered(font, y, "Waiting for content", size, 1,1,1,blend2, true)
    end

    if connect_pin ~= "" then
        font:write(0, HEIGHT - 18, connect_info, 16, 1,1,1,0.6)
    elseif updating then
        font:write(0, HEIGHT - 18, status, 16, 1,1,1,0.6)
        update_progress = (target_update_progress - update_progress) * 0.05 + update_progress
        white:draw(0, HEIGHT - 20, (WIDTH-100) * update_progress, HEIGHT, 0.2)
    end

    if state_in > 0 then
        if branding_settings['branding-state-centered'] then
            states.draw(WIDTH/2+72, HEIGHT/2+50, 30, state_in)
        else
            states.draw(WIDTH-3, HEIGHT, 20, state_in)
        end
    end
end

local function branded()
    if branding:state() == "loaded" then
        start = sys.now()
        branded = branded_main
    end
end

local alpha = 0

function node.render()
    displays.primary()
    alpha = math.min(1, alpha + 0.016/1.0)
    gl.clear(0, 0, 0, alpha)
    if has_branding then
        branded(alpha)
    else
        vanilla(alpha)
    end
end
