-- Copyright (c) 2014-2020 Florian Wesch <fw@dividuum.de>
-- All rights reserved. No warranty, explicit or implicit, provided.

util.no_globals()
node.alias "root"

local CONFIG_CONTENT = node.make_nested()['config']

local ui = require "ui"
local rpc = require "rpc"
local json = require "json"
local py = rpc.create()

local branding, branding_loaded
if CONFIG_CONTENT['config/branding.jpg'] then
    branding_loaded, branding = pcall(resource.load_image, {
        file = 'config/branding.jpg'
    })
elseif CONFIG_CONTENT['config/branding.mp4'] then
    branding_loaded, branding = pcall(resource.load_video, {
        file = 'config/branding.mp4',
        looped = true,
        audio = true,
        raw = true,
    })
end
if not branding_loaded then
    print("cannot load branding file", branding)
    branding = nil
end

local function json_config(filename, defaults)
    local config = defaults
    util.json_watch(filename, function(settings)
        for k, v in pairs(settings) do
            config[k] = v
        end
    end)
    return config
end

local cec_menu = json_config("config/cec_menu.json", {
    enabled = true,
    wifi = false,
    reboot = false,
    info_link = true,
})

local branding_settings = json_config("config/branding.json", {
    ["register-url"] = "https://info-beamer.com/register",
    ["acknowledge-info-beamer"] = true,
    ["branding-action-centered"] = false,
    ["branding-state-centered"] = false,
    ["branding-wifi-template"] = 'Configuration WiFi %s active',
})

local logo = resource.load_image{file = "logo-large.png", fastload = true}
local font = resource.load_font "font.ttf"
local white = resource.create_colored_texture(1, 1, 1, 1)
local black = resource.create_colored_texture(0, 0, 0, 1)
local dot = white

local SERIAL = sys.get_env "SERIAL"
local CHANNEL = sys.get_env "CHANNEL"
local VERSION = sys.get_env "VERSION"
local UUID = CONTENTS.UUID and resource.load_file("UUID")
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

-- Dual display support
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

--------------------------

local ui, menu = ui.create()

local function header(path)
    ui:place(WIDTH-500, 500)
    ui:background()
    ui:spacer(80)
    ui:image("logo-small.png", 72)
    ui:spacer(80)
    ui:label(table.concat({"Device", path}, " / "), 20)
    ui:sep()
end

local function footer()
    ui:sep()
    ui:label(string.format("Version %s %s", CHANNEL, VERSION), 20)
end

local function DisplayMenu()
    local mode = "welcome"
    local function menu()
        for i in ui:loop() do
            header "Display"
            if ui:checkbox("Show welcome screen", mode=="welcome").pressed then
                mode = "welcome"
                ui:pulse()
            end
            if ui:checkbox("Identify display hardware", mode=="identify").pressed then
                mode = "identify"
                ui:pulse()
            end
            footer()
        end
    end
    return {
        menu = menu;
        selected_mode = function(query_mode)
            return mode == query_mode
        end;
    }
end
local display_menu = DisplayMenu()

local function HardwareMenu()
    local sensor
    py.register("device_sensor", function(new_sensor)
        sensor = new_sensor
    end)
    return function()
        for i in ui:loop() do
            if i % 600 == 0 then
                py.update_device_sensor()
            end
            header "Hardware"
            if sensor then
                ui:keyvalf("Serial", sensor.environ.SERIAL)
                ui:keyvalf("Revision", sensor.pi.revision)
                ui:sep()
                ui:keyvalf("Temperature", "%.1fC", sensor.temp)
                ui:sep()
                ui:keyvalf("Free disk", "%.1fGB", sensor.disk.available/1024/1024)
                ui:sep()
                ui:keyvalf("ARM memory", "%dMB", sensor.ram.arm/1024)
                ui:keyvalf("GPU memory", "%dMB", sensor.ram.gpu/1024)
            else

                ui:label("One moment...")
            end
            footer()
        end
    end
end
local hardware_menu = HardwareMenu()

local function NetworkMenu()
    local status
    py.register("device_status", function(new_status)
        status = new_status
    end)
    return function()
        for i in ui:loop() do
            if i % 120 == 0 then
                py.update_device_status()
            end
            header "Network"
            if status then
                ui:keyvalf("Connected to service", status.network.connected and "Yes" or "No")
                ui:sep()
                ui:keyvalf("Interface", status.network.interface)
                ui:keyvalf("IP",
                    status.network.device.ip == json.null
                    and "<none>" or status.network.device.ip
                )
                ui:keyvalf("MAC", status.network.device.mac)
                if status.network.gateway ~= json.null then
                    ui:spacer()
                    ui:keyvalf("Gateway IP", status.network.gateway.ip)
                    ui:keyvalf("Gateway MAC", status.network.gateway.mac)
                end
                ui:sep()
                ui:keyvalf("Peer-to-Peer enabled", status.p2p.enabled and "Yes" or "No")
                ui:keyvalf("Detected peers", "%d", status.p2p.peers)
            else
                ui:label("One moment...")
            end
            footer()
        end
    end
end
local network_menu = NetworkMenu()

