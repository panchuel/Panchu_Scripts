-- ── Lokasenna library ────────────────────────────────────────────────
local lib_path = reaper.GetExtState("Lokasenna_GUI", "lib_path_v2")
if not lib_path or lib_path == "" then
    reaper.MB(
        "Couldn't load Lokasenna_GUI v2.\n\n" ..
        "Please run:\nScripts > ReaTeam Scripts > Development >\n" ..
        "Lokasenna_GUI v2 > Library > Set Lokasenna_GUI v2 library path.lua",
        "Region Creator", 0)
    error("missing Lokasenna_GUI v2")
end
loadfile(lib_path .. "Core.lua")()
GUI.req(lib_path .. "Classes/Class - Button.lua")()
GUI.req(lib_path .. "Classes/Class - Tabs.lua")()
GUI.req(lib_path .. "Classes/Class - Menubox.lua")()
GUI.req(lib_path .. "Classes/Class - Textbox.lua")()
GUI.req(lib_path .. "Classes/Class - Label.lua")()
GUI.req(lib_path .. "Classes/Class - Frame.lua")()
if missing_lib then error("missing Lokasenna class") end

-- ── Footer override ──────────────────────────────────────────────────
GUI.version = 0
GUI.Draw_Version = function()
    local str = "Region Creator v1.0  \xe2\x80\x94  by Panchuel"
    GUI.font(4)
    GUI.color("txt")
    local sw, sh = gfx.measurestr(str)
    gfx.x = math.floor((gfx.w - sw) / 2)
    gfx.y = gfx.h - sh - 4
    gfx.drawstr(str)
end

-- ── RC_Checklist: custom checkbox list (no external class needed) ────
GUI.RC_Checklist = {}
GUI.RC_Checklist.__index = GUI.RC_Checklist

function GUI.RC_Checklist:new(name, z, x, y, w, h)
    local e = setmetatable({}, self)
    e.name     = name
    e.type     = "RC_Checklist"
    e.z        = z
    e.x, e.y, e.w, e.h = x, y, w, h
    e.optarray = {}
    e.optsel   = {}
    e.numopts  = 0
    e.item_h   = 19
    return e
end

function GUI.RC_Checklist:init()             end
function GUI.RC_Checklist:onupdate()         end
function GUI.RC_Checklist:onresize()         end
function GUI.RC_Checklist:lostfocus()        end
function GUI.RC_Checklist:getfocus()         end
function GUI.RC_Checklist:onmouseover()      end
function GUI.RC_Checklist:onmousedown()      end
function GUI.RC_Checklist:ondrag()           end
function GUI.RC_Checklist:ondoubleclick()    end
function GUI.RC_Checklist:onwheel()          end
function GUI.RC_Checklist:ontype()           end
function GUI.RC_Checklist:onmouser_down()    end
function GUI.RC_Checklist:onr_drag()         end
function GUI.RC_Checklist:onmouser_up()      end
function GUI.RC_Checklist:onr_doubleclick()  end
function GUI.RC_Checklist:onmousem_down()    end
function GUI.RC_Checklist:onm_drag()         end
function GUI.RC_Checklist:onmousem_up()      end
function GUI.RC_Checklist:onm_doubleclick()  end
function GUI.RC_Checklist:redraw()           end

function GUI.RC_Checklist:draw()
    local x, y, w, h = self.x, self.y, self.w, self.h
    GUI.color("elm_bg")
    gfx.rect(x, y, w, h, true)
    GUI.color("elm_frame")
    gfx.rect(x, y, w, h, false)
    if self.numopts == 0 then return end
    GUI.font(4)
    local ih   = self.item_h
    local maxv = math.floor((h - 4) / ih)
    for i = 1, math.min(self.numopts, maxv) do
        local iy = y + (i - 1) * ih + 3
        GUI.color("elm_frame")
        gfx.rect(x + 5, iy + 2, 12, 12, false)
        if self.optsel[i] then
            GUI.color("elm_fill")
            gfx.rect(x + 7, iy + 4, 8, 8, true)
        end
        GUI.color("txt")
        gfx.x, gfx.y = x + 24, iy + 1
        gfx.drawstr(self.optarray[i] or "")
    end
    if self.numopts > maxv then
        GUI.color("elm_frame")
        gfx.x, gfx.y = x + 5, y + h - ih + 2
        gfx.drawstr(string.format("... +%d more (click Refresh)", self.numopts - maxv))
    end
end

