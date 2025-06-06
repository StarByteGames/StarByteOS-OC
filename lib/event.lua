local event = {}

function event.pull(filter)
    return coroutine.yield(filter)
end

return event
