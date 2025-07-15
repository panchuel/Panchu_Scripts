--@description Renderizador SFX con jerarquía + GUI + Wildcards + Persistencia (Refactorizado)
--@version 9.0
--@author Panchu
--@provides [main] .

-- ============================================================================
-- CONFIGURACIÓN Y CONSTANTES
-- ============================================================================

local Config = {
    CONSTANTS = {
        ORIGINAL_TAG = "SFX_ORIGINAL",
        VARIATION_TAG = "SFX_VARIATION",
        SCRIPT_NAME = "SFX Renderer",
        VERSION = "9.0",
        AUTHOR = "Daniel \"Panchuel\" Montoya"
    },
    
    DEFAULT_SETTINGS = {
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
    },
    
    SLIDER_RANGES = {
        volume = {min = 0.0, max = 12.0},
        pan = {min = 0.0, max = 1.0},
        pitch = {min = 0.0, max = 12.0},
        rate = {min = 0.0, max = 0.5},
        position = {min = 0.0, max = 5.0},
        length = {min = 0.0, max = 0.5},
        fadein = {min = 0.0, max = 1.0},
        fadeout = {min = 0.0, max = 1.0}
    },
    
    FILE_TYPES = {
        SFX = {id = "sx", index = 0, folder = "SFX"},
        MUSIC = {id = "mx", index = 1, folder = "Music"},
        DIALOGUE = {id = "dx", index = 2, folder = "Dialogue"},
        ENVIRONMENT = {id = "env", index = 3, folder = "Environment"}
    }
}

-- ============================================================================
-- UTILIDADES (Single Responsibility)
-- ============================================================================

local Utils = {}

function Utils.clean_name(name)
    return name:gsub("[^%w_]", "_"):gsub("__+", "_")
end

function Utils.get_file_type_by_id(id)
    for _, file_type in pairs(Config.FILE_TYPES) do
        if file_type.id == id then
            return file_type
        end
    end
    return Config.FILE_TYPES.SFX
end

function Utils.get_file_type_by_index(index)
    for _, file_type in pairs(Config.FILE_TYPES) do
        if file_type.index == index then
            return file_type
        end
    end
    return Config.FILE_TYPES.SFX
end

-- ============================================================================
-- INTERFACES (Interface Segregation Principle)
-- ============================================================================

-- Interface para persistencia
local IPersistence = {}
function IPersistence:load() error("Not implemented") end
function IPersistence:save(data) error("Not implemented") end

-- Interface para gestión de tracks
local ITrackManager = {}
function ITrackManager:get_name(track) error("Not implemented") end
function ITrackManager:get_parent_track(track) error("Not implemented") end
function ITrackManager:get_child_tracks(track) error("Not implemented") end
function ITrackManager:is_valid_subfolder(track) error("Not implemented") end

-- Interface para gestión de items
local IItemManager = {}
function IItemManager:is_original(item) error("Not implemented") end
function IItemManager:is_variation(item) error("Not implemented") end
function IItemManager:mark_as_original(item) error("Not implemented") end
function IItemManager:mark_as_variation(item) error("Not implemented") end

-- Interface para procesamiento de regiones
local IRegionProcessor = {}
function IRegionProcessor:process_selected_tracks() error("Not implemented") end
function IRegionProcessor:get_valid_tracks() error("Not implemented") end

-- ============================================================================
-- GESTIÓN DE CONFIGURACIÓN (Single Responsibility)
-- ============================================================================

local SettingsManager = setmetatable({}, {__index = IPersistence})

function SettingsManager:new()
    return setmetatable({}, {__index = self})
end

function SettingsManager:load()
    local settings = {}
    for key, default in pairs(Config.DEFAULT_SETTINGS) do
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

function SettingsManager:save(settings)
    for key, value in pairs(settings) do
        if type(value) == "boolean" then
            reaper.SetExtState("SFX_Renderer", key, value and "true" or "false", true)
        else
            reaper.SetExtState("SFX_Renderer", key, tostring(value), true)
        end
    end
end

-- ============================================================================
-- GESTIÓN DE TRACKS (Single Responsibility)
-- ============================================================================

local TrackManager = setmetatable({}, {__index = ITrackManager})

function TrackManager:new()
    return setmetatable({}, {__index = self})
end

function TrackManager:get_name(track)
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    return name or "Unnamed"
end

function TrackManager:get_index(track)
    return reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
end

function TrackManager:get_folder_depth(track)
    return reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
end

function TrackManager:get_parent_track(track)
    local idx = self:get_index(track)
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

