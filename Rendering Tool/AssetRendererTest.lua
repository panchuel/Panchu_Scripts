--@description Region Creator
--@version 1.0
--@author Panchu
--@provides [main] .

local reaper = reaper

-- ============================================
-- PART 1: AUDIO TYPES - STRUCTURE AND PERSISTENCE
-- ============================================

local default_audio_types = {
    {
        name = "SFX",
        prefix = "sx",
        wildcard = "$prefix_$root_$parent_",
        config = { bpm = 0, meter = "", character = "", quest_type = "", quest_name = "", line_number = 1 }
    },
    {
        name = "Music",
        prefix = "mx",
        wildcard = "$prefix_$root_$parent_$bpm_$meter_",
        config = { bpm = 120, meter = "4-4", character = "", quest_type = "", quest_name = "", line_number = 1 }
    },
    {
        name = "Dialogue",
        prefix = "dx",
        wildcard = "$prefix_$character_$questtype_$questname_$line_",
        config = { bpm = 0, meter = "", character = "", quest_type = "SQ", quest_name = "", line_number = 1 }
    },
    {
        name = "Environment",
        prefix = "env",
        wildcard = "$prefix_$root_$parent_",
        config = { bpm = 0, meter = "", character = "", quest_type = "", quest_name = "", line_number = 1 }
    }
}

local function load_audio_types()
    local types = {}
    local count = tonumber(reaper.GetExtState("SFX_Renderer", "audio_type_count")) or 0
    if count == 0 then return default_audio_types end

    for i = 1, count do
        local key = "audio_type_" .. i
        local str = reaper.GetExtState("SFX_Renderer", key)
        if str ~= "" then
            local name, prefix, wildcard, config_str

            -- Detect old 6-field format (with base_path and use_hierarchy) vs new 4-field
            local pipe_count = select(2, str:gsub("|", ""))
            if pipe_count >= 5 then
                local _bp, _uh
                name, prefix, _bp, wildcard, _uh, config_str =
                    str:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
            else
                name, prefix, wildcard, config_str =
                    str:match("([^|]*)|([^|]*)|([^|]*)|(.+)")
            end

            if name then
                local config = {}
                for k, v in config_str:gmatch("([^,=]+)=([^,]*)") do
                    if tonumber(v) then config[k] = tonumber(v) else config[k] = v end
                end

                table.insert(types, {
                    name = name,
                    prefix = prefix,
                    wildcard = wildcard,
                    config = config
                })
            end
        end
    end
    return #types > 0 and types or default_audio_types
end

