--@description Create regions from parent track name
--@version 1.0
--@author Panchuel
--@link https://github.com/panchuel/Panchu_Scripts
--@license MIT
--@about
--  # Create regions from parent track name
--
--  Makes one region per selected item, named after the folder track the item
--  lives in. A folder called Weapons gives you regions called Weapons, which
--  is what you want when a folder holds many takes of the same sound.
--
--  An item that is not inside a folder falls back to its own take name, with
--  the file extension trimmed, so loose items still get something sensible.
--
--  Each region gets a random colour so neighbours stay easy to tell apart in
--  the ruler.

-- Lua 5.4 seeds the generator itself, 5.3 does not and would hand out the
-- same colours in every session.
math.randomseed(os.time())

local function take_name(item)
    local take = reaper.GetActiveTake(item)
    if not take then return nil end
    local _, name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    if not name or name == "" then return nil end
    -- Trim at the first dot, so "shot.wav" names the region "shot".
    return name:match("^[^%.]+") or name
end

local function parent_name(item)
    local track = reaper.GetMediaItemTrack(item)
    if not track then return nil end

    local parent = reaper.GetParentTrack(track)
    if not parent then return nil end

    local _, name = reaper.GetSetMediaTrackInfo_String(parent, "P_NAME", "", false)
    if not name or name == "" then return nil end
    return name
end

-- The folder wins, the item is the fallback. An empty item outside a folder
-- has neither, and is reported rather than silently skipped.
local function region_name(item)
    return parent_name(item) or take_name(item)
end

local function random_colour()
    return reaper.ColorToNative(
        math.random(0, 255), math.random(0, 255), math.random(0, 255)) | 0x1000000
end

local function main()
    local count = reaper.CountSelectedMediaItems(0)
    if count == 0 then
        reaper.MB("Select one or more items first.",
            "Create regions from parent track name", 0)
        return
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    local made, skipped = 0, 0

    for i = 0, count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local name = region_name(item)

        if name then
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            reaper.AddProjectMarker2(0, true, pos, pos + len, name, -1, random_colour())
            made = made + 1
        else
            skipped = skipped + 1
        end
    end

    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Create regions from parent track name", -1)
    reaper.UpdateArrange()

    if skipped > 0 then
        reaper.MB(string.format(
            "Created %d region(s).\n\n%d item(s) were skipped: they are empty " ..
            "and are not inside a named folder, so there was no name to use.",
            made, skipped), "Create regions from parent track name", 0)
    end
end

main()