function TrackManager:get_child_tracks(folder_track)
    local child_tracks = {}
    local folder_idx = self:get_index(folder_track)
    local total_tracks = reaper.CountTracks(0)
    
    for i = folder_idx + 1, total_tracks - 1 do
        local track = reaper.GetTrack(0, i)
        local depth = self:get_folder_depth(track)
        table.insert(child_tracks, track)
        if depth < 0 then break end
    end
    
    return child_tracks
end

function TrackManager:is_valid_subfolder(track)
    if self:get_folder_depth(track) ~= 1 then return false end
    local child_tracks = self:get_child_tracks(track)
    return #child_tracks > 0
end

-- ============================================================================
-- GESTIÓN DE ITEMS (Single Responsibility)
-- ============================================================================

local ItemManager = setmetatable({}, {__index = IItemManager})

function ItemManager:new()
    return setmetatable({}, {__index = self})
end

function ItemManager:get_notes(item)
    local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    return notes or ""
end

function ItemManager:set_notes(item, notes)
    reaper.GetSetMediaItemInfo_String(item, "P_NOTES", notes, true)
end

function ItemManager:is_original(item)
    local notes = self:get_notes(item)
    return notes:find(Config.CONSTANTS.ORIGINAL_TAG) and not notes:find(Config.CONSTANTS.VARIATION_TAG)
end

function ItemManager:is_variation(item)
    local notes = self:get_notes(item)
    return notes:find(Config.CONSTANTS.VARIATION_TAG)
end

function ItemManager:mark_as_original(item)
    if not self:is_original(item) and not self:is_variation(item) then
        local current_notes = self:get_notes(item)
        self:set_notes(item, current_notes .. " " .. Config.CONSTANTS.ORIGINAL_TAG)
    end
end

function ItemManager:mark_as_variation(item)
    self:set_notes(item, Config.CONSTANTS.VARIATION_TAG)
end

-- ============================================================================
-- ESTRATEGIAS DE NAMING (Strategy Pattern)
-- ============================================================================

local INamingStrategy = {}
function INamingStrategy:build_name(root_name, sub_name, settings) error("Not implemented") end

local SFXNamingStrategy = setmetatable({}, {__index = INamingStrategy})
function SFXNamingStrategy:build_name(root_name, sub_name, settings)
    return string.format("%s_%s_%s", settings.prefix, root_name, sub_name)
end

local MusicNamingStrategy = setmetatable({}, {__index = INamingStrategy})
function MusicNamingStrategy:build_name(root_name, sub_name, settings)
    return string.format("mx_%s_%s_%d_%s", 
        root_name, sub_name, settings.music_bpm, settings.music_meter)
end

local DialogueNamingStrategy = setmetatable({}, {__index = INamingStrategy})
function DialogueNamingStrategy:build_name(root_name, sub_name, settings)
    local char_field = settings.dx_character ~= "" and settings.dx_character or "unknown"
    local questType_field = settings.dx_quest_type ~= "" and settings.dx_quest_type or "SQ"
    local questName_field = settings.dx_quest_name ~= "" and settings.dx_quest_name or sub_name
    return string.format("dx_%s_%s_%s_%02d", 
        char_field, questType_field, questName_field, settings.dx_line_number)
end

local EnvironmentNamingStrategy = setmetatable({}, {__index = INamingStrategy})
function EnvironmentNamingStrategy:build_name(root_name, sub_name, settings)
    return string.format("env_%s_%s", root_name, sub_name)
end

-- Factory para estrategias de naming
local NamingStrategyFactory = {}
function NamingStrategyFactory.create(file_type)
    local strategies = {
        sx = SFXNamingStrategy,
        mx = MusicNamingStrategy,
        dx = DialogueNamingStrategy,
        env = EnvironmentNamingStrategy
    }
    return strategies[file_type] or SFXNamingStrategy
end

-- ============================================================================
-- GESTIÓN DE PARÁMETROS ALEATORIOS (Single Responsibility)
-- ============================================================================

local RandomizationManager = {}

function RandomizationManager:new()
    return setmetatable({}, {__index = self})
end

function RandomizationManager:apply_to_item(new_item, new_take, original_item, original_take, random_params)
    local appliers = {
        {param = "volume", func = self._apply_volume},
        {param = "pan", func = self._apply_pan},
        {param = "pitch", func = self._apply_pitch},
        {param = "rate", func = self._apply_rate},
        {param = "length", func = self._apply_length},
        {param = "fadein", func = self._apply_fadein},
        {param = "fadeout", func = self._apply_fadeout},
        {param = "fadeshape", func = self._apply_fadeshape}
    }
    
    for _, applier in ipairs(appliers) do
        if random_params[applier.param] and random_params[applier.param].enable then
            applier.func(self, new_item, new_take, random_params[applier.param].amount)
        end
    end
