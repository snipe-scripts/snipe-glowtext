# Glow Text

Standalone FiveM admin placement for the `glowglyphs` prop pack.

Supported characters: A-Z, a-z, 0-9, spaces, line breaks, and
`. , ! ? ' " : ; - _ / \ ( ) & + = @ # % * < > ← → ↑ ↓`.

## Resources

- `glowglyphs` streams A-Z, a-z, 0-9 and the supported punctuation props.
- `glowtext` provides the admin NUI, native gizmo, SQL persistence and client streaming.

The script does not use Qbox, QBCore, ESX or ox_lib. It uses the server's existing
`oxmysql` resource solely as its MySQL/MariaDB driver.

## Configuration

Add admin Rockstar license identifiers to `Config.AdminLicenses` in `server/config.lua`.
The server checks permission again for every open, insert, update and delete request.

The in-game command is:

```text
/glowtext
```

The `glowtext_placements` table is created automatically. This resource does not
migrate an older table: drop the old table before starting this version, or apply
the included `glowtext.sql` through your normal schema workflow.

## Editor controls

- `T`: translation gizmo
- `R`: rotation gizmo
- `S`: scale gizmo
- `L`: local/world axes
- Left mouse: drag a gizmo handle
- Left Alt: switch between gizmo cursor and free camera
- `W/A/S/D`, `E/Q`, mouse: move the free camera
- Shift: faster free camera
- Enter: save
- Backspace: cancel

Placed text is reconstructed locally for each client within `Config.StreamDistance`.
Only the compact placement definition, per-glyph tint indexes and 4x3 group matrix are stored in SQL.

Click a character in the preview to select it. Ctrl + left-click toggles multiple
characters, Shift + left-click selects a range, and `Select all` selects the full
word. The colour palette applies to the current selection. The preview follows the
selected layout: newlines become horizontal rows or adjacent vertical columns. Every
row or column remains part of the same saved placement and uses the same gizmo.
Selecting a character also selects its current palette colour; mixed-colour selections
show `Mixed` until a new colour is applied.

`Enable glow` switches between the emissive `_v4` model and its non-emissive `_matte` counterpart; no separate
world light or light-colour setting is used.

`Enable RGB effect` cycles through the configured colour palette. `Frequency`
controls complete colour cycles per second, while `Character spread` offsets the
hue of each following character. A spread of `0°` keeps every character in sync;
higher values create a travelling rainbow. RGB works with both glow and matte props
and is animated in the character preview and placement gizmo.

RGB settings are stored inside the existing `glyph_tints_json` value, so this update
does not add database columns or require a migration. Placements saved by older
versions continue to load with RGB disabled.

When editing an existing placement, `Save changes` updates its content and appearance
while preserving the saved transform. Use `Update with gizmo` only when the placement
also needs to be moved, rotated or scaled.

Scale has a configured minimum of `0.10` and no configured maximum. Extremely large
values are still limited by the game engine's numeric and rendering capabilities.
