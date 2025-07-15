-- Verifica que ReaImGui esté instalado
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("ReaImGui no está instalado. Por favor, instala ReaImGui desde ReaPack.", "Error", 0)
    return
end

-- Crear el contexto ImGui
local ctx = reaper.ImGui_CreateContext('Separar y Unir Ítems')

-- Valor inicial de distancia
local distance = 1.0
local selected_items_names = {}

-- Función para obtener los nombres de los ítems seleccionados
function getSelectedItemsNames()
    local items = {}
    local num_items = reaper.CountSelectedMediaItems(0)
    for i = 0, num_items - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        local retval, item_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        table.insert(items, item_name)
    end
    return items
end

-- Función para separar ítems seleccionados
function separateItems(distance)
    local num_items = reaper.CountSelectedMediaItems(0)
    if num_items > 1 then
        local first_item = reaper.GetSelectedMediaItem(0, 0)
        local current_position = reaper.GetMediaItemInfo_Value(first_item, "D_POSITION")
        local first_item_length = reaper.GetMediaItemInfo_Value(first_item, "D_LENGTH")
        
        current_position = current_position + first_item_length + distance

        for i = 1, num_items - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            reaper.SetMediaItemInfo_Value(item, "D_POSITION", current_position)
            current_position = current_position + item_length + distance
        end
    end
end

-- Función para unir ítems seleccionados
function joinItems()
    local num_items = reaper.CountSelectedMediaItems(0)
    if num_items > 1 then
        local first_item = reaper.GetSelectedMediaItem(0, 0)
        local current_position = reaper.GetMediaItemInfo_Value(first_item, "D_POSITION")
        local first_item_length = reaper.GetMediaItemInfo_Value(first_item, "D_LENGTH")

        current_position = current_position + first_item_length

        for i = 1, num_items - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            reaper.SetMediaItemInfo_Value(item, "D_POSITION", current_position)
            current_position = current_position + item_length
        end
    end
end

-- Función para mostrar la interfaz gráfica
function showUI()
    -- Ajustar el tamaño de la ventana dinámicamente al contenido
    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 200, 100, 99999, 99999)  -- Sin tamaño máximo

    local visible, open = reaper.ImGui_Begin(ctx, 'Separar y Unir Ítems', true)

    if visible then
        -- Obtener los ítems seleccionados
        selected_items_names = getSelectedItemsNames()

        -- Mostrar los nombres de los ítems seleccionados
        reaper.ImGui_Text(ctx, 'Ítems seleccionados:')
        local item_names_display = table.concat(selected_items_names, '\n')
        reaper.ImGui_Text(ctx, item_names_display)

        reaper.ImGui_Separator(ctx)

        -- Campo de texto para la distancia
        local input_changed
        input_changed, distance = reaper.ImGui_InputDouble(ctx, ' ', distance, 0.1, 1.0, "%.2f")

        -- Mostrar la distancia debajo del campo de texto
        reaper.ImGui_Text(ctx, string.format("Distancia: %.2f s", distance))

        -- Separador para los botones
        reaper.ImGui_Separator(ctx)

        -- Botón para aplicar la separación
        if reaper.ImGui_Button(ctx, 'Aplicar separación') then
            reaper.Undo_BeginBlock()
            separateItems(distance)
            reaper.Undo_EndBlock("Separar ítems seleccionados", -1)
        end

        reaper.ImGui_SameLine(ctx)  -- Coloca el siguiente botón en la misma línea

        -- Botón para unir ítems
        if reaper.ImGui_Button(ctx, 'Unir ítems') then
            reaper.Undo_BeginBlock()
            joinItems()
            reaper.Undo_EndBlock("Unir ítems seleccionados", -1)
        end

        reaper.ImGui_End(ctx)
    end

    if open then
        reaper.defer(showUI)
    end
end

-- Inicia la interfaz
showUI()