end

function RandomizationManager:_apply_volume(new_item, new_take, amount)
    if amount > 0 then
        local vol_db = (math.random() * 2 - 1) * amount
        local vol_linear = 10^(vol_db / 20)
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_VOL", vol_linear)
    end
end

function RandomizationManager:_apply_pan(new_item, new_take, amount)
    if amount > 0 then
        local pan_val = (math.random() * 2 - 1) * amount
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_PAN", pan_val)
    end
end

function RandomizationManager:_apply_pitch(new_item, new_take, amount)
    if amount > 0 then
        local pitch_offset = (math.random() * 2 - 1) * amount
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_PITCH", pitch_offset)
    end
end

function RandomizationManager:_apply_rate(new_item, new_take, amount)
    if amount > 0 then
        local rate_factor = 1.0 + (math.random() * 2 - 1) * amount
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_PLAYRATE", rate_factor)
        
        local length = reaper.GetMediaItemInfo_Value(new_item, "D_LENGTH")
        reaper.SetMediaItemInfo_Value(new_item, "D_LENGTH", length / rate_factor)
    end
end

function RandomizationManager:_apply_length(new_item, new_take, amount)
    if amount > 0 then
        local length_factor = 1.0 + (math.random() * 2 - 1) * amount
        local length = reaper.GetMediaItemInfo_Value(new_item, "D_LENGTH")
        reaper.SetMediaItemInfo_Value(new_item, "D_LENGTH", length * length_factor)
    end
end

function RandomizationManager:_apply_fadein(new_item, new_take, amount)
    if amount > 0 then
        local fadein_len = reaper.GetMediaItemInfo_Value(new_item, "D_FADEINLEN")
        local fadein_factor = 1.0 + (math.random() * 2 - 1) * amount
        reaper.SetMediaItemInfo_Value(new_item, "D_FADEINLEN", fadein_len * fadein_factor)
    end
end

function RandomizationManager:_apply_fadeout(new_item, new_take, amount)
    if amount > 0 then
        local fadeout_len = reaper.GetMediaItemInfo_Value(new_item, "D_FADEOUTLEN")
        local fadeout_factor = 1.0 + (math.random() * 2 - 1) * amount
        reaper.SetMediaItemInfo_Value(new_item, "D_FADEOUTLEN", fadeout_len * fadeout_factor)
    end
end