local function WiFiMenu()
    local wifi = {active=false}
    local can_switch = true
    py.register("wifi_config_status", function(new_wifi)
        if new_wifi.active ~= wifi.active then
            can_switch = true
        end
        wifi = new_wifi
    end)
    return function()
        for i in ui:loop() do
            if i % 120 == 0 then
                py.wifi_status()
            end
            header "WiFi"
            if can_switch then
                if ui:checkbox("Enable Configuration WiFi", wifi.active).pressed then
                    if wifi.active then
                        if py.wifi_stop() then
                            ui:pulse()
                        end
                    else
                        if py.wifi_start() then
                            ui:pulse()
                        end
                    end
                    can_switch = false
                end
            else
                ui:label("One moment...")
            end

            if wifi.active then
                ui:sep()
                ui:label_center("Scan this QR code to connect", 20)
                ui:label_center("to the configuration WiFi", 20)
                ui:spacer(10)
                ui:qrcode(string.format(
                    "WIFI:S:%s;T:WPA;P:%s;;",
                    wifi.ssid,
                    wifi.password
                ), 300)
                ui:spacer(10)
            end
            footer()
        end
    end
end
local wifi_menu = WiFiMenu()

local function os_menu()
    header "System"
    if ui:button("Trigger OS update").pressed then
        if py.os_update() then
            ui:pulse()
        end
    end
    if cec_menu.reboot and ui:button("Reboot").pressed then
        if py.os_reboot() then
            ui:pulse()
        end
    end
    if cec_menu.info_link then
        ui:sep()
        if connect_pin == "" and UUID then
            ui:label_center("Go to device detail page", 20)
            ui:spacer(10)
            ui:qrcode("https://info-beamer.com/d/" .. UUID:sub(1, 8), 300)
            ui:spacer(10)
        else
            ui:label_center("Register this device", 20)
            ui:spacer(10)
            ui:qrcode(branding_settings['register-url'], 300)
            ui:spacer(10)
        end
    end
    footer()
end

local function main_menu()
    header()
    if ui:button("Hardware..").pressed then
        menu:enter(hardware_menu)
    end
    if ui:button("Display..").pressed then
        menu:enter(display_menu.menu)
    end
    if ui:button("Network..").pressed then
        menu:enter(network_menu)
    end
    if cec_menu.wifi and ui:button("WiFi..").pressed then
        menu:enter(wifi_menu)
    end
    if ui:button("System..").pressed then
        menu:enter(os_menu)
    end
    footer()
end

local function idle_menu()
    if cec_menu.enabled and ui:menu_trigger().pressed then
        menu:enter(main_menu)
    end
end

menu:open(idle_menu)

--------------------------

local function StateIcons(names)
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
local states = StateIcons{
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

    if CHANNEL == "testing" then
        channel_message("Testing Channel", 1,.65,0)
    elseif CHANNEL == "bleeding" then
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
            font:write(WIDTH-60, 3, "HDMI-0", 18, 1,1,1,alpha*0.3)
        end
        displays.secondary()
        local center_y = HEIGHT / 2
        if not displays.overlap then
            background:draw(0, 0, WIDTH, HEIGHT, alpha)
        end
        if connect_pin ~= "" then
            font:write(WIDTH-60, 3, "HDMI-1", 18, 1,1,1,alpha*0.3)
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

    if type(branding) == "image" then
        branding:draw(0, 0, WIDTH, HEIGHT, fadein)
    else
        gl.clear(0,0,0,0)
        branding:place(0, 0, WIDTH, HEIGHT):alpha(fadein):layer(-1)
    end
    black:draw(0, HEIGHT - 20, WIDTH, HEIGHT, fade_bottom)

    if branding_settings['acknowledge-info-beamer'] then
       font:write(WIDTH-180, HEIGHT-18, "powered by info-beamer", 16, 1,1,1, fade_bottom*2 - ib_out)
    end

    local y = HEIGHT-19
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

local function identify()
    gl.clear(1,1,1,1)
    local get_display_info = sys.get_ext("screen").get_display_info
    local function info(text, display)
        black:draw(20, 20, WIDTH-20, HEIGHT-20)
        white:draw(40, 40, WIDTH-40, HEIGHT-40)
        black:draw(60, 60, WIDTH-60, HEIGHT-60)
        local center_y = HEIGHT/2
        centered(font, center_y-80, text, 160, 1,1,1,1)
        local fps = get_display_info()
        font:write(80, 80, string.format(
            "Surface resolution: %dx%d / %dHz",
            NATIVE_WIDTH, NATIVE_HEIGHT, fps
        ), 30, 1,1,1,1)
        font:write(80, 110, string.format(
            "This display: %dx%d+%d,%d",
            display.x2 - display.x1,
            display.y2 - display.y1,
            display.x1, display.y1
        ), 30, 1,1,1,1)
    end

    displays.primary()
    info("HDMI-0", sys.displays[1])
    if displays.has_secondary then
        displays.secondary()
        info("HDMI-1", sys.displays[2])
    end
end

local alpha = 0
function node.render()
    if display_menu.selected_mode "identify" then
        identify()
    else
        displays.primary()
        alpha = math.min(1, alpha + 0.016/1.0)
        gl.clear(0, 0, 0, alpha)
        if branding then
            branded(alpha)
        else
            vanilla(alpha)
        end
    end
    menu:run()
end
