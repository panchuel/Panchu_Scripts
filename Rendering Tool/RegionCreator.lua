--@description Region Creator
--@version 1.0
--@author Panchu
--@provides [main] .

RC = {}   -- shared namespace; all modules read/write through this table

local _PATH = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]

local function load_module(name)
    local fn, err = loadfile(_PATH .. "src/" .. name)
    if not fn then
        reaper.MB("Error loading " .. name .. ":\n\n" .. tostring(err), "Region Creator", 0)
        return false
    end
    fn()
    return true
end

for _, m in ipairs({
    "config.lua",
    "audio_types.lua",
    "settings.lua",
    "track_utils.lua",
    "wildcards.lua",
    "regions.lua",
    "gui.lua",
}) do
    if not load_module(m) then return end
end

gui_start()
