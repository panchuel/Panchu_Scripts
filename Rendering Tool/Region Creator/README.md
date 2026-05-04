# Region Creator v1.0

A REAPER Lua script that automatically creates named regions from a track folder structure, using configurable wildcards and per-audio-type naming conventions.

---

## Overview

Region Creator reads selected parent folder tracks in your REAPER project, scans their child tracks for media items, calculates the time range that covers all items, and creates a region for that span. The region name is generated from a wildcard pattern that can embed track names, prefixes, BPM, meter, and dialogue metadata.

All settings persist between sessions via REAPER's `GetExtState` / `SetExtState`.

---

## Requirements

- REAPER 6+
- [Lokasenna_GUI v2](https://github.com/jalovatt/Lokasenna_GUI) — must be installed and its library path set via:
  `Scripts > ReaTeam Scripts > Development > Lokasenna_GUI v2 > Library > Set Lokasenna_GUI v2 library path.lua`

---

## Installation

1. Copy the `Region Creator/` folder to your REAPER Scripts directory (e.g. `AppData/Roaming/REAPER/Scripts/`).
2. In REAPER: `Actions > Load ReaScript` → select `Region Creator/RegionCreator.lua`.
3. Optionally assign a keyboard shortcut or toolbar button.

> `AssetRendererTest.lua` is a legacy entry point that redirects to `RegionCreator.lua` for backwards compatibility.

---

## File Structure

```
Region Creator/
├── RegionCreator.lua       # Controller — REAPER action entry point
└── src/
    ├── config.lua          # Defaults: audio types, settings constants
    ├── audio_types.lua     # Audio type CRUD + sync helpers
    ├── settings.lua        # State initialization from ExtState
    ├── track_utils.lua     # Track traversal utilities
    ├── wildcards.lua       # Wildcard expansion
    ├── regions.lua         # Region creation + hierarchy
    └── gui.lua             # Lokasenna UI + gui_start()
```

All modules share a single global namespace table `RC`. `RegionCreator.lua` initializes it as `RC = {}`, then loads each module sequentially via `loadfile`. Functions declared without `local` become globals accessible across all modules.

---

## How It Works

### Track Hierarchy Expected

The script expects a two-level folder structure:

```
Root folder (optional — may be the project itself)
└── Parent folder  ← select this track before clicking "Create Regions"
    ├── Child track  [media items]
    ├── Child track  [media items]
    └── ...
```

- A **parent folder** is a track with `I_FOLDERDEPTH == 1` that has at least one child track with media items.
- If the parent has no grandparent, the project filename is used as the root name.

### Region Creation Flow

1. Count selected tracks (`CountSelectedTracks`).
2. For each selected track: validate it is a parent folder.
3. Mark original items on the track (`mark_original_items`).
4. Resolve `root_name` (grandparent track name or project filename).
5. Collect all descendant tracks (`get_child_tracks`) and calculate the bounding time range across all media items.
6. Expand the wildcard pattern with `expand_wildcards(pattern, prefix, root_name, folder_name)`.
7. Call `AddProjectMarker2` to create the region.
8. Store hierarchy metadata in `RC.region_hierarchy_data` keyed by `"start_end"` position string.

---

## Audio Types

Four types are built in and fully configurable:

| Type        | Prefix | Default Pattern                                  |
|-------------|--------|--------------------------------------------------|
| SFX         | `sx`   | `$prefix_$root_$parent_`                         |
| Music       | `mx`   | `$prefix_$root_$parent_$bpm_$meter_`             |
| Dialogue    | `dx`   | `$prefix_$character_$questtype_$questname_$line_`|
| Environment | `env`  | `$prefix_$root_$parent_`                         |

Each type stores its own `prefix`, `wildcard` pattern, and type-specific config (`bpm`, `meter`, `character`, `quest_type`, `quest_name`, `line_number`).

Types are persisted in ExtState under the key `SFX_Renderer` as pipe-separated strings.

---

## Wildcard Tokens

Use these tokens in the Pattern field (Settings tab):

| Token         | Expands to                                    |
|---------------|-----------------------------------------------|
| `$prefix`     | Type prefix (`sx`, `mx`, `dx`, `env`)         |
| `$root`       | Root folder name (or project name)            |
| `$parent`     | Selected parent folder name                   |
| `$bpm`        | BPM value (Music type)                        |
| `$meter`      | Meter string e.g. `4-4` (Music type)          |
| `$character`  | Character name (Dialogue type)                |
| `$questtype`  | Quest type e.g. `SQ`, `MQ` (Dialogue type)   |
| `$questname`  | Quest name — falls back to `$parent` if empty |
| `$line`       | Zero-padded line number `01`, `02` ...        |
| `$region`     | Alias for `$parent` (legacy)                  |

---

## UI — Tabs

The window is 460 × 420 px with three tabs, built with Lokasenna_GUI v2.

### Main Tab

- **Audio Type** selector — choose which type to use for region creation.
- **Hierarchy view** — live tree showing the selected track's context:
  ```
  Root   ProjectName
    └── SelectedFolder
        ├── ChildTrack   [3 items]
        └── ChildTrack   [1 item]
  ```
  Updates automatically on track selection change.
- **Create Regions** — runs the region creation for all selected parent folders.
- **Update Hierarchy** — places cursor inside a region and manually override its `root` / `parent` metadata.

### Settings Tab

- **Audio Type** selector (mirrors Main tab — switching here also changes the active type).
- **Pattern** text field — edit the wildcard pattern for the active type.
- **Wildcard reference** — read-only list of all available tokens.
- **Type-specific settings** (shown only when relevant):
  - *Music*: BPM, Meter
  - *Dialogue*: Character, Quest Type, Quest Name, Line number

### Audio Types Tab

- Edit **Prefix** and **Pattern** for all four types simultaneously.
- **Save Audio Types** — persists current values to ExtState.
- **Reset to Defaults** — restores factory defaults after confirmation.

---

## Persistence

Settings are stored in REAPER ExtState under the key `SFX_Renderer`. They survive project close and REAPER restart.

| ExtState key          | Description                          |
|-----------------------|--------------------------------------|
| `audio_type_count`    | Number of audio types                |
| `audio_type_N`        | Serialized audio type N              |
| `wildcard_template`   | Last active wildcard pattern         |
| `music_bpm`           | BPM value                            |
| `music_meter`         | Meter string                         |
| `dx_character`        | Dialogue character                   |
| `dx_quest_type`       | Dialogue quest type                  |
| `dx_quest_name`       | Dialogue quest name                  |
| `dx_line_number`      | Dialogue line number                 |

---

## RC State Table

All runtime state lives in the global `RC` table:

```lua
RC.EXT_KEY              -- ExtState key ("SFX_Renderer")
RC.audio_types          -- array of audio type tables
RC.selected_type_idx    -- index into RC.audio_types (1-based)
RC.prefix               -- active prefix
RC.wildcard_template    -- active pattern
RC.music_bpm            -- BPM
RC.music_meter          -- meter string
RC.dx_character         -- dialogue character
RC.dx_quest_type        -- dialogue quest type
RC.dx_quest_name        -- dialogue quest name
RC.dx_line_number       -- dialogue line number
RC.valid_tracks         -- regions created this session
RC.random_params        -- randomization settings (reserved)
RC.slider_ranges        -- slider min/max bounds (reserved)
RC.region_hierarchy_data -- position-keyed hierarchy cache
```

---

## Author

**Panchuel** — Region Creator v1.0
