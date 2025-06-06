local console = require('lib.console')
local keyboard = require('lib.keyboard')
local event = require('lib.event')
local filesystem = require('lib.filesystem')

local currentPath = "/"
local prompt = currentPath .. "> "
local commandHistory = {}
local historyIndex = 0
local commands = {}

local function loadCommands()
    local files = {}

    console.writeLine("Listing /bin:")
    for file in filesystem.list("/bin") do
        console.writeLine(" - " .. file)
        table.insert(files, file)
    end

    for _, file in ipairs(files) do
        if string.sub(file, -4) == ".lua" then
            local cmdName = string.sub(file, 1, #file - 4)
            local cmdPath = "/bin/" .. file
            commands[cmdName] = cmdPath
        end
    end
end

local function executeCommand(command)
    local parts = string.split(command, " ")
    local cmd = table.remove(parts, 1)

    if cmd == "help" then
        console.writeLine("Available commands:")
        console.writeLine("  help - Show this help")
        for cmdName, _ in pairs(commands) do
            console.writeLine("  " .. cmdName)
        end
    elseif commands[cmd] then
        local cmdPath = commands[cmd]
        local cmdFunc = loadfile(cmdPath)
        if cmdFunc then
            local success, result = pcall(cmdFunc, parts)
            if not success then
                console.writeLine("Error executing command: " .. result)
            end
        else
            console.writeLine("Error: Could not load command.")
        end
    else
        console.writeLine("Unknown command: " .. cmd)
    end
end

local function drawPrompt()
    console.write(prompt)
end

console.clear()
loadCommands()
drawPrompt()

local currentInput = ""

while true do
    local eventName, _, char, code = event.pull("key_down")

    if code == keyboard.keys.back then
        if #currentInput > 0 then
            currentInput = string.sub(currentInput, 1, #currentInput - 1)
            console.cursorX = console.cursorX - 1
            console.setCursor(console.cursorX, console.cursorY)
            console.write(" ")
            console.setCursor(console.cursorX, console.cursorY)
        end
    elseif code == keyboard.keys.enter then
        console.writeLine("")
        table.insert(commandHistory, currentInput)
        historyIndex = #commandHistory + 1
        executeCommand(currentInput)
        currentInput = ""
        drawPrompt()
    elseif code == keyboard.keys.up then
        if #commandHistory > 0 then
            historyIndex = math.max(1, historyIndex - 1)
            currentInput = commandHistory[historyIndex] or ""
            console.setCursor(1, console.cursorY)
            console.write(string.rep(" ", console.width))
            console.setCursor(1, console.cursorY)
            drawPrompt()
            console.write(currentInput)
        end
    elseif code == keyboard.keys.down then
        if #commandHistory > 0 then
            historyIndex = math.min(#commandHistory + 1, historyIndex + 1)
            currentInput = commandHistory[historyIndex] or ""
            console.setCursor(1, console.cursorY)
            console.write(string.rep(" ", console.width))
            console.setCursor(1, console.cursorY)
            drawPrompt()
            console.write(currentInput)
        end
    elseif char and char > 0 then
        currentInput = currentInput .. string.char(char)
        console.write(string.char(char))
    end

    while true do
    end
end