function RandomizationManager:_apply_fadeshape(new_item, new_take, amount)
    if amount > 0 then
        local shapes = {0, 1, 2, 3}
        local new_shape = shapes[math.random(1, #shapes)]
        reaper.SetMediaItemInfo_Value(new_item, "C_FADEINSHAPE", new_shape)
        reaper.SetMediaItemInfo_Value(new_item, "C_FADEOUTSHAPE", new_shape)
    end
end

-- ============================================================================
-- GESTIÓN DE REGIONES (Single Responsibility)
-- ============================================================================

local RegionManager = {}

function RegionManager:new()
    return setmetatable({}, {__index = self})
end

function RegionManager:get_selected()
    local _, region_index = reaper.GetLastMarkerAndCurRegion(0, reaper.GetCursorPosition())
    if region_index >= 0 then
        local _, isrgn, pos, rgnend, name, _ = reaper.EnumProjectMarkers(region_index)
        if isrgn then
            return {name = name, start = pos, end_pos = rgnend}
        end
    end
    return nil
end

function RegionManager:get_all()
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

function RegionManager:find_max_variation_number(base_name)
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

function RegionManager:create(name, start_pos, end_pos)
    reaper.AddProjectMarker2(0, true, start_pos, end_pos, name, -1, 0)
end

-- ============================================================================
-- PROCESADOR PRINCIPAL (Dependency Inversion + Open/Closed)
-- ============================================================================

local RegionProcessor = setmetatable({}, {__index = IRegionProcessor})

function RegionProcessor:new(track_manager, item_manager, region_manager, randomization_manager)
    local self = {
        track_manager = track_manager,
        item_manager = item_manager,
        region_manager = region_manager,
        randomization_manager = randomization_manager,
        valid_tracks = {},
        region_root_data = {},
        region_parent_data = {}
    }
    return setmetatable(self, {__index = RegionProcessor})
end

function RegionProcessor:process_selected_tracks(settings)
    self.valid_tracks = {}
    self.region_root_data = {}
    self.region_parent_data = {}
    
    local root_folder, root_name = self:_get_root_folder_info()
    
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        local subfolder = reaper.GetSelectedTrack(0, i)
        if self.track_manager:is_valid_subfolder(subfolder) then
            self:_process_single_subfolder(subfolder, root_name, settings)
        end
    end
    
    return #self.valid_tracks
end

function RegionProcessor:get_valid_tracks()
    return self.valid_tracks, self.region_root_data, self.region_parent_data
end

function RegionProcessor:_get_root_folder_info()
    local root_folder = nil
    local root_name = "Project"
    
    if reaper.CountSelectedTracks(0) > 0 then
        local first_track = reaper.GetSelectedTrack(0, 0)
        root_folder = self.track_manager:get_parent_track(first_track)
        
        if root_folder then
            root_name = self.track_manager:get_name(root_folder)
        else
            local _, project_name = reaper.EnumProjects(-1, "")
            root_name = project_name:match("([^\\/]+)$"):gsub("%..+$", "") or "Project"
        end
    end
    
    return root_folder, root_name
end

function RegionProcessor:_process_single_subfolder(subfolder, root_name, settings)
    self:_mark_original_items(subfolder)
    
    local sub_name = Utils.clean_name(self.track_manager:get_name(subfolder))
    local clean_root_name = Utils.clean_name(root_name)
    
    local min_start, max_end = self:_calculate_folder_time_range(subfolder)
    if min_start == math.huge or max_end == 0 then return end
    
    local naming_strategy = NamingStrategyFactory.create(settings.prefix_type)
    local base_name = naming_strategy:build_name(clean_root_name, sub_name, settings)
    local total_duration = max_end - min_start
    
    self:_create_variations(subfolder, base_name, min_start, max_end, total_duration, clean_root_name, sub_name, settings)
end

function RegionProcessor:_mark_original_items(subfolder)
    local child_tracks = self.track_manager:get_child_tracks(subfolder)
    for _, child in ipairs(child_tracks) do
        for k = 0, reaper.CountTrackMediaItems(child) - 1 do
            local item = reaper.GetTrackMediaItem(child, k)
            self.item_manager:mark_as_original(item)
        end
    end
end

function RegionProcessor:_calculate_folder_time_range(folder_track)
    local min_start = math.huge
    local max_end = 0
    local child_tracks = self.track_manager:get_child_tracks(folder_track)
    
    for _, child in ipairs(child_tracks) do
        for k = 0, reaper.CountTrackMediaItems(child) - 1 do
            local item = reaper.GetTrackMediaItem(child, k)
            if self.item_manager:is_original(item) then
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

function RegionProcessor:_create_variations(subfolder, base_name, min_start, max_end, total_duration, root_name, sub_name, settings)
    local variations = (settings.prefix_type == "sx") and settings.variations or 0
    local actual_variations = variations > 0 and variations or 1
    
    local max_end_all = self:_get_max_end_time(subfolder)
    local base_offset = max_end_all - min_start + settings.separation_time
    local max_variation = self.region_manager:find_max_variation_number(base_name)
    
    for variation = 1, actual_variations do
        local rand_offset = 0
        if variations > 0 and settings.randomize_position > 0 then
            rand_offset = (math.random() * 2 - 1) * settings.randomize_position
        end
        
        local time_offset = 0
        if variations > 0 then
            time_offset = base_offset + (variation - 1) * (total_duration + settings.separation_time)
            self:_duplicate_original_items(subfolder, time_offset + rand_offset, settings)
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
        
        self.region_manager:create(region_name, region_start, region_end)
        
        self.region_root_data[region_name] = root_name
        self.region_parent_data[region_name] = sub_name
        
        table.insert(self.valid_tracks, {
            name = region_name,
            start = region_start,
            end_pos = region_end,
            variation = variation_number
        })
    end
end

function RegionProcessor:_duplicate_original_items(folder_track, total_offset, settings)
    local child_tracks = self.track_manager:get_child_tracks(folder_track)
    local random_params = self:_build_random_params(settings)
    
    for _, child in ipairs(child_tracks) do
        for k = 0, reaper.CountTrackMediaItems(child) - 1 do
            local item = reaper.GetTrackMediaItem(child, k)
            
            if self.item_manager:is_original(item) then
                local take = reaper.GetActiveTake(item)
                
                if take then
                    local new_item = self:_create_duplicate_item(item, child, total_offset)
                    local new_take = self:_create_duplicate_take(take, new_item)
                    
                    self.randomization_manager:apply_to_item(new_item, new_take, item, take, random_params)
                    self.item_manager:mark_as_variation(new_item)
                end
            end
        end
    end
end

function RegionProcessor:_create_duplicate_item(original_item, track, offset)
    local new_item = reaper.AddMediaItemToTrack(track)
    
    local properties = {
        "D_POSITION", "D_LENGTH", "D_SNAPOFFSET", "B_MUTE", "C_LOCK",
        "D_FADEINLEN", "D_FADEOUTLEN", "C_FADEINSHAPE", "C_FADEOUTSHAPE"
    }
    
    for _, prop in ipairs(properties) do
        local value = reaper.GetMediaItemInfo_Value(original_item, prop)
        if prop == "D_POSITION" then
            value = value + offset
        end
        reaper.SetMediaItemInfo_Value(new_item, prop, value)
    end
    
    return new_item
end

function RegionProcessor:_create_duplicate_take(original_take, new_item)
    local new_take = reaper.AddTakeToMediaItem(new_item)
    local source = reaper.GetMediaItemTake_Source(original_take)
    reaper.SetMediaItemTake_Source(new_take, source)
    
    local take_properties = {"D_VOL", "D_PAN", "D_PITCH", "D_PLAYRATE"}
    for _, prop in ipairs(take_properties) do
        local value = reaper.GetMediaItemTakeInfo_Value(original_take, prop)
        reaper.SetMediaItemTakeInfo_Value(new_take, prop, value)
    end
    
    return new_take
end

function RegionProcessor:_get_max_end_time(folder_track)
    local max_end = 0
    local child_tracks = self.track_manager:get_child_tracks(folder_track)
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

function RegionProcessor:_build_random_params(settings)
    return {
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
end

-- ============================================================================
-- GESTIÓN DE RENDER (Single Responsibility)
-- ============================================================================

local RenderManager = {}

function RenderManager:new()
    return setmetatable({}, {__index = self})
end

function RenderManager:prepare_render(regions, settings, region_root_data, region_parent_data)
    if #regions == 0 then
        reaper.ShowMessageBox("No hay regiones creadas.", "Error", 0)
        return
    end
    
    self:_configure_basic_settings(settings)
    local render_path = self:_build_render_path(regions[1], settings, region_root_data)
    
    reaper.RecursiveCreateDirectory(render_path, 0)
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE", render_path, true)
    
    local expanded_pattern = self:_expand_wildcards(
        settings.wildcard_template, 
        regions[1], 
        region_root_data, 
        region_parent_data
    )
    
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", expanded_pattern, true)
    reaper.Main_OnCommand(40015, 0)
end

function RenderManager:browse_output_folder(current_path)
    if reaper.JS_Dialog_BrowseForFolder then
        local ret, folder_path = reaper.JS_Dialog_BrowseForFolder("Select Output Folder", current_path)
        if ret == 1 then
            return folder_path:gsub("[\\/]$", "") .. "/"
        end
    else
        local ret, folder_path = reaper.GetUserFileNameForWrite("", "Select Output Folder", "")
        if ret then
            folder_path = folder_path:match("(.*[\\/])")
            if folder_path then
                return folder_path
            end
        end
    end
    return current_path
end

function RenderManager:_configure_basic_settings(settings)
    local render_path = settings.custom_output_path ~= "" and settings.custom_output_path or reaper.GetProjectPath("") .. "/Renders/"
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE", render_path, true)
    reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT", "wav", true)
    reaper.GetSetProjectInfo_String(0, "RENDER_SETTINGS", "24bit", true)
end

function RenderManager:_build_render_path(first_region, settings, region_root_data)
    local render_path = settings.custom_output_path ~= "" and settings.custom_output_path or reaper.GetProjectPath("") .. "/Renders/"
    
    local file_type = Utils.get_file_type_by_id(settings.prefix_type)
    render_path = render_path .. file_type.folder .. "/"
    
    local root_folder_name = region_root_data[first_region.name] or "General"
    if root_folder_name == "Root" then
        root_folder_name = "General"
    end
    
    render_path = render_path .. root_folder_name .. "/"
    return render_path
end

function RenderManager:_expand_wildcards(template, first_region, region_root_data, region_parent_data)
    local root_name = region_root_data[first_region.name] or "Root"
    local parent_name = region_parent_data[first_region.name] or "Parent"
    
    local expanded = template
    expanded = expanded:gsub("%$root", root_name)
    expanded = expanded:gsub("%$parent", parent_name)
    expanded = expanded:gsub("%$region", first_region.name)
    
    return expanded
end

-- ============================================================================
-- INTERFAZ DE USUARIO (Separated Concerns)
-- ============================================================================

local GUI = {}

function GUI:new(settings_manager, region_processor, render_manager)
    local self = {
        ctx = reaper.ImGui_CreateContext(Config.CONSTANTS.SCRIPT_NAME .. ' v' .. Config.CONSTANTS.VERSION),
        font = reaper.ImGui_CreateFont('sans-serif', 16),
        settings_manager = settings_manager,
        region_processor = region_processor,
        render_manager = render_manager,
        settings = settings_manager:load(),
        is_open = true
    }
    
    reaper.ImGui_Attach(self.ctx, self.font)
    return setmetatable(self, {__index = GUI})
end

function GUI:show()
    if self.is_open then
        self:_render_window()
        reaper.defer(function() self:show() end)
    else
        self:_cleanup()
    end
end

function GUI:_render_window()
    local visible, open = reaper.ImGui_Begin(
        self.ctx, 
        Config.CONSTANTS.SCRIPT_NAME .. ' v' .. Config.CONSTANTS.VERSION, 
        true, 
        reaper.ImGui_WindowFlags_AlwaysAutoResize()
    )
    
    if visible then
        reaper.ImGui_PushFont(self.ctx, self.font)
        
        self:_render_track_info()
        self:_render_file_type_settings()
        self:_render_variation_settings()
        self:_render_wildcard_settings()
        self:_render_output_settings()
        self:_render_action_buttons()
        self:_render_credits()
        
        reaper.ImGui_PopFont(self.ctx)
        reaper.ImGui_End(self.ctx)
    end
    
    self.is_open = open
end

function GUI:_render_track_info()
    local sel_count = reaper.CountSelectedTracks(0)
    reaper.ImGui_Text(self.ctx, "Selected tracks: " .. sel_count)
    
    if sel_count > 0 then
        local first_track = reaper.GetSelectedTrack(0, 0)
        local track_manager = TrackManager:new()
        local depth = track_manager:get_folder_depth(first_track)
        reaper.ImGui_Text(self.ctx, "First track depth: " .. depth)
        
        local root_track = track_manager:get_parent_track(first_track)
        if root_track then
            local root_name = track_manager:get_name(root_track)
            reaper.ImGui_Text(self.ctx, "Detected root folder: " .. Utils.clean_name(root_name))
        end
    end
    
    reaper.ImGui_Separator(self.ctx)
end

function GUI:_render_file_type_settings()
    reaper.ImGui_Text(self.ctx, "File type:")
    reaper.ImGui_SameLine(self.ctx)
    
    local types = "SFX\0Music\0Dialogue\0Environment\0"
    local current_type = Utils.get_file_type_by_id(self.settings.prefix_type).index
    local changed, new_idx = reaper.ImGui_Combo(self.ctx, "##filetype", current_type, types)
    
    if changed then
        self.settings.prefix_type = Utils.get_file_type_by_index(new_idx).id
    end
    
    -- Renderizar configuraciones específicas según el tipo
    local file_type = Utils.get_file_type_by_id(self.settings.prefix_type)
    if file_type.id == "sx" then
        self:_render_sfx_settings()
    elseif file_type.id == "mx" then
        self:_render_music_settings()
    elseif file_type.id == "dx" then
        self:_render_dialogue_settings()
    end
    
    reaper.ImGui_Separator(self.ctx)
end

function GUI:_render_sfx_settings()
    reaper.ImGui_Text(self.ctx, "Prefix for region names:")
    reaper.ImGui_SetNextItemWidth(self.ctx, 100)
    _, self.settings.prefix = reaper.ImGui_InputText(self.ctx, "##prefix", self.settings.prefix)
end

function GUI:_render_music_settings()
    reaper.ImGui_Text(self.ctx, "BPM:")
    reaper.ImGui_SetNextItemWidth(self.ctx, 120)
    _, self.settings.music_bpm = reaper.ImGui_InputInt(self.ctx, "##music_bpm", self.settings.music_bpm)
    self.settings.music_bpm = math.max(1, self.settings.music_bpm)
    
    reaper.ImGui_Text(self.ctx, "Meter (e.g: 4-4):")
    reaper.ImGui_SetNextItemWidth(self.ctx, 120)
    _, self.settings.music_meter = reaper.ImGui_InputText(self.ctx, "##music_meter", self.settings.music_meter)
end

function GUI:_render_dialogue_settings()
    reaper.ImGui_Text(self.ctx, "Character:")
    reaper.ImGui_SetNextItemWidth(self.ctx, 180)
    _, self.settings.dx_character = reaper.ImGui_InputText(self.ctx, "##dx_character", self.settings.dx_character)
    
    reaper.ImGui_Text(self.ctx, "Quest Type (e.g: SQ, HC):")
    reaper.ImGui_SetNextItemWidth(self.ctx, 120)
    _, self.settings.dx_quest_type = reaper.ImGui_InputText(self.ctx, "##dx_quest_type", self.settings.dx_quest_type)
    
    reaper.ImGui_Text(self.ctx, "Quest Name:")
    reaper.ImGui_SetNextItemWidth(self.ctx, 180)
    _, self.settings.dx_quest_name = reaper.ImGui_InputText(self.ctx, "##dx_quest_name", self.settings.dx_quest_name)
    
    reaper.ImGui_Text(self.ctx, "Line Number:")
    reaper.ImGui_SetNextItemWidth(self.ctx, 80)
    _, self.settings.dx_line_number = reaper.ImGui_InputInt(self.ctx, "##dx_line_number", self.settings.dx_line_number)
    self.settings.dx_line_number = math.max(1, self.settings.dx_line_number)
end

function GUI:_render_variation_settings()
    if self.settings.prefix_type == "sx" then
        reaper.ImGui_Text(self.ctx, "Variations per subfolder (0 = regions only):")
        reaper.ImGui_SetNextItemWidth(self.ctx, 100)
        _, self.settings.variations = reaper.ImGui_InputInt(self.ctx, "Variations", self.settings.variations)
        self.settings.variations = math.max(0, math.min(self.settings.variations, 100))
        
        if self.settings.variations > 0 then
            self:_render_variation_parameters()
        end
        
        reaper.ImGui_Separator(self.ctx)
    end
end

function GUI:_render_variation_parameters()
    reaper.ImGui_Text(self.ctx, "Separation between variations (s):")
    reaper.ImGui_SetNextItemWidth(self.ctx, 100)
    _, self.settings.separation_time = reaper.ImGui_InputDouble(self.ctx, "##sep", self.settings.separation_time)
    self.settings.separation_time = math.max(0.1, self.settings.separation_time)
    
    reaper.ImGui_Text(self.ctx, "Position randomization (s):")
    reaper.ImGui_SetNextItemWidth(self.ctx, 150)
    _, self.settings.randomize_position = reaper.ImGui_SliderDouble(
        self.ctx, "##rand_pos", self.settings.randomize_position, 
        Config.SLIDER_RANGES.position.min, Config.SLIDER_RANGES.position.max, 
        "Position: %.2f s"
    )
    
    if reaper.ImGui_CollapsingHeader(self.ctx, "Variation Parameters") then
        self:_render_randomization_parameters()
    end
end

function GUI:_render_randomization_parameters()
    local parameters = {
        {name = "Volume", key = "volume", unit = "dB"},
        {name = "Pan", key = "pan", unit = ""},
        {name = "Pitch", key = "pitch", unit = "semitones"},
        {name = "Rate", key = "rate", unit = ""},
        {name = "Length", key = "length", unit = ""},
        {name = "Fade In", key = "fadein", unit = ""},
        {name = "Fade Out", key = "fadeout", unit = ""},
        {name = "Fade Shape", key = "fadeshape", unit = "(randomly changes)"}
    }
    
    for _, param in ipairs(parameters) do
        local enable_key = param.key .. "_enable"
        local amount_key = param.key .. "_amount"
        
        _, self.settings[enable_key] = reaper.ImGui_Checkbox(self.ctx, param.name, self.settings[enable_key])
        
        if self.settings[enable_key] and param.key ~= "fadeshape" then
            reaper.ImGui_SameLine(self.ctx)
            reaper.ImGui_SetNextItemWidth(self.ctx, 200)
            
            local range = Config.SLIDER_RANGES[param.key]
            if range then
                local format = param.key == "pitch" and "%.1f " .. param.unit or "%.2f " .. param.unit
                _, self.settings[amount_key] = reaper.ImGui_SliderDouble(
                    self.ctx, "##rand_" .. param.key, 
                    self.settings[amount_key], 
                    range.min, range.max, 
                    format
                )
            end
        elseif param.key == "fadeshape" and self.settings[enable_key] then
            reaper.ImGui_SameLine(self.ctx)
            reaper.ImGui_Text(self.ctx, param.unit)
        end
    end
end

function GUI:_render_wildcard_settings()
    reaper.ImGui_Text(self.ctx, "Filename Pattern:")
    reaper.ImGui_SetNextItemWidth(self.ctx, 300)
    _, self.settings.wildcard_template = reaper.ImGui_InputText(self.ctx, "##wildcard_template", self.settings.wildcard_template)
    
    reaper.ImGui_Text(self.ctx, "Available wildcards:")
    reaper.ImGui_BulletText(self.ctx, "$root: Parent folder name")
    reaper.ImGui_BulletText(self.ctx, "$parent: Subfolder name (selected track)")
    reaper.ImGui_BulletText(self.ctx, "$region: Region name")
    reaper.ImGui_BulletText(self.ctx, "Also any other REAPER wildcard (e.g. $track)")
    
    reaper.ImGui_Separator(self.ctx)
end

function GUI:_render_output_settings()
    reaper.ImGui_Text(self.ctx, "Output folder:")
    
    local display_path = self.settings.custom_output_path
    if display_path == "" then
        display_path = "Project/Renders/ (default)"
    end
    
    reaper.ImGui_Text(self.ctx, "Current: " .. display_path)
    
    if reaper.ImGui_Button(self.ctx, "Browse Output Folder", 250, 30) then
        self.settings.custom_output_path = self.render_manager:browse_output_folder(self.settings.custom_output_path)
    end
    
    reaper.ImGui_SameLine(self.ctx)
    if reaper.ImGui_Button(self.ctx, "Reset to Default", 150, 30) then
        self.settings.custom_output_path = ""
    end
    
    reaper.ImGui_Separator(self.ctx)
end

function GUI:_render_action_buttons()
    if reaper.ImGui_Button(self.ctx, "Create regions", 250, 40) then
        reaper.defer(function() self:_process_subfolders() end)
    end
    
    reaper.ImGui_SameLine(self.ctx)
    if reaper.ImGui_Button(self.ctx, "Prepare Render", 250, 40) then
        self:_prepare_render()
    end
end

function GUI:_render_credits()
    reaper.ImGui_Separator(self.ctx)
    reaper.ImGui_Spacing(self.ctx)
    reaper.ImGui_Text(self.ctx, "Developed by " .. Config.CONSTANTS.AUTHOR)
    reaper.ImGui_Spacing(self.ctx)
end

function GUI:_process_subfolders()
    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()
    
    local orig_variations = self.settings.variations
    
    if self.settings.prefix_type ~= "sx" then
        self.settings.variations = 0
    end
    
    if self.settings.variations > 0 then
        math.randomseed(os.time())
    end
    
    local total = self.region_processor:process_selected_tracks(self.settings)
    
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
    
    self.settings.variations = orig_variations
    
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Create regions from subfolders", -1)
end

function GUI:_prepare_render()
    local valid_tracks, region_root_data, region_parent_data = self.region_processor:get_valid_tracks()
    
    if #valid_tracks == 0 then
        local region_manager = RegionManager:new()
        valid_tracks = region_manager:get_all()
        
        -- Si no hay tracks válidos del procesador, intentar obtener la región seleccionada
        if #valid_tracks == 0 then
            local selected_region = region_manager:get_selected()
            if selected_region then
                valid_tracks = {selected_region}
            end
        end
    end
    
    self.render_manager:prepare_render(valid_tracks, self.settings, region_root_data, region_parent_data)
end

function GUI:_cleanup()
    self.settings_manager:save(self.settings)
    
    if reaper.ImGui_DestroyContext then
        reaper.ImGui_DestroyContext(self.ctx)
    end
end

-- ============================================================================
-- FACTORY PRINCIPAL (Dependency Injection)
-- ============================================================================

local AppFactory = {}

function AppFactory.create()
    -- Crear dependencias
    local settings_manager = SettingsManager:new()
    local track_manager = TrackManager:new()
    local item_manager = ItemManager:new()
    local region_manager = RegionManager:new()
    local randomization_manager = RandomizationManager:new()
    local render_manager = RenderManager:new()
    
    -- Crear procesador principal con dependencias inyectadas
    local region_processor = RegionProcessor:new(
        track_manager, 
        item_manager, 
        region_manager, 
        randomization_manager
    )
    
    -- Crear GUI con dependencias inyectadas
    local gui = GUI:new(settings_manager, region_processor, render_manager)
    
    return gui
end

-- ============================================================================
-- PUNTO DE ENTRADA
-- ============================================================================

local app = AppFactory.create()
app:show()