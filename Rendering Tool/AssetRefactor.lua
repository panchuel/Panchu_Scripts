--@description Renderizador SFX con jerarquía + GUI + Wildcards + Persistencia + Renderizado Manual por Jerarquías
--@version 2.2
--@author Panchu
--@provides [main] .

local reaper = reaper
local ctx = reaper.ImGui_CreateContext('SFX Renderer v2.2')
local font = reaper.ImGui_CreateFont('sans-serif', 16)
reaper.ImGui_Attach(ctx, font)

-- Valores predeterminados
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
    fadeshape_enable = false
}

-- Cargar configuración
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

-- Guardar configuración
local function save_settings(settings)
    for key, value in pairs(settings) do
        if type(value) == "boolean" then
            reaper.SetExtState("SFX_Renderer", key, value and "true" or "false", true)
        else
            reaper.SetExtState("SFX_Renderer", key, tostring(value), true)
        end
    end
end

-- Cargar configuración inicial
local settings = load_settings()

-- Variables globales
local prefix = settings.prefix
local prefix_type = settings.prefix_type
local valid_tracks = {}
local region_root_data = {}
local region_parent_data = {}
local variations = settings.variations
local separation_time = settings.separation_time
local randomize_position = settings.randomize_position
local wildcard_template = settings.wildcard_template
local custom_output_path = settings.custom_output_path

-- Configuración para tipos de archivo
local music_bpm = settings.music_bpm
local music_meter = settings.music_meter
local dx_character = settings.dx_character
local dx_quest_type = settings.dx_quest_type
local dx_quest_name = settings.dx_quest_name
local dx_line_number = settings.dx_line_number

-- Parámetros de aleatorización para SFX
local random_params = {
    volume = {enable = settings.volume_enable, amount = settings.volume_amount},
    pan = {enable = settings.pan_enable, amount = settings.pan_amount},
    pitch = {enable = settings.pitch_enable, amount = settings.pitch_amount},
    rate = {enable = settings.rate_enable, amount = settings.rate_amount},
    position = {enable = true, amount = 0.0},
    length = {enable = settings.length_enable, amount = settings.length_amount},
    fadein = {enable = settings.fadein_enable, amount = settings.fadein_amount},
    fadeout = {enable = settings.fadeout_enable, amount = settings.fadeout_amount},
    fadeshape = {enable = settings.fadeshape_enable, amount = 1}
}

-- Rangos para los sliders
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

-- Variables para renderizado manual por jerarquías
local hierarchy_render_queue = {}
local current_hierarchy_index = 1

-- Constantes
local ORIGINAL_TAG = "SFX_ORIGINAL"
local VARIATION_TAG = "SFX_VARIATION"

-- Almacenar información jerárquica usando ID único
local region_hierarchy_data = {}  -- {region_id = {root = "AMB", parent = "Jurassic"}}

-- ==================================================
-- Funciones auxiliares
-- ==================================================

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

