local loadedModules = {}

function require(moduleName)
    if loadedModules[moduleName] then
        return loadedModules[moduleName]
    end

    local addr = computer.getBootAddress()
    local invoke = component.invoke

    local path = moduleName:gsub("%.", "/") .. ".lua"

    local handle = invoke(addr, "open", path)
    if not handle then
        error("Module not found: " .. moduleName .. " at path " .. path)
    end

    local content = ""
    repeat
        local data = invoke(addr, "read", handle, math.huge)
        content = content .. (data or "")
    until not data
    invoke(addr, "close", handle)

    local func, err = load(content, "=" .. path, "bt", _G)
    if not func then
        error("Error loading module '" .. moduleName .. "': " .. err)
    end

    local result = func()
    loadedModules[moduleName] = result or true
    return loadedModules[moduleName]
end
