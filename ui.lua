local DrawState = {}
function DrawState.new()
    return setmetatable({
        _x = 0,
        _width = 0,
        _top_y = 0,
        _draw_y = 0,
    }, {__index = DrawState})
end

function DrawState:start(x, width)
    self._draw_y = self._top_y
    self._x = x
    self._width = width
end

function DrawState:element(s)
    s.x = self._x
    s.y = self._draw_y
    s.w = self._width
    s.advance = function(h)
        self._draw_y = self._draw_y + h + 2
    end
    s.selectable = true
    s.disable = function()
        s.selectable = false
    end
    return s
end

local UIImages = {}
function UIImages.new()
    return setmetatable({
        _images = {},
    }, {__index = UIImages})
end

function UIImages:get(file, expire)
    expire = expire or 86400
    if not self._images[file] then
        local res = resource.load_image{
            file = resource.open_file(file),
        }
        self._images[file] = {
            lru = sys.now(),
            res = res,
            expire = expire,
        }
    end
    self._images[file].lru = sys.now()
    return self._images[file].res
end

function UIImages:get_qr(text)
    local key = "qr:" .. text
    if not self._images[key] then
        local res = resource.create_qr_code(text)
        self._images[key] = {
            lru = sys.now(),
            res = res,
            expire = 5,
        }
    end
    self._images[key].lru = sys.now()
    return self._images[key].res
end


function UIImages:flush()
    for key, img in pairs(self._images) do
        if img.lru + img.expire < sys.now() then
            img.res:dispose()
            self._images[key] = nil
        end
    end
end


local UI = {}
function UI.new()
    local images = UIImages.new()
    images:get "ui-check-on.png" -- preload
    images:get "ui-check-off.png"
    local ui = setmetatable({
        _elems = {},
        _font = resource.load_font "font.ttf",
        _white = resource.create_colored_texture(1,1,1,1),
        _black = resource.create_colored_texture(0,0,0,1),
        _active = 1,
        _direction = 1,
        _draw_state = DrawState.new(),
        _images = images,
        _x = 0,
        _width = 0,
        _pulse = sys.now(),
    }, {__index = UI})
    local width = math.max(500, _G.WIDTH / 3)
    ui:place(_G.WIDTH - width, width)
    return ui
end

function UI:begin()
    self._elems = {}
end

function UI:save()
    return { 
        active = self._active,
        direction = self._direction,
    }
end

function UI:restore(state)
    self._active = state.active
    self._direction = state.direction
end

function UI:restart()
    self._active = 1
    self._direction = 1
end

function UI:pulse()
    self._pulse = sys.now()
end

function UI:move(delta)
    self._direction = delta
    self._active = self._active + delta
end

function UI:trigger()
    self._triggered = true
end

function UI:move_up()
    return self:move(-1)
end

function UI:move_down()
    return self:move(1)
end

function UI:loop()
    local start = sys.now()
    local iter = 0
    return function()
        if iter > 0 then
            coroutine.yield()
        end
        iter = iter + 1
        return iter - 1, sys.now() - start
    end
end

function UI:place(x, width)
    self._x = x
    self._width = width
    self._border_left = x > 0
    self._border_right = x + width < _G.WIDTH
end

function UI:finish()
    self._draw_state:start(
        self._x, self._width
    )
    for idx, elem in ipairs(self._elems) do
        elem.draw(self._draw_state:element(elem.state))
    end
    if self._active < 1 then
        self._active = 1
        self._direction = 1
    elseif self._active > #self._elems then
        self._active = #self._elems
        self._direction = -1
    end
    local function next_down()
        for idx = self._active+1, #self._elems do
            if self._elems[idx].state.selectable then
                self._active = idx
                return true
            end
        end
    end
    local function next_up()
        for idx = self._active-1, 1, -1 do
            if self._elems[idx].state.selectable then
                self._active = idx
                return true
            end
        end
    end
    local active_elem = self._elems[self._active]
    if active_elem and not active_elem.state.selectable then
        if self._direction == -1 then
            if not next_up() then next_down() end
        else
            if not next_down() then next_up() end
        end
    end
    self._triggered = false
    self._images:flush()
end

function UI:add_elem(fn)
    local idx = #self._elems + 1
    local state = {
        pressed = self._active == idx and self._triggered,
        active = self._active == idx,
    }
    self._elems[idx] = {
        draw = fn,
        state = state,
    }
    return state
end

function UI:menu_trigger()
    return self:add_elem(function(s) end)
end

function UI:text_color(active)
    if active then
        return 1, 1, 0, 1
    else
        return 1, 1, 1, 1
    end
end

function UI:background()
    return self:add_elem(function(s)
        self._black:draw(s.x, 0, s.x + s.w, HEIGHT, 0.95)
        if self._border_left then
            self._white:draw(s.x-2, 0, s.x, HEIGHT, 0.5)
        end
        if self._border_right then
            self._white:draw(s.x+s.w, 0, s.x+s.w+2, HEIGHT, 0.5)
        end

        local pulse = math.max(0, 1.0 - (sys.now() - self._pulse)*4)
        if pulse > 0 then
            self._white:draw(s.x, 0, s.x + s.w, HEIGHT, pulse*0.1)
        end
        s.disable()
    end)
end

