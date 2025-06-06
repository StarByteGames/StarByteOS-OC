local console = require('lib.console')
local os = require('os')

return function()
    console.writeLine(os.date())
end
