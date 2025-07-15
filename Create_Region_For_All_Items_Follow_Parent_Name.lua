function main()
    -- Comienza una acción que se puede deshacer en Reaper
    reaper.Undo_BeginBlock()

    -- Obtiene el número de ítems seleccionados
    local num_items = reaper.CountSelectedMediaItems(0)
    
    -- Itera sobre todos los ítems seleccionados
    for i = 0, num_items - 1 do
        -- Obtiene el ítem en la posición 'i'
        local item = reaper.GetSelectedMediaItem(0, i)

        -- Obtiene la pista donde está el ítem
        local track = reaper.GetMediaItemTrack(item)

        -- Obtiene el inicio y final del ítem
        local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local item_end = item_start + item_length

        -- Obtiene el nombre del ítem
        local take = reaper.GetActiveTake(item)
        local retval, item_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        
        -- Elimina todo lo que está después del primer punto "."
        local clean_name = item_name:match("^[^%.]+") or item_name
        
        -- Genera valores RGB
        local r =math.random(0,255)
        local g =math.random(0,255)
        local b =math.random(0,255)
        
        -- Crea el color RGB a un formato que reaper entienda
        local color = reaper.ColorToNative(r,g,b) | 0x1000000 

        -- Crea una región con el nombre del ítem
        reaper.AddProjectMarker2(0, true, item_start, item_end, clean_name, -1, color)
    end

    -- Finaliza la acción deshacer
    reaper.Undo_EndBlock("Crear regiones para cada ítem seleccionado", -1)
end

-- Llama a la función principal
main()