function UI:label(text, size, opt)
    opt = opt or {}
    size = size or opt.size or 32
    local padding = opt.padding or 5
    return self:add_elem(function(s)
        self._font:write(s.x + padding*2, s.y + padding, text, size, 1,1,1,1)
        s.advance(size + padding*2)
        s.disable()
    end)
end

function UI:labelf(fmt, ...)
    return self:label(string.format(fmt, ...))
end

function UI:label_center(text, size, opt)
    opt = opt or {}
    size = size or opt.size or 32
    local padding = opt.padding or 5
    local w = self._font:width(text, size)
    return self:add_elem(function(s)
        self._font:write(s.x + (s.w-w)/2, s.y + padding, text, size, 1,1,1,1)
        s.advance(size + padding*2)
        s.disable()
    end)
end

function UI:keyvalf(key, valfmt, ...)
    local size = 32
    local padding = 5
    local key_w = self._font:width(key, size)
    local val = string.format(valfmt, ...)
    local val_w = self._font:width(val, size)
    return self:add_elem(function(s)
        self._font:write(s.x + padding*2, s.y + padding, key, size, 1,1,1,1)
        self._font:write(s.x + s.w - padding*2 - val_w, s.y + padding, val, size, 1,1,1,1)
        -- self._white:draw(
        --     s.x + padding*2 + key_w, s.y + padding + size,
        --     s.x + s.w - padding*2 - val_w, s.y + padding + size+1,
        --     0.2
        -- )
        -- local w = s.w - padding*4 - key_w - val_w
        -- local dots = ("."):rep(w/9 - 3)
        -- self._font:write(s.x + padding*2 + key_w + 14, s.y + padding, dots, size, 1,1,1,0.3)
        s.advance(size + padding*2)
        s.disable()
    end)
end

function UI:button(text, opt)
    opt = opt or {}
    local size = opt.size or 32
    local padding = opt.padding or 5
    return self:add_elem(function(s)
        if s.active then
            self._white:draw(s.x, s.y, s.x + s.w, s.y + size + padding*2, 0.5)
        end
        self._font:write(s.x + padding*2, s.y + padding, text, size, self:text_color(s.active))
        s.advance(size + padding*2)
    end)
end

function UI:checkbox(text, value, opt)
    opt = opt or {}
    local size = opt.size or 32
    local padding = opt.padding or 5
    return self:add_elem(function(s)
        if s.active then
            self._white:draw(s.x, s.y, s.x + s.w, s.y + size + padding*2, 0.5)
        end
        local img = self._images:get(value and "ui-check-on.png" or "ui-check-off.png")
        img:draw(s.x + padding, s.y + padding, s.x + padding + size, s.y + padding + size)
        self._font:write(s.x + padding*2 + size*1.2, s.y + padding, text, size, self:text_color(s.active))
        s.advance(size + padding*2)
    end)
end

function UI:image(file, height)
    height = height or 100
    return self:add_elem(function(s)
        local img = self._images:get(file)
        local w, h = img:size()
        local x1, y1, x2, y2 = util.scale_into(
            s.w, height, w, h
        )
        img:draw(s.x + x1, s.y + y1, s.x + x2, s.y + y2)
        s.advance(height)
        s.disable()
    end)
end

function UI:qrcode(text, height)
    height = height or 100
    return self:add_elem(function(s)
        local img = self._images:get_qr(text)
        local x1, y1, x2, y2 = util.scale_into(
            s.w, height, height, height
        )
        img:draw(s.x + x1, s.y + y1, s.x + x2, s.y + y2)
        s.advance(height)
        s.disable()
    end)
end

function UI:sep(height)
    height = height or 40
    return self:add_elem(function(s)
        self._white:draw(s.x, s.y+height/2-1, s.x + s.w, s.y +height/2+1, 0.5)
        s.disable()
        s.advance(height)
    end)
end

function UI:spacer(height)
    height = height or 40
    return self:add_elem(function(s)
        s.disable()
        s.advance(height)
    end)
end


local MenuStack = {}
function MenuStack.new(ui)
    return setmetatable({
        _stack = {},
        _ui = ui,
        _menu = nil,
    }, {__index = MenuStack})
end

function MenuStack:open(fn)
    self._ui:restart()
    self._menu = coroutine.wrap(function()
        while true do
            fn()
            coroutine.yield()
        end
    end)
end

function MenuStack:enter(fn)
    table.insert(self._stack, {
        ui = self._ui:save(),
        menu = self._menu,
    })
    return self:open(fn)
end

function MenuStack:leave()
    if #self._stack == 0 then
        return
    end
    local prev = table.remove(self._stack)
    self._ui:restore(prev.ui)
    self._menu = prev.menu
end

function MenuStack:run()
    self._ui:begin()
    self._menu()
    self._ui:finish()
end

local function create()
    local ui = UI.new()
    local menu = MenuStack.new(ui)

    local function handle_key(key)
        if key == "up" then
            ui:move_up()
        elseif key == "down" then
            ui:move_down()
        elseif key == "select" then
            ui:trigger()
        elseif key == "exit" then
            menu:leave()
        end
    end

    util.data_mapper{
        ["sys/cec/key"] = handle_key,
        ["ui/key"]      = handle_key,
    }
    return ui, menu
end

return {
    create = create,
}