local function save_audio_types(types)
    reaper.SetExtState("SFX_Renderer", "audio_type_count", tostring(#types), true)
    for i, t in ipairs(types) do
        local key = "audio_type_" .. i
        local config_str = ""
        for k, v in pairs(t.config) do
            config_str = config_str .. k .. "=" .. tostring(v) .. ","
        end
        config_str = config_str:gsub(",$", "")

        local str = string.format("%s|%s|%s|%s",
            t.name, t.prefix, t.wildcard, config_str)
        reaper.SetExtState("SFX_Renderer", key, str, true)
    end
end

local audio_types = load_audio_types()
local selected_type_idx = 1

-- ============================================
-- PART 2: SETTINGS AND GLOBAL VARIABLES
-- ============================================

local default_settings = {
    prefix = "sx",
    prefix_type = "sx",
    variations = 0,
    separation_time = 1.0,
    randomize_position = 0.0,
    wildcard_template = "$region",
    music_bpm = 120,
    music_meter = "4-4",
    dx_character = "",
    dx_quest_type = "SQ",
    dx_quest_name = "",
    dx_line_number = 1,
    volume_enable = false,
    volume_amount = 3.0,
    pan_enable = false,
    pan_amount = 0.1,
    pitch_enable = false,
    pitch_amount = 0.5,
    rate_enable = false,
    rate_amount = 0.1,
    length_enable = false,
    length_amount = 0.1,
    fadein_enable = false,
    fadein_amount = 0.1,
    fadeout_enable = false,
    fadeout_amount = 0.1,
    fadeshape_enable = false
}

local function load_settings()
    local settings = {}
    for key, default in pairs(default_settings) do
        local value = reaper.GetExtState("SFX_Renderer", key)
        if value ~= "" then
            if type(default) == "number" then
                settings[key] = tonumber(value) or default
            elseif type(default) == "boolean" then
                settings[key] = (value == "true")
            else
                settings[key] = value
            end
        else
            settings[key] = default
        end
    end
    return settings
end

local function save_settings(settings)
    for key, value in pairs(settings) do
        if type(value) == "boolean" then
            reaper.SetExtState("SFX_Renderer", key, value and "true" or "false", true)
        else
            reaper.SetExtState("SFX_Renderer", key, tostring(value), true)
        end
    end
end

local settings = load_settings()

-- Global variables
local prefix = settings.prefix
local prefix_type = settings.prefix_type
local valid_tracks = {}
local variations = settings.variations
local separation_time = settings.separation_time
local randomize_position = settings.randomize_position
local wildcard_template = settings.wildcard_template

local music_bpm = settings.music_bpm
local music_meter = settings.music_meter
local dx_character = settings.dx_character
local dx_quest_type = settings.dx_quest_type
local dx_quest_name = settings.dx_quest_name
local dx_line_number = settings.dx_line_number

local random_params = {
    volume   = { enable = settings.volume_enable,   amount = settings.volume_amount },
    pan      = { enable = settings.pan_enable,      amount = settings.pan_amount },
    pitch    = { enable = settings.pitch_enable,    amount = settings.pitch_amount },
    rate     = { enable = settings.rate_enable,     amount = settings.rate_amount },
    position = { enable = true,                     amount = 0.0 },
    length   = { enable = settings.length_enable,   amount = settings.length_amount },
    fadein   = { enable = settings.fadein_enable,   amount = settings.fadein_amount },
    fadeout  = { enable = settings.fadeout_enable,  amount = settings.fadeout_amount },
    fadeshape = { enable = settings.fadeshape_enable, amount = 1 }
}

local slider_ranges = {
    volume   = { min = 0.0, max = 12.0 },
    pan      = { min = 0.0, max = 1.0 },
    pitch    = { min = 0.0, max = 12.0 },
    rate     = { min = 0.0, max = 0.5 },
    position = { min = 0.0, max = 5.0 },
    length   = { min = 0.0, max = 0.5 },
    fadein   = { min = 0.0, max = 1.0 },
    fadeout  = { min = 0.0, max = 1.0 }
}

local ORIGINAL_TAG = "SFX_ORIGINAL"
local VARIATION_TAG = "SFX_VARIATION"
local region_hierarchy_data = {}


-- ============================================
-- PART 3: BASIC AUXILIARY FUNCTIONS
-- ============================================

local function clean_name(name)
    return name:gsub("[^%w_]", "_"):gsub("__+", "_")
end

local function get_track_name(track)
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    return name or "Unnamed"
end

local function get_track_index(track)
    return reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
end

local function get_folder_depth(track)
    return reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
end

local function get_parent_track(track)
    local idx = get_track_index(track)
    if idx == 0 then return nil end

    local current_level = 0
    for i = 0, idx - 1 do
        current_level = current_level + reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, i), "I_FOLDERDEPTH")
    end

    for i = idx - 1, 0, -1 do
        local candidate = reaper.GetTrack(0, i)
        local depth = reaper.GetMediaTrackInfo_Value(candidate, "I_FOLDERDEPTH")

        if depth == 1 then
            local candidate_level = 0
            for j = 0, i - 1 do
                candidate_level = candidate_level + reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, j), "I_FOLDERDEPTH")
            end

            if candidate_level == current_level - 1 then
                return candidate
            end
        end
    end

    return nil
end

local function get_child_tracks(folder_track)
    local child_tracks = {}
    local folder_idx = get_track_index(folder_track)
    local total_tracks = reaper.CountTracks(0)

    for i = folder_idx + 1, total_tracks - 1 do
        local track = reaper.GetTrack(0, i)
        local depth = get_folder_depth(track)
        table.insert(child_tracks, track)
        if depth < 0 then break end
    end

    return child_tracks
end

local function get_direct_child_tracks(folder_track)
    local direct = {}
    local start_idx = get_track_index(folder_track) + 1
    local total = reaper.CountTracks(0)
    local nesting = 0
    for i = start_idx, total - 1 do
        local tr = reaper.GetTrack(0, i)
        local d = get_folder_depth(tr)
        if nesting == 0 then table.insert(direct, tr) end
        nesting = nesting + d
        if nesting < 0 then break end
    end
    return direct
end

local function get_item_notes(item)
    local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    return notes or ""
end

local function set_item_notes(item, notes)
    reaper.GetSetMediaItemInfo_String(item, "P_NOTES", notes, true)
end

local function is_original_item(item)
    local notes = get_item_notes(item)
    return notes:find(ORIGINAL_TAG) and not notes:find(VARIATION_TAG)
end

local function is_variation_item(item)
    local notes = get_item_notes(item)
    return notes:find(VARIATION_TAG)
end

local function mark_original_items(folder_track)
    local child_tracks = get_child_tracks(folder_track)
    for _, child in ipairs(child_tracks) do
        for k = 0, reaper.CountTrackMediaItems(child) - 1 do
            local item = reaper.GetTrackMediaItem(child, k)
            if not is_original_item(item) and not is_variation_item(item) then
                local current_notes = get_item_notes(item)
                set_item_notes(item, current_notes .. " " .. ORIGINAL_TAG)
            end
        end
    end
end

