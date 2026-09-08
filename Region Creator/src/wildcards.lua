-- Finds the audio type owning this prefix so UCS tokens can resolve
-- against it; falls back to the currently selected type.
local function type_for_prefix(prefix)
    for _, t in ipairs(RC.audio_types or {}) do
        if t.prefix == prefix then return t end
    end
    return (RC.audio_types or {})[RC.selected_type_idx]
end

function expand_wildcards(pattern, prefix, root, parent)
    local qname = RC.dx_quest_name ~= "" and RC.dx_quest_name or parent
    local char  = RC.dx_character  ~= "" and RC.dx_character  or "unknown"
    local qtype = RC.dx_quest_type ~= "" and RC.dx_quest_type or "SQ"

    local atype = type_for_prefix(prefix)
    local catid = (atype and atype.ucs_catid ~= "" and atype.ucs_catid) or "NoCatID"

    -- Normalize $WildcardName to $wildcardname so patterns typed in any case expand correctly
    pattern = pattern:gsub("%$(%a+)", function(w) return "$" .. w:lower() end)

    -- Custom per-type fields first (longest keys first so e.g. $ammo2 wins
    -- over $ammo), then the built-in tokens.
    if atype and atype.fields and #atype.fields > 0 then
        local sorted = {}
        for i, f in ipairs(atype.fields) do sorted[i] = f end
        table.sort(sorted, function(a, b) return #a.key > #b.key end)
        for _, f in ipairs(sorted) do
            local value = (f.value and f.value ~= "") and f.value or "unknown"
            pattern = pattern:gsub("%$" .. f.key, (value:gsub("%%", "%%%%")))
        end
    end

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
        :gsub("%$catid",     catid)
        :gsub("%$fxname",    ucs_sanitize_field(parent))
        :gsub("%$creatorid", ucs_sanitize_field(RC.ucs_creator_id or ""))
        :gsub("%$sourceid",  ucs_sanitize_field(RC.ucs_source_id or ""))
        :gsub("%$userdata",  ucs_sanitize_field(RC.ucs_user_data or ""))
        :gsub("%$region",    parent)   -- legacy alias
end
