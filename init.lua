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

loadfile("/boot/boot.lua")(loadfile)

if _G.KERNEL_PATH then
    local v, err = pcall(loadfile, _G.KERNEL_PATH)
    do
        local console = require('lib.console')
        console.clear()
        console.writeLine("Kernel error:", err())
        console.writeLine("Booting fallback kernel...")
    end

    local start = computer.uptime()
    while computer.uptime() - start < 50 do
        coroutine.yield()
    end

    local _, err = pcall(loadfile, "/boot/fallback_kernel.lua")

else
    error("No kernel selected!")
end

error("Booting faild!")
