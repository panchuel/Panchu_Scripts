--@description RegionForge — Hierarchical region creation & batch render for REAPER
--@version 1.2
--@author Panchuel
--@link https://github.com/panchuel/Panchu_Scripts
--@provides
--  [main] RegionForge.lua
--  src/config.lua
--  src/audio_types.lua
--  src/settings.lua
--  src/track_utils.lua
--  src/ucs_data.lua
--  src/ucs.lua
--  src/wildcards.lua
--  src/wav_writer.lua
--  src/regions.lua
--  src/render_direct.lua
--  src/render.lua
--  src/gui.lua

RC = {}   -- shared namespace; all modules read/write through this table

local _PATH = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]

local function load_module(name)
    local fn, err = loadfile(_PATH .. "src/" .. name)
    if not fn then
        reaper.MB("Error loading " .. name .. ":\n\n" .. tostring(err), "RegionForge", 0)
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
    "ucs_data.lua",
    "ucs.lua",
    "wildcards.lua",
    "wav_writer.lua",
    "regions.lua",
    "render_direct.lua",
    "render.lua",
    "gui.lua",
}) do
    if not load_module(m) then return end
end

gui_start()
