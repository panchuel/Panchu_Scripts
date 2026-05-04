local function get_region_id(index)
    local _, isrgn, pos, rgnend = reaper.EnumProjectMarkers(index)
    if not isrgn then return nil end
    return string.format("%.10f_%.10f", pos, rgnend)
end

function update_region_hierarchy(region_index, root, parent)
    local id = get_region_id(region_index)
    if id then
        RC.region_hierarchy_data[id] = { root = root, parent = parent }
        return true
    end
    return false
end

function get_region_hierarchy(region_index)
    local id = get_region_id(region_index)
    if id and RC.region_hierarchy_data[id] then
        return RC.region_hierarchy_data[id]
    end
    local _, isrgn, _, _, name = reaper.EnumProjectMarkers(region_index)
    if isrgn then
        local r, p = name:match("^%w+_([^_]+)_([^_]+)_$")
        if r and p then return { root = r, parent = p } end
    end
    return { root = "General", parent = "Parent" }
end

local function calculate_folder_time_range(folder_track)
    local min_s, max_e = math.huge, 0
    for _, child in ipairs(get_child_tracks(folder_track)) do
        for k = 0, reaper.CountTrackMediaItems(child) - 1 do
            local item = reaper.GetTrackMediaItem(child, k)
            local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local len  = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            min_s = math.min(min_s, pos)
            max_e = math.max(max_e, pos + len)
        end
    end
    return min_s, max_e
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

    local atype = RC.audio_types[RC.selected_type_idx] or { prefix = "sx", wildcard = "$region" }
    local total = 0

    for i = 0, sel_count - 1 do
        local tr = reaper.GetSelectedTrack(0, i)
        if not is_valid_parent_folder(tr) then goto continue end

        mark_original_items(tr)

        local folder_name = clean_name(get_track_name(tr))
        local root_name
        local parent_tr = get_parent_track(tr)
        if parent_tr then
            root_name = clean_name(get_track_name(parent_tr))
        else
            local _, proj = reaper.EnumProjects(-1, "")
            root_name = (proj:match("([^\\/]+)$") or "Project"):gsub("%..+$", "")
        end

        local min_s, max_e = calculate_folder_time_range(tr)
        if min_s == math.huge or max_e == 0 then goto continue end

        local region_name = expand_wildcards(atype.wildcard, atype.prefix, root_name, folder_name)
        local idx = reaper.AddProjectMarker2(0, true, min_s, max_e, region_name, -1, 0)
        update_region_hierarchy(idx, root_name, folder_name)

        table.insert(RC.valid_tracks, {
            name = region_name, start = min_s, end_pos = max_e, variation = 1,
        })
        total = total + 1
        ::continue::
    end
    return total
end

function create_regions()
    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()

    if not RC.audio_types[RC.selected_type_idx] then
        reaper.ShowMessageBox("No audio type selected.", "Invalid Selection", 0)
        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock("Create Regions", -1)
        return
    end

    sync_config_to_audio_type()
    local n = create_regions_from_folder_structure()
    if n > 0 then
        reaper.ShowMessageBox(string.format("Created %d region(s).", n), "Regions Created", 0)
    end

    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Create Regions", -1)
end

function update_selected_region_hierarchy()
    local pos = reaper.GetCursorPosition()
    local sel_region
    for i = 0, reaper.CountProjectMarkers(0) - 1 do
        local _, isrgn, rpos, rend, name = reaper.EnumProjectMarkers(i)
        if isrgn and pos >= rpos and pos <= rend then
            sel_region = { index = i, name = name }
            break
        end
    end

    if not sel_region then
        reaper.ShowMessageBox("Place cursor inside a region to update it.", "Region not detected", 0)
        return
    end

    local h = get_region_hierarchy(sel_region.index)
    local ok, input = reaper.GetUserInputs("Update Hierarchy", 2,
        "Root,Parent:", h.root .. "," .. h.parent)

    if ok then
        local r, p = input:match("([^,]+),([^,]+)")
        if r and p then
            r = r:match("^%s*(.-)%s*$")
            p = p:match("^%s*(.-)%s*$")
            if update_region_hierarchy(sel_region.index, r, p) then
                reaper.ShowMessageBox("Root: " .. r .. "\nParent: " .. p, "Updated", 0)
            else
                reaper.ShowMessageBox("Error updating hierarchy.", "Error", 0)
            end
        else
            reaper.ShowMessageBox("Use format: root,parent", "Error", 0)
        end
    end
end
