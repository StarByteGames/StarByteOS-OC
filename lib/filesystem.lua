local filesystem = {}

local mtab = {
    name = "",
    children = {},
    links = {}
}
local fstab = {}

function filesystem.proxy(filter, options)
    checkArg(1, filter, "string")
    if not component.list("filesystem")[filter] or next(options or {}) then
        return filesystem.internal.proxy(filter, options)
    end
    return component.proxy(filter)
end

function filesystem.exists(path)
    local file = filesystem.open(path, "r")
    if file then
        file:close()
        return true
    else
        return false
    end
end

function filesystem.list(path)
    local node, rest, vnode, vrest = filesystem.findNode(path, false, true)
    local result = {}
    if node then
        result = node.fs and node.fs.list(rest or "") or {}
        if not vrest then
            for k, n in pairs(vnode.children) do
                if not n.fs or fstab[filesystem.concat(path, k)] then
                    table.insert(result, k .. "/")
                end
            end
            for k in pairs(vnode.links) do
                table.insert(result, k)
            end
        end
    end
    local set = {}
    for _, name in ipairs(result) do
        set[filesystem.canonical(name)] = name
    end
    return function()
        local key, value = next(set)
        set[key or false] = nil
        return value
    end
end

function filesystem.readFile(path)
    local file, err = filesystem.open(path, "r")
    if not file then
        error("filesystem.open failed: " .. tostring(err or "unknown error"))
    end

    local content, readErr = file:read("*a")
    local ok, closeErr = pcall(function()
        file:close()
    end)
    if not ok then
        error("Culd not close!!!")
    end

    if content == nil then
        error("file:read failed: " .. tostring(readErr or "unknown error"))
    end

    return content
end

function filesystem.dofile(path)
    local content, err = filesystem.readFile(path)
    if not content then
        error("readFile failed: " .. tostring(err))
    end
    local chunk, err = load(content, "=" .. path)
    if not chunk then
        error("load failed: " .. tostring(err))
    end
    local ok, result = pcall(chunk)
    if not ok then
        error("execution failed: " .. tostring(result))
    end
    return result
end

function filesystem.open(path, mode)
    checkArg(1, path, "string")
    mode = tostring(mode or "r")
    checkArg(2, mode, "string")

    local validModes = {
        r = true,
        rb = true,
        w = true,
        wb = true,
        a = true,
        ab = true
    }
    assert(validModes[mode], "bad argument #2 (r[b], w[b] or a[b] expected, got " .. mode .. ")")

    local node, rest = filesystem.findNode(path, false, true)
    if not node then
        error("filesystem.findNode failed: " .. tostring(rest or "unknown error"))
    end

    if not node.fs then
        error("filesystem.open failed: node.fs is nil")
    end

    if not rest then
        error("filesystem.open failed: path remainder is nil")
    end

    if (mode == "r" or mode == "rb") and not node.fs.exists(rest) then
        error("file not found: " .. rest)
    end

    local handle, reason = node.fs.open(rest, mode)
    if not handle then
        error("node.fs.open failed: " .. tostring(reason or "unknown error"))
    end

    return setmetatable({
        fs = node.fs,
        handle = handle
    }, {
        __index = function(tbl, key)
            if not tbl.fs[key] then
                return
            end
            if not tbl.handle then
                error("file is closed")
            end
            return function(self, ...)
                local h = self.handle
                if key == "close" then
                    self.handle = nil
                end
                return self.fs[key](h, ...)
            end
        end
    })
end

function filesystem.segments(path)
    local parts = {}
    for part in path:gmatch("[^\\/]+") do
        local current, up = part:find("^%.?%.$")
        if current then
            if up == 2 then
                table.remove(parts)
            end
        else
            table.insert(parts, part)
        end
    end
    return parts
end

