--@description Renderizador SFX con jerarquía + GUI + Wildcards + Persistencia
--@version 8.9
--@author Panchu
--@provides [main] .

local reaper = reaper
local ctx = reaper.ImGui_CreateContext('SFX Renderer')
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

-- Asignar valores a variables
local prefix = settings.prefix
local prefix_type = settings.prefix_type
local valid_tracks = {}
local region_root_data = {}
local region_parent_data = {}
local variations = settings.variations
local separation_time = settings.separation_time
local randomize_position = settings.randomize_position
local progress = 0.0
local processing = false
local ORIGINAL_TAG = "SFX_ORIGINAL"
local VARIATION_TAG = "SFX_VARIATION"
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

-- ==================================================
-- Funciones auxiliares
-- ==================================================

-- Función para limpiar nombres (remover caracteres inválidos)
local function clean_name(name)
    return name:gsub("[^%w_]", "_"):gsub("__+", "_")
end

-- Función para obtener nombre de track
local function get_track_name(track)
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    return name or "Unnamed"
end

-- Función para obtener índice de track
local function get_track_index(track)
    return reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
end

-- Función para obtener profundidad de carpeta
local function get_folder_depth(track)
    return reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
end

-- Función para encontrar el track padre
local function get_parent_track(track)
    local idx = get_track_index(track)
    if idx == 0 then return nil end  -- El primer track no puede tener padre
    
    -- Calcular nivel de anidamiento actual
    local current_level = 0
    for i = 0, idx - 1 do
        current_level = current_level + reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, i), "I_FOLDERDEPTH")
    end
    
    -- Buscar hacia atrás el padre inmediato
    for i = idx - 1, 0, -1 do
        local candidate = reaper.GetTrack(0, i)
        local depth = reaper.GetMediaTrackInfo_Value(candidate, "I_FOLDERDEPTH")
        
        if depth == 1 then  -- Solo tracks que abren carpetas
            -- Calcular nivel en el candidato
            local candidate_level = 0
            for j = 0, i - 1 do
                candidate_level = candidate_level + reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, j), "I_FOLDERDEPTH")
            end
            
            -- Verificar si es el padre directo
            if candidate_level == current_level - 1 then
                return candidate
            end
        end
    end
    
    return nil  -- No se encontró padre
end

-- Función para obtener todos los tracks hijos de una carpeta
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

-- Función para obtener/setear notas de items
local function get_item_notes(item)
    local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    return notes or ""
end

local function set_item_notes(item, notes)
    reaper.GetSetMediaItemInfo_String(item, "P_NOTES", notes, true)
end

-- Función para verificar si un item es original
local function is_original_item(item)
    local notes = get_item_notes(item)
    return notes:find(ORIGINAL_TAG) and not notes:find(VARIATION_TAG)
end

-- Función para verificar si un item es variación
local function is_variation_item(item)
    local notes = get_item_notes(item)
    return notes:find(VARIATION_TAG)
end

-- Función para marcar items originales (solo si no están marcados)
local function mark_original_items(folder_track)
    local child_tracks = get_child_tracks(folder_track)
    for _, child in ipairs(child_tracks) do
        for k = 0, reaper.CountTrackMediaItems(child) - 1 do
            local item = reaper.GetTrackMediaItem(child, k)
            
            -- Solo marcar si no tiene ninguna identificación
            if not is_original_item(item) and not is_variation_item(item) then
                local current_notes = get_item_notes(item)
                set_item_notes(item, current_notes .. " " .. ORIGINAL_TAG)
            end
        end
    end
end

-- Función para encontrar el tiempo máximo de cualquier item en los tracks
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

-- Función para verificar si un track es una subcarpeta válida
local function is_valid_subfolder(track)
    if get_folder_depth(track) ~= 1 then return false end
    local child_tracks = get_child_tracks(track)
    return #child_tracks > 0
end

-- Función para expandir wildcards personalizados
local function expand_wildcards(pattern, region_name)
    if region_root_data[region_name] then
        pattern = pattern:gsub("%$root", region_root_data[region_name])
    else
        pattern = pattern:gsub("%$root", "Root")
    end
    
    if region_parent_data[region_name] then
        pattern = pattern:gsub("%$parent", region_parent_data[region_name])
    else
        pattern = pattern:gsub("%$parent", "Parent")
    end
    
    pattern = pattern:gsub("%$region", region_name or "Region")
    
    return pattern
