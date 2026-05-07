-- ── render.lua ────────────────────────────────────────────────────────
-- Provides render_region, render_all_regions, render_regions_by_type.
-- All three are global so gui.lua can call them from button callbacks.

local function resolve_base()
    if RC.render_base_dir and RC.render_base_dir ~= "" then
        return RC.render_base_dir
    end
    local p = reaper.GetProjectPath(0)
    if not p or p == "" then p = reaper.GetResourcePath() end
    return p .. "/Renders"
end


local function normalize_path(p)
    if package.config:sub(1, 1) == "\\" then
        return (p:gsub("/", "\\"))
    end
    return p
end

local function ensure_dir(path)
    reaper.RecursiveCreateDirectory(path, 0)
end

local function find_region_by_id(id)
    for i = 0, reaper.CountProjectMarkers(0) - 1 do
        local _, isrgn, pos, rend, name = reaper.EnumProjectMarkers(i)
        if isrgn then
            if string.format("%.10f_%.10f", pos, rend) == id then
                return { index = i, pos = pos, rend = rend, name = name }
            end
        end
    end
    return nil
end

-- Match an audio type by its prefix appearing at the start of a region name.
local function type_for_region(region_name)
    for _, t in ipairs(RC.audio_types) do
        if region_name:sub(1, #t.prefix + 1) == t.prefix .. "_" then
            return t
        end
    end
    return RC.audio_types[RC.selected_type_idx]
end

-- ── Public API ────────────────────────────────────────────────────────

function render_region(region_id)
    local region = find_region_by_id(region_id)
    if not region then
        RC.render_status = "Error: region not found"
        return false
    end

    local hier   = RC.region_hierarchy_data[region_id] or get_region_hierarchy(region.index)
    local root   = hier.root   or "Unknown"
    local parent = hier.parent or "Unknown"
    local atype  = type_for_region(region.name)

    local base    = resolve_base()
    local out_dir = (atype.path_pattern or "{base}/$prefix/$root/$parent/"):gsub("{base}", base)
    out_dir       = expand_wildcards(out_dir, atype.prefix, root, parent)
    -- Use the region name directly: it was already expanded with the correct values at creation time.
    local filename = region.name

    out_dir = normalize_path(out_dir:gsub("[/\\]+$", ""))
    ensure_dir(out_dir)

    -- Save current render settings and time selection
    local _, old_file    = reaper.GetSetProjectInfo_String(0, "RENDER_FILE",    "", false)
    local _, old_pattern = reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "", false)
    local old_bounds     = reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 0, false)
    local old_settings   = reaper.GetSetProjectInfo(0, "RENDER_SETTINGS",   0, false)
    local old_sel_s, old_sel_e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

    -- Set time selection to this region's range (BOUNDSFLAG=2 = time selection; most reliable)
    reaper.GetSet_LoopTimeRange(true, false, region.pos, region.rend, false)
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE",    out_dir,  true)
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", filename, true)
    reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 2, true)
    if old_settings ~= 0 then
        reaper.GetSetProjectInfo(0, "RENDER_SETTINGS", 0, true)
    end

    -- Render (shows REAPER progress window; blocks until done or cancelled)
    reaper.Main_OnCommand(42230, 0)

    -- Restore render settings and time selection
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE",    old_file,    true)
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", old_pattern, true)
    reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", old_bounds,  true)
    if old_settings ~= 0 then
        reaper.GetSetProjectInfo(0, "RENDER_SETTINGS", old_settings, true)
    end
    reaper.GetSet_LoopTimeRange(true, false, old_sel_s, old_sel_e, false)

    RC.render_status = "→ " .. out_dir
    RC.last_render_dir = out_dir
    return true
end

-- Builds the list of region IDs to operate on.
-- If RC.region_hierarchy_data is populated (regions created this session) use it.
-- Otherwise scan all project markers so previously-created regions are still renderable.
local function collect_project_region_ids()
    if next(RC.region_hierarchy_data) then
        local ids = {}
        for id in pairs(RC.region_hierarchy_data) do ids[#ids + 1] = id end
        return ids
    end
    local ids = {}
    for i = 0, reaper.CountProjectMarkers(0) - 1 do
        local _, isrgn, pos, rend = reaper.EnumProjectMarkers(i)
        if isrgn then
            ids[#ids + 1] = string.format("%.10f_%.10f", pos, rend)
        end
    end
    return ids
end

function render_all_regions()
    local ids = collect_project_region_ids()

    if #ids == 0 then
        RC.render_status = "No regions in project"
        return
    end

    for n, id in ipairs(ids) do
        RC.render_status = string.format("Rendering %d/%d...", n, #ids)
        render_region(id)
    end
    RC.render_status = string.format("Done (%d) → %s", #ids, RC.last_render_dir or "?")
end

function render_regions_by_type(type_idx)
    local atype = RC.audio_types[type_idx]
    if not atype then
        RC.render_status = "Invalid type index"
        return
    end

    local all_ids = collect_project_region_ids()
    local ids = {}
    for _, id in ipairs(all_ids) do
        local region = find_region_by_id(id)
        if region and region.name:sub(1, #atype.prefix + 1) == atype.prefix .. "_" then
            ids[#ids + 1] = id
        end
    end

    if #ids == 0 then
        RC.render_status = "No regions found for: " .. atype.name
        return
    end

    for n, id in ipairs(ids) do
        RC.render_status = string.format("Rendering %d/%d (%s)...", n, #ids, atype.name)
        render_region(id)
    end
    RC.render_status = string.format("Done (%d %s) → %s", #ids, atype.name, RC.last_render_dir or "?")
end

function render_queue(id_list)
    RC.render_results = {}
    if #id_list == 0 then
        RC.render_status = "No regions selected"
        return
    end
    for n, id in ipairs(id_list) do
        RC.render_status = string.format("Rendering %d/%d...", n, #id_list)
        local ok, err = pcall(render_region, id)
        RC.render_results[#RC.render_results + 1] = {
            id  = id,
            ok  = ok,
            err = not ok and tostring(err) or nil,
        }
    end
    local done, failed = 0, 0
    for _, r in ipairs(RC.render_results) do
        if r.ok then done = done + 1 else failed = failed + 1 end
    end
    if failed == 0 then
        RC.render_status = string.format("Done (%d) → %s", done, RC.last_render_dir or "?")
    else
        RC.render_status = string.format("Done %d  Failed %d → %s",
            done, failed, RC.last_render_dir or "?")
    end
end

RC.render_status  = "Ready"
RC.render_results = {}
