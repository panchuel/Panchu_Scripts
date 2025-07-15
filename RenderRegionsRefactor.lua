--@description SFX Renderer (SOLID Refactor) - Versión Corregida
--@version 9.1
--@author Panchu
--@provides [main] .

local reaper = reaper

------------------------------------------
-- Módulo: ConfigManager
------------------------------------------
local Config = {
    ORIGINAL_TAG = "SFX_ORIGINAL",
    VARIATION_TAG = "SFX_VARIATION",
    
    types = {
        sx = {name = "SFX", folder = "SFX", has_variations = true, prefix = "sx"},
        mx = {name = "Music", folder = "Music", has_variations = false, prefix = "mx"},
        dx = {name = "Dialogue", folder = "Dialogue", has_variations = false, prefix = "dx"},
        env = {name = "Environment", folder = "Environment", has_variations = false, prefix = "env"}
    },
    
    current_type = "sx",
    wildcard_template = "$region",
    variations = 0,
    separation_time = 1.0,
    randomize_position = 0.0,
    music_bpm = 120,
    music_meter = "4-4",
    dx_character = "",
    dx_quest_type = "SQ",
    dx_quest_name = "",
    dx_line_number = 1,
    
    random_params = {
        volume = {enable = false, amount = 3.0},
        pan = {enable = false, amount = 0.1},
        pitch = {enable = false, amount = 0.5},
        rate = {enable = false, amount = 0.1},
        position = {enable = true, amount = 0.0},
        length = {enable = false, amount = 0.1},
        fadein = {enable = false, amount = 0.1},
        fadeout = {enable = false, amount = 0.1},
        fadeshape = {enable = false, amount = 1}
    },
    
    slider_ranges = {
        volume = {min = 0.0, max = 12.0},
        pan = {min = 0.0, max = 1.0},
        pitch = {min = 0.0, max = 12.0},
        rate = {min = 0.0, max = 0.5},
        position = {min = 0.0, max = 5.0},
        length = {min = 0.0, max = 0.5},
        fadein = {min = 0.0, max = 1.0},
        fadeout = {min = 0.0, max = 1.0}
    }
}

------------------------------------------
-- Módulo: StateManager
------------------------------------------
local State = {
    valid_tracks = {},
    region_root_data = {},
    region_parent_data = {},
    selected_tracks_count = 0
}

------------------------------------------
-- Módulo: Utils
------------------------------------------
local Utils = {}

function Utils.clean_name(name)
    return name:gsub("[^%w_]", "_"):gsub("__+", "_")
end

function Utils.get_track_name(track)
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    return name or "Unnamed"
end

function Utils.get_track_index(track)
    return reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
end

function Utils.get_folder_depth(track)
    return reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
end

------------------------------------------
-- Módulo: TrackManager
------------------------------------------
local TrackManager = {}

function TrackManager.get_parent_track(track)
    local idx = Utils.get_track_index(track)
    if idx == 0 then return nil end
    
    local current_level = 0
    for i = 0, idx - 1 do
        current_level = current_level + Utils.get_folder_depth(reaper.GetTrack(0, i))
    end
    
    for i = idx - 1, 0, -1 do
        local candidate = reaper.GetTrack(0, i)
        if Utils.get_folder_depth(candidate) == 1 then
            local candidate_level = 0
            for j = 0, i - 1 do
                candidate_level = candidate_level + Utils.get_folder_depth(reaper.GetTrack(0, j))
            end
            
            if candidate_level == current_level - 1 then
                return candidate
            end
        end
    end
    
    return nil
end

function TrackManager.get_child_tracks(folder_track)
    local child_tracks = {}
    local folder_idx = Utils.get_track_index(folder_track)
    
    for i = folder_idx + 1, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        table.insert(child_tracks, track)
        if Utils.get_folder_depth(track) < 0 then break end
    end
    
    return child_tracks
end

function TrackManager.is_valid_subfolder(track)
    return Utils.get_folder_depth(track) == 1 and #TrackManager.get_child_tracks(track) > 0
end

------------------------------------------
-- Módulo: ItemManager
------------------------------------------
local ItemManager = {}

function ItemManager.get_item_notes(item)
    local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    return notes or ""