function GUI.RC_Checklist:onmousedown()
    local rel_y = GUI.mouse.y - self.y - 3
    local idx   = math.floor(rel_y / self.item_h) + 1
    if idx >= 1 and idx <= self.numopts then
        self.optsel[idx] = not self.optsel[idx]
        if GUI.redraw_z then GUI.redraw_z[self.z] = true end
    end
end

function GUI.RC_Checklist:onmouseup() end

-- ── Window ───────────────────────────────────────────────────────────
GUI.name   = "Region Creator v1.0"
GUI.w, GUI.h = 460, 550
GUI.fonts[5] = {"Calibri", 11}
GUI.anchor, GUI.corner = "screen", "C"

-- ── Layout constants ─────────────────────────────────────────────────
local LM    = 16
local TW    = GUI.w - LM * 2
local TAB_H = 16
local CY    = TAB_H + 6   -- content start Y = 22

-- ── Z-layer map ──────────────────────────────────────────────────────
--  1 = Tabs bar (always visible)
--  2 = Main tab
--  3 = Settings tab
--  4 = Audio Types tab
--  5 = Music-specific  (managed manually)
--  6 = Dialogue-specific (managed manually)

-- ── Tabs ─────────────────────────────────────────────────────────────
GUI.New("tabs", "Tabs", 1, 0, 0, 100, TAB_H, "Main,Settings,Audio Types,Render", 4)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TAB 1 — MAIN  (z=2)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local y = CY

GUI.New("lbl_atype", "Label", 2, LM, y + 5, "Audio Type:", false, 3)

