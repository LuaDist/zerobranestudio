local lfs = require "lfs"

local share = _PROGDIR .. "/../share/zerobranestudio"
lfs.chdir(share)
assert(loadfile("src/main.lua"))("zbstudio")