end

function ItemManager.set_item_notes(item, notes)
    reaper.GetSetMediaItemInfo_String(item, "P_NOTES", notes, true)
end

function ItemManager.is_original_item(item)
    local notes = ItemManager.get_item_notes(item)
    return notes:find(Config.ORIGINAL_TAG) and not notes:find(Config.VARIATION_TAG)
end

function ItemManager.is_variation_item(item)
    local notes = ItemManager.get_item_notes(item)
    return notes:find(Config.VARIATION_TAG)
end

function ItemManager.mark_original_items(folder_track)
    for _, child in ipairs(TrackManager.get_child_tracks(folder_track)) do
        for k = 0, reaper.CountTrackMediaItems(child) - 1 do
            local item = reaper.GetTrackMediaItem(child, k)
            if not ItemManager.is_original_item(item) and not ItemManager.is_variation_item(item) then
                ItemManager.set_item_notes(item, ItemManager.get_item_notes(item) .. " " .. Config.ORIGINAL_TAG)
            end
        end
    end
end

-- NUEVA FUNCIÓN: Duplicar items con desplazamiento
function ItemManager.duplicate_items(folder_track, time_offset)
    for _, child in ipairs(TrackManager.get_child_tracks(folder_track)) do
        local item_count = reaper.CountTrackMediaItems(child)
        for k = 0, item_count - 1 do
            local item = reaper.GetTrackMediaItem(child, k)
            if ItemManager.is_original_item(item) then
                local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local new_item = reaper.SplitMediaItem(item, pos + 0.0001) -- Truco para duplicar
                if new_item then
                    reaper.SetMediaItemPosition(new_item, pos + time_offset, false)
                    local notes = ItemManager.get_item_notes(new_item)
                    notes = notes:gsub(Config.ORIGINAL_TAG, Config.VARIATION_TAG)
                    ItemManager.set_item_notes(new_item, notes)
                end
            end
        end
    end
end

-- NUEVA FUNCIÓN: Aplicar variaciones aleatorias a los items
function ItemManager.apply_randomization(item)
    -- Volumen
    if Config.random_params.volume.enable then
        local vol = 1.0 + (math.random() * 2 - 1) * Config.random_params.volume.amount
        reaper.SetMediaItemInfo_Value(item, "D_VOL", vol)
    end
    
    -- Pan
    if Config.random_params.pan.enable then
        for i = 0, reaper.CountTakes(item) - 1 do
            local take = reaper.GetTake(item, i)
            if take then
                local pan = (math.random() * 2 - 1) * Config.random_params.pan.amount
                reaper.SetMediaItemTakeInfo_Value(take, "D_PAN", pan)
            end
        end
    end
    
    -- Pitch (ajuste de tasa de reproducción)
    if Config.random_params.pitch.enable then
        for i = 0, reaper.CountTakes(item) - 1 do
            local take = reaper.GetTake(item, i)
            if take then
                local rate = 1.0 + (math.random() * 2 - 1) * Config.random_params.pitch.amount
                reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate)
            end
        end
    end
end

------------------------------------------
-- Módulo: RegionManager
------------------------------------------
local RegionManager = {
    name_generators = {
        sx = function(root, sub)
            return string.format("%s_%s_%s", Config.types.sx.prefix, root, sub)
        end,
        mx = function(root, sub)
            return string.format("%s_%s_%s_%d_%s", 
                Config.types.mx.prefix, root, sub, Config.music_bpm, Config.music_meter)
        end,
        dx = function(root, sub)
            local char = Config.dx_character ~= "" and Config.dx_character or "unknown"
            local quest_type = Config.dx_quest_type ~= "" and Config.dx_quest_type or "SQ"
            local quest_name = Config.dx_quest_name ~= "" and Config.dx_quest_name or sub
            return string.format("%s_%s_%s_%s_%02d", 
                Config.types.dx.prefix, char, quest_type, quest_name, Config.dx_line_number)
        end,
        env = function(root, sub)
            return string.format("env_%s_%s", root, sub)
        end
    }
}

