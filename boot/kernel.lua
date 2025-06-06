local computer = require('lib.computer')
local console = require('lib.console')
local filesystem = require('lib.filesystem')

filesystem.mount(computer.getBootAddress(), "/")

local processes = {}
local pidCounter = 0

local protectedProcesses = {}

local function spawnProcess(func, protect)
    pidCounter = pidCounter + 1
    local pid = pidCounter
    processes[pid] = coroutine.create(func)
    if protect then
        protectedProcesses[pid] = true
    end
    return pid
end

local function killProcess(pid)
    if protectedProcesses[pid] then
        console.writeLine("Process " .. pid .. " is protected and cannot be killed.")
        return
    end
    if processes[pid] then
        processes[pid] = nil
        protectedProcesses[pid] = nil
        console.writeLine("Process " .. pid .. " killed.")
    else
        console.writeLine("Process " .. pid .. " not found.")
    end
end

local function runScheduler()
    while true do
        for pid, thread in pairs(processes) do
            local ok, err = coroutine.resume(thread)
            if not ok then
                console.writeLine("Process " .. pid .. " crashed with error:")
                console.writeLine(err)
                processes[pid] = nil
                protectedProcesses[pid] = nil
            elseif coroutine.status(thread) == "dead" then
                processes[pid] = nil
                protectedProcesses[pid] = nil
            end
        end
        computer.pullSignal(0.05)
    end
end

spawnProcess(function()
    console.writeLine("Kernel started.")
    while true do
        coroutine.yield()
    end
end, true)

spawnProcess(function()
    local result, err = filesystem.dofile("/bin/shell.lua")
    if not result then
        console.writeLine("Error starting shell: " .. tostring(err))
        return
    else
        console.writeLine("Shell started.")
    end
end, true)

runScheduler()
