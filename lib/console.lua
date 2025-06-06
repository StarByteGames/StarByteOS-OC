local graphics = require('lib.graphics')

local console = {}

console.width = 80
console.height = 25
console.cursorX = 1
console.cursorY = 1

local function print(...)
    local text = table.concat((function(t)
        for i = 1, #t do
            t[i] = tostring(t[i])
        end
        return t
    end)({...}), " ")
    console.cursorX, console.cursorY = graphics.print(text, console.cursorX, console.cursorY)
    return text
end

function console.clear()
    graphics.clear(" ")
    console.setCursor(1, 1)
end

function console.setCursor(x, y)
    console.cursorX = x
    console.cursorY = y
end

function console.write(...)
    local text = print(...)
    console.cursorX = console.cursorX + #text
end

function console.writeLine(...)
    print(...)
    console.cursorX = 1
    console.cursorY = console.cursorY + 1
end

return console
