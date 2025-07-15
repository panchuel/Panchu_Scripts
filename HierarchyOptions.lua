-- HierarchyOptions.lua
local options = {
    minimal_view = false,  -- Estado por defecto
    solo = false,
    jump = false
}

-- Función para alternar una opción
local function toggle_option(option_name)
    if options[option_name] ~= nil then
        options[option_name] = not options[option_name]
    end
end

-- Función para obtener el estado actual de una opción
local function get_option(option_name)
    return options[option_name]
end

-- Función para inicializar o cargar configuraciones (opcional)
local function load_default_options()
    options.minimal_view = false
    options.solo = false
    options.jump = false
end

return {
    toggle_option = toggle_option,
    get_option = get_option,
    load_default_options = load_default_options
}

