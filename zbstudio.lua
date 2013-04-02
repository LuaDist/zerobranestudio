local lfs = require "lfs"

-- Get LuaDist deployment path
local paths = {}
package.path:gsub("([^;]+)", function(c) table.insert(paths, c) end)
local path = paths[2]:gsub("[/\\]bin[/\\]%.%..*","")

local share = path .. "/share/zerobranestudio"

lfs.chdir(share)
assert(loadfile("src/main.lua"))("zbstudio")