function RegionManager.calculate_time_range(folder_track)
    local min_start, max_end = math.huge, 0
    for _, child in ipairs(TrackManager.get_child_tracks(folder_track)) do
        for k = 0, reaper.CountTrackMediaItems(child) - 1 do
            local item = reaper.GetTrackMediaItem(child, k)
            if ItemManager.is_original_item(item) then
                local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                min_start = math.min(min_start, pos)
                max_end = math.max(max_end, pos + len)
            end
        end
    end
    return min_start, max_end
end

function RegionManager.create_regions()
    -- Inicializar semilla aleatoria
    math.randomseed(reaper.time_precise())
    
    State.valid_tracks = {}
    State.region_root_data = {}
    State.region_parent_data = {}
    
    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()
    
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        local subfolder = reaper.GetSelectedTrack(0, i)
        if TrackManager.is_valid_subfolder(subfolder) then
            RegionManager.process_subfolder(subfolder)
        end
    end
    
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Create regions from subfolders", -1)
end

function RegionManager.process_subfolder(subfolder)
    -- Paso 1: Marcar items originales
    ItemManager.mark_original_items(subfolder)
    
    local sub_name = Utils.clean_name(Utils.get_track_name(subfolder))
    local root_folder = TrackManager.get_parent_track(subfolder)
    local root_name = root_folder and Utils.clean_name(Utils.get_track_name(root_folder)) or "Root"
    
    local base_name = RegionManager.name_generators[Config.current_type](root_name, sub_name)
    local min_start, max_end = RegionManager.calculate_time_range(subfolder)
    
    if min_start == math.huge then return end
    
    local actual_variations = Config.variations > 0 and Config.variations or 1
    local max_end_all = 0
    
    -- Calcular tiempo máximo existente
    for _, child in ipairs(TrackManager.get_child_tracks(subfolder)) do
        for k = 0, reaper.CountTrackMediaItems(child) - 1 do
            local item = reaper.GetTrackMediaItem(child, k)
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            max_end_all = math.max(max_end_all, pos + len)
        end
    end
    
    local base_offset = max_end_all - min_start + Config.separation_time
    
    -- Paso 2: Duplicar items para variaciones
    for variation = 2, actual_variations do
        local time_offset = base_offset + (variation - 2) * (max_end - min_start + Config.separation_time)
        ItemManager.duplicate_items(subfolder, time_offset)
    end
    
    -- Paso 3: Aplicar aleatorización a variaciones
    if Config.variations > 1 then
        for _, child in ipairs(TrackManager.get_child_tracks(subfolder)) do
            for k = 0, reaper.CountTrackMediaItems(child) - 1 do
                local item = reaper.GetTrackMediaItem(child, k)
                if ItemManager.is_variation_item(item) then
                    ItemManager.apply_randomization(item)
                end
            end
        end
    end
    
    -- Paso 4: Crear regiones
    for variation = 1, actual_variations do
        local rand_offset = 0
        if Config.variations > 0 and Config.randomize_position > 0 then
            rand_offset = (math.random() * 2 - 1) * Config.randomize_position
        end
        
        local time_offset = Config.variations > 0 and (base_offset + (variation - 1) * (max_end - min_start + Config.separation_time)) or 0
        local region_name = string.format("%s_%02d", base_name, variation)
        
        local region_start = min_start + time_offset + rand_offset
        local region_end = max_end + time_offset + rand_offset
        
        reaper.AddProjectMarker2(0, true, region_start, region_end, region_name, -1, 0)
        
        State.region_root_data[region_name] = root_name
        State.region_parent_data[region_name] = sub_name
        
        table.insert(State.valid_tracks, {
            name = region_name,
            start = region_start,
            end_pos = region_end,
            variation = variation,
            folder_track = subfolder
        })
    end
end

------------------------------------------
-- Módulo: RenderManager
------------------------------------------
local RenderManager = {}

function RenderManager.get_selected_region()
    local _, region_index = reaper.GetLastMarkerAndCurRegion(0, reaper.GetCursorPosition())
    if region_index >= 0 then
        local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(region_index)
        if isrgn then return {{name = name, start = pos, end_pos = rgnend}} end
    end
    return {}
end