local _type_names = {}
for _, t in ipairs(RC.audio_types) do _type_names[#_type_names + 1] = t.name end
GUI.New("sel_type", "Menubox", 2, LM + 96, y, TW - 96, 24, "",
    table.concat(_type_names, ","))
y = y + 36

-- Track hierarchy tree view
GUI.New("lbl_tree_hdr", "Label", 2, LM, y + 4, "Hierarchy:", false, 3)
for _i = 0, 5 do
    GUI.New("lbl_tr" .. _i, "Label", 2, LM + 6, y + 24 + _i * 16, "", false, 4)
end
y = y + 116

GUI.New("btn_create", "Button", 2, LM, y, TW, 48, "Create Regions",
    function() reaper.defer(create_regions) end)
y = y + 60

GUI.New("btn_hierarchy", "Button", 2, LM, y, TW, 34, "Update Hierarchy",
    function() reaper.defer(update_selected_region_hierarchy) end)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TAB 2 — SETTINGS  (z=3)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
y = CY

GUI.New("lbl_atype_s", "Label",   3, LM,       y + 5, "Audio Type:", false, 3)
GUI.New("sel_type_s",  "Menubox", 3, LM + 96,  y, TW - 96, 24, "",
    table.concat(_type_names, ","))
y = y + 36

GUI.New("lbl_pattern_hdr", "Label", 3, LM, y, "Pattern:", false, 3)
y = y + 22
GUI.New("txt_pattern", "Textbox", 3, LM, y, TW, 24, "", 4)
y = y + 32

local _wildcards = {
    "$prefix    -  Type prefix  (sx, mx, dx, env)",
    "$root      -  Root folder name",
    "$parent    -  Parent / folder name",
    "$bpm       -  BPM  (Music)",
    "$meter     -  Meter  (Music)",
    "$character -  Character  (Dialogue)",
    "$questtype -  Quest type  (Dialogue)",
    "$questname -  Quest name  (Dialogue)",
    "$line      -  Line number  01, 02 ...  (Dialogue)",
}
for i, wc in ipairs(_wildcards) do
    GUI.New("lbl_wc" .. i, "Label", 3, LM + 8, y, wc, false, 4)
    y = y + 14
end

y = y + 6
GUI.New("frm_sep", "Frame", 3, LM, y, TW, 2, false, true, "elm_frame", 0)
y = y + 14

GUI.New("lbl_type_cfg", "Label", 3, LM, y, "Type settings:", false, 3)
y = y + 26

local TS_Y = y

-- Music settings  (z=5)
GUI.New("lbl_bpm",   "Label",   5, LM,       TS_Y + 4,  "BPM:",   false, 3)
GUI.New("txt_bpm",   "Textbox", 5, LM + 52,  TS_Y,       90, 24,  "", 4)
GUI.New("lbl_meter", "Label",   5, LM + 156, TS_Y + 4,  "Meter:", false, 3)
GUI.New("txt_meter", "Textbox", 5, LM + 212, TS_Y,       90, 24,  "", 4)

-- Dialogue settings  (z=6)
GUI.New("lbl_char",  "Label",   6, LM,       TS_Y + 4,  "Character:",  false, 3)
GUI.New("txt_char",  "Textbox", 6, LM + 98,  TS_Y,       TW - 98, 24, "", 4)
GUI.New("lbl_qtype", "Label",   6, LM,       TS_Y + 34, "Quest Type:", false, 3)
GUI.New("txt_qtype", "Textbox", 6, LM + 98,  TS_Y + 30,  TW - 98, 24, "", 4)
GUI.New("lbl_qname", "Label",   6, LM,       TS_Y + 64, "Quest Name:", false, 3)
GUI.New("txt_qname", "Textbox", 6, LM + 98,  TS_Y + 60,  TW - 98, 24, "", 4)
GUI.New("lbl_line",  "Label",   6, LM,       TS_Y + 94, "Line:",       false, 3)
GUI.New("txt_line",  "Textbox", 6, LM + 98,  TS_Y + 90,  60,      24, "", 4)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TAB 3 — AUDIO TYPES  (z=4)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
y = CY
for i, at in ipairs(RC.audio_types) do
    GUI.New("lbl_atname" .. i, "Label",   4, LM,       y,      i .. ".  " .. at.name, false, 3)
    y = y + 22
    GUI.New("lbl_atpfx"  .. i, "Label",   4, LM + 16,  y + 4,  "Prefix:",  false, 4)
    GUI.New("txt_atpfx"  .. i, "Textbox", 4, LM + 68,  y,  80, 24, "", 4)
    GUI.New("lbl_atpat"  .. i, "Label",   4, LM + 162, y + 4,  "Pattern:", false, 4)
    GUI.New("txt_atpat"  .. i, "Textbox", 4, LM + 224, y,
        GUI.w - LM - (LM + 224), 24, "", 4)
    y = y + 32
end

y = y + 8
local BW = math.floor((TW - 8) / 2)

GUI.New("btn_save_types", "Button", 4, LM, y, BW, 30, "Save Audio Types", function()
    for i = 1, #RC.audio_types do
        RC.audio_types[i].prefix   = GUI.Val("txt_atpfx" .. i) or RC.audio_types[i].prefix
        RC.audio_types[i].wildcard = GUI.Val("txt_atpat" .. i) or RC.audio_types[i].wildcard
    end
    sync_config_to_audio_type()
    save_audio_types(RC.audio_types)
    GUI.Val("txt_pattern", RC.wildcard_template)
    reaper.MB("Audio types saved.", "Saved", 0)
end)

GUI.New("btn_reset_types", "Button", 4, LM + BW + 8, y, BW, 30, "Reset to Defaults", function()
    local ok = reaper.ShowMessageBox("Reset all audio types to default settings?", "Confirm Reset", 4)
    if ok == 6 then
        RC.audio_types = {}
        for _, dt in ipairs(RC.default_audio_types) do
            local entry = { name=dt.name, prefix=dt.prefix, wildcard=dt.wildcard, config={} }
            for k, v in pairs(dt.config) do entry.config[k] = v end
            table.insert(RC.audio_types, entry)
        end
        save_audio_types(RC.audio_types)
        RC.selected_type_idx = 1
        sync_config_from_audio_type()
        for i, at in ipairs(RC.audio_types) do
            GUI.Val("txt_atpfx" .. i, at.prefix)
            GUI.Val("txt_atpat" .. i, at.wildcard)
            GUI.Val("txt_rpath" .. i, at.path_pattern or "{base}/$prefix/$root/$parent/")
        end
        GUI.Val("txt_pattern", RC.wildcard_template)
        reaper.MB("Audio types reset to defaults.", "Reset Complete", 0)
    end
end)

-- ── Region list builder ──────────────────────────────────────────────
local function populate_region_checklist()
    RC.region_list = {}
    for i = 0, reaper.CountProjectMarkers(0) - 1 do
        local _, isrgn, pos, rend, name = reaper.EnumProjectMarkers(i)
        if isrgn then
            local id    = string.format("%.10f_%.10f", pos, rend)
            local badge = ""
            for _, t in ipairs(RC.audio_types) do
                if name:sub(1, #t.prefix + 1) == t.prefix .. "_" then
                    badge = "[" .. t.prefix .. "] "
                    break
                end
            end
            RC.region_list[#RC.region_list + 1] = { id = id, raw_name = name, display = badge .. name }
        end
    end
    local chk = GUI.elms.chk_regions
    if not chk then return end
    if #RC.region_list == 0 then
        chk.optarray = { "(no regions in project)" }
        chk.numopts  = 1
        chk.optsel   = { false }
    else
        local opts = {}
        for _, r in ipairs(RC.region_list) do opts[#opts + 1] = r.display end
        chk.optarray = opts
        chk.numopts  = #opts
        chk.optsel   = {}
        for i = 1, #opts do chk.optsel[i] = true end
    end
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TAB 4 — RENDER  (z=7)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
y = CY

GUI.New("lbl_rpath_hdr", "Label", 7, LM, y, "Output paths:", false, 3)
y = y + 18
GUI.New("lbl_base_note", "Label", 7, LM + 8, y, "{base}  =  <ProjectFolder>/Renders", false, 4)
y = y + 18

for _i, _at in ipairs(RC.audio_types) do
    GUI.New("lbl_rpath" .. _i, "Label",   7, LM,      y + 5, _at.name .. ":", false, 3)
    GUI.New("txt_rpath" .. _i, "Textbox", 7, LM + 90, y, TW - 90, 24, "", 4)
    y = y + 32
end

y = y + 2
GUI.New("btn_save_paths", "Button", 7, LM, y, TW, 26, "Save Output Paths", function()
    for i = 1, #RC.audio_types do
        RC.audio_types[i].path_pattern = GUI.Val("txt_rpath" .. i) or RC.audio_types[i].path_pattern
    end
    save_audio_types(RC.audio_types)
    reaper.MB("Output paths saved.", "Saved", 0)
end)
y = y + 34

GUI.New("frm_sep_r", "Frame", 7, LM, y, TW, 2, false, true, "elm_frame", 0)
y = y + 12

local _BH = math.floor((TW - 8) / 3)
GUI.New("lbl_rgn_hdr", "Label",  7, LM,              y + 5, "Regions:", false, 3)
GUI.New("btn_refresh",  "Button", 7, LM + TW - 70,   y,     70, 22, "Refresh", function()
    populate_region_checklist()
end)
y = y + 30

-- z=9: checklist + selection buttons (shown together with z=7 on Render tab)
GUI.New("chk_regions", "RC_Checklist", 9, LM, y, TW, 130)
y = y + 136

GUI.New("btn_sel_all",  "Button", 9, LM,               y, _BH, 22, "Select All", function()
    local chk = GUI.elms.chk_regions
    for i = 1, chk.numopts do chk.optsel[i] = true end
end)
GUI.New("btn_sel_none", "Button", 9, LM + _BH + 4,     y, _BH, 22, "None", function()
    local chk = GUI.elms.chk_regions
    for i = 1, chk.numopts do chk.optsel[i] = false end
end)
GUI.New("btn_filter",   "Button", 9, LM + (_BH + 4)*2, y, TW - (_BH + 4)*2, 22,
    "Filter by Type", function()
        if not RC.region_list then return end
        local pfx = (RC.audio_types[RC.selected_type_idx] or {}).prefix or ""
        local chk = GUI.elms.chk_regions
        for i, r in ipairs(RC.region_list) do
            chk.optsel[i] = r.raw_name:sub(1, #pfx + 1) == pfx .. "_"
        end
    end)
y = y + 30

GUI.New("frm_sep_r2", "Frame", 7, LM, y, TW, 2, false, true, "elm_frame", 0)
y = y + 10

GUI.New("btn_render", "Button", 7, LM, y, TW, 40, "Render Selected", function()
    local ids = {}
    local chk = GUI.elms.chk_regions
    if chk and RC.region_list then
        for i, sel in ipairs(chk.optsel) do
            if sel and RC.region_list[i] then ids[#ids + 1] = RC.region_list[i].id end
        end
    end
    RC.render_status = "Rendering..."
    render_queue(ids)
end)
y = y + 48

GUI.New("btn_open_folder", "Button", 7, LM, y, math.floor(TW / 2) - 4, 22, "Open Folder", function()
    local d = RC.last_render_dir
    if d and d ~= "" then
        os.execute('explorer "' .. d:gsub("/", "\\") .. '"')
    else
        reaper.MB("Render a region first.", "Open Folder", 0)
    end
end)
y = y + 30

GUI.New("lbl_render_status", "Label", 7, LM, y, "Ready", false, 5)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- UPDATE FUNCTION  (runs every frame)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local _prev_type_idx      = 0
local _prev_tab           = 0
local _prev_type_name     = ""
local _prev_state_count   = -1
local _prev_sel_track     = nil
local _prev_render_status = ""

-- Keeps sel_type (Main) and sel_type_s (Settings) in sync with a given index.
-- Call whenever RC.selected_type_idx changes from any tab.
local function sync_type_selectors(idx)
    GUI.Val("sel_type",   idx)
    GUI.Val("sel_type_s", idx)
end

local function refresh_tree_view()
    local L = "\xe2\x94\x94\xe2\x94\x80\xe2\x94\x80 "  -- └──
    local T = "\xe2\x94\x9c\xe2\x94\x80\xe2\x94\x80 "  -- ├──

    local sel = reaper.GetSelectedTrack(0, 0)
    if not sel then
        GUI.Val("lbl_tr0", "  No track selected")
        for i = 1, 5 do GUI.Val("lbl_tr" .. i, "") end
        return
    end

    local parent_name = get_track_name(sel)
    local root_folder = get_parent_track(sel)
    local root_name
    if root_folder then
        root_name = get_track_name(root_folder)
    else
        local _, proj_name = reaper.EnumProjects(-1, "")
        root_name = (proj_name:match("([^\\/]+)$") or "Project"):gsub("%..+$", "")
    end

    local all_desc    = get_child_tracks(sel)
    local item_tracks = {}
    for _, tr in ipairs(all_desc) do
        if reaper.CountTrackMediaItems(tr) > 0 then
            table.insert(item_tracks, tr)
        end
    end

    local total    = #item_tracks
    local max_show = 3

    GUI.Val("lbl_tr0", "Root   " .. root_name)
    GUI.Val("lbl_tr1", "  " .. L .. parent_name)

    if total == 0 then
        GUI.Val("lbl_tr2", "        " .. L .. "(no items)")
        for i = 3, 5 do GUI.Val("lbl_tr" .. i, "") end
        return
    end

    local show = math.min(max_show, total)
    for i = 1, show do
        local cname     = get_track_name(item_tracks[i])
        local n         = reaper.CountTrackMediaItems(item_tracks[i])
        local connector = (i == total and total <= max_show) and L or T
        GUI.Val("lbl_tr" .. (i + 1), "        " .. connector .. cname .. "   [" .. n .. " items]")
    end
    for i = show + 2, 5 do GUI.Val("lbl_tr" .. i, "") end
    if total > max_show then
        GUI.Val("lbl_tr5", "           ... " .. (total - max_show) .. " more")
    end
end

GUI.func = function()
    local cur_tab      = GUI.elms.tabs.retval
    local new_type_idx = GUI.Val("sel_type")

    if cur_tab == 2 and _prev_tab ~= 2 then
        sync_type_selectors(RC.selected_type_idx)
    end

    local effective_idx = (cur_tab == 2) and GUI.Val("sel_type_s") or new_type_idx

    if _prev_tab == 2 and cur_tab ~= 2 then
        RC.wildcard_template = GUI.Val("txt_pattern") or RC.wildcard_template
        if RC.audio_types[RC.selected_type_idx] then
            RC.audio_types[RC.selected_type_idx].wildcard = RC.wildcard_template
        end
        RC.music_bpm      = tonumber(GUI.Val("txt_bpm"))  or RC.music_bpm
        RC.music_meter    = GUI.Val("txt_meter")           or RC.music_meter
        RC.dx_character   = GUI.Val("txt_char")            or RC.dx_character
        RC.dx_quest_type  = GUI.Val("txt_qtype")           or RC.dx_quest_type
        RC.dx_quest_name  = GUI.Val("txt_qname")           or RC.dx_quest_name
        RC.dx_line_number = tonumber(GUI.Val("txt_line"))  or RC.dx_line_number
    end

    if effective_idx ~= _prev_type_idx and _prev_type_idx > 0 then
        sync_config_to_audio_type()
        RC.selected_type_idx = effective_idx
        sync_config_from_audio_type()
        sync_type_selectors(RC.selected_type_idx)
        GUI.Val("txt_pattern", RC.wildcard_template)
        GUI.Val("txt_bpm",     tostring(RC.music_bpm))
        GUI.Val("txt_meter",   RC.music_meter)
        GUI.Val("txt_char",    RC.dx_character)
        GUI.Val("txt_qtype",   RC.dx_quest_type)
        GUI.Val("txt_qname",   RC.dx_quest_name)
        GUI.Val("txt_line",    tostring(RC.dx_line_number))
    end

    local on_settings = (cur_tab == 2)
    local type_name   = RC.audio_types[RC.selected_type_idx]
        and RC.audio_types[RC.selected_type_idx].name or ""

    GUI.elms_hide[5] = not (on_settings and type_name == "Music")
    GUI.elms_hide[6] = not (on_settings and type_name == "Dialogue")

    local on_render = (cur_tab == 4)
    if on_render then
        if _prev_tab ~= 4 then populate_region_checklist() end
        if RC.render_status ~= _prev_render_status then
            GUI.Val("lbl_render_status", RC.render_status)
            _prev_render_status = RC.render_status
        end
    end

    if type_name ~= _prev_type_name then
        if     type_name == "Music"    then GUI.Val("lbl_type_cfg", "Music settings:")
        elseif type_name == "Dialogue" then GUI.Val("lbl_type_cfg", "Dialogue settings:")
        else                                GUI.Val("lbl_type_cfg", "No type-specific settings")
        end
        _prev_type_name = type_name
    end

    local sc      = reaper.GetProjectStateChangeCount(0)
    local cur_sel = reaper.GetSelectedTrack(0, 0)
    if sc ~= _prev_state_count or cur_sel ~= _prev_sel_track then
        refresh_tree_view()
        _prev_state_count = sc
        _prev_sel_track   = cur_sel
    end

    _prev_type_idx = effective_idx
    _prev_tab      = cur_tab
end

GUI.freq = 0

GUI.exit = function()
    RC.wildcard_template  = GUI.Val("txt_pattern")         or RC.wildcard_template
    RC.music_bpm          = tonumber(GUI.Val("txt_bpm"))   or RC.music_bpm
    RC.music_meter        = GUI.Val("txt_meter")            or RC.music_meter
    RC.dx_character       = GUI.Val("txt_char")             or RC.dx_character
    RC.dx_quest_type      = GUI.Val("txt_qtype")            or RC.dx_quest_type
    RC.dx_quest_name      = GUI.Val("txt_qname")            or RC.dx_quest_name
    RC.dx_line_number     = tonumber(GUI.Val("txt_line"))   or RC.dx_line_number

    for i = 1, #RC.audio_types do
        RC.audio_types[i].prefix       = GUI.Val("txt_atpfx" .. i) or RC.audio_types[i].prefix
        RC.audio_types[i].wildcard     = GUI.Val("txt_atpat" .. i) or RC.audio_types[i].wildcard
        RC.audio_types[i].path_pattern = GUI.Val("txt_rpath"  .. i) or RC.audio_types[i].path_pattern
    end
    if RC.audio_types[RC.selected_type_idx] then
        RC.audio_types[RC.selected_type_idx].wildcard = RC.wildcard_template
    end
    sync_config_to_audio_type()

    save_settings({
        wildcard_template = RC.wildcard_template,
        prefix_type       = RC.prefix_type,
        music_bpm         = RC.music_bpm,
        music_meter       = RC.music_meter,
        dx_character      = RC.dx_character,
        dx_quest_type     = RC.dx_quest_type,
        dx_quest_name     = RC.dx_quest_name,
        dx_line_number    = RC.dx_line_number,
    })
    save_audio_types(RC.audio_types)
end

-- ── Entry point called by the controller ────────────────────────────
function gui_start()
    local function script()
        GUI.Init()

        sync_type_selectors(RC.selected_type_idx)
        GUI.Val("txt_pattern", RC.wildcard_template)
        GUI.Val("txt_bpm",     tostring(RC.music_bpm))
        GUI.Val("txt_meter",   RC.music_meter)
        GUI.Val("txt_char",    RC.dx_character)
        GUI.Val("txt_qtype",   RC.dx_quest_type)
        GUI.Val("txt_qname",   RC.dx_quest_name)
        GUI.Val("txt_line",    tostring(RC.dx_line_number))

        for i, at in ipairs(RC.audio_types) do
            GUI.Val("txt_atpfx" .. i, at.prefix)
            GUI.Val("txt_atpat" .. i, at.wildcard)
            GUI.Val("txt_rpath" .. i, at.path_pattern or "{base}/$prefix/$root/$parent/")
        end

        GUI.Val("lbl_render_status", RC.render_status)

        GUI.elms.tabs:update_sets({ {2}, {3}, {4}, {7, 9} })
        GUI.elms_hide[5] = true
        GUI.elms_hide[6] = true

        _prev_type_idx      = RC.selected_type_idx
        _prev_render_status = RC.render_status
        refresh_tree_view()

        reaper.defer(GUI.Main)
    end

    xpcall(script, GUI.crash)
end
