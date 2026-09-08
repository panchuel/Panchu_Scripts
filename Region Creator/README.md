# RegionForge v1.2 - Hierarchical Region Generation for REAPER

**Automated region creation from track folder structure with per-type wildcard naming, UCS 8.2 support and batch render — with or without REAPER's render window**

![REAPER Compatibility](https://img.shields.io/badge/REAPER-6.0%2B-orange)
![Version](https://img.shields.io/badge/Version-1.2-blue)
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
- **Modular audio types** — create and delete your own types (up to 8) from the tool, each with its own prefix, pattern and output path
- **Custom fields** — add per-type variables (up to 5) that become wildcards: a field `weapontype` is usable as `$weapontype` in names and paths, with its value editable on the Main tab
- **UCS 8.2 naming mode** — optional per-type [Universal Category System](https://universalcategorysystem.com) naming (`CatID_FXName_CreatorID_SourceID_UserData`) with the full 82-category / 753-CatID catalog built in
- **Direct render engine** — renders regions straight to WAV without ever opening REAPER's render window; async with in-GUI progress
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
   — or enable UCS naming in the UCS tab and pick Category/SubCategory
4. Click Create Regions
5. Switch to the Render tab, select regions and click Render Selected
```

---

## GUI Tabs

| Tab | Purpose |
|-----|---------|
| **Main** | Select audio type, preview track hierarchy, create regions, edit custom field values |
| **Audio Config** | Edit the selected type (name, prefix, wildcard pattern); add/remove types and custom fields |
| **UCS** | Enable UCS naming per type, pick Category/SubCategory, set CreatorID/SourceID/UserData, live filename preview |
| **Render** | Set output paths, choose render engine and bit depth, pick regions, render |

---

## Render Engines

| Engine | Formats | REAPER render window |
|--------|---------|----------------------|
| **Direct (default)** | WAV — 16-bit PCM, 24-bit PCM, 32-bit float; sample rate selectable (project / 44.1k / 48k / 88.2k / 96k) | Never opens. Audio is read through per-track AudioAccessors and the file is written from Lua. Progress is shown in the Render tab and the GUI stays responsive. |
| **REAPER render** | Anything REAPER can render (MP3, FLAC, OGG...) | Uses your most recent render settings; shows REAPER's progress window. |

**How the Direct engine builds the mix** — REAPER's script API cannot tap the master output, so the engine sums every audible track that has items inside the region range. Included: media items, take FX, **each track's own FX chain**, track volume/pan, mutes, solos and the parent-folder/master volume chain. **Not included: FX on parent folder tracks or on the master, sends, and envelopes.** If your sound relies on bus processing (e.g. reverb on the parent folder), switch the Engine to *REAPER render (native)* for full fidelity.

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
| `$catid` | UCS CatID e.g. `AMBForst` | UCS |
| `$fxname` | Parent folder name in CamelCase | UCS |
| `$creatorid` | Creator ID from the UCS tab | UCS |
| `$sourceid` | Source ID from the UCS tab | UCS |
| `$userdata` | User data from the UCS tab | UCS |

UCS tokens work in output path templates too (e.g. `{base}/$catid/`).

### Custom field tokens

Every custom field you add in **Audio Config → + Field** becomes a wildcard named after it. Example: on a new "Weapons" type, add a field `weapontype` with value `Pistol`, set the pattern to `$prefix_$root_$weapontype_$parent_` and regions come out as `wp_Weapons_Pistol_Shot_`. Field values are edited on the **Main** tab under *Custom fields*.

### Example outputs
```
SFX:          sx_Weapons_Pistol_
Music:        mx_OST_MainTheme_120_4-4_
Dialogue:     dx_merchant_SQ_tutorial_welcome_01_
Environment:  env_Ambient_Jungle_
UCS mode:     AMBForst_JungleDay_PANCH_ProjectX
```

---

## UCS Naming Mode

Enable **Use UCS naming for this audio type** in the UCS tab and the type creates regions with its UCS pattern (default `$catid_$fxname_$creatorid_$sourceid`) instead of its regular wildcard.

- **Category / SubCategory** pickers cover the full UCS v8.2 list; the resulting CatID is stored per audio type.
- **CreatorID / SourceID / UserData** are shared across types and sanitized to UCS rules (CamelCase, `_` reserved as field separator).
- `$fxname` is derived from the parent folder name automatically.
- The live preview shows the exact filename before you create anything.

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
    ├── ucs_data.lua        # UCS v8.2 catalog          (pure Lua, no REAPER API)
    ├── ucs.lua             # UCS sanitizing & lookups  (pure Lua, no REAPER API)
    ├── wildcards.lua       # Token expansion
    ├── wav_writer.lua      # WAV file writer           (pure Lua, no REAPER API)
    ├── regions.lua         # Region creation
    ├── render_direct.lua   # Direct render engine (AudioAccessor → WAV)
    ├── render.lua          # Render queue + engine dispatch
    └── gui.lua             # Lokasenna UI
```

The modules marked *pure Lua* have no `reaper.*` dependencies by design: they are the portable core for a future standalone/plugin version of the tool.

---

## Troubleshooting

| Symptom | Solution |
|---------|----------|
| Script fails to open | Run the Lokasenna_GUI v2 library path setter |
| No regions created | Selected tracks must be parent folders with child tracks containing media items |
| Region name looks wrong | Check the wildcard pattern in Audio Config (or the UCS pattern in the UCS tab) for the active type |
| Rendered WAV is silent | Direct engine: tracks must be unmuted, routed to master (master send on) and have items inside the region range |
| Rendered WAV missing bus FX | Direct engine doesn't apply parent-folder/master FX — switch Engine to "REAPER render (native)" |
| Need MP3/FLAC output | Switch Engine to "REAPER render (native)" in the Render tab |
| Browse button slow to open | Install js_ReaScriptAPI for an instant native dialog; otherwise PowerShell loads in background (~2s) |

---

**Version**: 1.2 — **Author**: Daniel "Panchuel" Montoya — **Compatibility**: REAPER 6.0+ · Lokasenna_GUI v2
