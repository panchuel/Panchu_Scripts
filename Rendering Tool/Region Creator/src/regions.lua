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
        -- Strip the known prefix (e.g. "sx_", "mx_") then split remaining into segments.
        -- Region name format: prefix_root_parent_ (root and parent may themselves contain _).
        -- We find the matching audio type to know the prefix, then extract segments 2..n-2
        -- as root and segment n-1 as parent (last segment before trailing _).
        -- Find the matching audio type by prefix
        local matched_prefix
        for _, t in ipairs(RC.audio_types or {}) do
            if name:sub(1, #t.prefix + 1) == t.prefix .. "_" then
                matched_prefix = t.prefix
                break
            end
        end
        local body = matched_prefix and name:match("^" .. matched_prefix .. "_(.+)$")
        if body then
            body = body:gsub("_$", "")
            local segs = {}
            for s in body:gmatch("[^_]+") do segs[#segs + 1] = s end

            -- Count how many wildcards appear after $parent in this type's wildcard template.
            -- Those correspond to trailing segments (e.g. $bpm, $meter) that are NOT root/parent.
            local extra = 0
            for _, t in ipairs(RC.audio_types or {}) do
                if t.prefix == matched_prefix and t.wildcard then
                    local after = t.wildcard:match("%$parent(.*)")
                    if after then
                        for _ in after:gmatch("%$%a+") do extra = extra + 1 end
                    end
                    break
                end
            end
            -- Remove trailing non-root/parent segments, keeping at least 2
            while extra > 0 and #segs > 2 do
                table.remove(segs)
                extra = extra - 1
            end

            if #segs >= 2 then
                local parent = segs[#segs]
                table.remove(segs, #segs)
                local root = table.concat(segs, "_")
                return { root = root, parent = parent }
            elseif #segs == 1 then
                return { root = segs[1], parent = segs[1] }
            end
        end
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

function validate_preconditions()
    if reaper.GetSelectedTrack(0, 0) == nil then
        return false,
            "No track selected.\n\nSelect one or more parent folder tracks before creating regions."
    end

    if not RC.audio_types or not RC.audio_types[RC.selected_type_idx or 0] then
        return false,
            "Audio type configuration is missing or corrupted.\n\n" ..
            "Go to the Audio Types tab and click Reset to Defaults."
    end

    local ext_ok = pcall(function()
        reaper.GetExtState(RC.EXT_KEY, "audio_type_count")
    end)
    if not ext_ok then
        return false,
            "Cannot read REAPER ExtState (key: " .. tostring(RC.EXT_KEY) .. ").\n\n" ..
            "Check script permissions or restart REAPER."
    end

    local lib_path = reaper.GetExtState("Lokasenna_GUI", "lib_path_v2")
    if not lib_path or lib_path == "" then
        return false,
            "Lokasenna_GUI v2 library path is not configured.\n\n" ..
            "Run: Scripts > ReaTeam Scripts > Development >\n" ..
            "Lokasenna_GUI v2 > Library > Set Lokasenna_GUI v2 library path.lua"
    end
    local f = io.open(lib_path .. "Core.lua", "r")
    if not f then
        return false,
            "Lokasenna_GUI v2 Core.lua not found at:\n" .. lib_path .. "\n\n" ..
            "Re-run the library path setter script."
    end
    f:close()

    local _, proj_path = reaper.EnumProjects(-1, "")
    if proj_path == "" then
        local choice = reaper.ShowMessageBox(
            "This project has never been saved.\n\n" ..
            "The region root name will default to \"Project\".\n\nContinue anyway?",
            "Region Creator — Unsaved Project", 4)
        if choice ~= 6 then return false, "" end
    end

    return true, ""
end

function create_regions()
    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()

    -- existing guard: kept as-is
    if not RC.audio_types[RC.selected_type_idx] then
        reaper.ShowMessageBox("No audio type selected.", "Invalid Selection", 0)
        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock("Create Regions", -1)
        return
    end

    -- precondition check
    local valid, msg = validate_preconditions()
    if not valid then
        if msg ~= "" then
            reaper.ShowMessageBox(msg, "Region Creator — Cannot Proceed", 0)
        end
        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock("Create Regions", -1)
        return
    end

    -- pcall protects against unexpected runtime errors in track/region logic
    local ok, err = pcall(function()
        sync_config_to_audio_type()
        local n = create_regions_from_folder_structure()
        if n > 0 then
            save_region_hierarchy()
            reaper.ShowMessageBox(string.format("Created %d region(s).", n), "Regions Created", 0)
        end
    end)

    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Create Regions", -1)

    if not ok then
        reaper.ShowMessageBox(
            "Unexpected error in Region Creator:\n\n" .. tostring(err),
            "Region Creator — Error", 0)
    end
end

function save_region_hierarchy()
    local lines = {}
    for id, h in pairs(RC.region_hierarchy_data) do
        lines[#lines + 1] = id .. "|" .. (h.root or "") .. "|" .. (h.parent or "")
    end
    reaper.SetExtState(RC.EXT_KEY, "region_hierarchy", table.concat(lines, "\n"), true)
end

function load_region_hierarchy()
    local data = {}
    local str = reaper.GetExtState(RC.EXT_KEY, "region_hierarchy")
    if str == "" then return data end
    for line in (str .. "\n"):gmatch("([^\n]+)") do
        local id, root, parent = line:match("^([^|]+)|([^|]*)|(.-)$")
        if id and id ~= "" then data[id] = { root = root or "", parent = parent or "" } end
    end
    return data
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

RC.region_hierarchy_data = load_region_hierarchy()