function RenderManager.get_all_regions()
    local regions = {}
    for i = 0, reaper.CountProjectMarkers(0) - 1 do
        local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(i)
        if isrgn then
            table.insert(regions, {name = name, start = pos, end_pos = rgnend})
        end
    end
    return regions
end

function RenderManager.configure_common_settings()
    local render_path = reaper.GetProjectPath("") .. "/Renders/"
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE", render_path, true)
    reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT", "wav", true)
    reaper.GetSetProjectInfo_String(0, "RENDER_SETTINGS", "24bit", true)
end

function RenderManager.expand_wildcards(pattern, region_name)
    if State.region_root_data[region_name] then
        pattern = pattern:gsub("%$root", State.region_root_data[region_name])
    else
        pattern = pattern:gsub("%$root", "Root")
    end
    
    if State.region_parent_data[region_name] then
        pattern = pattern:gsub("%$parent", State.region_parent_data[region_name])
    else
        pattern = pattern:gsub("%$parent", "Parent")
    end
    
    pattern = pattern:gsub("%$region", region_name or "Region")
    return pattern
end

function RenderManager.configure_path_and_pattern(region)
    local type_folder = Config.types[Config.current_type].folder
    local render_path = reaper.GetProjectPath("") .. "/Renders/" .. type_folder .. "/"
    
    local root_folder_name = State.region_root_data[region.name] or "General"
    if root_folder_name == "Root" then root_folder_name = "General" end
    
    render_path = render_path .. root_folder_name .. "/"
    reaper.RecursiveCreateDirectory(render_path, 0)
    
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE", render_path, true)
    
    local parent_name = State.region_parent_data[region.name] or "Parent"
    local expanded_pattern = RenderManager.expand_wildcards(Config.wildcard_template, region.name)
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", expanded_pattern, true)
end

function RenderManager.open_render_dialog()
    reaper.Main_OnCommand(40015, 0)  -- File: Render project to disk...
end

function RenderManager.prepare(selected_only)
    local regions = selected_only and RenderManager.get_selected_region() or RenderManager.get_all_regions()
    if #regions == 0 then
        reaper.ShowMessageBox("No regions found", "Error", 0)
        return
    end
    
    RenderManager.configure_common_settings()
    RenderManager.configure_path_and_pattern(regions[1])
    RenderManager.open_render_dialog()
end

------------------------------------------
-- Módulo: UIManager
------------------------------------------
local UI = {
    ctx = reaper.ImGui_CreateContext('SFX Renderer'),
    font = reaper.ImGui_CreateFont('sans-serif', 16)
}

function UI.draw_file_type_selector()
    reaper.ImGui_Text(UI.ctx, "File type:")
    reaper.ImGui_SameLine(UI.ctx)
    
    local types_str = table.concat({
        Config.types.sx.name,
        Config.types.mx.name,
        Config.types.dx.name,
        Config.types.env.name
    }, "\0") .. "\0"
    
    local current_idx = 0
    local types_order = {"sx", "mx", "dx", "env"}
    for i, t in ipairs(types_order) do
        if t == Config.current_type then
            current_idx = i - 1
            break
        end
    end
    
    local changed, new_idx = reaper.ImGui_Combo(UI.ctx, "##filetype", current_idx, types_str)
    if changed then
        Config.current_type = types_order[new_idx + 1]
    end
end

