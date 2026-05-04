-- Legacy entry point — delegates to RegionCreator.lua
-- Kept for backward compatibility with saved REAPER actions.
local _PATH = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]
dofile(_PATH .. "RegionCreator.lua")
