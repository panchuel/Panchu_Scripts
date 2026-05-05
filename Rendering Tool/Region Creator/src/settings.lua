function load_settings()
    local s = {}
    for key, default in pairs(RC.default_settings) do
        local raw = reaper.GetExtState(RC.EXT_KEY, key)
        if raw ~= "" then
            if     type(default) == "number"  then s[key] = tonumber(raw) or default
            elseif type(default) == "boolean" then s[key] = (raw == "true")
            else                                   s[key] = raw
            end
        else
            s[key] = default
        end
    end
    return s
end

function save_settings(s)
    for key, value in pairs(s) do
        local str = type(value) == "boolean" and (value and "true" or "false") or tostring(value)
        reaper.SetExtState(RC.EXT_KEY, key, str, true)
    end
end

local s = load_settings()

RC.prefix             = s.prefix
RC.prefix_type        = s.prefix_type
RC.valid_tracks       = {}
RC.variations         = s.variations
RC.separation_time    = s.separation_time
RC.randomize_position = s.randomize_position
RC.wildcard_template  = s.wildcard_template
RC.music_bpm          = s.music_bpm
RC.music_meter        = s.music_meter
RC.dx_character       = s.dx_character
RC.dx_quest_type      = s.dx_quest_type
RC.dx_quest_name      = s.dx_quest_name
RC.dx_line_number     = s.dx_line_number

RC.random_params = {
    volume    = { enable = s.volume_enable,    amount = s.volume_amount   },
    pan       = { enable = s.pan_enable,       amount = s.pan_amount      },
    pitch     = { enable = s.pitch_enable,     amount = s.pitch_amount    },
    rate      = { enable = s.rate_enable,      amount = s.rate_amount     },
    position  = { enable = true,               amount = 0.0               },
    length    = { enable = s.length_enable,    amount = s.length_amount   },
    fadein    = { enable = s.fadein_enable,    amount = s.fadein_amount   },
    fadeout   = { enable = s.fadeout_enable,   amount = s.fadeout_amount  },
    fadeshape = { enable = s.fadeshape_enable, amount = 1                 },
}

RC.slider_ranges = {
    volume   = { min = 0.0, max = 12.0 },
    pan      = { min = 0.0, max = 1.0  },
    pitch    = { min = 0.0, max = 12.0 },
    rate     = { min = 0.0, max = 0.5  },
    position = { min = 0.0, max = 5.0  },
    length   = { min = 0.0, max = 0.5  },
    fadein   = { min = 0.0, max = 1.0  },
    fadeout  = { min = 0.0, max = 1.0  },
}

RC.region_hierarchy_data = {}

-- Safety net: fill any RC field that could be nil due to corrupted ExtState,
-- module load order changes, or missing keys added in future versions.
local function ensure_rc_complete()
    local d = RC.default_settings
    if RC.prefix             == nil then RC.prefix             = d.prefix             end
    if RC.prefix_type        == nil then RC.prefix_type        = d.prefix_type        end
    if RC.wildcard_template  == nil then RC.wildcard_template  = d.wildcard_template  end
    if RC.music_bpm          == nil then RC.music_bpm          = d.music_bpm          end
    if RC.music_meter        == nil then RC.music_meter        = d.music_meter        end
    if RC.dx_character       == nil then RC.dx_character       = d.dx_character       end
    if RC.dx_quest_type      == nil then RC.dx_quest_type      = d.dx_quest_type      end
    if RC.dx_quest_name      == nil then RC.dx_quest_name      = d.dx_quest_name      end
    if RC.dx_line_number     == nil then RC.dx_line_number     = d.dx_line_number     end
    if RC.valid_tracks       == nil then RC.valid_tracks       = {}                   end
    if RC.region_hierarchy_data == nil then RC.region_hierarchy_data = {}             end
    if RC.audio_types        == nil then RC.audio_types        = RC.default_audio_types end
    if RC.selected_type_idx  == nil then RC.selected_type_idx  = 1                   end
    if RC.random_params      == nil then
        RC.random_params = {
            volume    = { enable = false, amount = d.volume_amount   },
            pan       = { enable = false, amount = d.pan_amount      },
            pitch     = { enable = false, amount = d.pitch_amount    },
            rate      = { enable = false, amount = d.rate_amount     },
            position  = { enable = true,  amount = 0.0               },
            length    = { enable = false, amount = d.length_amount   },
            fadein    = { enable = false, amount = d.fadein_amount   },
            fadeout   = { enable = false, amount = d.fadeout_amount  },
            fadeshape = { enable = false, amount = 1                 },
        }
    end
    -- Render fields (also initialized by render.lua, but guarded here as fallback)
    if RC.render_status == nil then RC.render_status = "Ready" end
    if RC.render_mode   == nil then RC.render_mode   = 1       end
    -- Ensure each audio type has path_pattern (may be absent if loaded from v1/v2 ExtState)
    for i, t in ipairs(RC.audio_types or {}) do
        if not t.path_pattern or t.path_pattern == "" then
            local def = RC.default_audio_types and RC.default_audio_types[i]
            t.path_pattern = def and def.path_pattern or "{base}/$prefix/$root/$parent/"
        end
    end
end

ensure_rc_complete()
