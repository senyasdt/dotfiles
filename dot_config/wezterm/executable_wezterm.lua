-- Compatibility entry point: WezTerm searches this before ~/.wezterm.lua.
-- Keep configuration in the modular root entry point only.
local wezterm = require("wezterm")
return dofile(wezterm.home_dir .. "/.wezterm.lua")
