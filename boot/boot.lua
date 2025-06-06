local component = component
local computer = computer

local keyboard = {
    pressedChars = {},
    pressedCodes = {}
}

keyboard.keys = {
    up = 0xC8,
    down = 0xD0,
    enter = 0x1C
}

function keyboard.isKeyDown(code)
    return keyboard.pressedCodes[code]
end

local function dofile(path)
    local addr, invoke = computer.getBootAddress(), component.invoke
    local function loadfile(file)
        local handle = assert(invoke(addr, "open", file))
        local buffer = ""
        repeat
            local data = invoke(addr, "read", handle, math.maxinteger or math.huge)
            buffer = buffer .. (data or "")
        until not data
        invoke(addr, "close", handle)
        return load(buffer, "=" .. file, "bt", _G)
    end
    loadfile(path)(loadfile)
end

local gpu = component.proxy(component.list("gpu")())
local screen = component.list("screen")()
gpu.bind(screen)
gpu.setResolution(80, 25)

local kernels
local timeout
do
    dofile("/boot/fs.lua")
    local config = require('etc.config')
    kernels = config.kernels
    timeout = config.bootTimeout
end

if #kernels == 1 then
    _G.KERNEL_PATH = kernels[1].path
    return
end

local selected = 1
local startTime = computer.uptime()

local function draw()
    gpu.fill(1, 1, 80, 25, " ")
    local remaining = math.ceil(timeout - (computer.uptime()))
    gpu.set(1, 1, "Select Kernel to Boot (auto boot in " .. remaining .. "s):")
    for i, k in ipairs(kernels) do
        local prefix = (i == selected) and "> " or "  "
        gpu.set(3, i + 2, prefix .. k.name)
    end
end

draw()

while true do
    local elapsed = computer.uptime()
    if elapsed >= timeout then
        _G.KERNEL_PATH = kernels[1].path
        return
    end

    draw()
    local event, _, _, keyCode = computer.pullSignal(0.5)

    if event == "key_down" then
        if keyCode == keyboard.keys.up then
            selected = selected - 1
            if selected < 1 then
                selected = #kernels
            end
        elseif keyCode == keyboard.keys.down then
            selected = selected + 1
            if selected > #kernels then
                selected = 1
            end
        elseif keyCode == keyboard.keys.enter then
            _G.KERNEL_PATH = kernels[selected].path
            return
        end
    end
end
