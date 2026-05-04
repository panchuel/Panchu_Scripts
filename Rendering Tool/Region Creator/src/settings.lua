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