function filesystem.findNode(path, create, resolve_links)
    checkArg(1, path, "string")
    local visited = {}
    local parts = filesystem.segments(path)
    local ancestry = {}
    local node = mtab
    local index = 1

    while index <= #parts do
        local part = parts[index]
        ancestry[index] = node

        if not node.children[part] then
            local link_path = node.links[part]
            if link_path then
                if not resolve_links and #parts == index then
                    break
                end

                if visited[path] then
                    error(string.format("link cycle detected '%s'", path))
                end
                visited[path] = index
                local pst_path = "/" .. table.concat(parts, "/", index + 1)
                local pre_path

                if link_path:match("^[^/]") then
                    pre_path = table.concat(parts, "/", 1, index - 1) .. "/"
                    local link_parts = filesystem.segments(link_path)
                    local join_parts = filesystem.segments(pre_path .. link_path)
                    local back = (index - 1 + #link_parts) - #join_parts
                    index = index - back
                    node = ancestry[index]
                else
                    pre_path = ""
                    index = 1
                    node = mtab
                end

                path = pre_path .. link_path .. pst_path
                parts = filesystem.segments(path)
                part = nil
            elseif create then
                node.children[part] = {
                    name = part,
                    parent = node,
                    children = {},
                    links = {}
                }
            else
                error(string.format("path component '%s' not found in '%s'", part, path))
            end
        end

        if part then
            node = node.children[part]
            index = index + 1
        end
    end

    local vnode, vrest = node, #parts >= index and table.concat(parts, "/", index)
    local rest = vrest
    while node and not node.fs do
        rest = rest and filesystem.concat(node.name, rest) or node.name
        node = node.parent
    end
    return node, rest, vnode, vrest
end

function filesystem.concat(...)
    local set = table.pack(...)
    for index, value in ipairs(set) do
        checkArg(index, value, "string")
    end
    return filesystem.canonical(table.concat(set, "/"))
end

function filesystem.canonical(path)
    local result = table.concat(filesystem.segments(path), "/")
    if unicode.sub(path, 1, 1) == "/" then
        return "/" .. result
    else
        return result
    end
end

function filesystem.realPath(path)
    checkArg(1, path, "string")
    local node, rest = filesystem.findNode(path, false, true)
    if not node then
        return nil, rest
    end
    local parts = {rest or nil}
    repeat
        table.insert(parts, 1, node.name)
        node = node.parent
    until not node
    return table.concat(parts, "/")
end

function filesystem.mount(fs, path)
    checkArg(1, fs, "string", "table")
    if type(fs) == "string" then
        fs = filesystem.proxy(fs)
    end
    assert(type(fs) == "table", "bad argument #1 (file system proxy or address expected)")
    checkArg(2, path, "string")

    local real
    if not mtab.fs then
        if path == "/" then
            real = path
        else
            return nil, "rootfs must be mounted first"
        end
    else
        local why
        real, why = filesystem.realPath(path)
        if not real then
            return nil, why
        end

        if filesystem.exists(real) and not filesystem.isDirectory(real) then
            return nil, "mount point is not a directory"
        end
    end

    local fsnode
    if fstab[real] then
        return nil, "another filesystem is already mounted here"
    end
    for _, node in pairs(fstab) do
        if node.fs.address == fs.address then
            fsnode = node
            break
        end
    end

    if not fsnode then
        fsnode = select(3, filesystem.findNode(real, true))
        fs.fsnode = fsnode
    else
        local pwd = filesystem.path(real)
        local parent = select(3, findNode(pwd, true))
        local name = filesystem.name(real)
        fsnode = setmetatable({
            name = name,
            parent = parent
        }, {
            __index = fsnode
        })
        parent.children[name] = fsnode
    end

    fsnode.fs = fs
    fstab[real] = fsnode

    return true
end

function filesystem.makeDirectory(path)
    if filesystem.exists(path) then
        return nil, "file or directory with that name already exists"
    end
    local node, rest = filesystem.findNode(path)
    if node.fs and rest then
        local success, reason = node.fs.makeDirectory(rest)
        if not success and not reason and node.fs.isReadOnly() then
            reason = "filesystem is readonly"
        end
        return success, reason
    end
    if node.fs then
        return nil, "virtual directory with that name already exists"
    end
    return nil, "cannot create a directory in a virtual directory"
end

function filesystem.lastModified(path)
    local node, rest, vnode, vrest = filesystem.findNode(path, false, true)
    if not node or not vnode.fs and not vrest then
        return 0
    end
    if node.fs and rest then
        return node.fs.lastModified(rest)
    end
    return 0
end

function filesystem.mounts()
    local tmp = {}
    for path, node in pairs(filesystem.fstab) do
        table.insert(tmp, {node.fs, path})
    end
    return function()
        local next = table.remove(tmp)
        if next then
            return table.unpack(next)
        end
    end
end

function filesystem.link(target, linkpath)
    checkArg(1, target, "string")
    checkArg(2, linkpath, "string")

    if filesystem.exists(linkpath) then
        return nil, "file already exists"
    end
    local linkpath_parent = filesystem.path(linkpath)
    if not filesystem.exists(linkpath_parent) then
        return nil, "no such directory"
    end
    local linkpath_real, reason = filesystem.realPath(linkpath_parent)
    if not linkpath_real then
        return nil, reason
    end
    if not filesystem.isDirectory(linkpath_real) then
        return nil, "not a directory"
    end

    local _, _, vnode, _ = filesystem.findNode(linkpath_real, true)
    vnode.links[filesystem.name(linkpath)] = target
    return true
end

function filesystem.umount(fsOrPath)
    checkArg(1, fsOrPath, "string", "table")
    local real
    local fs
    local addr
    if type(fsOrPath) == "string" then
        real = filesystem.realPath(fsOrPath)
        addr = fsOrPath
    else
        fs = fsOrPath
    end

    local paths = {}
    for path, node in pairs(filesystem.fstab) do
        if real == path or addr == node.fs.address or fs == node.fs then
            table.insert(paths, path)
        end
    end
    for _, path in ipairs(paths) do
        local node = filesystem.fstab[path]
        filesystem.fstab[path] = nil
        node.fs = nil
        node.parent.children[node.name] = nil
    end
    return #paths > 0
end

function filesystem.size(path)
    local node, rest, vnode, vrest = filesystem.findNode(path, false, true)
    if not node or not vnode.fs and (not vrest or vnode.links[vrest]) then
        return 0
    end
    if node.fs and rest then
        return node.fs.size(rest)
    end
    return 0
end

function filesystem.isLink(path)
    local name = filesystem.name(path)
    local node, rest, vnode, vrest = filesystem.findNode(filesystem.path(path), false, true)
    if not node then
        return nil, rest
    end
    local target = vnode.links[name]
    if not vrest and target ~= nil then
        return true, target
    end
    return false
end

function filesystem.copy(fromPath, toPath)
    local data = false
    local input, reason = filesystem.open(fromPath, "rb")
    if input then
        local output = filesystem.open(toPath, "wb")
        if output then
            repeat
                data, reason = input:read(1024)
                if not data then
                    break
                end
                data, reason = output:write(data)
                if not data then
                    data, reason = false, "failed to write"
                end
            until not data
            output:close()
        end
        input:close()
    end
    return data == nil, reason
end

function filesystem.readonly_wrap(proxy)
    checkArg(1, proxy, "table")
    if proxy.isReadOnly() then
        return proxy
    end

    local function roerr()
        return nil, "filesystem is readonly"
    end
    return setmetatable({
        rename = roerr,
        open = function(path, mode)
            checkArg(1, path, "string")
            checkArg(2, mode, "string")
            if mode:match("[wa]") then
                return roerr()
            end
            return proxy.open(path, mode)
        end,
        isReadOnly = function()
            return true
        end,
        write = roerr,
        setLabel = roerr,
        makeDirectory = roerr,
        remove = roerr
    }, {
        __index = proxy
    })
end

function filesystem.bind_proxy(path)
    local real, reason = filesystem.realPath(path)
    if not real then
        return nil, reason
    end
    if not filesystem.isDirectory(real) then
        return nil, "must bind to a directory"
    end
    local real_fs, real_fs_path = filesystem.get(real)
    if real == real_fs_path then
        return real_fs
    end
    local rest = real:sub(#real_fs_path + 1)
    local function wrap_relative(fp)
        return function(mpath, ...)
            return fp(filesystem.concat(rest, mpath), ...)
        end
    end
    local bind = {
        type = "filesystem_bind",
        address = real,
        isReadOnly = real_fs.isReadOnly,
        list = wrap_relative(real_fs.list),
        isDirectory = wrap_relative(real_fs.isDirectory),
        size = wrap_relative(real_fs.size),
        lastModified = wrap_relative(real_fs.lastModified),
        exists = wrap_relative(real_fs.exists),
        open = wrap_relative(real_fs.open),
        remove = wrap_relative(real_fs.remove),
        read = real_fs.read,
        write = real_fs.write,
        close = real_fs.close,
        getLabel = function()
            return ""
        end,
        setLabel = function()
            return nil, "cannot set the label of a bind point"
        end
    }
    return bind
end

filesystem.internal = {}
function filesystem.internal.proxy(filter, options)
    checkArg(1, filter, "string")
    checkArg(2, options, "table", "nil")
    options = options or {}
    local address, proxy, reason
    if options.bind then
        proxy, reason = filesystem.bind_proxy(filter)
    else
        for c in component.list("filesystem", true) do
            if component.invoke(c, "getLabel") == filter then
                address = c
                break
            end
            if c:sub(1, filter:len()) == filter then
                address = c
                break
            end
        end
        if not address then
            return nil, "no such file system"
        end
        proxy, reason = component.proxy(address)
    end
    if not proxy then
        return proxy, reason
    end
    if options.readonly then
        proxy = filesystem.readonly_wrap(proxy)
    end
    return proxy
end

function filesystem.remove(path)
    local function removeVirtual()
        local _, _, vnode, vrest = filesystem.findNode(filesystem.path(path), false, true)
        if not vrest then
            local name = filesystem.name(path)
            if vnode.children[name] or vnode.links[name] then
                vnode.children[name] = nil
                vnode.links[name] = nil
                while vnode and vnode.parent and not vnode.fs and not next(vnode.children) and not next(vnode.links) do
                    vnode.parent.children[vnode.name] = nil
                    vnode = vnode.parent
                end
                return true
            end
        end
        return false
    end
    local function removePhysical()
        local node, rest = filesystem.findNode(path)
        if node.fs and rest then
            return node.fs.remove(rest)
        end
        return false
    end
    local success = removeVirtual()
    success = removePhysical() or success
    if success then
        return true
    else
        return nil, "no such file or directory"
    end
end

function filesystem.rename(oldPath, newPath)
    if filesystem.isLink(oldPath) then
        local _, _, vnode, _ = filesystem.findNode(filesystem.path(oldPath))
        local target = vnode.links[filesystem.name(oldPath)]
        local result, reason = filesystem.link(target, newPath)
        if result then
            filesystem.remove(oldPath)
        end
        return result, reason
    else
        local oldNode, oldRest = filesystem.findNode(oldPath)
        local newNode, newRest = filesystem.findNode(newPath)
        if oldNode.fs and oldRest and newNode.fs and newRest then
            if oldNode.fs.address == newNode.fs.address then
                return oldNode.fs.rename(oldRest, newRest)
            else
                local result, reason = filesystem.copy(oldPath, newPath)
                if result then
                    return filesystem.remove(oldPath)
                else
                    return nil, reason
                end
            end
        end
        return nil, "trying to read from or write to virtual directory"
    end
end

local isAutorunEnabled = nil
local function saveConfig()
    local root = filesystem.get("/")
    if root and not root.isReadOnly() then
        local f = filesystem.open("/etc/filesystem.cfg", "w")
        if f then
            f:write("autorun=" .. tostring(isAutorunEnabled))
            f:close()
        end
    end
end

function filesystem.isAutorunEnabled()
    if isAutorunEnabled == nil then
        local env = {}
        local config = loadfile("/etc/filesystem.cfg", nil, env)
        if config then
            pcall(config)
            isAutorunEnabled = not not env.autorun
        else
            isAutorunEnabled = true
        end
        saveConfig()
    end
    return isAutorunEnabled
end

function filesystem.setAutorunEnabled(value)
    checkArg(1, value, "boolean")
    isAutorunEnabled = value
    saveConfig()
end

filesystem.fstab = fstab

return filesystem
