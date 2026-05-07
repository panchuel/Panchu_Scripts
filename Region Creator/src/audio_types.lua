-- Serialization format history:
--   v1 (3 pipes):  name|prefix|wildcard|config
--   v2 (5 pipes):  name|prefix|bp|wildcard|uh|config  (legacy, unused fields)
--   v3 (4 pipes):  name|prefix|wildcard|path_pattern|config  ← current
local DEFAULT_PATH = "{base}/$prefix/$root/$parent/"

function load_audio_types()
    local types = {}
    local count = tonumber(reaper.GetExtState(RC.EXT_KEY, "audio_type_count")) or 0
    if count == 0 then return RC.default_audio_types end

    for i = 1, count do
        local str = reaper.GetExtState(RC.EXT_KEY, "audio_type_" .. i)
        if str ~= "" then
            local name, prefix, wildcard, path_pattern, config_str
            local def_path = (RC.default_audio_types[i] or {}).path_pattern or DEFAULT_PATH
            local pipe_count = select(2, str:gsub("|", ""))

            if pipe_count >= 5 then
                -- v2 legacy: discard bp and uh fields
                local _bp, _uh
                name, prefix, _bp, wildcard, _uh, config_str =
                    str:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
                path_pattern = def_path
            elseif pipe_count == 4 then
                -- v3 current: includes path_pattern
                name, prefix, wildcard, path_pattern, config_str =
                    str:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
            else
                -- v1: no path_pattern
                name, prefix, wildcard, config_str =
                    str:match("([^|]*)|([^|]*)|([^|]*)|(.+)")
                path_pattern = def_path
            end

            if name then
                local config = {}
                for k, v in config_str:gmatch("([^,=]+)=([^,]*)") do
                    config[k] = tonumber(v) or v
                end
                table.insert(types, {
                    name         = name,
                    prefix       = prefix,
                    wildcard     = wildcard,
                    path_pattern = path_pattern,
                    config       = config,
                })
            end
        end
    end
    return #types > 0 and types or RC.default_audio_types
end

function save_audio_types(types)
    reaper.SetExtState(RC.EXT_KEY, "audio_type_count", tostring(#types), true)
    for i, t in ipairs(types) do
        local cfg = ""
        for k, v in pairs(t.config) do cfg = cfg .. k .. "=" .. tostring(v) .. "," end
        -- v3 format: name|prefix|wildcard|path_pattern|config
        reaper.SetExtState(RC.EXT_KEY, "audio_type_" .. i,
            string.format("%s|%s|%s|%s|%s",
                t.name, t.prefix, t.wildcard,
                t.path_pattern or DEFAULT_PATH,
                cfg:gsub(",$", "")), true)
    end
end

function sync_config_from_audio_type()
    local t = RC.audio_types[RC.selected_type_idx]
    if not t then return end
    RC.prefix            = t.prefix
    RC.prefix_type       = t.prefix
    RC.wildcard_template = t.wildcard
    RC.music_bpm         = t.config.bpm         or 120
    RC.music_meter       = t.config.meter        or "4-4"
    RC.dx_character      = t.config.character    or ""
    RC.dx_quest_type     = t.config.quest_type   or "SQ"
    RC.dx_quest_name     = t.config.quest_name   or ""
    RC.dx_line_number    = t.config.line_number  or 1
end

function sync_config_to_audio_type()
    local t = RC.audio_types[RC.selected_type_idx]
    if not t then return end
    t.wildcard           = RC.wildcard_template
    t.config.bpm         = RC.music_bpm
    t.config.meter       = RC.music_meter
    t.config.character   = RC.dx_character
    t.config.quest_type  = RC.dx_quest_type
    t.config.quest_name  = RC.dx_quest_name
    t.config.line_number = RC.dx_line_number
end

RC.audio_types       = load_audio_types()
RC.selected_type_idx = 1