-- Aplicar parámetros aleatorizados a un nuevo item
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
    
    if random_params.fadeshape.enable and random_params.fadeshake.enable then
        local shapes = {0, 1, 2, 3}
        local new_shape = shapes[math.random(1, #shapes)]
        reaper.SetMediaItemInfo_Value(new_item, "C_FADEINSHAPE", new_shape)
        reaper.SetMediaItemInfo_Value(new_item, "C_FADEOUTSHAPE", new_shape)
    end
end

-- ==================================================
-- Funciones para manejar jerarquías con ID único
-- ==================================================

-- Obtener un ID único para una región
local function get_region_id(index)
    local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(index)
    if not isrgn then return nil end
    return string.format("%.10f_%.10f", pos, rgnend)  -- Usar posición como ID único
end

-- Actualizar datos jerárquicos
local function update_region_hierarchy(region_index, root, parent)
    local region_id = get_region_id(region_index)
    if region_id then
        region_hierarchy_data[region_id] = {root = root, parent = parent}
        return true
    end
    return false
end

-- Obtener datos jerárquicos para una región
local function get_region_hierarchy(region_index)
    local region_id = get_region_id(region_index)
    if region_id and region_hierarchy_data[region_id] then
        return region_hierarchy_data[region_id]
    end
    
    -- Intentar extraer de nombre si es posible
    local _, isrgn, _, _, name, _ = reaper.EnumProjectMarkers(region_index)
    if isrgn then
        local root, parent = name:match("^%w+_([^_]+)_([^_]+)_%d+$")
        if root and parent then
            return {root = root, parent = parent}
        end
    end
    
    return {root = "General", parent = "Parent"}
end

-- ==================================================
-- Funciones para detección y manejo de regiones
-- ==================================================

-- Función para obtener la región seleccionada (MOVIDA ARRIBA PARA SOLUCIONAR EL ERROR)
local function get_selected_region()
    local pos = reaper.GetCursorPosition()
    local _, region_index = reaper.GetLastMarkerAndCurRegion(0, pos)
    
    if region_index >= 0 then
        local _, isrgn, rgnpos, rgnend, name, _ = reaper.EnumProjectMarkers(region_index)
        if isrgn then
            return {
                name = name,
                start = rgnpos,
                end_pos = rgnend,
                index = region_index
            }
        end
    end
    
    -- Buscar manualmente si no se detectó automáticamente
    local marker_count = reaper.CountProjectMarkers(0)
    for i = 0, marker_count - 1 do
        local _, isrgn, rgnpos, rgnend, name, _ = reaper.EnumProjectMarkers(i)
        if isrgn then
            local is_selected = false
            
            -- Verificar si está en la selección de tiempo
            local sel_start, sel_end = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
            if sel_start == rgnpos and sel_end == rgnend then
                is_selected = true
            end
            
            -- Verificar si el cursor está dentro de la región
            if pos >= rgnpos and pos <= rgnend then
                is_selected = true
            end
            
            if is_selected then
                return {
                    name = name,
                    start = rgnpos,
                    end_pos = rgnend,
                    index = i
                }
            end
        end
    end
    
    return nil
end

-- Función para actualizar jerarquía cuando se modifica una región
local function update_hierarchy_for_renamed_region()
    local region = get_selected_region()
    if not region then
        reaper.ShowMessageBox("Selecciona una región primero", "Actualizar Jerarquía", 0)
        return
    end
    
    local current_name = region.name
    local current_hierarchy = get_region_hierarchy(region.index)
    
    local prompt = "Región: " .. current_name .. "\n\nIngresa nueva jerarquía:"
    local default_values = current_hierarchy.root .. "," .. current_hierarchy.parent
    
    local retval, user_input = reaper.GetUserInputs("Actualizar Jerarquía", 2, 
        "Root,Parent:", default_values)
    
    if retval then
        local root, parent = user_input:match("([^,]+),([^,]+)")
        if root and parent then
            if update_region_hierarchy(region.index, root, parent) then
                reaper.ShowMessageBox("Jerarquía actualizada:\nRoot: " .. root .. "\nParent: " .. parent, 
                    "Actualización Exitosa", 0)
            else
                reaper.ShowMessageBox("Error al actualizar jerarquía", "Error", 0)
            end
        else
            reaper.ShowMessageBox("Formato incorrecto. Usa: root,parent", "Error", 0)
        end
    end
end

-- ==================================================
-- Funciones para renderizado
-- ==================================================

local function calculate_folder_time_range(folder_track)
    local min_start = math.huge
    local max_end = 0
    local child_tracks = get_child_tracks(folder_track)
    
    for _, child in ipairs(child_tracks) do
        for k = 0, reaper.CountTrackMediaItems(child) - 1 do
            local item = reaper.GetTrackMediaItem(child, k)
            if is_original_item(item) then
                local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local end_pos = pos + len
                
                min_start = math.min(min_start, pos)
                max_end = math.max(max_end, end_pos)
            end
        end
    end
    
    return min_start, max_end
end

local function duplicate_original_items(folder_track, total_offset)
    local child_tracks = get_child_tracks(folder_track)
    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()
    
    for _, child in ipairs(child_tracks) do
        for k = 0, reaper.CountTrackMediaItems(child) - 1 do
            local item = reaper.GetTrackMediaItem(child, k)
            
            if is_original_item(item) then
                local take = reaper.GetActiveTake(item)
                
                if take then
                    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    local snap = reaper.GetMediaItemInfo_Value(item, "D_SNAPOFFSET")
                    local mute = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
                    local lock = reaper.GetMediaItemInfo_Value(item, "C_LOCK")
                    local fadein = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN")
                    local fadeout = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
                    local fadeinshape = reaper.GetMediaItemInfo_Value(item, "C_FADEINSHAPE")
                    local fadeoutshape = reaper.GetMediaItemInfo_Value(item, "C_FADEOUTSHAPE")
                    
                    local new_item = reaper.AddMediaItemToTrack(child)
                    
                    reaper.SetMediaItemInfo_Value(new_item, "D_POSITION", pos + total_offset)
                    reaper.SetMediaItemInfo_Value(new_item, "D_LENGTH", length)
                    reaper.SetMediaItemInfo_Value(new_item, "D_SNAPOFFSET", snap)
                    reaper.SetMediaItemInfo_Value(new_item, "B_MUTE", mute)
                    reaper.SetMediaItemInfo_Value(new_item, "C_LOCK", lock)
                    reaper.SetMediaItemInfo_Value(new_item, "D_FADEINLEN", fadein)
                    reaper.SetMediaItemInfo_Value(new_item, "D_FADEOUTLEN", fadeout)
                    reaper.SetMediaItemInfo_Value(new_item, "C_FADEINSHAPE", fadeinshape)
                    reaper.SetMediaItemInfo_Value(new_item, "C_FADEOUTSHAPE", fadeoutshape)
                    
                    local new_take = reaper.AddTakeToMediaItem(new_item)
                    local source = reaper.GetMediaItemTake_Source(take)
                    reaper.SetMediaItemTake_Source(new_take, source)
                    
                    local vol = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
                    local pan = reaper.GetMediaItemTakeInfo_Value(take, "D_PAN")
                    local pitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH")
                    local playrate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
                    reaper.SetMediaItemTakeInfo_Value(new_take, "D_VOL", vol)
                    reaper.SetMediaItemTakeInfo_Value(new_take, "D_PAN", pan)
                    reaper.SetMediaItemTakeInfo_Value(new_take, "D_PITCH", pitch)
                    reaper.SetMediaItemTakeInfo_Value(new_take, "D_PLAYRATE", playrate)
                    
                    apply_random_parameters(new_item, new_take, item, take)
                    
                    set_item_notes(new_item, VARIATION_TAG)
                end
            end
        end
    end
    
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Duplicate original items", -1)
    reaper.PreventUIRefresh(-1)
end

local function find_max_variation_number(base_name)
    local max_number = 0
    local marker_count = reaper.CountProjectMarkers(0)
    
    for i = 0, marker_count - 1 do
        local _, isrgn, _, _, name, _ = reaper.EnumProjectMarkers(i)
        if isrgn and name then
            local pattern = base_name .. "_(%d+)$"
            local number_str = name:match(pattern)
            if number_str then
                local number = tonumber(number_str)
                if number and number > max_number then
                    max_number = number
                end
            end
        end
    end
    
    return max_number
end

local function get_max_end_time(folder_track)
    local max_end = 0
    local child_tracks = get_child_tracks(folder_track)
    for _, child in ipairs(child_tracks) do
        for k = 0, reaper.CountTrackMediaItems(child) - 1 do
            local item = reaper.GetTrackMediaItem(child, k)
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local end_pos = pos + len
            max_end = math.max(max_end, end_pos)
        end
    end
    return max_end
end

-- Función principal para crear regiones
local function create_regions_from_subfolders()
    valid_tracks = {}
    region_root_data = {}
    region_parent_data = {}

    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        local subfolder = reaper.GetSelectedTrack(0, i)
        if not is_valid_subfolder(subfolder) then goto continue end

        mark_original_items(subfolder)

        local sub_name = clean_name(get_track_name(subfolder))
        
        -- OBTENER ROOT ESPECÍFICO PARA CADA SUBFOLDER
        local root_track = get_parent_track(subfolder)
        local root_name = "Project"
        
        if root_track then
            root_name = clean_name(get_track_name(root_track))
        else
            local _, project_name = reaper.EnumProjects(-1, "")
            root_name = project_name:match("([^\\/]+)$"):gsub("%..+$", "") or "Project"
        end

        local min_start, max_end = calculate_folder_time_range(subfolder)
        if min_start == math.huge or max_end == 0 then goto continue end

        local total_duration = max_end - min_start
        local base_name
        
        if prefix_type == "sx" then
            base_name = string.format("%s_%s_%s", prefix, root_name, sub_name)
        elseif prefix_type == "mx" then
            base_name = string.format("%s_%s_%s_%d_%s", 
                prefix_type, root_name, sub_name, music_bpm, music_meter)
        elseif prefix_type == "dx" then
            local char_field = dx_character ~= "" and dx_character or "unknown"
            local questType_field = dx_quest_type ~= "" and dx_quest_type or "SQ"
            local questName_field = dx_quest_name ~= "" and dx_quest_name or sub_name
            base_name = string.format("%s_%s_%s_%s_%02d", 
                prefix_type, char_field, questType_field, questName_field, dx_line_number)
        elseif prefix_type == "env" then
            base_name = string.format("env_%s_%s", root_name, sub_name)
        end

        local actual_variations = variations > 0 and variations or 1
        local max_end_all = get_max_end_time(subfolder)
        local base_offset = max_end_all - min_start + separation_time
        local max_variation = find_max_variation_number(base_name)
        
        for variation = 1, actual_variations do
            local rand_offset = 0
            if variations > 0 and randomize_position > 0 then
                rand_offset = (math.random() * 2 - 1) * randomize_position
            end
            
            local time_offset = 0
            if variations > 0 then
                time_offset = base_offset + (variation - 1) * (total_duration + separation_time)
                duplicate_original_items(subfolder, time_offset + rand_offset)
            end
            
            local variation_number = max_variation + variation
            local region_name = string.format("%s_%02d", base_name, variation_number)
            
            local region_start, region_end
            if variations == 0 then
                region_start = min_start
                region_end = max_end
            else
                region_start = min_start + time_offset + rand_offset
                region_end = max_end + time_offset + rand_offset
            end
            
            local region_index = reaper.AddProjectMarker2(0, true, region_start, region_end, region_name, -1, 0)
            
            -- ALMACENAR DATOS JERÁRQUICOS CON ID ÚNICO
            update_region_hierarchy(region_index, root_name, sub_name)
            
            table.insert(valid_tracks, { 
                name = region_name, 
                start = region_start,
                end_pos = region_end,
                variation = variation_number
            })
        end

        ::continue::
    end

    return #valid_tracks
end

-- Función para renderizado
local function prepare_render_with_existing_regions(render_all)
    local regions = {}
    
    if render_all then
        -- Todas las regiones
        local marker_count = reaper.CountProjectMarkers(0)
        for i = 0, marker_count - 1 do
            local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(i)
            if isrgn then
                table.insert(regions, {name = name, start = pos, end_pos = rgnend, index = i})
            end
        end
    else
        -- Solo la región seleccionada
        local region = get_selected_region()
        if region then
            table.insert(regions, region)
        else
            reaper.ShowMessageBox("No hay región seleccionada.\n\nSelecciona una región:\n1. Coloca el cursor dentro de ella\n2. O selecciona su rango de tiempo", "Región no detectada", 0)
            return
        end
    end
    
    if #regions == 0 then
        reaper.ShowMessageBox("No hay regiones creadas.", "Error", 0)
        return
    end
    
    local render_path = custom_output_path ~= "" and custom_output_path or reaper.GetProjectPath("") .. "/Renders/"
    
    local type_folder = "SFX"
    if prefix_type == "mx" then type_folder = "Music"
    elseif prefix_type == "dx" then type_folder = "Dialogue"
    elseif prefix_type == "env" then type_folder = "Environment" end
    
    render_path = render_path .. type_folder .. "/"
    
    -- Para la región, obtener root y parent específicos
    local first_region = regions[1]
    local hierarchy = get_region_hierarchy(first_region.index)
    local root_folder_name = hierarchy.root
    local parent_name = hierarchy.parent
    
    if root_folder_name == "Root" then
        root_folder_name = "General"
    end
    
    render_path = render_path .. root_folder_name .. "/"
    
    reaper.RecursiveCreateDirectory(render_path, 0)
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE", render_path, true)
    
    local expanded_pattern = wildcard_template
        :gsub("%$root", root_folder_name)
        :gsub("%$parent", parent_name)
        :gsub("%$region", first_region.name)
    
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", expanded_pattern, true)
    reaper.GetSetProjectInfo_String(0, "RENDER_BOUNDSFLAG", "1", true) -- Regiones
    reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT", "wav", true)
    reaper.GetSetProjectInfo_String(0, "RENDER_SETTINGS", "24bit", true)
    
    -- Configurar para renderizar solo la región seleccionada si es el caso
    if not render_all then
        reaper.GetSetProjectInfo_String(0, "RENDER_FILTER", "1", true) -- Solo regiones/marcadores seleccionados
        reaper.SetProjectMarker(first_region.index, true, first_region.start, first_region.end_pos, first_region.name, -1)
    else
        reaper.GetSetProjectInfo_String(0, "RENDER_FILTER", "0", true) -- Todas las regiones
    end
    
    reaper.Main_OnCommand(40015, 0)
end

-- ==================================================
-- Funciones para migración y análisis
-- ==================================================

-- Extraer información jerárquica de nombres de regiones existentes
local function extract_hierarchy_from_region_names()
    local regions = {}
    local marker_count = reaper.CountProjectMarkers(0)
    local extracted_count = 0
    
    -- Obtener todas las regiones
    for i = 0, marker_count - 1 do
        local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(i)
        if isrgn then
            table.insert(regions, {
                name = name,
                start = pos,
                end_pos = rgnend,
                index = i
            })
        end
    end
    
    if #regions == 0 then
        reaper.ShowMessageBox("No hay regiones en el proyecto.", "Sin Regiones", 0)
        return 0
    end
    
    -- Intentar extraer información jerárquica de los nombres
    for _, region in ipairs(regions) do
        local name = region.name
        local root, parent = nil, nil
        
        -- Patrón para SFX: sx_root_parent_number o prefix_root_parent_number
        root, parent = name:match("^%w+_([^_]+)_([^_]+)_%d+$")
        
        if root and parent then
            update_region_hierarchy(region.index, root, parent)
            extracted_count = extracted_count + 1
        end
    end
    
    return extracted_count
end

-- Migrar regiones existentes para que funcionen con el nuevo sistema
local function migrate_existing_regions()
    local migration_message = "🔄 MIGRACIÓN DE REGIONES EXISTENTES 🔄\n\n"
    migration_message = migration_message .. "Este proceso intentará extraer información jerárquica\n"
    migration_message = migration_message .. "de los nombres de las regiones existentes.\n\n"
    migration_message = migration_message .. "Funciona mejor con regiones que sigan el patrón:\n"
    migration_message = migration_message .. "prefix_root_parent_number\n"
    migration_message = migration_message .. "(ej: sx_FootSteps_Dirt_01)\n\n"
    migration_message = migration_message .. "¿Continuar con la migración?"
    
    local result = reaper.ShowMessageBox(migration_message, "Migrar Regiones", 1)
    if result ~= 1 then return end
    
    local extracted_count = extract_hierarchy_from_region_names()
    local marker_count = reaper.CountProjectMarkers(0)
    local region_count = 0
    
    -- Contar regiones totales
    for i = 0, marker_count - 1 do
        local _, isrgn, _, _, _, _ = reaper.EnumProjectMarkers(i)
        if isrgn then
            region_count = region_count + 1
        end
    end
    
    local result_message = "📊 RESULTADO DE LA MIGRACIÓN 📊\n\n"
    result_message = result_message .. string.format("Regiones totales: %d\n", region_count)
    result_message = result_message .. string.format("Jerarquías extraídas: %d\n", extracted_count)
    result_message = result_message .. string.format("Sin información: %d\n\n", region_count - extracted_count)
    
    if extracted_count > 0 then
        result_message = result_message .. "✅ Migración exitosa!\n"
        result_message = result_message .. "Ahora puedes usar las funciones de jerarquía.\n\n"
        result_message = result_message .. "Usa '🔍 Analyze Hierarchies' para ver los resultados."
    else
        result_message = result_message .. "❌ No se pudo extraer información jerárquica.\n\n"
        result_message = result_message .. "POSIBLES SOLUCIONES:\n"
        result_message = result_message .. "1. Recrear regiones con 'Create regions'\n"
        result_message = result_message .. "2. Usar migración manual (siguiente opción)\n"
        result_message = result_message .. "3. Usar renderizado normal sin jerarquías"
    end
    
    reaper.ShowMessageBox(result_message, "Resultado de Migración", 0)
end

-- Migración manual para regiones que no siguen el patrón estándar
local function manual_region_migration()
    local regions = {}
    local marker_count = reaper.CountProjectMarkers(0)
    
    -- Obtener todas las regiones
    for i = 0, marker_count - 1 do
        local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(i)
        if isrgn then
            table.insert(regions, {
                name = name,
                start = pos,
                end_pos = rgnend,
                index = i
            })
        end
    end
    
    if #regions == 0 then
        reaper.ShowMessageBox("No hay regiones en el proyecto.", "Sin Regiones", 0)
        return
    end
    
    local manual_message = "🔧 MIGRACIÓN MANUAL 🔧\n\n"
    manual_message = manual_message .. "Para cada región, ingresa manualmente:\n"
    manual_message = manual_message .. "• Root (carpeta padre)\n"
    manual_message = manual_message .. "• Parent (subcarpeta)\n\n"
    manual_message = manual_message .. string.format("Se procesarán %d regiones.\n\n", #regions)
    manual_message = manual_message .. "Formato de entrada: root,parent\n"
    manual_message = manual_message .. "Ejemplo: FootSteps,Dirt\n\n"
    manual_message = manual_message .. "¿Continuar?"
    
    local result = reaper.ShowMessageBox(manual_message, "Migración Manual", 1)
    if result ~= 1 then return end
    
    local migrated_count = 0
    
    for i, region in ipairs(regions) do
        local prompt = string.format("Región %d de %d:\n%s\n\nIngresa: root,parent", i, #regions, region.name)
        
        local retval, user_input = reaper.GetUserInputs("Migración Manual", 1, "root,parent:", "")
        
        if retval and user_input ~= "" then
            local root, parent = user_input:match("([^,]+),([^,]+)")
            if root and parent then
                -- Limpiar espacios
                root = root:match("^%s*(.-)%s*$")
                parent = parent:match("^%s*(.-)%s*$")
                
                update_region_hierarchy(region.index, root, parent)
                migrated_count = migrated_count + 1
            else
                reaper.ShowMessageBox("Formato incorrecto. Saltando región: " .. region.name, "Error de Formato", 0)
            end
        else
            -- Usuario canceló o saltó
            break
        end
    end
    
    local final_message = string.format("✅ Migración manual completada!\n\nRegiones migradas: %d de %d\n\nAhora puedes usar las funciones de jerarquía.", migrated_count, #regions)
    reaper.ShowMessageBox(final_message, "Migración Completada", 0)
end

-- Verificar si las regiones actuales tienen información jerárquica
local function check_hierarchy_data_status()
    local regions = {}
    local marker_count = reaper.CountProjectMarkers(0)
    
    for i = 0, marker_count - 1 do
        local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(i)
        if isrgn then
            table.insert(regions, {name = name, index = i})
        end
    end
    
    if #regions == 0 then
        reaper.ShowMessageBox("No hay regiones en el proyecto.", "Sin Regiones", 0)
        return
    end
    
    local with_data = 0
    local without_data = 0
    
    for _, region in ipairs(regions) do
        local hierarchy = get_region_hierarchy(region.index)
        if hierarchy.root ~= "General" and hierarchy.parent ~= "Parent" then
            with_data = with_data + 1
        else
            without_data = without_data + 1
        end
    end
    
    local status_message = "📊 ESTADO DE INFORMACIÓN JERÁRQUICA 📊\n\n"
    status_message = status_message .. string.format("Regiones totales: %d\n", #regions)
    status_message = status_message .. string.format("Con información jerárquica: %d\n", with_data)
    status_message = status_message .. string.format("Sin información jerárquica: %d\n\n", without_data)
    
    if with_data == #regions then
        status_message = status_message .. "✅ Todas las regiones tienen información jerárquica.\n"
        status_message = status_message .. "Puedes usar todas las funciones de jerarquía."
    elseif with_data > 0 then
        status_message = status_message .. "⚠️  Información jerárquica parcial.\n"
        status_message = status_message .. "Algunas funciones pueden no trabajar correctamente.\n\n"
        status_message = status_message .. "RECOMENDACIÓN: Migrar regiones restantes."
    else
        status_message = status_message .. "❌ Ninguna región tiene información jerárquica.\n\n"
        status_message = status_message .. "SOLUCIONES:\n"
        status_message = status_message .. "1. Usar 'Migrate Existing Regions'\n"
        status_message = status_message .. "2. Recrear regiones con 'Create regions'\n"
        status_message = status_message .. "3. Usar renderizado normal"
    end
    
    reaper.ShowMessageBox(status_message, "Estado de Información", 0)
end

-- Función mejorada de análisis que maneja regiones sin información
local function analyze_hierarchies_safe()
    local regions = {}
    local marker_count = reaper.CountProjectMarkers(0)
    
    for i = 0, marker_count - 1 do
        local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(i)
        if isrgn then
            table.insert(regions, {
                name = name,
                start = pos,
                end_pos = rgnend,
                index = i
            })
        end
    end
    
    if #regions == 0 then
        reaper.ShowMessageBox("No hay regiones en el proyecto.", "Sin Regiones", 0)
        return {}
    end
    
    -- Verificar si hay información jerárquica
    local has_hierarchy_data = false
    for _, region in ipairs(regions) do
        local hierarchy = get_region_hierarchy(region.index)
        if hierarchy.root ~= "General" and hierarchy.parent ~= "Parent" then
            has_hierarchy_data = true
            break
        end
    end
    
    if not has_hierarchy_data then
        local no_data_message = "❌ SIN INFORMACIÓN JERÁRQUICA ❌\n\n"
        no_data_message = no_data_message .. "Las regiones existentes no tienen información\n"
        no_data_message = no_data_message .. "jerárquica necesaria para el análisis.\n\n"
        no_data_message = no_data_message .. "SOLUCIONES DISPONIBLES:\n\n"
        no_data_message = no_data_message .. "1️⃣ MIGRACIÓN AUTOMÁTICA\n"
        no_data_message = no_data_message .. "   • Usar 'Migrate Existing Regions'\n"
        no_data_message = no_data_message .. "   • Extrae info de nombres de regiones\n\n"
        no_data_message = no_data_message .. "2️⃣ MIGRACIÓN MANUAL\n"
        no_data_message = no_data_message .. "   • Usar 'Manual Migration'\n"
        no_data_message = no_data_message .. "   • Ingresar root,parent manualmente\n\n"
        no_data_message = no_data_message .. "3️⃣ RECREAR REGIONES\n"
        no_data_message = no_data_message .. "   • Seleccionar subcarpetas originales\n"
        no_data_message = no_data_message .. "   • Usar 'Create regions' nuevamente\n\n"
        no_data_message = no_data_message .. "¿Quieres intentar migración automática ahora?"
        
        local result = reaper.ShowMessageBox(no_data_message, "Sin Información Jerárquica", 1)
        if result == 1 then
            migrate_existing_regions()
        end
        return {}
    end
    
    -- Proceder con análisis normal
    local hierarchies = {}
    
    for _, region in ipairs(regions) do
        local hierarchy = get_region_hierarchy(region.index)
        local root = hierarchy.root
        local parent = hierarchy.parent
        local hierarchy_key = root .. "|" .. parent
        
        if not hierarchies[hierarchy_key] then
            hierarchies[hierarchy_key] = {
                root = root,
                parent = parent,
                regions = {},
                display_name = root .. " > " .. parent
            }
        end
        
        table.insert(hierarchies[hierarchy_key].regions, region)
    end
    
    local hierarchy_list = {}
    for _, hierarchy in pairs(hierarchies) do
        table.insert(hierarchy_list, hierarchy)
    end
    
    return hierarchy_list
end

-- Mostrar análisis de jerarquías (actualizado para usar función segura)
local function show_hierarchy_analysis()
    local hierarchies = analyze_hierarchies_safe()
    
    if #hierarchies == 0 then
        return
    end
    
    local analysis_message = "📊 ANÁLISIS DE JERARQUÍAS 📊\n\n"
    analysis_message = analysis_message .. string.format("Total de jerarquías: %d\n\n", #hierarchies)
    
    for i, hierarchy in ipairs(hierarchies) do
        analysis_message = analysis_message .. string.format("%d. %s\n", i, hierarchy.display_name)
        analysis_message = analysis_message .. string.format("   Regiones: %d\n", #hierarchy.regions)
        
        -- Mostrar primeras 3 regiones
        for j, region in ipairs(hierarchy.regions) do
            if j <= 3 then
                analysis_message = analysis_message .. string.format("   • %s\n", region.name)
            elseif j == 4 then
                analysis_message = analysis_message .. string.format("   • ... y %d más\n", #hierarchy.regions - 3)
                break
            end
        end
        analysis_message = analysis_message .. "\n"
    end
    
    if #hierarchies > 1 then
        analysis_message = analysis_message .. "🎯 RECOMENDACIÓN: Usar renderizado manual por jerarquías\n"
        analysis_message = analysis_message .. "para evitar que todos los archivos se guarden en la misma carpeta."
    else
        analysis_message = analysis_message .. "✅ Una sola jerarquía detectada.\n"
        analysis_message = analysis_message .. "El renderizado normal funcionará correctamente."
    end
    
    reaper.ShowMessageBox(analysis_message, "Análisis de Jerarquías", 0)
end

-- Preparar cola de renderizado por jerarquías (actualizado)
local function prepare_hierarchy_render_queue()
    local hierarchies = analyze_hierarchies_safe()
    
    if #hierarchies == 0 then
        return false
    end
    
    if #hierarchies == 1 then
        local single_msg = "Solo hay una jerarquía detectada.\n\n"
        single_msg = single_msg .. "¿Quieres usar renderizado normal en su lugar?\n"
        single_msg = single_msg .. "(Recomendado para una sola jerarquía)"
        
        local result = reaper.ShowMessageBox(single_msg, "Una Sola Jerarquía", 4) -- Yes/No
        if result == 6 then -- Yes
            return false
        end
    end
    
    -- Mostrar información de la cola
    local queue_message = "🎯 RENDERIZADO MANUAL POR JERARQUÍAS 🎯\n\n"
    queue_message = queue_message .. string.format("Se configurarán %d jerarquías para renderizado:\n\n", #hierarchies)
    
    for i, hierarchy in ipairs(hierarchies) do
        queue_message = queue_message .. string.format("%d. %s (%d regiones)\n", i, hierarchy.display_name, #hierarchy.regions)
    end
    
    queue_message = queue_message .. "\n📋 PROCESO:\n"
    queue_message = queue_message .. "1. Se configurará cada jerarquía individualmente\n"
    queue_message = queue_message .. "2. Cada una tendrá su ruta y patrón específico\n"
    queue_message = queue_message .. "3. Renderizas manualmente una por una\n"
    queue_message = queue_message .. "4. Garantiza archivos en carpetas correctas\n\n"
    queue_message = queue_message .. "¿Iniciar el proceso?"
    
    local result = reaper.ShowMessageBox(queue_message, "Confirmar Renderizado por Jerarquías", 1) -- OK/Cancel
    if result ~= 1 then
        return false
    end
    
    -- Guardar cola de renderizado
    hierarchy_render_queue = hierarchies
    current_hierarchy_index = 1
    
    return true
end

-- Configurar REAPER para renderizar la siguiente jerarquía
local function setup_next_hierarchy_render()
    if #hierarchy_render_queue == 0 then
        reaper.ShowMessageBox("No hay jerarquías en la cola de renderizado.", "Cola Vacía", 0)
        return false
    end
    
    if current_hierarchy_index > #hierarchy_render_queue then
        reaper.ShowMessageBox("🎉 Todas las jerarquías han sido procesadas!", "Renderizado Completado", 0)
        hierarchy_render_queue = {}
        current_hierarchy_index = 1
        return false
    end
    
    local hierarchy = hierarchy_render_queue[current_hierarchy_index]
    
    -- Construir ruta de salida para esta jerarquía
    local base_path = custom_output_path ~= "" and custom_output_path or reaper.GetProjectPath("") .. "/Renders/"
    
    -- Añadir carpeta de tipo
    local type_folder = "SFX"
    if prefix_type == "mx" then type_folder = "Music"
    elseif prefix_type == "dx" then type_folder = "Dialogue"
    elseif prefix_type == "env" then type_folder = "Environment" end
    
    local hierarchy_path = base_path .. type_folder .. "/"
    
    -- Añadir carpeta de root
    local clean_root = hierarchy.root == "Root" and "General" or clean_name(hierarchy.root)
    hierarchy_path = hierarchy_path .. clean_root .. "/"
    
    -- Añadir carpeta de parent
    hierarchy_path = hierarchy_path .. clean_name(hierarchy.parent) .. "/"
    
    -- Crear directorios si no existen
    reaper.RecursiveCreateDirectory(hierarchy_path, 0)
    
    -- Configurar REAPER
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE", hierarchy_path, true)
    
    -- Expandir wildcards para esta jerarquía específica
    local expanded_pattern = wildcard_template
        :gsub("%$root", hierarchy.root)
        :gsub("%$parent", hierarchy.parent)
    
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", expanded_pattern, true)
    reaper.GetSetProjectInfo_String(0, "RENDER_BOUNDSFLAG", "1", true) -- Regiones
    reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT", "wav", true)
    reaper.GetSetProjectInfo_String(0, "RENDER_SETTINGS", "24bit", true)
    
    -- Mostrar información de configuración
    local config_message = string.format("✅ JERARQUÍA %d de %d CONFIGURADA ✅\n\n", current_hierarchy_index, #hierarchy_render_queue)
    config_message = config_message .. string.format("Jerarquía: %s\n", hierarchy.display_name)
    config_message = config_message .. string.format("Carpeta: %s\n", hierarchy_path)
    config_message = config_message .. string.format("Patrón: %s\n", expanded_pattern)
    config_message = config_message .. string.format("Regiones: %d\n\n", #hierarchy.regions)
    
    config_message = config_message .. "REGIONES A RENDERIZAR:\n"
    for i, region in ipairs(hierarchy.regions) do
        if i <= 5 then
            config_message = config_message .. string.format("• %s\n", region.name)
        elseif i == 6 then
            config_message = config_message .. string.format("• ... y %d más\n", #hierarchy.regions - 5)
            break
        end
    end
    
    config_message = config_message .. "\n💡 IMPORTANTE:\n"
    config_message = config_message .. "• Se abrirá el diálogo de render\n"
    config_message = config_message .. "• Verifica que 'Regiones/marcadores' esté seleccionado\n"
    config_message = config_message .. "• Renderiza solo esta jerarquía\n"
    config_message = config_message .. "• Luego usa 'Siguiente Jerarquía' para continuar\n\n"
    config_message = config_message .. "¿Abrir diálogo de render?"
    
    local result = reaper.ShowMessageBox(config_message, "Jerarquía Configurada", 1) -- OK/Cancel
    if result == 1 then
        -- Incrementar índice para la próxima jerarquía
        current_hierarchy_index = current_hierarchy_index + 1
        
        -- Abrir diálogo de render
        reaper.Main_OnCommand(40015, 0)
        return true
    end
    
    return false
end

-- Mostrar estado de la cola de renderizado
local function show_render_queue_status()
    if #hierarchy_render_queue == 0 then
        reaper.ShowMessageBox("No hay cola de renderizado activa.\nUsa 'Preparar Renderizado por Jerarquías' primero.", "Sin Cola", 0)
        return
    end
    
    local status_message = "📋 ESTADO DE LA COLA DE RENDERIZADO 📋\n\n"
    status_message = status_message .. string.format("Progreso: %d de %d jerarquías\n\n", current_hierarchy_index - 1, #hierarchy_render_queue)
    
    for i, hierarchy in ipairs(hierarchy_render_queue) do
        local status_icon = "⏳"
        if i < current_hierarchy_index then
            status_icon = "✅"
        elseif i == current_hierarchy_index then
            status_icon = "▶️"
        end
        
        status_message = status_message .. string.format("%s %d. %s (%d regiones)\n", 
            status_icon, i, hierarchy.display_name, #hierarchy.regions)
    end
    
    status_message = status_message .. "\n📌 LEYENDA:\n"
    status_message = status_message .. "✅ Configurado y listo\n"
    status_message = status_message .. "▶️ Siguiente a configurar\n"
    status_message = status_message .. "⏳ Pendiente\n"
    
    if current_hierarchy_index <= #hierarchy_render_queue then
        status_message = status_message .. "\n🎯 Usa 'Siguiente Jerarquía' para continuar."
    else
        status_message = status_message .. "\n🎉 ¡Todas las jerarquías completadas!"
    end
    
    reaper.ShowMessageBox(status_message, "Estado de la Cola", 0)
end

-- ==================================================
-- Funciones principales
-- ==================================================

local function process_subfolders()
    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()
    
    local orig_variations = variations
    
    if prefix_type ~= "sx" then
        variations = 0
    end
    
    if variations > 0 and (randomize_position > 0 or 
       random_params.volume.enable or random_params.pan.enable or 
       random_params.pitch.enable or random_params.rate.enable or 
       random_params.length.enable or random_params.fadein.enable or 
       random_params.fadeout.enable or random_params.fadeshape.enable) then
        math.randomseed(os.time())
    end
    
    local total = create_regions_from_subfolders()
    
    if total == 0 then
        local msg = "No valid subfolders found.\n\n"
        msg = msg .. "Select SUB-FOLDERS that meet:\n"
        msg = msg .. "1. Have folder depth = 1\n"
        msg = msg .. "2. Contain child tracks\n"
        msg = msg .. "3. Are within a folder structure\n\n"
        msg = msg .. "Example structure:\n"
        msg = msg .. "Footsteps (root folder)\n"
        msg = msg .. "  └── dirt (subfolder - SELECT THIS)\n"
        msg = msg .. "      ├── Move_Air\n"
        msg = msg .. "      └── Move_Air2"
        
        reaper.ShowMessageBox(msg, "Selection Error", 0)
    end
    
    variations = orig_variations
    
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Create regions from subfolders", -1)
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

-- ==================================================
-- Interfaz gráfica
-- ==================================================

function loop()
    local visible, open = reaper.ImGui_Begin(ctx, 'SFX Renderer v2.2', true, 
        reaper.ImGui_WindowFlags_AlwaysAutoResize())
    
    if visible then
        reaper.ImGui_PushFont(ctx, font)
        
        local sel_count = reaper.CountSelectedTracks(0)
        reaper.ImGui_Text(ctx, "Selected tracks: " .. sel_count)
        
        if sel_count > 0 then
            local first_track = reaper.GetSelectedTrack(0, 0)
            local depth = get_folder_depth(first_track)
            reaper.ImGui_Text(ctx, "First track depth: " .. depth)
            
            local root_track = get_parent_track(first_track)
            if root_track then
                local root_name = get_track_name(root_track)
                reaper.ImGui_Text(ctx, "Detected root folder: " .. clean_name(root_name))
            end
        end

        reaper.ImGui_Separator(ctx)
        
        -- Selector de tipo de archivo
        reaper.ImGui_Text(ctx, "File type:")
        reaper.ImGui_SameLine(ctx)
        local types = "SFX\0Music\0Dialogue\0Environment\0"
        local current_type = (prefix_type == "sx") and 0 or (prefix_type == "mx") and 1 or (prefix_type == "dx") and 2 or 3
        local changed, new_idx = reaper.ImGui_Combo(ctx, "##filetype", current_type, types)
        if changed then
            prefix_type = (new_idx == 0) and "sx" or (new_idx == 1) and "mx" or (new_idx == 2) and "dx" or "env"
        end
        
        -- Configuración específica para cada tipo
        if prefix_type == "sx" then
            reaper.ImGui_Text(ctx, "Prefix for region names:")
            reaper.ImGui_SetNextItemWidth(ctx, 100)
            _, prefix = reaper.ImGui_InputText(ctx, "##prefix", prefix)
        elseif prefix_type == "mx" then
            reaper.ImGui_Text(ctx, "BPM:")
            reaper.ImGui_SetNextItemWidth(ctx, 120)
            _, music_bpm = reaper.ImGui_InputInt(ctx, "##music_bpm", music_bpm)
            music_bpm = math.max(1, music_bpm)
            
            reaper.ImGui_Text(ctx, "Meter (e.g: 4-4):")
            reaper.ImGui_SetNextItemWidth(ctx, 120)
            _, music_meter = reaper.ImGui_InputText(ctx, "##music_meter", music_meter)
        elseif prefix_type == "dx" then
            reaper.ImGui_Text(ctx, "Character:")
            reaper.ImGui_SetNextItemWidth(ctx, 180)
            _, dx_character = reaper.ImGui_InputText(ctx, "##dx_character", dx_character)
            
            reaper.ImGui_Text(ctx, "Quest Type (e.g: SQ, HC):")
            reaper.ImGui_SetNextItemWidth(ctx, 120)
            _, dx_quest_type = reaper.ImGui_InputText(ctx, "##dx_quest_type", dx_quest_type)
            
            reaper.ImGui_Text(ctx, "Quest Name:")
            reaper.ImGui_SetNextItemWidth(ctx, 180)
            _, dx_quest_name = reaper.ImGui_InputText(ctx, "##dx_quest_name", dx_quest_name)
            
            reaper.ImGui_Text(ctx, "Line Number:")
            reaper.ImGui_SetNextItemWidth(ctx, 80)
            _, dx_line_number = reaper.ImGui_InputInt(ctx, "##dx_line_number", dx_line_number)
            dx_line_number = math.max(1, dx_line_number)
        end
        
        reaper.ImGui_Separator(ctx)
        
        -- Mostrar opciones solo para SFX
        if prefix_type == "sx" then
            reaper.ImGui_Text(ctx, "Variations per subfolder (0 = regions only):")
            reaper.ImGui_SetNextItemWidth(ctx, 100)
            _, variations = reaper.ImGui_InputInt(ctx, "Variations", variations)
            variations = math.max(0, math.min(variations, 100))
            
            if variations > 0 then
                reaper.ImGui_Text(ctx, "Separation between variations (s):")
                reaper.ImGui_SetNextItemWidth(ctx, 100)
                _, separation_time = reaper.ImGui_InputDouble(ctx, "##sep", separation_time)
                separation_time = math.max(0.1, separation_time)
                
                reaper.ImGui_Text(ctx, "Position randomization (s):")
                reaper.ImGui_SetNextItemWidth(ctx, 150)
                _, randomize_position = reaper.ImGui_SliderDouble(ctx, "##rand_pos", randomize_position, 
                    slider_ranges.position.min, slider_ranges.position.max, "Position: %.2f s")
                
                if reaper.ImGui_CollapsingHeader(ctx, "Variation Parameters") then
                    reaper.ImGui_Text(ctx, "Enable and adjust parameters for variations:")
                    
                    _, random_params.volume.enable = reaper.ImGui_Checkbox(ctx, "Volume", random_params.volume.enable)
                    if random_params.volume.enable then
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, 200)
                        _, random_params.volume.amount = reaper.ImGui_SliderDouble(ctx, "##rand_vol", 
                            random_params.volume.amount, slider_ranges.volume.min, slider_ranges.volume.max, 
                            "%.2f dB")
                    end
                    
                    _, random_params.pan.enable = reaper.ImGui_Checkbox(ctx, "Pan", random_params.pan.enable)
                    if random_params.pan.enable then
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, 200)
                        _, random_params.pan.amount = reaper.ImGui_SliderDouble(ctx, "##rand_pan", 
                            random_params.pan.amount, slider_ranges.pan.min, slider_ranges.pan.max, 
                            "%.2f")
                    end
                    
                    _, random_params.pitch.enable = reaper.ImGui_Checkbox(ctx, "Pitch", random_params.pitch.enable)
                    if random_params.pitch.enable then
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, 200)
                        _, random_params.pitch.amount = reaper.ImGui_SliderDouble(ctx, "##rand_pitch", 
                            random_params.pitch.amount, slider_ranges.pitch.min, slider_ranges.pitch.max, 
                            "%.1f semitones")
                    end
                    
                    _, random_params.rate.enable = reaper.ImGui_Checkbox(ctx, "Rate", random_params.rate.enable)
                    if random_params.rate.enable then
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, 200)
                        _, random_params.rate.amount = reaper.ImGui_SliderDouble(ctx, "##rand_rate", 
                            random_params.rate.amount, slider_ranges.rate.min, slider_ranges.rate.max, 
                            "%.2f")
                    end
                    
                    _, random_params.length.enable = reaper.ImGui_Checkbox(ctx, "Length", random_params.length.enable)
                    if random_params.length.enable then
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, 200)
                        _, random_params.length.amount = reaper.ImGui_SliderDouble(ctx, "##rand_len", 
                            random_params.length.amount, slider_ranges.length.min, slider_ranges.length.max, 
                            "%.2f")
                    end
                    
                    _, random_params.fadein.enable = reaper.ImGui_Checkbox(ctx, "Fade In", random_params.fadein.enable)
                    if random_params.fadein.enable then
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, 200)
                        _, random_params.fadein.amount = reaper.ImGui_SliderDouble(ctx, "##rand_fadein", 
                            random_params.fadein.amount, slider_ranges.fadein.min, slider_ranges.fadein.max, 
                            "%.2f")
                    end
                    
                    _, random_params.fadeout.enable = reaper.ImGui_Checkbox(ctx, "Fade Out", random_params.fadeout.enable)
                    if random_params.fadeout.enable then
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, 200)
                        _, random_params.fadeout.amount = reaper.ImGui_SliderDouble(ctx, "##rand_fadeout", 
                            random_params.fadeout.amount, slider_ranges.fadeout.min, slider_ranges.fadeout.max, 
                            "%.2f")
                    end
                    
                    _, random_params.fadeshape.enable = reaper.ImGui_Checkbox(ctx, "Fade Shape", random_params.fadeshape.enable)
                    if random_params.fadeshape.enable then
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_Text(ctx, "(randomly changes)")
                    end
                end
            end
        end

        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Text(ctx, "Filename Pattern:")
        
        reaper.ImGui_SetNextItemWidth(ctx, 300)
        _, wildcard_template = reaper.ImGui_InputText(ctx, "##wildcard_template", wildcard_template)
        
        reaper.ImGui_Text(ctx, "Available wildcards:")
        reaper.ImGui_BulletText(ctx, "$root: Parent folder name")
        reaper.ImGui_BulletText(ctx, "$parent: Subfolder name (selected track)")
        reaper.ImGui_BulletText(ctx, "$region: Region name")
        reaper.ImGui_BulletText(ctx, "Also any other REAPER wildcard (e.g. $track)")
        
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Text(ctx, "Output folder:")
        
        local display_path = custom_output_path
        if display_path == "" then
            display_path = "Project/Renders/ (default)"
        end
        
        reaper.ImGui_Text(ctx, "Current: " .. display_path)
        
        if reaper.ImGui_Button(ctx, "Browse Output Folder", 250, 30) then
            browse_output_folder()
        end
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Reset to Default", 150, 30) then
            custom_output_path = ""
        end

        -- Botones principales
        if reaper.ImGui_Button(ctx, "Create regions", 250, 40) then
            reaper.defer(process_subfolders)
        end
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Render All Regions", 250, 40) then
            prepare_render_with_existing_regions(true)
        end
        
        reaper.ImGui_NewLine(ctx)
        if reaper.ImGui_Button(ctx, "Render Selected Region", 250, 40) then
            prepare_render_with_existing_regions(false)
        end

        -- NUEVOS BOTONES PARA RENDERIZADO POR JERARQUÍAS
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Text(ctx, "Hierarchy Rendering:")
        
        if reaper.ImGui_Button(ctx, "Analyze Hierarchies", 166, 30) then
            show_hierarchy_analysis()
        end
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Prepare Queue", 166, 30) then
            prepare_hierarchy_render_queue()
        end
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Next Hierarchy", 166, 30) then
            setup_next_hierarchy_render()
        end
        
        reaper.ImGui_Spacing(ctx)
        if reaper.ImGui_Button(ctx, "Queue Status", 166, 25) then
            show_render_queue_status()
        end
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Clear Queue", 166, 25) then
            hierarchy_render_queue = {}
            current_hierarchy_index = 1
            reaper.ShowMessageBox("Cola de renderizado limpiada.", "Cola Limpiada", 0)
        end
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Check Status", 166, 25) then
            check_hierarchy_data_status()
        end
        
        -- NUEVOS BOTONES PARA MIGRACIÓN DE REGIONES EXISTENTES
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Text(ctx, "Migration Tools:")
        
        if reaper.ImGui_Button(ctx, "Migrate Existing Regions", 250, 30) then
            migrate_existing_regions()
        end
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Manual Migration", 250, 30) then
            manual_region_migration()
        end
        
        -- Botón para actualizar jerarquía de regiones renombradas
        reaper.ImGui_Spacing(ctx)
        if reaper.ImGui_Button(ctx, "Update Hierarchy", 166, 25) then
            update_hierarchy_for_renamed_region()
        end

        -- Créditos
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Text(ctx, "Developed by Daniel \"Panchuel\" Montoya")
        reaper.ImGui_Spacing(ctx)

        reaper.ImGui_PopFont(ctx)
        reaper.ImGui_End(ctx)
    end

    if not open then
        -- Guardar configuración al cerrar la ventana
        local settings_to_save = {
            prefix = prefix,
            prefix_type = prefix_type,
            variations = variations,
            separation_time = separation_time,
            randomize_position = randomize_position,
            wildcard_template = wildcard_template,
            custom_output_path = custom_output_path,
            music_bpm = music_bpm,
            music_meter = music_meter,
            dx_character = dx_character,
            dx_quest_type = dx_quest_type,
            dx_quest_name = dx_quest_name,
            dx_line_number = dx_line_number,
            volume_enable = random_params.volume.enable,
            volume_amount = random_params.volume.amount,
            pan_enable = random_params.pan.enable,
            pan_amount = random_params.pan.amount,
            pitch_enable = random_params.pitch.enable,
            pitch_amount = random_params.pitch.amount,
            rate_enable = random_params.rate.enable,
            rate_amount = random_params.rate.amount,
            length_enable = random_params.length.enable,
            length_amount = random_params.length.amount,
            fadein_enable = random_params.fadein.enable,
            fadein_amount = random_params.fadein.amount,
            fadeout_enable = random_params.fadeout.enable,
            fadeout_amount = random_params.fadeout.amount,
            fadeshape_enable = random_params.fadeshape.enable
        }
        
        save_settings(settings_to_save)
        
        if reaper.ImGui_DestroyContext then
            reaper.ImGui_DestroyContext(ctx)
        end
    else
        reaper.defer(loop)
    end
end

-- Iniciar
reaper.defer(loop)