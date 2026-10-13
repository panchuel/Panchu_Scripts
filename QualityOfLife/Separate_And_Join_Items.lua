--@description Separate and join items
--@version 1.0
--@author Panchuel
--@link https://github.com/panchuel/Panchu_Scripts
--@license MIT
--@about
--  # Separate and join items
--
--  Lays the selected items end to end, either with an even gap between them
--  or butted together with none. Useful for spacing out a batch of takes
--  before rendering them, or closing the gaps again afterwards.
--
--  The first item never moves: everything else lines up after it, so the
--  result stays anchored where you put it.
--
--  Items are laid out in timeline order rather than selection order, so a
--  selection spanning several tracks does not come out shuffled.
--
--  Requires ReaImGui, installable from ReaPack.

if not reaper.ImGui_GetBuiltinPath then
    reaper.MB(
        "This script needs ReaImGui.\n\n" ..
        "Install it from Extensions > ReaPack > Browse packages, " ..
        "then search for ReaImGui.",
        "Separate and join items", 0)
    return
end

package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua"
local ImGui = require "imgui" "0.9"

local ctx     = ImGui.CreateContext("Separate and join items")
local spacing = 1.0

local function take_name(item)
    local take = reaper.GetActiveTake(item)
    if not take then return "(empty item)" end
    local _, name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    return (name ~= "" and name) or "(unnamed)"
end

local function selected_items()
    local items = {}
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
        items[#items + 1] = reaper.GetSelectedMediaItem(0, i)
    end

    -- Spacing is a timeline operation, so sort by position. Selection order
    -- follows track order first, which would scramble the result whenever a
    -- selection crosses more than one track.
    table.sort(items, function(a, b)
        return reaper.GetMediaItemInfo_Value(a, "D_POSITION")
             < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
    end)
    return items
end

-- Lays the items end to end after the first one, leaving `gap` seconds
-- between them. Joining is just gap = 0, so both buttons share this.
local function lay_out(gap, undo_label)
    local items = selected_items()
    if #items < 2 then return end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    local pos = reaper.GetMediaItemInfo_Value(items[1], "D_POSITION")
              + reaper.GetMediaItemInfo_Value(items[1], "D_LENGTH") + gap

    for i = 2, #items do
        reaper.SetMediaItemInfo_Value(items[i], "D_POSITION", pos)
        pos = pos + reaper.GetMediaItemInfo_Value(items[i], "D_LENGTH") + gap
    end

    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock(undo_label, -1)
    reaper.UpdateArrange()
end

local function loop()
    ImGui.SetNextWindowSizeConstraints(ctx, 260, 140, 99999, 99999)

    local visible, open = ImGui.Begin(ctx, "Separate and join items", true)

    if visible then
        local items = selected_items()

        if #items == 0 then
            ImGui.Text(ctx, "No items selected.")
        else
            ImGui.Text(ctx, string.format("%d item(s) selected:", #items))
            local names = {}
            for i, item in ipairs(items) do names[i] = take_name(item) end
            ImGui.Text(ctx, table.concat(names, "\n"))
        end

        ImGui.Separator(ctx)

        local changed
        changed, spacing = ImGui.InputDouble(ctx, "Gap (seconds)", spacing, 0.1, 1.0, "%.2f")
        if spacing < 0 then spacing = 0 end

        ImGui.Separator(ctx)

        -- Nothing to lay out below two items, so the buttons say so rather
        -- than appearing to do nothing.
        local enough = #items > 1

        if not enough then
            ImGui.Text(ctx, "Select at least two items.")
        else
            if ImGui.Button(ctx, "Apply gap") then
                lay_out(spacing, "Separate items")
            end
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, "Join") then
                lay_out(0, "Join items")
            end
        end

        ImGui.End(ctx)
    end

    if open then reaper.defer(loop) end
end

loop()
