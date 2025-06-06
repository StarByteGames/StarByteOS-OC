local gpu = component.proxy(component.list("gpu")())

local graphics = {}

graphics.width, graphics.height = gpu.getResolution()

function graphics.bindScreen(screen)
    gpu.bind(screen)
end

function graphics.setResolution(w, h)
    gpu.setResolution(w, h)
    graphics.width, graphics.height = w, h
end

function graphics.clear(char)
    char = char or " "
    gpu.fill(1, 1, graphics.width, graphics.height, char)
end

function graphics.setForeground(color)
    gpu.setForeground(color)
end

function graphics.setBackground(color)
    gpu.setBackground(color)
end

function graphics.print(text, cursorX, cursorY)
    local x, y = cursorX, cursorY
    local w, h = graphics.width, graphics.height

    for i = 1, #text do
        local char = text:sub(i, i)

        gpu.set(x, y, char)

        x = x + 1
        if x > w then
            x = 1
            y = y + 1
        end
    end
    return x, y
end

return graphics
