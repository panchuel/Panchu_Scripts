if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("ReaImGui no está instalado. Por favor, instala ReaImGui desde ReaPack.", "Error", 0)
    return
end

local ctx = reaper.ImGui_CreateContext('Jerarquía del Proyecto')
dofile("C:\\Users\\Panchuel\\AppData\\Roaming\\REAPER\\Scripts\\Panchu_Scripts\\SyncProjectHierarchy.lua")

local function draw_node_recursive(node)
    if not node or not node.name or not node.index then
        return
    end

    if #node.children > 0 then
        if reaper.ImGui_TreeNode(ctx, node.name) then
            for _, child in ipairs(node.children) do
                draw_node_recursive(child)
            end
            reaper.ImGui_TreePop(ctx)
        end
    else
        reaper.ImGui_Selectable(ctx, node.name, false)
    end
end

local function showUI()
    if not _G.get_project_hierarchy then
        reaper.ShowConsoleMsg("La jerarquía no está disponible. Carga el script de funcionalidad primero.\n")
        return
    end

    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 200, 100, 99999, 99999)

    local visible, open = reaper.ImGui_Begin(ctx, 'Jerarquía del Proyecto', true)

    if visible then
        if reaper.ImGui_Button(ctx, "Cargar Jerarquía") then
            sync_project_hierarchy()
        end

        local project_hierarchy = _G.get_project_hierarchy()
        if project_hierarchy then
            for _, node in ipairs(project_hierarchy) do
                draw_node_recursive(node)
            end
        else
            reaper.ImGui_Text(ctx, "No hay jerarquía cargada.")
        end

        reaper.ImGui_End(ctx)
    end

    if open then
        reaper.defer(showUI)
    else
        if ctx then -- Asegurarse de que el contexto no sea nil
            reaper.ImGui_DestroyContext(ctx)
            ctx = nil -- Prevenir múltiples destrucciones
        end
    end
end

reaper.defer(showUI)

