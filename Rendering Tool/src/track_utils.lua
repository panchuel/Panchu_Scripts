function clean_name(name)
    return name:gsub("[^%w_]", "_"):gsub("__+", "_")
end

function get_track_name(track)
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    return name or "Unnamed"
end

function get_track_index(track)
    return reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
end

function get_folder_depth(track)
    return reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
end

function get_parent_track(track)
    local idx = get_track_index(track)
    if idx == 0 then return nil end

    local current_level = 0
    for i = 0, idx - 1 do
        current_level = current_level +
            reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, i), "I_FOLDERDEPTH")
    end

    for i = idx - 1, 0, -1 do
        local candidate = reaper.GetTrack(0, i)
        if reaper.GetMediaTrackInfo_Value(candidate, "I_FOLDERDEPTH") == 1 then
            local lvl = 0
            for j = 0, i - 1 do
                lvl = lvl + reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, j), "I_FOLDERDEPTH")
            end
            if lvl == current_level - 1 then return candidate end
        end
    end
    return nil
end

function get_child_tracks(folder_track)
    local children = {}
    local idx   = get_track_index(folder_track)
    local total = reaper.CountTracks(0)
    for i = idx + 1, total - 1 do
        local tr = reaper.GetTrack(0, i)
        table.insert(children, tr)
        if get_folder_depth(tr) < 0 then break end
    end
    return children
end

function get_direct_child_tracks(folder_track)
    local direct  = {}
    local nesting = 0
    local idx     = get_track_index(folder_track)
    local total   = reaper.CountTracks(0)
    for i = idx + 1, total - 1 do
        local tr = reaper.GetTrack(0, i)
        local d  = get_folder_depth(tr)
        if nesting == 0 then table.insert(direct, tr) end
        nesting = nesting + d
        if nesting < 0 then break end
    end
    return direct
end

function get_item_notes(item)
    local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    return notes or ""
end

function set_item_notes(item, notes)
    reaper.GetSetMediaItemInfo_String(item, "P_NOTES", notes, true)
end

function is_original_item(item)
    local n = get_item_notes(item)
    return n:find(RC.ORIGINAL_TAG) and not n:find(RC.VARIATION_TAG)
end

function is_variation_item(item)
    return get_item_notes(item):find(RC.VARIATION_TAG) ~= nil
end

function mark_original_items(folder_track)
    for _, child in ipairs(get_child_tracks(folder_track)) do
        for k = 0, reaper.CountTrackMediaItems(child) - 1 do
            local item = reaper.GetTrackMediaItem(child, k)
            if not is_original_item(item) and not is_variation_item(item) then
                set_item_notes(item, get_item_notes(item) .. " " .. RC.ORIGINAL_TAG)
            end
        end
    end
end

function apply_random_parameters(new_item, new_take)
    local rp = RC.random_params
    if rp.volume.enable and rp.volume.amount > 0 then
        local db = (math.random() * 2 - 1) * rp.volume.amount
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_VOL", 10 ^ (db / 20))
    end
    if rp.pan.enable and rp.pan.amount > 0 then
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_PAN",
            (math.random() * 2 - 1) * rp.pan.amount)
    end
    if rp.pitch.enable and rp.pitch.amount > 0 then
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_PITCH",
            (math.random() * 2 - 1) * rp.pitch.amount)
    end
    if rp.rate.enable and rp.rate.amount > 0 then
        local f = 1.0 + (math.random() * 2 - 1) * rp.rate.amount
        reaper.SetMediaItemTakeInfo_Value(new_take, "D_PLAYRATE", f)
        local l = reaper.GetMediaItemInfo_Value(new_item, "D_LENGTH")
        reaper.SetMediaItemInfo_Value(new_item, "D_LENGTH", l / f)
    end
    if rp.length.enable and rp.length.amount > 0 then
        local f = 1.0 + (math.random() * 2 - 1) * rp.length.amount
        local l = reaper.GetMediaItemInfo_Value(new_item, "D_LENGTH")
        reaper.SetMediaItemInfo_Value(new_item, "D_LENGTH", l * f)
    end
    if rp.fadein.enable and rp.fadein.amount > 0 then
        local l = reaper.GetMediaItemInfo_Value(new_item, "D_FADEINLEN")
        reaper.SetMediaItemInfo_Value(new_item, "D_FADEINLEN",
            l * (1 + (math.random() * 2 - 1) * rp.fadein.amount))
    end
    if rp.fadeout.enable and rp.fadeout.amount > 0 then
        local l = reaper.GetMediaItemInfo_Value(new_item, "D_FADEOUTLEN")
        reaper.SetMediaItemInfo_Value(new_item, "D_FADEOUTLEN",
            l * (1 + (math.random() * 2 - 1) * rp.fadeout.amount))
    end
    if rp.fadeshape.enable then
        local shape = ({ 0, 1, 2, 3 })[math.random(1, 4)]
        reaper.SetMediaItemInfo_Value(new_item, "C_FADEINSHAPE",  shape)
        reaper.SetMediaItemInfo_Value(new_item, "C_FADEOUTSHAPE", shape)
    end
end
