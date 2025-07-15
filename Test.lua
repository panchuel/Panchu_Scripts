function get_project_hierarchy()
    local hierarchy = {}

    -- Recorrer todos los tracks del proyecto
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

        -- Obtener la profundidad de la carpeta (si el track es un folder)
        local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")

        -- Almacenar el track con su nombre y su profundidad
        table.insert(hierarchy, {name = name, depth = depth})
    end

    -- Función para imprimir la jerarquía con indentación
    local function print_hierarchy()
        for i, track in ipairs(hierarchy) do
            -- Indentar según la profundidad
            local indent = string.rep("  ", track.depth)
            -- Imprimir el track con su indentación y profundidad
            print(string.format("Track added: %s (Depth: %d)", indent .. track.name, track.depth))
        end
    end

    -- Mostrar la jerarquía
    print("Syncing project hierarchy...")
    print_hierarchy()

    return hierarchy
end

-- Llamar a la función para mostrar la jerarquía
get_project_hierarchy()

