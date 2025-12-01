--@description SFX Renderer Simplified with Improved UX
--@version 4.0
--@author Panchu
--@provides [main] .

local reaper = reaper
local ctx = reaper.ImGui_CreateContext('SFX Renderer v4.0')
local font = reaper.ImGui_CreateFont('sans-serif', 16)
reaper.ImGui_Attach(ctx, font)

-- ============================================
-- PART 1: AUDIO TYPES - STRUCTURE AND PERSISTENCE
-- ============================================

local default_audio_types = {
    {
        name = "SFX",
        prefix = "sx",
        base_path = "Renders/SFX/",
        wildcard = "$region",
        config = { bpm = 0, meter = "", character = "", quest_type = "", quest_name = "", line_number = 1 }
    },
    {
        name = "Music",
        prefix = "mx",
        base_path = "Renders/Music/",
        wildcard = "$region",
        config = { bpm = 120, meter = "4-4", character = "", quest_type = "", quest_name = "", line_number = 1 }
    },
    {
        name = "Dialogue",
        prefix = "dx",
        base_path = "Renders/Dialogue/",
        wildcard = "$region",
        config = { bpm = 0, meter = "", character = "", quest_type = "SQ", quest_name = "", line_number = 1 }
    },
    {
        name = "Environment",
        prefix = "env",
        base_path = "Renders/Environment/",
        wildcard = "$region",
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
            local name, prefix, base_path, wildcard, config_str = str:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")

            if name then
                local config = {}
                for k, v in config_str:gmatch("([^,=]+)=([^,]*)") do
                    if tonumber(v) then config[k] = tonumber(v) else config[k] = v end
                end
                table.insert(types, {
                    name = name,
                    prefix = prefix,
                    base_path = base_path,
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
        local str = string.format("%s|%s|%s|%s|%s", t.name, t.prefix, t.base_path, t.wildcard, config_str)
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
    custom_output_path = "",
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
    fadeshape_enable = false,
    auto_detect_silence = true,
    silence_threshold = -40.0,
    min_silence_length = 0.1
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

-- Variables globales - ahora vinculadas al tipo seleccionado
local prefix = settings.prefix
local prefix_type = settings.prefix_type
local valid_tracks = {}
local variations = settings.variations
local separation_time = settings.separation_time
local randomize_position = settings.randomize_position
local wildcard_template = settings.wildcard_template
local custom_output_path = settings.custom_output_path
local auto_detect_silence = settings.auto_detect_silence
local silence_threshold = settings.silence_threshold
local min_silence_length = settings.min_silence_length

-- Configuraciones específicas por tipo
local music_bpm = settings.music_bpm
local music_meter = settings.music_meter
local dx_character = settings.dx_character
local dx_quest_type = settings.dx_quest_type
local dx_quest_name = settings.dx_quest_name
local dx_line_number = settings.dx_line_number

local random_params = {
    volume = {enable = settings.volume_enable, amount = settings.volume_amount},
    pan = {enable = settings.pan_enable, amount = settings.pan_amount},
    pitch = {enable = settings.pitchEnable, amount = settings.pitch_amount},
    rate = {enable = settings.rate_enable, amount = settings.rate_amount},
    position = {enable = true, amount = 0.0},
    length = {enable = settings.length_enable, amount = settings.length_amount},
    fadein = {enable = settings.fadein_enable, amount = settings.fadein_amount},
    fadeout = {enable = settings.fadeout_enable, amount = settings.fadeout_amount},
    fadeshape = {enable = settings.fadeshape_enable, amount = 1}
}

local slider_ranges = {
    volume = {min = 0.0, max = 12.0},
    pan = {min = 0.0, max = 1.0},
    pitch = {min = 0.0, max = 12.0},
    rate = {min = 0.0, max = 0.5},
    position = {min = 0.0, max = 5.0},
    length = {min = 0.0, max = 0.5},
    fadein = {min = 0.0, max = 1.0},
    fadeout = {min = 0.0, max = 1.0}
}

local ORIGINAL_TAG = "SFX_ORIGINAL"
local VARIATION_TAG = "SFX_VARIATION"
local region_hierarchy_data = {}

-- Variables de UI
local show_settings = false
local show_variation_params = false
local show_audio_types_editor = false

-- ============================================
-- PART 2: BASIC AUXILIARY FUNCTIONS
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

local function is_valid_subfolder(track)
    if get_folder_depth(track) ~= 1 then return false end
    local child_tracks = get_child_tracks(track)
    return #child_tracks > 0
end

local function apply_random_parameters(new_item, new_take, original_item, original_take)
    if random_params.volume.enable and random_params.volume.amount > 0 then
        local vol_db = (math.random() * 2 - 1) * random_params.volume.amount
        local vol_linear = 10^(vol_db / 20)
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_VOL", vol_linear)
    end
    
    if random_params.pan.enable and random_params.pan.amount > 0 then
        local pan_val = (math.random() * 2 - 1) * random_params.pan.amount
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_PAN", pan_val)
    end
    
    if random_params.pitch.enable and random_params.pitch.amount > 0 then
        local pitch_offset = (math.random() * 2 - 1) * random_params.pitch.amount
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_PITCH", pitch_offset)
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
        local shapes = {0, 1, 2, 3}
        local new_shape = shapes[math.random(1, #shapes)]
        reaper.SetMediaItemInfo_Value(new_item, "C_FADEINSHAPE", new_shape)
        reaper.SetMediaItemInfo_Value(new_item, "C_FADEOUTSHAPE", new_shape)
    end
end

-- ============================================
-- PART 3: HIERARCHIES AND AUTO-CORRECTION
-- ============================================

local function get_region_id(index)
    local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(index)
    if not isrgn then return nil end
    return string.format("%.10f_%.10f", pos, rgnend)
end

local function update_region_hierarchy(region_index, root, parent)
    local region_id = get_region_id(region_index)
    if region_id then
        region_hierarchy_data[region_id] = {root = root, parent = parent}
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
        local root, parent = name:match("^%w+_([^_]+)_([^_]+)_%d+$")
        if root and parent then
            return {root = root, parent = parent}
        end
    end
    
    return {root = "General", parent = "Parent"}
end

local function auto_migrate_regions()
    local marker_count = reaper.CountProjectMarkers(0)
    local migrated = 0
    
    for i = 0, marker_count - 1 do
        local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(i)
        if isrgn then
            local region_id = get_region_id(i)
            
            if not region_hierarchy_data[region_id] then
                local root, parent = name:match("^%w+_([^_]+)_([^_]+)_%d+$")
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
                local expected_pattern = string.format("^%s_%s_%s_%%d+$", 
                    prefix_type, stored_data.root, stored_data.parent)
                
                if not name:match(expected_pattern) then
                    local new_root, new_parent = name:match("^%w+_([^_]+)_([^_]+)_%d+$")
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
-- PART 4: CONTEXT DETECTION
-- ============================================

local function get_selected_regions_manual()
    -- Detectar regiones seleccionadas manualmente en el Region/Marker Manager
    local selected_regions = {}
    local marker_count = reaper.CountProjectMarkers(0)
    
    -- Método 1: Verificar si hay time selection que cubra regiones
    local loop_start, loop_end = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    
    if loop_start ~= loop_end then
        -- Hay time selection, buscar regiones dentro de ese rango
        for i = 0, marker_count - 1 do
            local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(i)
            if isrgn then
                -- Verificar si la región está completamente o parcialmente dentro del time selection
                if (pos >= loop_start and pos < loop_end) or 
                   (rgnend > loop_start and rgnend <= loop_end) or
                   (pos <= loop_start and rgnend >= loop_end) then
                    table.insert(selected_regions, {
                        name = name,
                        start = pos,
                        end_pos = rgnend,
                        index = i
                    })
                end
            end
        end
        
        return selected_regions
    end
    
    -- Método 2: Verificar si hay items seleccionados dentro de regiones específicas
    local sel_items = reaper.CountSelectedMediaItems(0)
    if sel_items > 0 then
        local items_regions = {}
        
        for j = 0, sel_items - 1 do
            local item = reaper.GetSelectedMediaItem(0, j)
            local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_end = item_pos + item_len
            
            -- Encontrar en qué región(es) está este item
            for i = 0, marker_count - 1 do
                local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(i)
                if isrgn then
                    -- Si el item está dentro de esta región
                    if (item_pos >= pos and item_pos < rgnend) or 
                       (item_end > pos and item_end <= rgnend) or
                       (item_pos <= pos and item_end >= rgnend) then
                        
                        local region_id = string.format("%d", i)
                        if not items_regions[region_id] then
                            items_regions[region_id] = {
                                name = name,
                                start = pos,
                                end_pos = rgnend,
                                index = i
                            }
                        end
                    end
                end
            end
        end
        
        -- Convertir tabla asociativa a array
        for _, region in pairs(items_regions) do
            table.insert(selected_regions, region)
        end
        
        -- Ordenar por posición
        table.sort(selected_regions, function(a, b) return a.start < b.start end)
        
        return selected_regions
    end
    
    return selected_regions
end

local function get_render_context()
    local sel_items = reaper.CountSelectedMediaItems(0)
    local sel_tracks = reaper.CountSelectedTracks(0)
    
    -- Prioridad 1: Regiones seleccionadas manualmente (time selection o items en regiones)
    local selected_regions = get_selected_regions_manual()
    if #selected_regions > 0 then
        return "selected_regions", selected_regions
    end
    
    -- Prioridad 2: Items seleccionados (crear región temporal)
    if sel_items > 0 then
        local items = {}
        for i = 0, sel_items - 1 do
            table.insert(items, reaper.GetSelectedMediaItem(0, i))
        end
        return "items", items
    end
    
    -- Prioridad 3: Tracks/carpetas seleccionadas
    if sel_tracks > 0 then
        local tracks = {}
        for i = 0, sel_tracks - 1 do
            table.insert(tracks, reaper.GetSelectedTrack(0, i))
        end
        return "tracks", tracks
    end
    
    -- Prioridad 4: Todo el proyecto
    return "project", nil
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
        current_type.config.bpm = music_bpm
        current_type.config.meter = music_meter
        current_type.config.character = dx_character
        current_type.config.quest_type = dx_quest_type
        current_type.config.quest_name = dx_quest_name
        current_type.config.line_number = dx_line_number
    end
end

-- ============================================
-- PART 6: SILENCE DETECTION
-- ============================================

local function detect_silence_gaps(track)
    local gaps = {}
    local item_count = reaper.CountTrackMediaItems(track)
    
    if item_count == 0 then return gaps end
    
    local items = {}
    for i = 0, item_count - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        table.insert(items, {item = item, pos = pos, end_pos = pos + len})
    end
    
    table.sort(items, function(a, b) return a.pos < b.pos end)
    
    for i = 1, #items - 1 do
        local current_end = items[i].end_pos
        local next_start = items[i + 1].pos
        local gap_length = next_start - current_end
        
        if gap_length >= min_silence_length then
            table.insert(gaps, {
                start = current_end,
                end_pos = next_start,
                length = gap_length
            })
        end
    end
    
    return gaps
end

local function create_regions_from_gaps(track)
    local gaps = detect_silence_gaps(track)
    local track_name = clean_name(get_track_name(track))
    local regions_created = 0
    local root_name = "Project"
    local parent_name = track_name

    local parent_track = get_parent_track(track)
    if parent_track then
        root_name = clean_name(get_track_name(parent_track))
    else
        local _, project_name = reaper.EnumProjects(-1, "")
        root_name = project_name:match("([^\\/]+)$"):gsub("%..+$", "") or "Project"
    end

    if #gaps == 0 then
        local item_count = reaper.CountTrackMediaItems(track)
        if item_count > 0 then
            local min_pos = math.huge
            local max_end = 0
            for i = 0, item_count - 1 do
                local item = reaper.GetTrackMediaItem(track, i)
                local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                min_pos = math.min(min_pos, pos)
                max_end = math.max(max_end, pos + len)
            end
            local region_name = string.format("%s_%s_%s_01", audio_type.prefix, root_name, track_name)
            local region_idx = reaper.AddProjectMarker2(0, true, min_pos, max_end, region_name, -1, 0)
            update_region_hierarchy(region_idx, "Project", track_name)
            regions_created = 1
        end
    else
        local item_count = reaper.CountTrackMediaItems(track)
        local first_item_pos = reaper.GetMediaItemInfo_Value(reaper.GetTrackMediaItem(track, 0), "D_POSITION")
        local region_name = string.format("%s_%s_%s_%02d", audio_type.prefix, root_name, track_name, 1)
        local region_idx = reaper.AddProjectMarker2(0, true, first_item_pos, gaps[1].start, region_name, -1, 0)
        update_region_hierarchy(region_idx, "Project", track_name)
        regions_created = regions_created + 1
        
        for i = 1, #gaps - 1 do
            region_name = string.format("%s_%s_%s_%02d", audio_type.prefix, root_name, track_name, i + 1)
            region_idx = reaper.AddProjectMarker2(0, true, gaps[i].end_pos, gaps[i + 1].start, region_name, -1, 0)
            update_region_hierarchy(region_idx, "Project", track_name)
            regions_created = regions_created + 1
        end
        
        local last_item = reaper.GetTrackMediaItem(track, item_count - 1)
        local last_end = reaper.GetMediaItemInfo_Value(last_item, "D_POSITION") + 
                         reaper.GetMediaItemInfo_Value(last_item, "D_LENGTH")
        
        region_name = string.format("%s_%s_%s_%02d", audio_type.prefix, root_name, track_name, #gaps + 1)
        region_idx = reaper.AddProjectMarker2(0, true, gaps[#gaps].end_pos, last_end, region_name, -1, 0)
        update_region_hierarchy(region_idx, "Project", track_name)
        regions_created = regions_created + 1
    end
    
    return regions_created
end

local function create_regions_with_type(track, audio_type)
    local gaps = detect_silence_gaps(track)
    local track_name = clean_name(get_track_name(track))
    local regions_created = 0
    local root_name = "Project"
    local parent_name = track_name

    local parent_track = get_parent_track(track)
    if parent_track then
        root_name = clean_name(get_track_name(parent_track))
    else
        local _, project_name = reaper.EnumProjects(-1, "")
        root_name = project_name:match("([^\\/]+)$"):gsub("%..+$", "") or "Project"
    end

    if #gaps == 0 then
        local item_count = reaper.CountTrackMediaItems(track)
        if item_count > 0 then
            local min_pos = math.huge
            local max_end = 0
            for i = 0, item_count - 1 do
                local item = reaper.GetTrackMediaItem(track, i)
                local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                min_pos = math.min(min_pos, pos)
                max_end = math.max(max_end, pos + len)
            end
            local region_name = string.format("%s_%s_01", audio_type.prefix, track_name)
            local region_idx = reaper.AddProjectMarker2(0, true, min_pos, max_end, region_name, -1, 0)
            update_region_hierarchy(region_idx, "Project", track_name)
            regions_created = 1
        end
    else
        local item_count = reaper.CountTrackMediaItems(track)
        local first_item_pos = reaper.GetMediaItemInfo_Value(reaper.GetTrackMediaItem(track, 0), "D_POSITION")
        local region_name = string.format("%s_%s_%02d", audio_type.prefix, track_name, 1)
        local region_idx = reaper.AddProjectMarker2(0, true, first_item_pos, gaps[1].start, region_name, -1, 0)
        update_region_hierarchy(region_idx, "Project", track_name)
        regions_created = regions_created + 1
        
        for i = 1, #gaps - 1 do
            region_name = string.format("%s_%s_%02d", audio_type.prefix, track_name, i + 1)
            region_idx = reaper.AddProjectMarker2(0, true, gaps[i].end_pos, gaps[i + 1].start, region_name, -1, 0)
            update_region_hierarchy(region_idx, "Project", track_name)
            regions_created = regions_created + 1
        end
        
        local last_item = reaper.GetTrackMediaItem(track, item_count - 1)
        local last_end = reaper.GetMediaItemInfo_Value(last_item, "D_POSITION") + 
                         reaper.GetMediaItemInfo_Value(last_item, "D_LENGTH")
        
        region_name = string.format("%s_%s_%02d", audio_type.prefix, track_name, #gaps + 1)
        region_idx = reaper.AddProjectMarker2(0, true, gaps[#gaps].end_pos, last_end, region_name, -1, 0)
        update_region_hierarchy(region_idx, "Project", track_name)
        regions_created = regions_created + 1
    end
    
    return regions_created
end

-- ============================================
-- PART 5.5: FOLDER DETECTION AND STRUCTURE
-- ============================================

local function calculate_folder_time_range(folder_track)
    local min_start = math.huge
    local max_end = 0
    local child_tracks = get_child_tracks(folder_track)
    
    for _, child in ipairs(child_tracks) do
        for k = 0, reaper.CountTrackMediaItems(child) - 1 do
            local item = reaper.GetTrackMediaItem(child, k)
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local end_pos = pos + len
            
            min_start = math.min(min_start, pos)
            max_end = math.max(max_end, end_pos)
        end
    end
    
    return min_start, max_end
end

local function is_valid_parent_folder(track)
    if get_folder_depth(track) ~= 1 then return false end
    local child_tracks = get_child_tracks(track)
    
    -- Verificar que haya tracks hijos con items
    for _, child in ipairs(child_tracks) do
        if reaper.CountTrackMediaItems(child) > 0 then
            return true
        end
    end
    
    return false
end

local function create_regions_from_folder_structure()
    local sel_count = reaper.CountSelectedTracks(0)
    
    if sel_count == 0 then
        reaper.ShowMessageBox("Select parent folders first.", "No Selection", 0)
        return 0
    end
    
    local total_regions = 0
    local audio_type = audio_types[selected_type_idx]
    
    for i = 0, sel_count - 1 do
        local folder_track = reaper.GetSelectedTrack(0, i)
        
        if not is_valid_parent_folder(folder_track) then
            goto continue
        end
        
        mark_original_items(folder_track)
        
        local folder_name = clean_name(get_track_name(folder_track))
        local root_name = "Project"
        
        -- Obtener root específico (si esta carpeta es subcarpeta de otra)
        local parent_folder = get_parent_track(folder_track)
        if parent_folder then
            root_name = clean_name(get_track_name(parent_folder))
        else
            local _, project_name = reaper.EnumProjects(-1, "")
            root_name = project_name:match("([^\\/]+)$"):gsub("%..+$", "") or "Project"
        end
        
        local min_start, max_end = calculate_folder_time_range(folder_track)
        
        if min_start == math.huge or max_end == 0 then
            goto continue
        end
        
        -- Construir nombre de región según el tipo de audio
        local region_name
        if audio_type.prefix == "sx" then
            region_name = string.format("%s_%s_%s_01", audio_type.prefix, root_name, folder_name)
        elseif audio_type.prefix == "mx" then
            region_name = string.format("%s_%s_%s_%d_%s_01", 
                audio_type.prefix, root_name, folder_name, music_bpm, music_meter)
        elseif audio_type.prefix == "dx" then
            local char_field = dx_character ~= "" and dx_character or "unknown"
            local questType_field = dx_quest_type ~= "" and dx_quest_type or "SQ"
            local questName_field = dx_quest_name ~= "" and dx_quest_name or folder_name
            region_name = string.format("%s_%s_%s_%s_%02d_01", 
                audio_type.prefix, char_field, questType_field, questName_field, dx_line_number)
        elseif audio_type.prefix == "env" then
            region_name = string.format("env_%s_%s_01", root_name, folder_name)
        end
        
        -- Crear región
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

local function detect_and_create_regions_gap()
    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()
    
    local total_regions = 0
    local audio_type = audio_types[selected_type_idx]
    sync_config_to_audio_type()
    
    if auto_detect_silence then
        -- Gap Detection mode: for individual tracks
        local sel_tracks = reaper.CountSelectedTracks(0)
        if sel_tracks == 0 then
            reaper.ShowMessageBox("Select tracks first.", "No Selection", 0)
            reaper.PreventUIRefresh(-1)
            reaper.Undo_EndBlock("Detect Regions", -1)
            return
        end
        
        for i = 0, sel_tracks - 1 do
            local track = reaper.GetSelectedTrack(0, i)
            local regions_created = create_regions_with_type(track, audio_type)
            total_regions = total_regions + regions_created
        end
        
        local msg = string.format("✅ Gap Detection completed:\n\n📊 Regions created: %d\n\n💡 Use 'Render' to export.", 
            total_regions)
        reaper.ShowMessageBox(msg, "Regions Created", 0)
        
    else
        -- Folder Structure mode: detects parent folders and creates region by total duration
        total_regions = create_regions_from_folder_structure()
        
        if total_regions == 0 then
            local msg = "⚠️ No valid parent folders found.\n\n"
            msg = msg .. "IMPORTANT: Select PARENT FOLDERS that meet:\n\n"
            msg = msg .. "1. Folder depth = 1 (is subfolder)\n"
            msg = msg .. "2. Contain child tracks with items\n"
            msg = msg .. "3. Items must be in child tracks\n\n"
            msg = msg .. "Correct structure:\n"
            msg = msg .. "Footsteps (parent folder) ✅ SELECT THIS\n"
            msg = msg .. "  ├── Dirt_Walk_01 (child track with items)\n"
            msg = msg .. "  └── Dirt_Walk_02 (child track with items)\n\n"
            msg = msg .. "💡 TIP: Enable 'Gap Detection' if you prefer\n"
            msg = msg .. "to create regions from individual tracks."
            
            reaper.ShowMessageBox(msg, "Selection Error", 0)
        else
            local msg = string.format("✅ Created %d region(s) from folders\n\n📐 Each region spans full duration of child tracks\n\n💡 Use 'Render' to export.", total_regions)
            reaper.ShowMessageBox(msg, "Regions Created", 0)
        end
    end
    
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Detect Regions", -1)
end

local function update_selected_region_hierarchy()
    local marker_count = reaper.CountProjectMarkers(0)
    local sel_region = nil
    
    -- Find region at cursor
    local pos = reaper.GetCursorPosition()
    for i = 0, marker_count - 1 do
        local _, isrgn, rgnpos, rgnend, name, _ = reaper.EnumProjectMarkers(i)
        if isrgn and pos >= rgnpos and pos <= rgnend then
            sel_region = {index = i, name = name}
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
            root = root:match("^%s*(.-)%s*$")
            parent = parent:match("^%s*(.-)%s*$")
            
            if update_region_hierarchy(sel_region.index, root, parent) then
                reaper.ShowMessageBox("✅ Hierarchy updated:\nRoot: " .. root .. "\nParent: " .. parent, 
                    "Update Successful", 0)
            else
                reaper.ShowMessageBox("Error updating hierarchy", "Error", 0)
            end
        else
            reaper.ShowMessageBox("Incorrect format. Use: root,parent", "Error", 0)
        end
    end
end

-- ============================================
-- PART 7: SMART CONTEXTUAL RENDERING
-- ============================================

local function get_context_display_string()
    local sel_items = reaper.CountSelectedMediaItems(0)
    local sel_tracks = reaper.CountSelectedTracks(0)
    local marker_count = reaper.CountProjectMarkers(0)
    
    -- Check selected regions manually
    local selected_regions = get_selected_regions_manual()
    if #selected_regions > 0 then
        return string.format("📌 %d selected region(s)", #selected_regions)
    end
    
    -- Check selected items
    if sel_items > 0 then
        return string.format("📦 %d selected item(s)", sel_items)
    end
    
    -- Check selected tracks
    if sel_tracks > 0 then
        return string.format("📁 %d selected track(s)", sel_tracks)
    end
    
    -- Check if project has regions
    if marker_count > 0 then
        return string.format("🌍 Entire project (%d regions)", marker_count)
    end
    
    -- Project always available (will create temp region if needed)
    return "🌍 Entire project"
end

local function smart_render()
    local migrated = auto_migrate_regions()
    local updated = auto_update_renamed_regions()
    
    if migrated > 0 or updated > 0 then
        local msg = string.format("🔄 Auto-correction: %d migrated, %d updated\n", migrated, updated)
        reaper.ShowConsoleMsg(msg)
    end
    
    local context_type, context_data = get_render_context()
    local render_regions = {}
    
    reaper.ShowConsoleMsg("\n" .. string.rep("=", 50) .. "\n")
    reaper.ShowConsoleMsg("🎬 RENDER STARTED\n")
    reaper.ShowConsoleMsg(string.rep("=", 50) .. "\n\n")
    
    if context_type == "selected_regions" then
        -- Manually selected regions
        render_regions = context_data
        reaper.ShowConsoleMsg(string.format("📌 CONTEXT: Rendering %d manually selected region(s)\n\n", #render_regions))
        
        -- Show which regions will be rendered
        for i, region in ipairs(render_regions) do
            reaper.ShowConsoleMsg(string.format("  %d. %s\n", i, region.name))
        end
        
    elseif context_type == "items" then
        reaper.ShowConsoleMsg("📦 CONTEXT: Rendering selected items\n\n")
        local min_pos = math.huge
        local max_end = 0
        
        for _, item in ipairs(context_data) do
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            min_pos = math.min(min_pos, pos)
            max_end = math.max(max_end, pos + len)
        end
        
        local temp_region_name = string.format("%s_Selection_01", prefix_type)
        local region_index = reaper.AddProjectMarker2(0, true, min_pos, max_end, temp_region_name, -1, 0)
        update_region_hierarchy(region_index, "Project", "Selection")
        
        table.insert(render_regions, {
            name = temp_region_name,
            start = min_pos,
            end_pos = max_end,
            index = region_index
        })
        
        reaper.ShowConsoleMsg("  Creating temporary region from selection...\n")
        
    elseif context_type == "tracks" then
        reaper.ShowConsoleMsg(string.format("📁 CONTEXT: Rendering from %d selected track(s)\n\n", #context_data))
        
        if auto_detect_silence then
            reaper.ShowConsoleMsg("  Using Gap Detection mode...\n")
            for _, track in ipairs(context_data) do
                local regions_created = create_regions_from_gaps(track)
                reaper.ShowConsoleMsg(string.format("  • Track: %d regions created\n", regions_created))
            end
        end
        
        local marker_count = reaper.CountProjectMarkers(0)
        for i = 0, marker_count - 1 do
            local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(i)
            if isrgn then
                table.insert(render_regions, {name = name, start = pos, end_pos = rgnend, index = i})
            end
        end
        
    elseif context_type == "project" then
        reaper.ShowConsoleMsg("🌍 CONTEXT: Rendering entire project\n\n")
        local marker_count = reaper.CountProjectMarkers(0)
        
        if marker_count == 0 then
            reaper.ShowConsoleMsg("  No regions found. Rendering entire project...\n\n")
            
            -- Use first track for hierarchy info if available
            local hierarchy = {root = "Project", parent = "Full"}
            if reaper.CountTracks(0) > 0 then
                local first_track = reaper.GetTrack(0, 0)
                local parent_track = get_parent_track(first_track)
                if parent_track then
                    hierarchy.root = clean_name(get_track_name(parent_track))
                    hierarchy.parent = clean_name(get_track_name(first_track))
                end
            end
            
            -- Create single item for render config (no actual region)
            table.insert(render_regions, {
                name = string.format("%s_Project_Full", prefix_type),
                start = 0,
                end_pos = reaper.GetProjectLength(0),
                index = -1,  -- Mark as no actual region
                hierarchy = hierarchy
            })
            
            reaper.ShowConsoleMsg("  Will render entire project without regions\n\n")
        else
            -- Regions exist - use them normalmente
            reaper.ShowConsoleMsg(string.format("  Found %d region(s):\n\n", marker_count))
            
            for i = 0, marker_count - 1 do
                local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(i)
                if isrgn then
                    table.insert(render_regions, {name = name, start = pos, end_pos = rgnend, index = i})
                    reaper.ShowConsoleMsg(string.format("  • %s\n", name))
                end
            end
        end
    end
    
    reaper.ShowConsoleMsg("\n")
    
    if #render_regions == 0 then
        reaper.ShowMessageBox("No content detected to render.", "No Content", 0)
        reaper.ShowConsoleMsg("❌ ERROR: No regions to render\n")
        return
    end
    
    local render_path = custom_output_path ~= "" and custom_output_path or reaper.GetProjectPath("") .. "/Renders/"
    
    local type_folder = "SFX"
    if prefix_type == "mx" then type_folder = "Music"
    elseif prefix_type == "dx" then type_folder = "Dialogue"
    elseif prefix_type == "env" then type_folder = "Environment" end
    
    render_path = render_path .. type_folder .. "/"
    
    local first_region = render_regions[1]
    local hierarchy
    
    if first_region.index == -1 then
        -- No actual region - use provided hierarchy or default
        hierarchy = first_region.hierarchy or {root = "Project", parent = "Full"}
    else
        -- Has actual region - get its hierarchy
        hierarchy = get_region_hierarchy(first_region.index)
    end
    
    local root_folder_name = hierarchy.root == "Root" and "General" or hierarchy.root
    local parent_name = hierarchy.parent
    
    render_path = render_path .. root_folder_name .. "/"
    
    reaper.RecursiveCreateDirectory(render_path, 0)
    
    -- Configure render settings
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE", render_path, true)
    
    local expanded_pattern = wildcard_template
        :gsub("%$root", root_folder_name)
        :gsub("%$parent", parent_name)
        :gsub("%$region", first_region.name)
    
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", expanded_pattern, true)
    
    -- Set bounds: "1" for Regions, "2" for Entire project
    if first_region.index == -1 then
        -- No actual region - render entire project
        reaper.GetSetProjectInfo_String(0, "RENDER_BOUNDSFLAG", "2", true)
    else
        -- Has regions - render by regions
        reaper.GetSetProjectInfo_String(0, "RENDER_BOUNDSFLAG", "1", true)
    end
    
    -- Set format and quality
    reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT", "wav", true)
    reaper.GetSetProjectInfo_String(0, "RENDER_SETTINGS", "24bit", true)
    
    -- Set source to "All tracks" (value 0)
    reaper.GetSetProjectInfo_String(0, "RENDER_CHANNELS", "0", true)
    
    local summary = string.format("✅ Ready to render\n📂 Output: %s\n📝 Pattern: %s\n🎯 Regions: %d\n", 
        render_path, expanded_pattern, #render_regions)
    reaper.ShowConsoleMsg(summary)
    reaper.ShowConsoleMsg(string.rep("=", 50) .. "\n\n")
    
    -- Open render dialog with proper settings
    reaper.Main_OnCommand(40015, 0)
end

-- ============================================
-- PART 8: AUTOMATIC DETECTION AND CREATION
-- ============================================

local function auto_detect_and_create_regions()
    reaper.defer(detect_and_create_regions_gap)
end

local function browse_output_folder()
    if reaper.JS_Dialog_BrowseForFolder then
        local ret, folder_path = reaper.JS_Dialog_BrowseForFolder("Select Output Folder", custom_output_path)
        if ret == 1 then
            custom_output_path = folder_path:gsub("[\\/]$", "") .. "/"
        end
    else
        local ret, folder_path = reaper.GetUserFileNameForWrite("", "Select Output Folder", "")
        if ret then
            folder_path = folder_path:match("(.*[\\/])")
            if folder_path then
                custom_output_path = folder_path
            end
        end
    end
end

-- ============================================
-- PART 9: UPDATED GUI
-- ============================================

function loop()
    local visible, open = reaper.ImGui_Begin(ctx, 'SimpleFX Render v4.0', true, 
        reaper.ImGui_WindowFlags_AlwaysAutoResize())
    
    if visible then
        -- Audio Type Selector
        reaper.ImGui_Text(ctx, "Audio Type:")
        reaper.ImGui_SameLine(ctx)
        
        local type_names = ""
        for _, t in ipairs(audio_types) do
            type_names = type_names .. t.name .. "\0"
        end
        
        local changed, new_idx = reaper.ImGui_Combo(ctx, "##audio_type", selected_type_idx - 1, type_names)
        if changed then
            sync_config_to_audio_type()
            selected_type_idx = new_idx + 1
            sync_config_from_audio_type()
        end
        
        reaper.ImGui_Spacing(ctx)
        
        -- Main Buttons
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x4CAF50FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x66BB6AFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x388E3CFF)
        
        if reaper.ImGui_Button(ctx, "🔍 Detect and Create Regions", 450, 50) then
            reaper.defer(detect_and_create_regions_gap)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Detects silence gaps in selected tracks\nor creates regions from parent folders")
        end
        
        reaper.ImGui_PopStyleColor(ctx, 3)
        reaper.ImGui_Spacing(ctx)
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2196F3FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x42A5F5FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x1976D2FF)
        
        if reaper.ImGui_Button(ctx, "📋 Update Hierarchy", 450, 40) then
            reaper.defer(update_selected_region_hierarchy)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Update hierarchy info for the region at cursor position")
        end
        
        reaper.ImGui_PopStyleColor(ctx, 3)
        reaper.ImGui_Spacing(ctx)
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF9800FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFFB74DFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xE65100FF)
        
        local context_display = get_context_display_string()
        if reaper.ImGui_Button(ctx, "🎬 Render", 450, 50) then
            reaper.defer(smart_render)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Current context: " .. context_display .. 
                "\n\nRender will use:\n" ..
                "• Selected regions (if any)\n" ..
                "• Selected items (if any)\n" ..
                "• Selected tracks (if any)\n" ..
                "• Entire project (fallback)")
        end
        
        reaper.ImGui_PopStyleColor(ctx, 3)
        reaper.ImGui_Separator(ctx)  -- ← Corrige aquí (era reaper_ImGui_Separator)
        
        -- Settings Buttons
        if reaper.ImGui_Button(ctx, show_settings and "▼ Settings" or "▶ Settings", 220, 35) then
            show_settings = not show_settings
        end
        
        reaper.ImGui_SameLine(ctx)
        
        if reaper.ImGui_Button(ctx, show_audio_types_editor and "▼ Audio Types" or "▶ Audio Types", 220, 35) then
            show_audio_types_editor = not show_audio_types_editor
        end
        
        -- Settings Panel
        if show_settings then
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Text(ctx, "═ SETTINGS ═")
            
            reaper.ImGui_Text(ctx, "Minimum silence (s):")
            reaper.ImGui_SetNextItemWidth(ctx, 200)
            _, min_silence_length = reaper.ImGui_SliderDouble(ctx, "##minsilence", min_silence_length, 0.01, 2.0, "%.2f s")
            
            reaper.ImGui_Text(ctx, "Filename pattern:")
            reaper.ImGui_SetNextItemWidth(ctx, 350)
            _, wildcard_template = reaper.ImGui_InputText(ctx, "##wildcard", wildcard_template)
            
            reaper.ImGui_BulletText(ctx, "$root - Root folder name")
            reaper.ImGui_BulletText(ctx, "$parent - Parent folder name")
            reaper.ImGui_BulletText(ctx, "$region - Region name")
            
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Text(ctx, "Output folder:")
            local display_path = custom_output_path ~= "" and custom_output_path or "Project/Renders/ (default)"
            reaper.ImGui_TextWrapped(ctx, display_path)
            
            if reaper.ImGui_Button(ctx, "📁 Browse", 220, 30) then
                browse_output_folder()
            end
            
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "↺ Reset", 220, 30) then
                custom_output_path = ""
            end
            
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Text(ctx, "Type-specific configuration:")
            local current_type = audio_types[selected_type_idx]
            if current_type.name == "Music" then
                reaper.ImGui_Text(ctx, "BPM:")
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SetNextItemWidth(ctx, 100)
                _, music_bpm = reaper.ImGui_InputInt(ctx, "##music_bpm", music_bpm)
                music_bpm = math.max(1, music_bpm)
                
                reaper.ImGui_Text(ctx, "Meter:")
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SetNextItemWidth(ctx, 100)
                _, music_meter = reaper.ImGui_InputText(ctx, "##music_meter", music_meter)
                
            elseif current_type.name == "Dialogue" then
                reaper.ImGui_Text(ctx, "Character:")
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SetNextItemWidth(ctx, 150)
                _, dx_character = reaper.ImGui_InputText(ctx, "##dx_character", dx_character)
                
                reaper.ImGui_Text(ctx, "Quest Type:")
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SetNextItemWidth(ctx, 100)
                _, dx_quest_type = reaper.ImGui_InputText(ctx, "##dx_quest_type", dx_quest_type)
                
                reaper.ImGui_Text(ctx, "Quest Name:")
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SetNextItemWidth(ctx, 150)
                _, dx_quest_name = reaper.ImGui_InputText(ctx, "##dx_quest_name", dx_quest_name)
                
                reaper.ImGui_Text(ctx, "Line:")
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SetNextItemWidth(ctx, 80)
                _, dx_line_number = reaper.ImGui_InputInt(ctx, "##dx_line_number", dx_line_number)
                dx_line_number = math.max(1, dx_line_number)
            end
        end
        
        -- Audio Types Panel
        if show_audio_types_editor then
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Text(ctx, "═ AUDIO TYPES ═")
            
            for i, audio_type in ipairs(audio_types) do
                reaper.ImGui_Text(ctx, string.format("%d. %s", i, audio_type.name))
                reaper.ImGui_Indent(ctx, 20)
                
                reaper.ImGui_Text(ctx, "Prefix:")
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SetNextItemWidth(ctx, 80)
                _, audio_type.prefix = reaper.ImGui_InputText(ctx, "##prefix_" .. i, audio_type.prefix)
                
                reaper.ImGui_Text(ctx, "Base path:")
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SetNextItemWidth(ctx, 150)
                _, audio_type.base_path = reaper.ImGui_InputText(ctx, "##path_" .. i, audio_type.base_path)
                
                reaper.ImGui_Text(ctx, "Pattern:")
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SetNextItemWidth(ctx, 150)
                _, audio_type.wildcard = reaper.ImGui_InputText(ctx, "##wildcard_" .. i, audio_type.wildcard)
                
                reaper.ImGui_Unindent(ctx, 20)
                reaper.ImGui_Spacing(ctx)
            end
            
            if reaper.ImGui_Button(ctx, "💾 Save Types", 200, 35) then
                sync_config_to_audio_type()
                save_audio_types(audio_types)
                reaper.ShowMessageBox("✅ Audio types and settings saved", "Saved", 0)
            end
        end
        
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Text(ctx, "v4.0 - SimpleFX Render by Panchuel")
        
        reaper.ImGui_End(ctx)
    end

    if not open then
        sync_config_to_audio_type()
        save_settings({
            auto_detect_silence = auto_detect_silence,
            min_silence_length = min_silence_length,
            custom_output_path = custom_output_path,
            wildcard_template = wildcard_template,
            prefix_type = prefix_type
        })
        save_audio_types(audio_types)
        
        if reaper.ImGui_DestroyContext then
            reaper.ImGui_DestroyContext(ctx)
        end
    else
        reaper.defer(loop)
    end
end

reaper.defer(loop)