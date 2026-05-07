function expand_wildcards(pattern, prefix, root, parent)
    local qname = RC.dx_quest_name ~= "" and RC.dx_quest_name or parent
    local char  = RC.dx_character  ~= "" and RC.dx_character  or "unknown"
    local qtype = RC.dx_quest_type ~= "" and RC.dx_quest_type or "SQ"
    -- Normalize $WildcardName to $wildcardname so patterns typed in any case expand correctly
    pattern = pattern:gsub("%$(%a+)", function(w) return "$" .. w:lower() end)
    return pattern
        :gsub("%$prefix",    prefix)
        :gsub("%$root",      root)
        :gsub("%$parent",    parent)
        :gsub("%$bpm",       tostring(RC.music_bpm))
        :gsub("%$meter",     RC.music_meter)
        :gsub("%$character", char)
        :gsub("%$questtype", qtype)
        :gsub("%$questname", qname)
        :gsub("%$line",      string.format("%02d", RC.dx_line_number))
        :gsub("%$region",    parent)   -- legacy alias
end