end

-- ==================================================
-- Funciones principales
-- ==================================================

-- Función para calcular el rango de tiempo de una carpeta (solo items originales)
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

-- Función para aplicar parámetros aleatorizados a un nuevo item
local function apply_random_parameters(new_item, new_take, original_item, original_take)
    -- Aleatorizar volumen (dB)
    if random_params.volume.enable and random_params.volume.amount > 0 then
        local vol_db = (math.random() * 2 - 1) * random_params.volume.amount
        local vol_linear = 10^(vol_db / 20)
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_VOL", vol_linear)
    end
    
    -- Aleatorizar pan
    if random_params.pan.enable and random_params.pan.amount > 0 then
        local pan_val = (math.random() * 2 - 1) * random_params.pan.amount
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_PAN", pan_val)
    end
    
    -- Aleatorizar pitch (semitonos)
    if random_params.pitch.enable and random_params.pitch.amount > 0 then
        local pitch_offset = (math.random() * 2 - 1) * random_params.pitch.amount
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_PITCH", pitch_offset)
    end
    
    -- Aleatorizar rate (velocidad de reproducción)
    if random_params.rate.enable and random_params.rate.amount > 0 then
        local rate_factor = 1.0 + (math.random() * 2 - 1) * random_params.rate.amount
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_PLAYRATE", rate_factor)
        
        -- Ajustar longitud para compensar el cambio de velocidad
        local length = reaper.GetMediaItemInfo_Value(new_item, "D_LENGTH")
        reaper.SetMediaItemInfo_Value(new_item, "D_LENGTH", length / rate_factor)
    end
    
    -- Aleatorizar longitud (sin cambiar pitch)
    if random_params.length.enable and random_params.length.amount > 0 then
        local length_factor = 1.0 + (math.random() * 2 - 1) * random_params.length.amount
        local length = reaper.GetMediaItemInfo_Value(new_item, "D_LENGTH")
        reaper.SetMediaItemInfo_Value(new_item, "D_LENGTH", length * length_factor)
    end
    
    -- Aleatorizar fades
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
    
    -- Aleatorizar forma de fades
    if random_params.fadeshape.enable and random_params.fadeshape.amount > 0 then
        local shapes = {0, 1, 2, 3}  -- 0=linear, 1=slow start, 2=slow end, 3=smooth
        local new_shape = shapes[math.random(1, #shapes)]
        reaper.SetMediaItemInfo_Value(new_item, "C_FADEINSHAPE", new_shape)
        reaper.SetMediaItemInfo_Value(new_item, "C_FADEOUTSHAPE", new_shape)
    end
end

-- Función para duplicar solo items originales
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
                    -- Obtener información del item
                    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    local snap = reaper.GetMediaItemInfo_Value(item, "D_SNAPOFFSET")
                    local mute = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
                    local lock = reaper.GetMediaItemInfo_Value(item, "C_LOCK")
                    local fadein = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN")
                    local fadeout = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
                    local fadeinshape = reaper.GetMediaItemInfo_Value(item, "C_FADEINSHAPE")
                    local fadeoutshape = reaper.GetMediaItemInfo_Value(item, "C_FADEOUTSHAPE")
                    
                    -- Crear un nuevo item en el mismo track
                    local new_item = reaper.AddMediaItemToTrack(child)
                    
                    -- Configurar el nuevo item
                    reaper.SetMediaItemInfo_Value(new_item, "D_POSITION", pos + total_offset)
                    reaper.SetMediaItemInfo_Value(new_item, "D_LENGTH", length)
                    reaper.SetMediaItemInfo_Value(new_item, "D_SNAPOFFSET", snap)
                    reaper.SetMediaItemInfo_Value(new_item, "B_MUTE", mute)
                    reaper.SetMediaItemInfo_Value(new_item, "C_LOCK", lock)
                    reaper.SetMediaItemInfo_Value(new_item, "D_FADEINLEN", fadein)
                    reaper.SetMediaItemInfo_Value(new_item, "D_FADEOUTLEN", fadeout)
                    reaper.SetMediaItemInfo_Value(new_item, "C_FADEINSHAPE", fadeinshape)
                    reaper.SetMediaItemInfo_Value(new_item, "C_FADEOUTSHAPE", fadeoutshape)
                    
                    -- Duplicar el take
                    local new_take = reaper.AddTakeToMediaItem(new_item)
                    local source = reaper.GetMediaItemTake_Source(take)
                    reaper.SetMediaItemTake_Source(new_take, source)
                    
                    -- Copiar propiedades del take
                    local vol = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
                    local pan = reaper.GetMediaItemTakeInfo_Value(take, "D_PAN")
                    local pitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH")
                    local playrate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
                    reaper.SetMediaItemTakeInfo_Value(new_take, "D_VOL", vol)
                    reaper.SetMediaItemTakeInfo_Value(new_take, "D_PAN", pan)
                    reaper.SetMediaItemTakeInfo_Value(new_take, "D_PITCH", pitch)
                    reaper.SetMediaItemTakeInfo_Value(new_take, "D_PLAYRATE", playrate)
                    
                    -- Aplicar parámetros aleatorizados
                    apply_random_parameters(new_item, new_take, item, take)
                    
                    -- Marcar como variación
                    set_item_notes(new_item, VARIATION_TAG)
                end
            end
        end
    end
    
    -- Actualizar la vista
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Duplicate original items", -1)
    reaper.PreventUIRefresh(-1)
end

-- Función para encontrar el máximo número de variación existente
local function find_max_variation_number(base_name)
    local max_number = 0
    local marker_count = reaper.CountProjectMarkers(0)
    
    for i = 0, marker_count - 1 do
        local _, isrgn, _, _, name, _ = reaper.EnumProjectMarkers(i)
        if isrgn and name then
            -- Buscar nombres con el patrón base_name_XX
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

-- Función principal para crear regiones
local function create_regions_from_subfolders()
    valid_tracks = {}
    region_root_data = {}  -- Reiniciar datos de wildcards
    region_parent_data = {}  -- Reiniciar datos de parent

    -- Obtener carpeta raíz común
    local root_folder = nil
    local root_name = "Project"
    
    if reaper.CountSelectedTracks(0) > 0 then
        local first_track = reaper.GetSelectedTrack(0, 0)
        root_folder = get_parent_track(first_track)
        
        if root_folder then
            root_name = get_track_name(root_folder)
        else
            local _, project_name = reaper.EnumProjects(-1, "")
            root_name = project_name:match("([^\\/]+)$"):gsub("%..+$", "") or "Project"
        end
    end

    -- Procesar cada subcarpeta seleccionada
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        local subfolder = reaper.GetSelectedTrack(0, i)
        if not is_valid_subfolder(subfolder) then goto continue end

        -- Marcar items originales (solo si no están marcados)
        mark_original_items(subfolder)

        local sub_name = clean_name(get_track_name(subfolder))
        local clean_root_name = root_folder and clean_name(get_track_name(root_folder)) or "Root"
        local clean_parent_name = clean_name(get_track_name(subfolder))  -- CORRECCIÓN: Usar nombre real del track

        -- Calcular rango de tiempo (solo items originales)
        local min_start, max_end = calculate_folder_time_range(subfolder)
        if min_start == math.huge or max_end == 0 then goto continue end

        local total_duration = max_end - min_start
        local base_name
        
        -- Construir nombre base según tipo de prefijo
        if prefix_type == "sx" then
            base_name = string.format("%s_%s_%s", prefix, clean_root_name, sub_name)
        elseif prefix_type == "mx" then
            base_name = string.format("%s_%s_%s_%d_%s", 
                prefix_type, clean_root_name, sub_name, music_bpm, music_meter)
        elseif prefix_type == "dx" then
            local char_field = dx_character ~= "" and dx_character or "unknown"
            local questType_field = dx_quest_type ~= "" and dx_quest_type or "SQ"
            local questName_field = dx_quest_name ~= "" and dx_quest_name or sub_name
            base_name = string.format("%s_%s_%s_%s_%02d", 
                prefix_type, char_field, questType_field, questName_field, dx_line_number)
        elseif prefix_type == "env" then
            base_name = string.format("env_%s_%s", clean_root_name, sub_name)
        end

        local actual_variations = variations > 0 and variations or 1
        
        -- Obtener el tiempo máximo actual en los tracks (para colocar después de todo)
        local max_end_all = get_max_end_time(subfolder)
        
        -- El desplazamiento base es después del último item existente
        local base_offset = max_end_all - min_start + separation_time
        
        -- Encontrar el máximo número de variación existente
        local max_variation = find_max_variation_number(base_name)
        
        for variation = 1, actual_variations do
            local rand_offset = 0
            if variations > 0 and randomize_position > 0 then
                rand_offset = (math.random() * 2 - 1) * randomize_position
            end
            
            local time_offset = 0
            if variations > 0 then
                time_offset = base_offset + (variation - 1) * (total_duration + separation_time)
                -- Duplicar solo items originales con el desplazamiento total
                duplicate_original_items(subfolder, time_offset + rand_offset)
            end
            
            local variation_number = max_variation + variation
            local region_name = string.format("%s_%02d", base_name, variation_number)
            
            local region_start, region_end
            if variations == 0 then
                region_start = min_start
                region_end = max_end
            else
                -- Usar el rango original desplazado para la región
                region_start = min_start + time_offset + rand_offset
                region_end = max_end + time_offset + rand_offset
            end
            
            -- Crear región sin color específico
            reaper.AddProjectMarker2(0, true, region_start, region_end, region_name, -1, 0)
            
            -- Almacenar root y parent para esta región
            region_root_data[region_name] = clean_root_name
            region_parent_data[region_name] = clean_parent_name  -- CORRECCIÓN: Usar nombre real
            
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

-- Función para obtener la región seleccionada
local function get_selected_region()
    local _, region_index = reaper.GetLastMarkerAndCurRegion(0, reaper.GetCursorPosition())
    if region_index >= 0 then
        local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(region_index)
        if isrgn then
            return name, pos, rgnend
        end
    end
    return nil
end

-- Función para obtener todas las regiones del proyecto
local function get_all_regions()
    local regions = {}
    local marker_count = reaper.CountProjectMarkers(0)
    
    for i = 0, marker_count - 1 do
        local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(i)
        if isrgn then
            table.insert(regions, {
                name = name,
                start = pos,
                end_pos = rgnend
            })
        end
    end
    
    return regions
end

-- Función para configurar la matriz de render
local function setup_render_matrix()
    if #valid_tracks == 0 then 
        reaper.ShowMessageBox("No hay regiones creadas aún.", "Error", 0)
        return false
    end
    
    -- Crear CSV para la matriz de render
    local csv_content = "Region,"
    
    -- Encabezados con nombres de tracks
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local _, name = reaper.GetTrackName(track)
        csv_content = csv_content .. name .. ","
    end
    
    -- Filas con asignación de tracks a regiones
    for _, region in ipairs(valid_tracks) do
        csv_content = csv_content .. "\n" .. region.name .. ","
        
        for i = 0, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, i)
            local include = 0
            
            -- Incluir solo tracks hijos de la carpeta
            local child_tracks = get_child_tracks(region.folder_track)
            for _, child in ipairs(child_tracks) do
                if child == track then
                    include = 1
                    break
                end
            end
            
            csv_content = csv_content .. include .. ","
        end
    end
    
    -- Obtener y crear directorio temporal
    local temp_dir = reaper.GetResourcePath() .. "/Temp/"
    reaper.RecursiveCreateDirectory(temp_dir, 0)
    
    -- Guardar CSV temporal
    local temp_path = temp_dir .. "render_matrix.csv"
    local file = io.open(temp_path, "w")
    if file then
        file:write(csv_content)
        file:close()
        
        -- Importar matriz de render
        reaper.GetSetProjectInfo_String(0, "RENDER_MATRIX", temp_path, true)
        return true
    else
        reaper.ShowMessageBox("No se pudo crear el archivo temporal: " .. temp_path, "Error", 0)
    end
    
    return false
end

-- Función para configurar el renderizado
local function configure_render_settings()
    -- Configurar ruta de salida (usar custom_output_path si está definida)
    local render_path = custom_output_path ~= "" and custom_output_path or reaper.GetProjectPath("") .. "/Renders/"
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE", render_path, true)
    
    -- Configurar formato
    reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT", "wav", true)
    
    -- Configurar profundidad de bits
    reaper.GetSetProjectInfo_String(0, "RENDER_SETTINGS", "24bit", true)
end

-- Función para abrir el diálogo de render
local function open_render_dialog()
    reaper.Main_OnCommand(40015, 0)  -- File: Render project to disk...
end

-- Función para preparar el renderizado con regiones existentes
local function prepare_render_with_existing_regions(selected_only)
    valid_tracks = {}
    
    -- Obtener regiones
    if selected_only then
        -- Solo la región seleccionada
        local name, start_pos, end_pos = get_selected_region()
        if name then
            table.insert(valid_tracks, {
                name = name,
                start = start_pos,
                end_pos = end_pos
            })
        else
            reaper.ShowMessageBox("No hay región seleccionada.", "Error", 0)
            return
        end
    else
        -- Todas las regiones
        valid_tracks = get_all_regions()
    end
    
    if #valid_tracks == 0 then
        reaper.ShowMessageBox("No hay regiones creadas.", "Error", 0)
        return
    end
    
    -- Configurar las opciones básicas de render
    configure_render_settings()
    
    -- Configurar ruta de salida con estructura de carpetas
    local render_path = custom_output_path ~= "" and custom_output_path or reaper.GetProjectPath("") .. "/Renders/"
    
    -- Añadir carpeta de tipo (SFX/Music/Dialogue)
    local type_folder = "SFX"
    if prefix_type == "mx" then type_folder = "Music"
    elseif prefix_type == "dx" then type_folder = "Dialogue"
    elseif prefix_type == "env" then type_folder = "Environment" end
    
    render_path = render_path .. type_folder .. "/"
    
    -- Obtener carpeta root de la primera región
    local root_folder_name = "General"
    local first_region = valid_tracks[1].name
    
    -- Intentar obtener el root folder de los datos almacenados
    if region_root_data[first_region] then
        root_folder_name = region_root_data[first_region]
    else
        -- Si no está en los datos, intentar obtenerlo de la selección actual
        if reaper.CountSelectedTracks(0) > 0 then
            local first_track = reaper.GetSelectedTrack(0, 0)
            local root_track = get_parent_track(first_track)
            if root_track then
                root_folder_name = clean_name(get_track_name(root_track))
            end
        end
    end
    
    -- Si es "Root", cambiarlo a "General"
    if root_folder_name == "Root" then
        root_folder_name = "General"
    end
    
    render_path = render_path .. root_folder_name .. "/"
    
    -- Crear directorios si no existen
    reaper.RecursiveCreateDirectory(render_path, 0)
    
    -- Configurar ruta final de render
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE", render_path, true)
    
    -- Obtener parent para expansión
    local parent_name = "Parent"
    if region_parent_data[first_region] then
        parent_name = region_parent_data[first_region]
    else
        -- Intentar obtener el nombre del track seleccionado
        if reaper.CountSelectedTracks(0) > 0 then
            local first_track = reaper.GetSelectedTrack(0, 0)
            parent_name = clean_name(get_track_name(first_track))
        end
    end
    
    -- EXPANDIR WILDCARDS ANTES DE CONFIGURAR EL PATRÓN
    local expanded_pattern = wildcard_template
        :gsub("%$root", root_folder_name)
        :gsub("%$parent", parent_name)  -- CORRECCIÓN: Usar valor real
        :gsub("%$region", first_region)
    
    -- Configurar patrón de nombre de archivo con wildcards expandidos
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", expanded_pattern, true)
    
    -- Abrir diálogo de render
    open_render_dialog()
end

-- Función para preparar el renderizado con regiones nuevas
local function prepare_render_with_new_regions()
    if #valid_tracks == 0 then
        reaper.ShowMessageBox("No hay regiones creadas. Primero crea regiones.", "Error", 0)
        return
    end
    
    -- Configurar las opciones básicas de render
    configure_render_settings()
    
    -- Configurar ruta de salida con estructura de carpetas
    local render_path = custom_output_path ~= "" and custom_output_path or reaper.GetProjectPath("") .. "/Renders/"
    
    -- Añadir carpeta de tipo (SFX/Music/Dialogue)
    local type_folder = "SFX"
    if prefix_type == "mx" then type_folder = "Music"
    elseif prefix_type == "dx" then type_folder = "Dialogue"
    elseif prefix_type == "env" then type_folder = "Environment" end
    
    render_path = render_path .. type_folder .. "/"
    
    -- Obtener carpeta root de la primera región
    local first_region = valid_tracks[1].name
    local root_folder_name = region_root_data[first_region] or "General"
    
    -- Si es "Root", cambiarlo a "General"
    if root_folder_name == "Root" then
        root_folder_name = "General"
    end
    
    render_path = render_path .. root_folder_name .. "/"
    
    -- Crear directorios si no existen
    reaper.RecursiveCreateDirectory(render_path, 0)
    
    -- Configurar ruta final de render
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE", render_path, true)
    
    -- Obtener parent para expansión
    local parent_name = "Parent"
    if region_parent_data[first_region] then
        parent_name = region_parent_data[first_region]
    else
        -- Intentar obtener el nombre del track seleccionado
        if reaper.CountSelectedTracks(0) > 0 then
            local first_track = reaper.GetSelectedTrack(0, 0)
            parent_name = clean_name(get_track_name(first_track))
        end
    end
    
    -- EXPANDIR WILDCARDS ANTES DE CONFIGURAR EL PATRÓN
    local expanded_pattern = wildcard_template
        :gsub("%$root", root_folder_name)
        :gsub("%$parent", parent_name)  -- CORRECCIÓN: Usar valor real
        :gsub("%$region", first_region)
    
    -- Configurar patrón de nombre de archivo con wildcards expandidos
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", expanded_pattern, true)
    
    -- Abrir diálogo de render
    open_render_dialog()
end

-- Función para procesar
local function process_subfolders()
    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()
    
    -- Para tipos que no son SFX, forzamos sin variaciones
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
    
    -- Restaurar valores originales
    variations = orig_variations
    
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Create regions from subfolders", -1)
end

-- Función para abrir el diálogo de selección de carpeta
local function browse_output_folder()
    -- Verificar si está disponible JS_Dialog_BrowseForFolder
    if reaper.JS_Dialog_BrowseForFolder then
        local ret, folder_path = reaper.JS_Dialog_BrowseForFolder("Select Output Folder", custom_output_path)
        if ret == 1 then
            -- Asegurarse de que la ruta termina con separador
            custom_output_path = folder_path:gsub("[\\/]$", "") .. "/"
        end
    else
        -- Alternativa: usar la función nativa de REAPER (menos flexible)
        local ret, folder_path = reaper.GetUserFileNameForWrite("", "Select Output Folder", "")
        if ret then
            -- Extraer la carpeta del archivo (aunque no es exactamente lo mismo)
            folder_path = folder_path:match("(.*[\\/])")
            if folder_path then
                custom_output_path = folder_path
            end
        end
    end
end

-- Interfaz gráfica
function loop()
    local visible, open = reaper.ImGui_Begin(ctx, 'SFX Renderer v8.9', true, 
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
                
                -- Sección para parámetros aleatorizados
                if reaper.ImGui_CollapsingHeader(ctx, "Variation Parameters") then
                    reaper.ImGui_Text(ctx, "Enable and adjust parameters for variations:")
                    
                    -- Volumen
                    _, random_params.volume.enable = reaper.ImGui_Checkbox(ctx, "Volume", random_params.volume.enable)
                    if random_params.volume.enable then
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, 200)
                        _, random_params.volume.amount = reaper.ImGui_SliderDouble(ctx, "##rand_vol", 
                            random_params.volume.amount, slider_ranges.volume.min, slider_ranges.volume.max, 
                            "%.2f dB")
                    end
                    
                    -- Pan
                    _, random_params.pan.enable = reaper.ImGui_Checkbox(ctx, "Pan", random_params.pan.enable)
                    if random_params.pan.enable then
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, 200)
                        _, random_params.pan.amount = reaper.ImGui_SliderDouble(ctx, "##rand_pan", 
                            random_params.pan.amount, slider_ranges.pan.min, slider_ranges.pan.max, 
                            "%.2f")
                    end
                    
                    -- Pitch
                    _, random_params.pitch.enable = reaper.ImGui_Checkbox(ctx, "Pitch", random_params.pitch.enable)
                    if random_params.pitch.enable then
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, 200)
                        _, random_params.pitch.amount = reaper.ImGui_SliderDouble(ctx, "##rand_pitch", 
                            random_params.pitch.amount, slider_ranges.pitch.min, slider_ranges.pitch.max, 
                            "%.1f semitones")
                    end
                    
                    -- Rate
                    _, random_params.rate.enable = reaper.ImGui_Checkbox(ctx, "Rate", random_params.rate.enable)
                    if random_params.rate.enable then
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, 200)
                        _, random_params.rate.amount = reaper.ImGui_SliderDouble(ctx, "##rand_rate", 
                            random_params.rate.amount, slider_ranges.rate.min, slider_ranges.rate.max, 
                            "%.2f")
                    end
                    
                    -- Longitud
                    _, random_params.length.enable = reaper.ImGui_Checkbox(ctx, "Length", random_params.length.enable)
                    if random_params.length.enable then
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, 200)
                        _, random_params.length.amount = reaper.ImGui_SliderDouble(ctx, "##rand_len", 
                            random_params.length.amount, slider_ranges.length.min, slider_ranges.length.max, 
                            "%.2f")
                    end
                    
                    -- Fade In
                    _, random_params.fadein.enable = reaper.ImGui_Checkbox(ctx, "Fade In", random_params.fadein.enable)
                    if random_params.fadein.enable then
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, 200)
                        _, random_params.fadein.amount = reaper.ImGui_SliderDouble(ctx, "##rand_fadein", 
                            random_params.fadein.amount, slider_ranges.fadein.min, slider_ranges.fadein.max, 
                            "%.2f")
                    end
                    
                    -- Fade Out
                    _, random_params.fadeout.enable = reaper.ImGui_Checkbox(ctx, "Fade Out", random_params.fadeout.enable)
                    if random_params.fadeout.enable then
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, 200)
                        _, random_params.fadeout.amount = reaper.ImGui_SliderDouble(ctx, "##rand_fadeout", 
                            random_params.fadeout.amount, slider_ranges.fadeout.min, slider_ranges.fadeout.max, 
                            "%.2f")
                    end
                    
                    -- Fade Shape
                    _, random_params.fadeshape.enable = reaper.ImGui_Checkbox(ctx, "Fade Shape", random_params.fadeshape.enable)
                    if random_params.fadeshape.enable then
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_Text(ctx, "(randomly changes)")
                    end
                end
            end
        end

        -- Sección de wildcards personalizados
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Text(ctx, "Filename Pattern:")
        
        -- Editor de plantilla
        reaper.ImGui_SetNextItemWidth(ctx, 300)
        _, wildcard_template = reaper.ImGui_InputText(ctx, "##wildcard_template", wildcard_template)
        
        -- Explicación de wildcards
        reaper.ImGui_Text(ctx, "Available wildcards:")
        reaper.ImGui_BulletText(ctx, "$root: Parent folder name")
        reaper.ImGui_BulletText(ctx, "$parent: Subfolder name (selected track)")
        reaper.ImGui_BulletText(ctx, "$region: Region name")
        reaper.ImGui_BulletText(ctx, "Also any other REAPER wildcard (e.g. $track)")
        
        -- Previsualización
        if #valid_tracks > 0 then
            local sample_region = valid_tracks[1].name
            local preview = expand_wildcards(wildcard_template, sample_region)
            reaper.ImGui_Text(ctx, "Preview: " .. preview)
        end
        
        -- NUEVA SECCIÓN: Selección de carpeta de salida
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Text(ctx, "Output folder:")
        
        -- Mostrar la ruta actual
        local display_path = custom_output_path
        if display_path == "" then
            display_path = "Project/Renders/ (default)"
        end
        
        reaper.ImGui_Text(ctx, "Current: " .. display_path)
        
        -- Botón para seleccionar carpeta
        if reaper.ImGui_Button(ctx, "Browse Output Folder", 250, 30) then
            browse_output_folder()
        end
        
        -- Botón para restablecer a la ruta por defecto
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Reset to Default", 150, 30) then
            custom_output_path = ""
        end

        -- Botón para crear regiones
        if reaper.ImGui_Button(ctx, "Create regions", 250, 40) then
            reaper.defer(process_subfolders)
        end
        
        -- Botones para preparar render
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Prepare Render", 250, 40) then
            prepare_render_with_existing_regions(true)
        end

        -- Créditos en la parte inferior
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