local function apply_random_parameters(new_item, new_take, original_item, original_take)
    if random_params.volume.enable and random_params.volume.amount > 0 then
        local vol_db = (math.random() * 2 - 1) * random_params.volume.amount
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_VOL", 10^(vol_db / 20))
    end

    if random_params.pan.enable and random_params.pan.amount > 0 then
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_PAN",
            (math.random() * 2 - 1) * random_params.pan.amount)
    end

    if random_params.pitch.enable and random_params.pitch.amount > 0 then
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_PITCH",
            (math.random() * 2 - 1) * random_params.pitch.amount)
    end

    if random_params.rate.enable and random_params.rate.amount > 0 then
        local rate_factor = 1.0 + (math.random() * 2 - 1) * random_params.rate.amount
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_PLAYRATE", rate_factor)
        local length = reaper.GetMediaItemInfo_Value(new_item, "D_LENGTH")
        reaper.SetMediaItemInfo_Value(new_item, "D_LENGTH", length / rate_factor)
    end

    if random_params.length.enable and random_params.length.amount > 0 then
        local length_factor = 1.0 + (math.random() * 2 - 1) * random_params.length.amount
        local length = reaper.GetMediaItemInfo_Value(new_item, "D_LENGTH")
        reaper.SetMediaItemInfo_Value(new_item, "D_LENGTH", length * length_factor)
    end

    if random_params.fadein.enable and random_params.fadein.amount > 0 then
        local fadein_len = reaper.GetMediaItemInfo_Value(new_item, "D_FADEINLEN")
        local fadein_factor = 1.0 + (math.random() * 2 - 1) * random_params.fadein.amount
        reaper.SetMediaItemInfo_Value(new_item, "D_FADEINLEN", fadein_len * fadein_factor)
    end

    if random_params.fadeout.enable and random_params.fadeout.amount > 0 then
        local fadeout_len = reaper.GetMediaItemInfo_Value(new_item, "D_FADEOUTLEN")
        local fadeout_factor = 1.0 + (math.random() * 2 - 1) * random_params.fadeout.amount
        reaper.SetMediaItemInfo_Value(new_item, "D_FADEOUTLEN", fadeout_len * fadeout_factor)
    end

    if random_params.fadeshape.enable then
        local shapes = { 0, 1, 2, 3 }
        local new_shape = shapes[math.random(1, #shapes)]
        reaper.SetMediaItemInfo_Value(new_item, "C_FADEINSHAPE", new_shape)
        reaper.SetMediaItemInfo_Value(new_item, "C_FADEOUTSHAPE", new_shape)
    end
end

-- ============================================
-- PART 4: HIERARCHIES AND AUTO-CORRECTION
-- ============================================

local function get_region_id(index)
    local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(index)
    if not isrgn then return nil end
    return string.format("%.10f_%.10f", pos, rgnend)
end

local function update_region_hierarchy(region_index, root, parent)
    local region_id = get_region_id(region_index)
    if region_id then
        region_hierarchy_data[region_id] = { root = root, parent = parent }
        return true
    end
    return false
end

local function get_region_hierarchy(region_index)
    local region_id = get_region_id(region_index)
    if region_id and region_hierarchy_data[region_id] then
        return region_hierarchy_data[region_id]
    end

    local _, isrgn, _, _, name, _ = reaper.EnumProjectMarkers(region_index)
    if isrgn then
        local root, parent = name:match("^%w+_([^_]+)_([^_]+)_$")
        if root and parent then
            return { root = root, parent = parent }
        end
    end

    return { root = "General", parent = "Parent" }
end

local function auto_migrate_regions()
    local marker_count = reaper.CountProjectMarkers(0)
    local migrated = 0

    for i = 0, marker_count - 1 do
        local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(i)
        if isrgn then
            local region_id = get_region_id(i)
            if not region_hierarchy_data[region_id] then
                local root, parent = name:match("^%w+_([^_]+)_([^_]+)_$")
                if root and parent then
                    update_region_hierarchy(i, root, parent)
                    migrated = migrated + 1
                end
            end
        end
    end

    return migrated
end

local function auto_update_renamed_regions()
    local marker_count = reaper.CountProjectMarkers(0)
    local updated = 0

    for i = 0, marker_count - 1 do
        local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(i)
        if isrgn then
            local region_id = get_region_id(i)
            local stored_data = region_hierarchy_data[region_id]

            if stored_data then
                local expected_pattern = string.format("^%s_%s_%s_$",
                    prefix_type, stored_data.root, stored_data.parent)

                if not name:match(expected_pattern) then
                    local new_root, new_parent = name:match("^%w+_([^_]+)_([^_]+)_$")
                    if new_root and new_parent then
                        update_region_hierarchy(i, new_root, new_parent)
                        updated = updated + 1
                    end
                end
            end
        end
    end

    return updated
end

-- ============================================
-- PART 5: UPDATE CONFIG FROM SELECTED TYPE
-- ============================================

local function sync_config_from_audio_type()
    local current_type = audio_types[selected_type_idx]
    if current_type then
        prefix = current_type.prefix
        prefix_type = current_type.prefix
        wildcard_template = current_type.wildcard
        music_bpm = current_type.config.bpm or 120
        music_meter = current_type.config.meter or "4-4"
        dx_character = current_type.config.character or ""
        dx_quest_type = current_type.config.quest_type or "SQ"
        dx_quest_name = current_type.config.quest_name or ""
        dx_line_number = current_type.config.line_number or 1
    end
end

local function sync_config_to_audio_type()
    local current_type = audio_types[selected_type_idx]
    if current_type then
        current_type.wildcard          = wildcard_template
        current_type.config.bpm        = music_bpm
        current_type.config.meter      = music_meter
        current_type.config.character  = dx_character
        current_type.config.quest_type = dx_quest_type
        current_type.config.quest_name = dx_quest_name
        current_type.config.line_number = dx_line_number
    end
end

-- ============================================
-- PART 6: WILDCARD EXPANSION
-- ============================================

local function expand_wildcards(pattern, prefix, root, parent)
    local questname_val = dx_quest_name ~= "" and dx_quest_name or parent
    local char_val      = dx_character  ~= "" and dx_character  or "unknown"
    local questtype_val = dx_quest_type ~= "" and dx_quest_type or "SQ"
    return pattern
        :gsub("%$prefix",    prefix)
        :gsub("%$root",      root)
        :gsub("%$parent",    parent)
        :gsub("%$bpm",       tostring(music_bpm))
        :gsub("%$meter",     music_meter)
        :gsub("%$character", char_val)
        :gsub("%$questtype", questtype_val)
        :gsub("%$questname", questname_val)
        :gsub("%$line",      string.format("%02d", dx_line_number))
        :gsub("%$region",    parent)   -- legacy alias for $parent
end

-- ============================================
-- PART 7: FOLDER STRUCTURE DETECTION
-- ============================================

local function calculate_folder_time_range(folder_track)
    local min_start = math.huge
    local max_end = 0

    for _, child in ipairs(get_child_tracks(folder_track)) do
        for k = 0, reaper.CountTrackMediaItems(child) - 1 do
            local item = reaper.GetTrackMediaItem(child, k)
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            min_start = math.min(min_start, pos)
            max_end = math.max(max_end, pos + len)
        end
    end

    return min_start, max_end
end

local function is_valid_parent_folder(track)
    if get_folder_depth(track) ~= 1 then return false end
    for _, child in ipairs(get_child_tracks(track)) do
        if reaper.CountTrackMediaItems(child) > 0 then return true end
    end
    return false
end

local function create_regions_from_folder_structure()
    local sel_count = reaper.CountSelectedTracks(0)
    if sel_count == 0 then
        reaper.ShowMessageBox("Select parent folders first.", "No Selection", 0)
        return 0
    end

    local audio_type = audio_types[selected_type_idx] or { prefix = "sx", wildcard = "$region" }
    local total_regions = 0

    for i = 0, sel_count - 1 do
        local folder_track = reaper.GetSelectedTrack(0, i)
        if not is_valid_parent_folder(folder_track) then goto continue end

        mark_original_items(folder_track)

        local folder_name = clean_name(get_track_name(folder_track))
        local root_name

        local parent_folder = get_parent_track(folder_track)
        if parent_folder then
            root_name = clean_name(get_track_name(parent_folder))
        else
            local _, project_name = reaper.EnumProjects(-1, "")
            root_name = project_name:match("([^\\/]+)$"):gsub("%..+$", "") or "Project"
        end

        local min_start, max_end = calculate_folder_time_range(folder_track)
        if min_start == math.huge or max_end == 0 then goto continue end

        local region_name = expand_wildcards(audio_type.wildcard, audio_type.prefix, root_name, folder_name)

        local region_index = reaper.AddProjectMarker2(0, true, min_start, max_end, region_name, -1, 0)
        update_region_hierarchy(region_index, root_name, folder_name)

        table.insert(valid_tracks, {
            name = region_name,
            start = min_start,
            end_pos = max_end,
            variation = 1
        })

        total_regions = total_regions + 1
        ::continue::
    end

    return total_regions
end

-- ============================================
-- PART 8: REGION CREATION ACTIONS
-- ============================================

local function create_regions()
    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()

    if not audio_types[selected_type_idx] then
        reaper.ShowMessageBox("Error: No audio type selected.", "Invalid Selection", 0)
        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock("Create Regions", -1)
        return
    end

    sync_config_to_audio_type()

    local total_regions = create_regions_from_folder_structure()

    if total_regions > 0 then
        reaper.ShowMessageBox(
            string.format("Created %d region(s).", total_regions),
            "Regions Created", 0)
    end

    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Create Regions", -1)
end

local function update_selected_region_hierarchy()
    local marker_count = reaper.CountProjectMarkers(0)
    local sel_region = nil

    local pos = reaper.GetCursorPosition()
    for i = 0, marker_count - 1 do
        local _, isrgn, rgnpos, rgnend, name, _ = reaper.EnumProjectMarkers(i)
        if isrgn and pos >= rgnpos and pos <= rgnend then
            sel_region = { index = i, name = name }
            break
        end
    end

    if not sel_region then
        reaper.ShowMessageBox("Place cursor inside a region to update it.", "Region not detected", 0)
        return
    end

    local current_hierarchy = get_region_hierarchy(sel_region.index)
    local retval, user_input = reaper.GetUserInputs("Update Hierarchy", 2,
        "Root,Parent:", current_hierarchy.root .. "," .. current_hierarchy.parent)

    if retval then
        local root, parent = user_input:match("([^,]+),([^,]+)")
        if root and parent then
            root   = root:match("^%s*(.-)%s*$")
            parent = parent:match("^%s*(.-)%s*$")
            if update_region_hierarchy(sel_region.index, root, parent) then
                reaper.ShowMessageBox("Hierarchy updated:\nRoot: " .. root .. "\nParent: " .. parent,
                    "Update Successful", 0)
            else
                reaper.ShowMessageBox("Error updating hierarchy.", "Error", 0)
            end
        else
            reaper.ShowMessageBox("Incorrect format. Use: root,parent", "Error", 0)
        end
    end
end

-- ============================================
-- PART 9: GUI (Lokasenna_GUI v2)
-- ============================================

local lib_path = reaper.GetExtState("Lokasenna_GUI", "lib_path_v2")
if not lib_path or lib_path == "" then
    reaper.MB(
        "Couldn't load Lokasenna_GUI v2.\n\n" ..
        "Please run:\nScripts > ReaTeam Scripts > Development >\n" ..
        "Lokasenna_GUI v2 > Library > Set Lokasenna_GUI v2 library path.lua",
        "Region Creator", 0)
    return
end
loadfile(lib_path .. "Core.lua")()
GUI.req(lib_path .. "Classes/Class - Button.lua")()
GUI.req(lib_path .. "Classes/Class - Tabs.lua")()
GUI.req(lib_path .. "Classes/Class - Menubox.lua")()
GUI.req(lib_path .. "Classes/Class - Textbox.lua")()
GUI.req(lib_path .. "Classes/Class - Label.lua")()
GUI.req(lib_path .. "Classes/Class - Frame.lua")()

if missing_lib then return 0 end

-- Hide built-in Lokasenna version watermark; we draw our own footer
GUI.version = 0

GUI.Draw_Version = function()
    local str = "Region Creator v1.0  \xe2\x80\x94  by Panchuel"
    GUI.font(4)
    GUI.color("txt")
    local str_w, str_h = gfx.measurestr(str)
    gfx.x = math.floor((gfx.w - str_w) / 2)
    gfx.y = gfx.h - str_h - 4
    gfx.drawstr(str)
end

-- ── Window ───────────────────────────────────────────────────────
GUI.name   = "Region Creator v1.0"
GUI.w, GUI.h = 460, 420
GUI.anchor, GUI.corner = "screen", "C"

-- ── Layout constants ─────────────────────────────────────────────
local LM   = 16                  -- left / right margin
local TW   = GUI.w - LM * 2     -- 428 px content width
local TAB_H = 20
local CY   = TAB_H + 8          -- content start Y = 28

-- ── Z-layer map ──────────────────────────────────────────────────
--  1 = Tabs bar (always visible)
--  2 = Main tab
--  3 = Settings tab
--  4 = Audio Types tab
--  5 = Music-specific (managed manually in GUI.func)
--  6 = Dialogue-specific (managed manually in GUI.func)

-- ── Tabs ─────────────────────────────────────────────────────────
GUI.New("tabs", "Tabs", 1, 0, 0, 148, TAB_H, "Main,Settings,Audio Types", 4)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TAB 1 — MAIN  (z=2)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local y = CY

GUI.New("lbl_atype", "Label", 2, LM, y + 5, "Audio Type:", false, 3)

local _type_names = {}
for _, t in ipairs(audio_types) do _type_names[#_type_names + 1] = t.name end
GUI.New("sel_type", "Menubox", 2, LM + 96, y, TW - 96, 24, "",
    table.concat(_type_names, ","))

y = y + 36

-- Track hierarchy tree view
GUI.New("lbl_tree_hdr", "Label", 2, LM, y + 4, "Hierarchy:", false, 3)
for _i = 0, 5 do
    GUI.New("lbl_tr" .. _i, "Label", 2, LM + 6, y + 24 + _i * 16, "", false, 4)
end
y = y + 116

GUI.New("btn_create", "Button", 2, LM, y, TW, 48, "Create Regions",
    function() reaper.defer(create_regions) end)
y = y + 60

GUI.New("btn_hierarchy", "Button", 2, LM, y, TW, 34, "Update Hierarchy",
    function() reaper.defer(update_selected_region_hierarchy) end)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TAB 2 — SETTINGS  (z=3)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
y = CY

GUI.New("lbl_atype_s", "Label",   3, LM,        y + 5,  "Audio Type:", false, 3)
GUI.New("sel_type_s",  "Menubox", 3, LM + 96,   y, TW - 96, 24, "", table.concat(_type_names, ","))
y = y + 36

GUI.New("lbl_pattern_hdr", "Label", 3, LM, y, "Pattern:", false, 3)
y = y + 22
GUI.New("txt_pattern", "Textbox", 3, LM, y, TW, 24, "", 4)
y = y + 32

local _wildcards = {
    "$prefix    -  Type prefix  (sx, mx, dx, env)",
    "$root      -  Root folder name",
    "$parent    -  Parent / folder name",
    "$bpm       -  BPM  (Music)",
    "$meter     -  Meter  (Music)",
    "$character -  Character  (Dialogue)",
    "$questtype -  Quest type  (Dialogue)",
    "$questname -  Quest name  (Dialogue)",
    "$line      -  Line number  01, 02 ...  (Dialogue)",
}
for i, wc in ipairs(_wildcards) do
    GUI.New("lbl_wc" .. i, "Label", 3, LM + 8, y, wc, false, 4)
    y = y + 14
end

y = y + 6
GUI.New("frm_sep", "Frame", 3, LM, y, TW, 2, false, true, "elm_frame", 0)
y = y + 14

GUI.New("lbl_type_cfg", "Label", 3, LM, y, "Type settings:", false, 3)
y = y + 26

local TS_Y = y   -- anchor Y for type-specific sections

-- ── Music settings  (z=5) ────────────────────────────────────────
GUI.New("lbl_bpm",   "Label",   5, LM,        TS_Y + 4,  "BPM:",   false, 3)
GUI.New("txt_bpm",   "Textbox", 5, LM + 52,   TS_Y,       90, 24,  "", 4)
GUI.New("lbl_meter", "Label",   5, LM + 156,  TS_Y + 4,  "Meter:", false, 3)
GUI.New("txt_meter", "Textbox", 5, LM + 212,  TS_Y,       90, 24,  "", 4)

-- ── Dialogue settings  (z=6) ─────────────────────────────────────
GUI.New("lbl_char",  "Label",   6, LM,        TS_Y + 4,   "Character:",  false, 3)
GUI.New("txt_char",  "Textbox", 6, LM + 98,   TS_Y,        TW - 98, 24, "", 4)
GUI.New("lbl_qtype", "Label",   6, LM,        TS_Y + 34,  "Quest Type:", false, 3)
GUI.New("txt_qtype", "Textbox", 6, LM + 98,   TS_Y + 30,   TW - 98, 24, "", 4)
GUI.New("lbl_qname", "Label",   6, LM,        TS_Y + 64,  "Quest Name:", false, 3)
GUI.New("txt_qname", "Textbox", 6, LM + 98,   TS_Y + 60,   TW - 98, 24, "", 4)
GUI.New("lbl_line",  "Label",   6, LM,        TS_Y + 94,  "Line:",       false, 3)
GUI.New("txt_line",  "Textbox", 6, LM + 98,   TS_Y + 90,   60,      24, "", 4)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TAB 3 — AUDIO TYPES  (z=4)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
y = CY
for i, at in ipairs(audio_types) do
    GUI.New("lbl_atname" .. i, "Label",   4, LM,        y,      i .. ".  " .. at.name, false, 3)
    y = y + 22
    GUI.New("lbl_atpfx"  .. i, "Label",   4, LM + 16,   y + 4,  "Prefix:",  false, 4)
    GUI.New("txt_atpfx"  .. i, "Textbox", 4, LM + 68,   y,  80, 24, "", 4)
    GUI.New("lbl_atpat"  .. i, "Label",   4, LM + 162,  y + 4,  "Pattern:", false, 4)
    GUI.New("txt_atpat"  .. i, "Textbox", 4, LM + 224,  y,  GUI.w - LM - (LM + 224), 24, "", 4)
    y = y + 32
end

y = y + 8
local BW = math.floor((TW - 8) / 2)

GUI.New("btn_save_types",  "Button", 4, LM,          y, BW, 30, "Save Audio Types", function()
    for i = 1, #audio_types do
        audio_types[i].prefix   = GUI.Val("txt_atpfx" .. i) or audio_types[i].prefix
        audio_types[i].wildcard = GUI.Val("txt_atpat" .. i) or audio_types[i].wildcard
    end
    sync_config_to_audio_type()
    save_audio_types(audio_types)
    GUI.Val("txt_pattern", wildcard_template)
    reaper.MB("Audio types saved.", "Saved", 0)
end)

GUI.New("btn_reset_types", "Button", 4, LM + BW + 8, y, BW, 30, "Reset to Defaults", function()
    local ok = reaper.ShowMessageBox("Reset all audio types to default settings?", "Confirm Reset", 4)
    if ok == 6 then
        audio_types = {}
        for _, dt in ipairs(default_audio_types) do
            local entry = { name = dt.name, prefix = dt.prefix, wildcard = dt.wildcard, config = {} }
            for k, v in pairs(dt.config) do entry.config[k] = v end
            table.insert(audio_types, entry)
        end
        save_audio_types(audio_types)
        selected_type_idx = 1
        sync_config_from_audio_type()
        for i, at in ipairs(audio_types) do
            GUI.Val("txt_atpfx" .. i, at.prefix)
            GUI.Val("txt_atpat" .. i, at.wildcard)
        end
        GUI.Val("txt_pattern", wildcard_template)
        reaper.MB("Audio types reset to defaults.", "Reset Complete", 0)
    end
end)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- UPDATE FUNCTION  (runs every frame)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local _prev_type_idx    = 0
local _prev_tab         = 0
local _prev_type_name   = ""
local _prev_state_count = -1
local _prev_sel_track   = nil

local function refresh_tree_view()
    local L = "\xe2\x94\x94\xe2\x94\x80\xe2\x94\x80 "  -- └──
    local T = "\xe2\x94\x9c\xe2\x94\x80\xe2\x94\x80 "  -- ├──

    local sel = reaper.GetSelectedTrack(0, 0)
    if not sel then
        GUI.Val("lbl_tr0", "  No track selected")
        for i = 1, 5 do GUI.Val("lbl_tr" .. i, "") end
        return
    end

    -- $root = parent of selected (or project name); $parent = selected track
    local parent_name = get_track_name(sel)
    local root_folder = get_parent_track(sel)
    local root_name
    if root_folder then
        root_name = get_track_name(root_folder)
    else
        local _, proj_name = reaper.EnumProjects(-1, "")
        root_name = (proj_name:match("([^\\/]+)$") or "Project"):gsub("%..+$", "")
    end

    -- Collect all descendants that carry items (same set used by Create Regions)
    local all_desc  = get_child_tracks(sel)
    local item_tracks = {}
    for _, tr in ipairs(all_desc) do
        if reaper.CountTrackMediaItems(tr) > 0 then
            table.insert(item_tracks, tr)
        end
    end

    local total    = #item_tracks
    local max_show = 3

    GUI.Val("lbl_tr0", "Root   " .. root_name)
    GUI.Val("lbl_tr1", "  " .. L .. parent_name)

    if total == 0 then
        GUI.Val("lbl_tr2", "        " .. L .. "(no items)")
        for i = 3, 5 do GUI.Val("lbl_tr" .. i, "") end
        return
    end

    local show = math.min(max_show, total)
    for i = 1, show do
        local cname     = get_track_name(item_tracks[i])
        local n         = reaper.CountTrackMediaItems(item_tracks[i])
        local connector = (i == total and total <= max_show) and L or T
        GUI.Val("lbl_tr" .. (i + 1), "        " .. connector .. cname .. "   [" .. n .. " items]")
    end

    for i = show + 2, 5 do GUI.Val("lbl_tr" .. i, "") end

    if total > max_show then
        GUI.Val("lbl_tr5", "           ... " .. (total - max_show) .. " more")
    end
end

GUI.func = function()
    local cur_tab      = GUI.elms.tabs.retval
    local new_type_idx = GUI.Val("sel_type")

    -- Entering Settings tab: sync the secondary type selector
    if cur_tab == 2 and _prev_tab ~= 2 then
        GUI.Val("sel_type_s", selected_type_idx)
    end

    -- Active type index: Settings tab has its own selector
    local effective_idx = (cur_tab == 2) and GUI.Val("sel_type_s") or new_type_idx

    -- ── Leaving Settings tab: persist pattern and type-specific values ──
    if _prev_tab == 2 and cur_tab ~= 2 then
        wildcard_template = GUI.Val("txt_pattern") or wildcard_template
        if audio_types[selected_type_idx] then
            audio_types[selected_type_idx].wildcard = wildcard_template
        end
        music_bpm      = tonumber(GUI.Val("txt_bpm"))   or music_bpm
        music_meter    = GUI.Val("txt_meter")            or music_meter
        dx_character   = GUI.Val("txt_char")             or dx_character
        dx_quest_type  = GUI.Val("txt_qtype")            or dx_quest_type
        dx_quest_name  = GUI.Val("txt_qname")            or dx_quest_name
        dx_line_number = tonumber(GUI.Val("txt_line"))   or dx_line_number
    end

    -- ── Audio type changed (either selector) ─────────────────────────
    if effective_idx ~= _prev_type_idx and _prev_type_idx > 0 then
        sync_config_to_audio_type()
        selected_type_idx = effective_idx
        sync_config_from_audio_type()
        GUI.Val("sel_type",   selected_type_idx)
        GUI.Val("sel_type_s", selected_type_idx)
        -- Refresh Settings tab fields
        GUI.Val("txt_pattern", wildcard_template)
        GUI.Val("txt_bpm",     tostring(music_bpm))
        GUI.Val("txt_meter",   music_meter)
        GUI.Val("txt_char",    dx_character)
        GUI.Val("txt_qtype",   dx_quest_type)
        GUI.Val("txt_qname",   dx_quest_name)
        GUI.Val("txt_line",    tostring(dx_line_number))
    end

    -- ── Type-specific layer visibility ────────────────────────────────
    local on_settings = (cur_tab == 2)
    local type_name   = audio_types[selected_type_idx] and audio_types[selected_type_idx].name or ""

    GUI.elms_hide[5] = not (on_settings and type_name == "Music")
    GUI.elms_hide[6] = not (on_settings and type_name == "Dialogue")

    -- ── Update "Type settings:" label text ───────────────────────────
    if type_name ~= _prev_type_name then
        if     type_name == "Music"    then GUI.Val("lbl_type_cfg", "Music settings:")
        elseif type_name == "Dialogue" then GUI.Val("lbl_type_cfg", "Dialogue settings:")
        else                                GUI.Val("lbl_type_cfg", "No type-specific settings") end
        _prev_type_name = type_name
    end

    -- ── Tree view: refresh on project state OR selection change ──────
    local sc      = reaper.GetProjectStateChangeCount(0)
    local cur_sel = reaper.GetSelectedTrack(0, 0)
    if sc ~= _prev_state_count or cur_sel ~= _prev_sel_track then
        refresh_tree_view()
        _prev_state_count = sc
        _prev_sel_track   = cur_sel
    end

    _prev_type_idx = effective_idx
    _prev_tab      = cur_tab
end

GUI.freq = 0   -- run every frame

-- ── Exit: persist all values ─────────────────────────────────────
GUI.exit = function()
    wildcard_template  = GUI.Val("txt_pattern")  or wildcard_template
    music_bpm          = tonumber(GUI.Val("txt_bpm"))   or music_bpm
    music_meter        = GUI.Val("txt_meter")    or music_meter
    dx_character       = GUI.Val("txt_char")     or dx_character
    dx_quest_type      = GUI.Val("txt_qtype")    or dx_quest_type
    dx_quest_name      = GUI.Val("txt_qname")    or dx_quest_name
    dx_line_number     = tonumber(GUI.Val("txt_line"))  or dx_line_number

    for i = 1, #audio_types do
        audio_types[i].prefix   = GUI.Val("txt_atpfx" .. i) or audio_types[i].prefix
        audio_types[i].wildcard = GUI.Val("txt_atpat" .. i) or audio_types[i].wildcard
    end

    if audio_types[selected_type_idx] then
        audio_types[selected_type_idx].wildcard = wildcard_template
    end
    sync_config_to_audio_type()

    save_settings({
        wildcard_template = wildcard_template,
        prefix_type       = prefix_type,
        music_bpm         = music_bpm,
        music_meter       = music_meter,
        dx_character      = dx_character,
        dx_quest_type     = dx_quest_type,
        dx_quest_name     = dx_quest_name,
        dx_line_number    = dx_line_number,
    })
    save_audio_types(audio_types)
end

-- ── Entry point ──────────────────────────────────────────────────
local function script()
    GUI.Init()

    -- Initial values
    GUI.Val("sel_type",    selected_type_idx)
    GUI.Val("sel_type_s",  selected_type_idx)
    GUI.Val("txt_pattern", wildcard_template)
    GUI.Val("txt_bpm",     tostring(music_bpm))
    GUI.Val("txt_meter",   music_meter)
    GUI.Val("txt_char",    dx_character)
    GUI.Val("txt_qtype",   dx_quest_type)
    GUI.Val("txt_qname",   dx_quest_name)
    GUI.Val("txt_line",    tostring(dx_line_number))

    for i, at in ipairs(audio_types) do
        GUI.Val("txt_atpfx" .. i, at.prefix)
        GUI.Val("txt_atpat" .. i, at.wildcard)
    end

    -- Assign layers to tabs  (z=5 and z=6 managed manually)
    GUI.elms.tabs:update_sets({ {2}, {3}, {4} })

    -- Hide type-specific layers initially
    GUI.elms_hide[5] = true
    GUI.elms_hide[6] = true

    _prev_type_idx = selected_type_idx

    refresh_tree_view()

    reaper.defer(GUI.Main)
end

xpcall(script, GUI.crash)