function UI.draw_sfx_settings()
    if Config.current_type ~= "sx" then return end
    
    reaper.ImGui_Text(UI.ctx, "Variations per subfolder (0 = regions only):")
    reaper.ImGui_SetNextItemWidth(UI.ctx, 100)
    local changed, new_val = reaper.ImGui_InputInt(UI.ctx, "Variations", Config.variations)
    if changed then Config.variations = math.max(0, math.min(new_val, 100)) end
    
    if Config.variations > 0 then
        reaper.ImGui_Text(UI.ctx, "Separation between variations (s):")
        reaper.ImGui_SetNextItemWidth(UI.ctx, 100)
        changed, new_val = reaper.ImGui_InputDouble(UI.ctx, "##sep", Config.separation_time)
        if changed then Config.separation_time = math.max(0.1, new_val) end
        
        reaper.ImGui_Text(UI.ctx, "Position randomization (s):")
        reaper.ImGui_SetNextItemWidth(UI.ctx, 150)
        changed, new_val = reaper.ImGui_SliderDouble(UI.ctx, "##rand_pos", Config.randomize_position, 
            Config.slider_ranges.position.min, Config.slider_ranges.position.max, "Position: %.2f s")
        if changed then Config.randomize_position = new_val end
        
        -- Configuración de aleatorización
        reaper.ImGui_Text(UI.ctx, "Randomization Settings:")
        
        -- Volumen
        reaper.ImGui_Checkbox(UI.ctx, "Volume", Config.random_params.volume.enable)
        if Config.random_params.volume.enable then
            reaper.ImGui_SameLine(UI.ctx)
            reaper.ImGui_SetNextItemWidth(UI.ctx, 100)
            changed, new_val = reaper.ImGui_SliderDouble(UI.ctx, "##vol_rand", Config.random_params.volume.amount, 
                Config.slider_ranges.volume.min, Config.slider_ranges.volume.max, "Amount: %.1f dB")
            if changed then Config.random_params.volume.amount = new_val end
        end
        
        -- Pan
        reaper.ImGui_Checkbox(UI.ctx, "Pan", Config.random_params.pan.enable)
        if Config.random_params.pan.enable then
            reaper.ImGui_SameLine(UI.ctx)
            reaper.ImGui_SetNextItemWidth(UI.ctx, 100)
            changed, new_val = reaper.ImGui_SliderDouble(UI.ctx, "##pan_rand", Config.random_params.pan.amount, 
                Config.slider_ranges.pan.min, Config.slider_ranges.pan.max, "Amount: %.2f")
            if changed then Config.random_params.pan.amount = new_val end
        end
        
        -- Pitch
        reaper.ImGui_Checkbox(UI.ctx, "Pitch", Config.random_params.pitch.enable)
        if Config.random_params.pitch.enable then
            reaper.ImGui_SameLine(UI.ctx)
            reaper.ImGui_SetNextItemWidth(UI.ctx, 100)
            changed, new_val = reaper.ImGui_SliderDouble(UI.ctx, "##pitch_rand", Config.random_params.pitch.amount, 
                Config.slider_ranges.pitch.min, Config.slider_ranges.pitch.max, "Amount: %.1f semitones")
            if changed then Config.random_params.pitch.amount = new_val end
        end
    end
end

function UI.draw_music_settings()
    if Config.current_type ~= "mx" then return end
    
    reaper.ImGui_Text(UI.ctx, "BPM:")
    reaper.ImGui_SetNextItemWidth(UI.ctx, 120)
    local changed, new_val = reaper.ImGui_InputInt(UI.ctx, "##music_bpm", Config.music_bpm)
    if changed then Config.music_bpm = math.max(1, new_val) end
    
    reaper.ImGui_Text(UI.ctx, "Meter (e.g: 4-4):")
    reaper.ImGui_SetNextItemWidth(UI.ctx, 120)
    changed, new_val = reaper.ImGui_InputText(UI.ctx, "##music_meter", Config.music_meter)
    if changed then Config.music_meter = new_val end
end

function UI.draw_dialogue_settings()
    if Config.current_type ~= "dx" then return end
    
    reaper.ImGui_Text(UI.ctx, "Character:")
    reaper.ImGui_SetNextItemWidth(UI.ctx, 180)
    local changed, new_val = reaper.ImGui_InputText(UI.ctx, "##dx_character", Config.dx_character)
    if changed then Config.dx_character = new_val end
    
    reaper.ImGui_Text(UI.ctx, "Quest Type (e.g: SQ, HC):")
    reaper.ImGui_SetNextItemWidth(UI.ctx, 120)
    changed, new_val = reaper.ImGui_InputText(UI.ctx, "##dx_quest_type", Config.dx_quest_type)
    if changed then Config.dx_quest_type = new_val end
    
    reaper.ImGui_Text(UI.ctx, "Quest Name:")
    reaper.ImGui_SetNextItemWidth(UI.ctx, 180)
    changed, new_val = reaper.ImGui_InputText(UI.ctx, "##dx_quest_name", Config.dx_quest_name)
    if changed then Config.dx_quest_name = new_val end
    
    reaper.ImGui_Text(UI.ctx, "Line Number:")
    reaper.ImGui_SetNextItemWidth(UI.ctx, 80)
    changed, new_val = reaper.ImGui_InputInt(UI.ctx, "##dx_line_number", Config.dx_line_number)
    if changed then Config.dx_line_number = math.max(1, new_val) end
