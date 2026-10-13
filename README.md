# Panchu Scripts

Free REAPER scripts by Daniel "Panchuel" Montoya. Install them through
ReaPack.

For **RenderSmith**, the region naming and batch asset delivery tool, see
[its own repository](https://github.com/panchuel/RenderSmith).

## Install

1. In REAPER, open **Extensions > ReaPack > Import repositories...**
2. Paste this URL and click **OK**:
   ```
   https://raw.githubusercontent.com/panchuel/Panchu_Scripts/master/index.xml
   ```
3. Open **Extensions > ReaPack > Browse packages** and install what you want.

## What is in here

### Create regions from parent track name

One region per selected item, named after the folder track the item lives in.
A folder called `Weapons` gives you regions called `Weapons`, which is what
you want when a folder holds many takes of the same sound.

An item that is not inside a folder falls back to its own take name, with the
file extension trimmed, so loose items still get something sensible. Each
region gets a random colour so neighbours stay easy to tell apart in the
ruler.

No dependencies.

### Separate and join items

Lays the selected items end to end, either with an even gap between them or
butted together with none. Useful for spacing out a batch of takes before
rendering, or closing the gaps again afterwards.

The first item never moves: everything else lines up after it, so the result
stays anchored where you put it. Items are laid out in timeline order rather
than selection order, so a selection spanning several tracks does not come out
shuffled.

Requires [ReaImGui](https://github.com/cfillion/reaimgui), installable from
ReaPack.

## Releasing

The index is generated from the scripts' own ReaPack headers, so it cannot
drift from what is in the files:

```
python tools/gen_index.py          # or: python tools/gen_index.py main
```

Bump `--@version` in a script, re-run that, commit. Adding a script to a
folder listed in `CATEGORIES` is enough for it to be picked up.

## License

MIT. Use them, change them, ship them inside whatever you like. The only
condition is that the copyright notice travels with the code.

See [LICENSE](LICENSE).
