# Glow Glyph Props

Collisionless, runtime-scalable GTA V/FiveM props for A-Z, a-z, 0-9 and common punctuation.
Every glyph has a glow variant and a truly non-emissive matte variant (178 props total).

Symbols: `. , ! ? ' " : ; - _ / \ ( ) & + = @ # % * < > ← → ↑ ↓`.

- Resource: `glowglyphs`
- Nominal uppercase cap height: 1 metre
- Visible colour: `SetObjectTextureVariation(object, variation)`
- Tint variations: 0 through 15

Tint palette:

- `0` white
- `1` red
- `2` orange
- `3` yellow
- `4` lime
- `5` green
- `6` teal
- `7` cyan
- `8` light blue
- `9` blue
- `10` purple
- `11` magenta
- `12` pink
- `13` warm white
- `14` cool white
- `15` dim/off surface

Append `_v4` for an emissive surface, or append `_matte`
for a tinted surface without emissive bloom. Neither model contains an embedded
YDR light; glow is an emissive-surface effect only:

```lua
local model = enabled and 'glowglyph_upper_a_v4' or 'glowglyph_upper_a_matte'
SetObjectTextureVariation(object, tintIndex)
```

`_SET_OBJECT_LIGHT_COLOR` is intentionally not used because these assets contain
no embedded lights. Entity-light natives cannot disable emissive material, which
is why the matte models remain separate assets.

Model naming:

- `glowglyph_upper_a_v4` through `glowglyph_upper_z_v4`
- `glowglyph_lower_a_v4` through `glowglyph_lower_z_v4`
- `glowglyph_num_0_v4` through `glowglyph_num_9_v4`
- punctuation uses `glowglyph_punct_<name>_v4`

Replace `_v4` with `_matte` for the matte counterpart.

The complete character-to-model mapping and placement advance are in
`glyph_manifest.json`.