end

function UI.draw_wildcards_section()
    reaper.ImGui_Separator(UI.ctx)
    reaper.ImGui_Text(UI.ctx, "Filename Pattern:")
    reaper.ImGui_SetNextItemWidth(UI.ctx, 300)
    local changed, new_val = reaper.ImGui_InputText(UI.ctx, "##wildcard_template", Config.wildcard_template)
    if changed then Config.wildcard_template = new_val end
    
    reaper.ImGui_Text(UI.ctx, "Available wildcards:")
    reaper.ImGui_BulletText(UI.ctx, "$root: Parent folder name")
    reaper.ImGui_BulletText(UI.ctx, "$parent: Subfolder name (selected track)")
    reaper.ImGui_BulletText(UI.ctx, "$region: Region name")
    reaper.ImGui_BulletText(UI.ctx, "Also any other REAPER wildcard (e.g. $track)")
    
    if #State.valid_tracks > 0 then
        local preview = RenderManager.expand_wildcards(Config.wildcard_template, State.valid_tracks[1].name)
        reaper.ImGui_Text(UI.ctx, "Preview: " .. preview)
    end
end

function UI.draw_action_buttons()
    if reaper.ImGui_Button(UI.ctx, "Create regions", 250, 40) then
        reaper.defer(RegionManager.create_regions)
    end
    
    reaper.ImGui_SameLine(UI.ctx)
    if reaper.ImGui_Button(UI.ctx, "Prepare Render", 250, 40) then
        reaper.defer(function() RenderManager.prepare(true) end)
    end
end

function UI.draw_credits()
    reaper.ImGui_Separator(UI.ctx)
    reaper.ImGui_Spacing(UI.ctx)
    reaper.ImGui_Text(UI.ctx, "Developed by Daniel \"Panchuel\" Montoya")
    reaper.ImGui_Spacing(UI.ctx)
end

function UI.draw()
    local visible, open = reaper.ImGui_Begin(UI.ctx, 'SFX Renderer v9.1', true, 
        reaper.ImGui_WindowFlags_AlwaysAutoResize())
    
    if not visible then return open end
    
    reaper.ImGui_PushFont(UI.ctx, UI.font)
    
    -- Sección de información
    reaper.ImGui_Text(UI.ctx, "Selected tracks: " .. State.selected_tracks_count)
    if State.selected_tracks_count > 0 then
        local first_track = reaper.GetSelectedTrack(0, 0)
        reaper.ImGui_Text(UI.ctx, "First track depth: " .. Utils.get_folder_depth(first_track))
        
        local root_track = TrackManager.get_parent_track(first_track)
        if root_track then
            reaper.ImGui_Text(UI.ctx, "Detected root folder: " .. Utils.clean_name(Utils.get_track_name(root_track)))
        end
    end
    
    reaper.ImGui_Separator(UI.ctx)
    
    -- Selector de tipo de archivo
    UI.draw_file_type_selector()
    
    -- Configuración específica
    UI.draw_sfx_settings()
    UI.draw_music_settings()
    UI.draw_dialogue_settings()
    
    -- Sección de wildcards
    UI.draw_wildcards_section()
    
    -- Botones de acción
    UI.draw_action_buttons()
    
    -- Créditos
    UI.draw_credits()
    
    reaper.ImGui_PopFont(UI.ctx)
    reaper.ImGui_End(UI.ctx)
    
    return open
end

------------------------------------------
-- Loop Principal
------------------------------------------
local function main_loop()
    State.selected_tracks_count = reaper.CountSelectedTracks(0)
    
    local open = UI.draw()
    
    if open then
        reaper.defer(main_loop)
    else
        if reaper.ImGui_DestroyContext then
            reaper.ImGui_DestroyContext(UI.ctx)
        end
    end
end

-- Iniciar
reaper.ImGui_Attach(UI.ctx, UI.font)
reaper.defer(main_loop)