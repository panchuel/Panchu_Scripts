function print_hierarchy(hierarchy, indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent)
    for _, node in ipairs(hierarchy) do
        reaper.ShowConsoleMsg(prefix .. "- " .. node.name .. " (Index: " .. tostring(node.index) .. ")\n")
        if #node.children > 0 then
            print_hierarchy(node.children, indent + 1)
        end
    end
end

function get_project_hierarchy()
    local hierarchy = {}
    local stack = {}

    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")

        -- Ignorar tracks sin nombre
        if not name or name == "" then
            name = nil -- No asignar "(Sin nombre)"
        end

        if name then
            local node = {
                type = "track",
                name = name,
                index = i + 1,
                children = {}
            }

            if depth > 0 then
                if #stack > 0 then
                    table.insert(stack[#stack].children, node)
                end
                table.insert(stack, node)
            elseif depth == 0 then
                if #stack > 0 then
                    table.insert(stack[#stack].children, node)
                else
                    table.insert(hierarchy, node)
                end
            elseif depth < 0 then
                for _ = 1, math.abs(depth) do
                    local completed_folder = table.remove(stack)
                    if #stack == 0 then
                        table.insert(hierarchy, completed_folder)
                    end
                end
                if #stack > 0 then
                    table.insert(stack[#stack].children, node)
                else
                    table.insert(hierarchy, node)
                end
            end
        end
    end

    while #stack > 0 do
        table.insert(hierarchy, table.remove(stack))
    end

    return hierarchy
end

function sync_project_hierarchy()
    local hierarchy = get_project_hierarchy()
    _G.get_project_hierarchy = function() return hierarchy end
    reaper.ClearConsole()
    reaper.ShowConsoleMsg("Jerarquía sincronizada:\n")
    print_hierarchy(hierarchy)
end

sync_project_hierarchy()

