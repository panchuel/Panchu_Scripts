RC.EXT_KEY       = "SFX_Renderer"
RC.ORIGINAL_TAG  = "SFX_ORIGINAL"
RC.VARIATION_TAG = "SFX_VARIATION"

RC.default_audio_types = {
    {
        name = "SFX", prefix = "sx", wildcard = "$prefix_$root_$parent_",
        config = { bpm=0, meter="", character="", quest_type="", quest_name="", line_number=1 },
    },
    {
        name = "Music", prefix = "mx", wildcard = "$prefix_$root_$parent_$bpm_$meter_",
        config = { bpm=120, meter="4-4", character="", quest_type="", quest_name="", line_number=1 },
    },
    {
        name = "Dialogue", prefix = "dx", wildcard = "$prefix_$character_$questtype_$questname_$line_",
        config = { bpm=0, meter="", character="", quest_type="SQ", quest_name="", line_number=1 },
    },
    {
        name = "Environment", prefix = "env", wildcard = "$prefix_$root_$parent_",
        config = { bpm=0, meter="", character="", quest_type="", quest_name="", line_number=1 },
    },
}

RC.default_settings = {
    prefix             = "sx",
    prefix_type        = "sx",
    variations         = 0,
    separation_time    = 1.0,
    randomize_position = 0.0,
    wildcard_template  = "$region",
    music_bpm          = 120,
    music_meter        = "4-4",
    dx_character       = "",
    dx_quest_type      = "SQ",
    dx_quest_name      = "",
    dx_line_number     = 1,
    volume_enable      = false,  volume_amount   = 3.0,
    pan_enable         = false,  pan_amount      = 0.1,
    pitch_enable       = false,  pitch_amount    = 0.5,
    rate_enable        = false,  rate_amount     = 0.1,
    length_enable      = false,  length_amount   = 0.1,
    fadein_enable      = false,  fadein_amount   = 0.1,
    fadeout_enable     = false,  fadeout_amount  = 0.1,
    fadeshape_enable   = false,
}
