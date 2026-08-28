Config = {}

Config.Command = 'glowtext'

Config.MaxTextLength = 128
Config.MaxGlyphs = 64
Config.StreamDistance = 350.0
Config.ModelLoadTimeout = 5000
Config.EntityDeleteTimeout = 1000
Config.MinScale = 0.10

Config.GlyphAdvance = 0.72
Config.SpaceAdvance = 0.55
Config.VerticalAdvance = 1.15

Config.WorldBounds = {
    minX = -10000.0,
    maxX = 10000.0,
    minY = -10000.0,
    maxY = 10000.0,
    minZ = -500.0,
    maxZ = 3000.0,
}

Config.Defaults = {
    text = 'Glow',
    layout = 'horizontal',
    alignment = 'center',
    spacing = 0.08,
    lineSpacing = 0.20,
    scale = 1.0,
    tint = 0,
    lightEnabled = true,
}

Config.Palette = {
    { name = 'White',      hex = '#ffffff', r = 255, g = 255, b = 255 },
    { name = 'Red',        hex = '#ff2020', r = 255, g = 32,  b = 32  },
    { name = 'Orange',     hex = '#ff7018', r = 255, g = 112, b = 24  },
    { name = 'Yellow',     hex = '#ffe020', r = 255, g = 224, b = 32  },
    { name = 'Lime',       hex = '#80ff20', r = 128, g = 255, b = 32  },
    { name = 'Green',      hex = '#20ff48', r = 32,  g = 255, b = 72  },
    { name = 'Teal',       hex = '#18ffb0', r = 24,  g = 255, b = 176 },
    { name = 'Cyan',       hex = '#18f0ff', r = 24,  g = 240, b = 255 },
    { name = 'Light blue', hex = '#40b0ff', r = 64,  g = 176, b = 255 },
    { name = 'Blue',       hex = '#3048ff', r = 48,  g = 72,  b = 255 },
    { name = 'Purple',     hex = '#9030ff', r = 144, g = 48,  b = 255 },
    { name = 'Magenta',    hex = '#f020ff', r = 240, g = 32,  b = 255 },
    { name = 'Pink',       hex = '#ff3090', r = 255, g = 48,  b = 144 },
    { name = 'Warm white', hex = '#ffd6aa', r = 255, g = 214, b = 170 },
    { name = 'Cool white', hex = '#bedcff', r = 190, g = 220, b = 255 },
    { name = 'Dim / off',  hex = '#08080c', r = 8,   g = 8,   b = 12  },
}
