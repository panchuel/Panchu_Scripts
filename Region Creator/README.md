# RegionForge v1.1 - Hierarchical Region Generation for REAPER

**Automated region creation from track folder structure with per-type wildcard naming and batch render**

![REAPER Compatibility](https://img.shields.io/badge/REAPER-6.0%2B-orange)
![Version](https://img.shields.io/badge/Version-1.1-blue)
![Lua](https://img.shields.io/badge/Lua-5.3-blueviolet)

## Installation via ReaPack

1. In REAPER open **Extensions > ReaPack > Import repositories...**
2. Paste the following URL and click **OK**:
   ```
   https://raw.githubusercontent.com/panchuel/Panchu_Scripts/master/index.xml
   ```
3. Go to **Extensions > ReaPack > Browse packages**, find **RegionForge** and install it.
4. Make sure [Lokasenna_GUI v2](https://github.com/jalovatt/Lokasenna_GUI) is installed — run its library path setter once:
   `Scripts > ReaTeam Scripts > Development > Lokasenna_GUI v2 > Library > Set Lokasenna_GUI v2 library path.lua`

### Manual installation
Copy the `RegionForge/` folder to your REAPER Scripts directory, then load `RegionForge.lua` via **Actions > Load ReaScript**.

---

## Key Features
- **Wildcard naming** — flexible token-based region naming per audio type
- **Four built-in audio types** — SFX, Music, Dialogue, Environment with independent configs
- **Hierarchy tree view** — live preview of the selected track structure before creating regions
- **Batch render** — checklist with Select All / None / Filter by Type, renders straight to organized folders
- **Configurable base folder** — set a custom root output path or leave blank to use the project folder
- **Persistent settings** — all configuration survives project close and REAPER restart

---

## Quick Start

```
1. Select one or more parent folder tracks in REAPER
2. Pick the Audio Type (SFX / Music / Dialogue / Environment)
3. Fill in any type-specific fields (BPM, character name, etc.)
4. Click Create Regions
5. Switch to the Render tab, select regions and click Render Selected
```

---

## GUI Tabs

| Tab | Purpose |
|-----|---------|
| **Main** | Select audio type, preview track hierarchy, create regions |
| **Audio Config** | Edit wildcard patterns and prefixes for all four types |
| **Render** | Set output paths, pick regions, render |

---

## Wildcard Tokens

| Token | Expands To | Type |
|-------|-----------|------|
| `$prefix` | Type prefix (`sx`, `mx`, `dx`, `env`) | All |
| `$root` | Root folder name or project filename | All |
| `$parent` | Selected parent folder name | All |
| `$bpm` | BPM value | Music |
| `$meter` | Meter string e.g. `4-4` | Music |
| `$character` | Character name | Dialogue |
| `$questtype` | Quest type e.g. `SQ`, `MQ` | Dialogue |
| `$questname` | Quest name — falls back to `$parent` if empty | Dialogue |
| `$line` | Zero-padded line number `01`, `02 ...` | Dialogue |

### Example outputs
```
SFX:          sx_Weapons_Pistol_
Music:        mx_OST_MainTheme_120_4-4_
Dialogue:     dx_merchant_SQ_tutorial_welcome_01_
Environment:  env_Ambient_Jungle_
```

---

## Output Path Templates

Each audio type has its own path template. The `{base}` token resolves to the base folder set in the Render tab (or the project folder if left blank).

Default: `{base}/$prefix/$root/$parent/`

---

## File Structure

```
RegionForge/
├── RegionForge.lua       # Entry point (REAPER action)
└── src/
    ├── config.lua          # Defaults and constants
    ├── audio_types.lua     # Audio type CRUD + sync
    ├── settings.lua        # ExtState load/save
    ├── track_utils.lua     # Track traversal
    ├── wildcards.lua       # Token expansion
    ├── regions.lua         # Region creation
    ├── render.lua          # Render engine
    └── gui.lua             # Lokasenna UI
```

---

## Troubleshooting

| Symptom | Solution |
|---------|----------|
| Script fails to open | Run the Lokasenna_GUI v2 library path setter |
| No regions created | Selected tracks must be parent folders with child tracks containing media items |
| Region name looks wrong | Check the wildcard pattern in Audio Config for the active type |
| Browse button slow to open | PowerShell loads in background — REAPER stays responsive, dialog appears after ~2s |

---

**Version**: 1.1 — **Author**: Daniel "Panchuel" Montoya — **Compatibility**: REAPER 6.0+ · Lokasenna_GUI v2
