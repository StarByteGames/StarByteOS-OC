local console = require('lib.console')

return function(args)
    console.writeLine(table.concat(args, " "))
end
