-- TODO: add one resource-level OpenTelemetry bootstrap only if this standalone
-- FiveM runtime gains a supported OTel SDK; do not instrument individual events ad hoc.

local RESOURCE_NAME = GetCurrentResourceName()
local placements = {}
local lastMutation = {}
local adminIdentifiers = {}
local databaseReady = false
local supportedPunctuation = {
    ['.'] = true, [','] = true, ['!'] = true, ['?'] = true,
    ["'"] = true, ['"'] = true, [':'] = true, [';'] = true,
    ['-'] = true, ['_'] = true, ['/'] = true, ['\\'] = true,
    ['('] = true, [')'] = true, ['&'] = true, ['+'] = true,
    ['='] = true, ['@'] = true, ['#'] = true, ['%'] = true,
    ['*'] = true, ['<'] = true, ['>'] = true,
    ['←'] = true, ['→'] = true, ['↑'] = true, ['↓'] = true,
}

local CREATE_TABLE_SQL = [[
    CREATE TABLE IF NOT EXISTS `glowtext_placements` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `text` VARCHAR(128) NOT NULL,
        `layout` VARCHAR(16) NOT NULL DEFAULT 'horizontal',
        `alignment` VARCHAR(16) NOT NULL DEFAULT 'center',
        `spacing` DOUBLE NOT NULL DEFAULT 0.08,
        `line_spacing` DOUBLE NOT NULL DEFAULT 0.20,
        `tint` TINYINT UNSIGNED NOT NULL DEFAULT 0,
        `glyph_tints_json` LONGTEXT NULL,
        `light_enabled` TINYINT(1) NOT NULL DEFAULT 1,
        `matrix_json` LONGTEXT NOT NULL,
        `created_by` VARCHAR(80) NOT NULL,
        `updated_by` VARCHAR(80) NOT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]]

for i = 1, #Config.AdminLicenses do
    adminIdentifiers[string.lower(Config.AdminLicenses[i])] = true
end

local function notify(sourceId, message, kind)
    TriggerClientEvent('glowtext:client:notify', sourceId, message, kind or 'info')
end

local function playerIdentifier(sourceId)
    local identifiers = GetPlayerIdentifiers(sourceId)
    for i = 1, #identifiers do
        local identifier = string.lower(identifiers[i])
        if identifier:sub(1, 8) == 'license:' then return identifier end
    end
    return identifiers[1] and string.lower(identifiers[1]) or 'unknown'
end

local function isAdmin(sourceId)
    if sourceId == 0 then return true end
    if Config.AllowAce and IsPlayerAceAllowed(sourceId, Config.AcePermission) then return true end
    local identifiers = GetPlayerIdentifiers(sourceId)
    for i = 1, #identifiers do
        if adminIdentifiers[string.lower(identifiers[i])] then return true end
    end
    return false
end

local function finiteNumber(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

local function clampInteger(value, minimum, maximum)
    value = math.floor(tonumber(value) or minimum)
    if value < minimum then value = minimum end
    if value > maximum then value = maximum end
    return value
end

local function clampNumber(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not finiteNumber(value) then value = fallback end
    if value < minimum then value = minimum end
    if value > maximum then value = maximum end
    return value + 0.0
end

local function utf8Characters(value)
    local result = {}
    local ok = pcall(function()
        for _, codepoint in utf8.codes(value) do
            result[#result + 1] = utf8.char(codepoint)
        end
    end)
    return ok and result or nil
end

local function visibleGlyphCount(value)
    local characters = utf8Characters(value)
    if not characters then return nil end
    local count = 0
    for i = 1, #characters do
        if characters[i] ~= ' ' and characters[i] ~= '\n' then count = count + 1 end
    end
    return count
end

local function normalizeGlyphTints(raw, glyphCount, fallbackTint)
    fallbackTint = clampInteger(fallbackTint, 0, #Config.Palette - 1)
    local result = {}
    if type(raw) == 'table' and #raw == glyphCount then
        for i = 1, glyphCount do
            result[i] = clampInteger(raw[i], 0, #Config.Palette - 1)
        end
        return result
    end

    for i = 1, glyphCount do result[i] = fallbackTint end
    return result
end

local function normalizeGlyphSpinAxes(rawAxes, rawFlags, glyphCount)
    local result = {}
    local validAxes = type(rawAxes) == 'table' and #rawAxes == glyphCount
    local validFlags = type(rawFlags) == 'table' and #rawFlags == glyphCount
    for i = 1, glyphCount do
        local axis = validAxes and tostring(rawAxes[i] or 'none'):lower() or 'none'
        if axis ~= 'x' and axis ~= 'y' and axis ~= 'z' then
            axis = validFlags and rawFlags[i] == true and 'x' or 'none'
        end
        result[i] = axis
    end
    return result
end

local function vectorLength(x, y, z)
    return math.sqrt(x * x + y * y + z * z)
end

local function validateMatrix(raw)
    if type(raw) ~= 'table' or #raw ~= 12 then return nil, 'The placement transform is invalid.' end
    local matrix = {}
    for i = 1, 12 do
        local value = tonumber(raw[i])
        if not finiteNumber(value) then
            return nil, 'The placement transform contains an invalid number.'
        end
        matrix[i] = value + 0.0
    end

    local rightLength = vectorLength(matrix[1], matrix[2], matrix[3])
    local forwardLength = vectorLength(matrix[4], matrix[5], matrix[6])
    local upLength = vectorLength(matrix[7], matrix[8], matrix[9])
    if rightLength < Config.MinScale
        or forwardLength < Config.MinScale
        or upLength < Config.MinScale then
        return nil, ('Scale must remain at or above %.2f.'):format(Config.MinScale)
    end

    local crossX = matrix[2] * matrix[6] - matrix[3] * matrix[5]
    local crossY = matrix[3] * matrix[4] - matrix[1] * matrix[6]
    local crossZ = matrix[1] * matrix[5] - matrix[2] * matrix[4]
    local determinant = crossX * matrix[7] + crossY * matrix[8] + crossZ * matrix[9]
    if math.abs(determinant) < 0.0001 then return nil, 'The placement transform is degenerate.' end

    local bounds = Config.WorldBounds
    if matrix[10] < bounds.minX or matrix[10] > bounds.maxX
        or matrix[11] < bounds.minY or matrix[11] > bounds.maxY
        or matrix[12] < bounds.minZ or matrix[12] > bounds.maxZ then
        return nil, 'The placement is outside the configured world bounds.'
    end
    return matrix
end

local function validatePayload(payload)
    if type(payload) ~= 'table' then return nil, 'Invalid placement payload.' end
    local text = tostring(payload.text or ''):gsub('\r', '')
    local characters = utf8Characters(text)
    if not characters then return nil, 'The text contains invalid UTF-8.' end
    if #characters == 0 then return nil, 'Enter at least one character.' end
    if #characters > Config.MaxTextLength then return nil, ('Text is limited to %d characters.'):format(Config.MaxTextLength) end
    for index = 1, #characters do
        local character = characters[index]
        if not character:match('[A-Za-z0-9 \n]') and not supportedPunctuation[character] then
            return nil, 'The text contains an unsupported character.'
        end
    end

    local glyphCount = visibleGlyphCount(text)
    if not glyphCount or glyphCount == 0 then return nil, 'Text must contain at least one supported glyph.' end
    if glyphCount > Config.MaxGlyphs then return nil, ('A placement is limited to %d visible glyphs.'):format(Config.MaxGlyphs) end

    local layout = payload.layout == 'vertical' and 'vertical' or 'horizontal'
    local alignment = payload.alignment
    if alignment ~= 'left' and alignment ~= 'center' and alignment ~= 'right' then alignment = 'center' end
    local spacing = tonumber(payload.spacing) or Config.Defaults.spacing
    local lineSpacing = tonumber(payload.lineSpacing) or Config.Defaults.lineSpacing
    if not finiteNumber(spacing) or spacing < -0.40 or spacing > 2.0 then return nil, 'Character spacing must be between -0.40 and 2.00.' end
    if not finiteNumber(lineSpacing) or lineSpacing < 0.0 or lineSpacing > 3.0 then return nil, 'Line spacing must be between 0.00 and 3.00.' end

    local tint = clampInteger(payload.tint, 0, #Config.Palette - 1)
    local glyphTints = normalizeGlyphTints(payload.glyphTints, glyphCount, tint)
    local rgbFrequency = tonumber(payload.rgbFrequency) or Config.Defaults.rgbFrequency
    local rgbSpread = tonumber(payload.rgbSpread) or Config.Defaults.rgbSpread
    local glyphSpinAxes = normalizeGlyphSpinAxes(payload.glyphSpinAxes, payload.glyphSpins, glyphCount)
    local spinFrequency = tonumber(payload.spinFrequency) or Config.Defaults.spinFrequency
    if not finiteNumber(rgbFrequency)
        or rgbFrequency < Config.RgbEffect.minFrequency
        or rgbFrequency > Config.RgbEffect.maxFrequency then
        return nil, ('RGB frequency must be between %.2f and %.2f Hz.'):format(
            Config.RgbEffect.minFrequency,
            Config.RgbEffect.maxFrequency
        )
    end
    if not finiteNumber(rgbSpread)
        or rgbSpread < Config.RgbEffect.minSpread
        or rgbSpread > Config.RgbEffect.maxSpread then
        return nil, ('RGB character spread must be between %d and %d degrees.'):format(
            Config.RgbEffect.minSpread,
            Config.RgbEffect.maxSpread
        )
    end
    if not finiteNumber(spinFrequency)
        or spinFrequency < Config.SpinEffect.minFrequency
        or spinFrequency > Config.SpinEffect.maxFrequency then
        return nil, ('Spin frequency must be between %.2f and %.2f Hz.'):format(
            Config.SpinEffect.minFrequency,
            Config.SpinEffect.maxFrequency
        )
    end
    local matrix, matrixError = validateMatrix(payload.matrix)
    if not matrix then return nil, matrixError end

    return {
        text = text,
        layout = layout,
        alignment = alignment,
        spacing = spacing + 0.0,
        lineSpacing = lineSpacing + 0.0,
        tint = tint,
        glyphTints = glyphTints,
        lightEnabled = payload.lightEnabled == true,
        rgbEnabled = payload.rgbEnabled == true,
        rgbFrequency = rgbFrequency + 0.0,
        rgbSpread = rgbSpread + 0.0,
        glyphSpinAxes = glyphSpinAxes,
        spinFrequency = spinFrequency + 0.0,
        matrix = matrix,
    }
end

local function rowToRecord(row)
    local ok, matrix = pcall(json.decode, row.matrix_json or '')
    if not ok or type(matrix) ~= 'table' or #matrix ~= 12 then
        print(('[%s] Skipping placement #%s because matrix_json is invalid.'):format(RESOURCE_NAME, tostring(row.id)))
        return nil
    end
    local tint = clampInteger(row.tint, 0, #Config.Palette - 1)
    local glyphTintData
    local rgbData
    local spinData
    if type(row.glyph_tints_json) == 'string' and row.glyph_tints_json ~= '' then
        local tintOk, decoded = pcall(json.decode, row.glyph_tints_json)
        if tintOk and type(decoded) == 'table' then
            if type(decoded.tints) == 'table' then
                glyphTintData = decoded.tints
                rgbData = decoded.rgb
                spinData = decoded.spin
            else
                -- Backwards compatibility for rows saved as a plain tint array.
                glyphTintData = decoded
            end
        end
    end
    local glyphCount = visibleGlyphCount(tostring(row.text or '')) or 0
    return {
        id = tostring(row.id),
        text = row.text,
        layout = row.layout,
        alignment = row.alignment,
        spacing = tonumber(row.spacing),
        lineSpacing = tonumber(row.line_spacing),
        tint = tint,
        glyphTints = normalizeGlyphTints(glyphTintData, glyphCount, tint),
        lightEnabled = row.light_enabled == true or tonumber(row.light_enabled) == 1,
        rgbEnabled = type(rgbData) == 'table' and rgbData.enabled == true or false,
        rgbFrequency = clampNumber(
            type(rgbData) == 'table' and rgbData.frequency or nil,
            Config.RgbEffect.minFrequency,
            Config.RgbEffect.maxFrequency,
            Config.Defaults.rgbFrequency
        ),
        rgbSpread = clampNumber(
            type(rgbData) == 'table' and rgbData.spread or nil,
            Config.RgbEffect.minSpread,
            Config.RgbEffect.maxSpread,
            Config.Defaults.rgbSpread
        ),
        glyphSpinAxes = normalizeGlyphSpinAxes(
            type(spinData) == 'table' and spinData.axes or nil,
            type(spinData) == 'table' and spinData.glyphs or nil,
            glyphCount
        ),
        spinFrequency = clampNumber(
            type(spinData) == 'table' and spinData.frequency or nil,
            Config.SpinEffect.minFrequency,
            Config.SpinEffect.maxFrequency,
            Config.Defaults.spinFrequency
        ),
        matrix = matrix,
        createdBy = row.created_by,
        updatedBy = row.updated_by,
        createdAt = tonumber(row.created_at),
        updatedAt = tonumber(row.updated_at),
    }
end

local function loadDatabase()
    placements = {}
    local rows = MySQL.query.await([[
        SELECT `id`, `text`, `layout`, `alignment`, `spacing`, `line_spacing`, `tint`, `glyph_tints_json`,
               `light_enabled`, `matrix_json`,
               `created_by`, `updated_by`, UNIX_TIMESTAMP(`created_at`) AS `created_at`,
               UNIX_TIMESTAMP(`updated_at`) AS `updated_at`
        FROM `glowtext_placements`
    ]]) or {}
    for i = 1, #rows do
        local record = rowToRecord(rows[i])
        if record then placements[record.id] = record end
    end
    print(('[%s] Loaded %d persistent SQL placement(s).'):format(RESOURCE_NAME, #rows))
end

local function publicRecord(record)
    return {
        id = record.id,
        text = record.text,
        layout = record.layout,
        alignment = record.alignment,
        spacing = record.spacing,
        lineSpacing = record.lineSpacing,
        tint = record.tint,
        glyphTints = record.glyphTints,
        lightEnabled = record.lightEnabled,
        rgbEnabled = record.rgbEnabled,
        rgbFrequency = record.rgbFrequency,
        rgbSpread = record.rgbSpread,
        glyphSpinAxes = record.glyphSpinAxes,
        spinFrequency = record.spinFrequency,
        matrix = record.matrix,
        createdAt = record.createdAt,
        updatedAt = record.updatedAt,
    }
end

local function publicPlacements()
    local result = {}
    for id, record in pairs(placements) do result[id] = publicRecord(record) end
    return result
end

local function databaseValues(record, identifier)
    local appearance = {
        tints = record.glyphTints,
        rgb = {
            enabled = record.rgbEnabled,
            frequency = record.rgbFrequency,
            spread = record.rgbSpread,
        },
        spin = {
            axes = record.glyphSpinAxes,
            frequency = record.spinFrequency,
        },
    }
    return {
        record.text, record.layout, record.alignment, record.spacing, record.lineSpacing,
        record.tint, json.encode(appearance), record.lightEnabled and 1 or 0,
        json.encode(record.matrix), identifier,
    }
end

local function mutationAllowed(sourceId)
    local now = GetGameTimer()
    local previous = lastMutation[sourceId] or 0
    if now - previous < 500 then return false end
    lastMutation[sourceId] = now
    return true
end

local function requireDatabase(sourceId)
    if databaseReady then return true end
    notify(sourceId, 'The Glow Text database is still starting. Try again in a moment.', 'error')
    return false
end

RegisterNetEvent('glowtext:server:requestSync', function()
    local sourceId = source
    CreateThread(function()
        local timeout = 100
        while not databaseReady and timeout > 0 do Wait(100); timeout = timeout - 1 end
        TriggerClientEvent('glowtext:client:sync', sourceId, publicPlacements())
    end)
end)

RegisterNetEvent('glowtext:server:requestOpen', function()
    local sourceId = source
    if not isAdmin(sourceId) then notify(sourceId, 'You are not configured as a Glow Text admin.', 'error'); return end
    if not requireDatabase(sourceId) then return end
    TriggerClientEvent('glowtext:client:openAdmin', sourceId, publicPlacements())
end)

RegisterNetEvent('glowtext:server:save', function(payload)
    local sourceId = source
    if not isAdmin(sourceId) or not requireDatabase(sourceId) then return end
    if not mutationAllowed(sourceId) then notify(sourceId, 'Please wait before saving another placement.', 'error'); return end

    local record, validationError = validatePayload(payload)
    if not record then notify(sourceId, validationError, 'error'); return end
    local requestedId = tostring(payload.id or '')
    local existing = requestedId ~= '' and placements[requestedId] or nil
    local identifier = playerIdentifier(sourceId)
    local values = databaseValues(record, identifier)
    local id

    if existing then
        values[#values + 1] = tonumber(requestedId)
        local affected = MySQL.update.await([[
            UPDATE `glowtext_placements`
            SET `text` = ?, `layout` = ?, `alignment` = ?, `spacing` = ?, `line_spacing` = ?,
                `tint` = ?, `glyph_tints_json` = ?, `light_enabled` = ?, `matrix_json` = ?,
                `updated_by` = ? WHERE `id` = ?
        ]], values)
        if affected == nil then notify(sourceId, 'The SQL update failed.', 'error'); return end
        id = requestedId
        record.createdAt = existing.createdAt
        record.createdBy = existing.createdBy
    else
        values[#values + 1] = identifier
        id = MySQL.insert.await([[
            INSERT INTO `glowtext_placements`
                (`text`, `layout`, `alignment`, `spacing`, `line_spacing`, `tint`, `glyph_tints_json`, `light_enabled`,
                 `matrix_json`, `updated_by`, `created_by`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], values)
        if not id then notify(sourceId, 'The SQL insert failed.', 'error'); return end
        id = tostring(id)
        record.createdAt = os.time()
        record.createdBy = identifier
    end

    record.id = id
    record.updatedAt = os.time()
    record.updatedBy = identifier
    placements[id] = record
    TriggerClientEvent('glowtext:client:upsert', -1, publicRecord(record))
    notify(sourceId, existing and ('Placement #%s updated.'):format(id) or ('Placement #%s saved.'):format(id), 'success')
    print(('[%s] %s SQL placement #%s by %s (%d glyphs).'):format(RESOURCE_NAME, existing and 'Updated' or 'Created', id, identifier, visibleGlyphCount(record.text) or 0))
end)

RegisterNetEvent('glowtext:server:delete', function(id)
    local sourceId = source
    if not isAdmin(sourceId) or not requireDatabase(sourceId) or not mutationAllowed(sourceId) then return end
    id = tostring(id or '')
    if id == '' or not placements[id] then notify(sourceId, 'That placement no longer exists.', 'error'); return end
    local affected = MySQL.update.await('DELETE FROM `glowtext_placements` WHERE `id` = ?', { tonumber(id) })
    if not affected or affected < 1 then notify(sourceId, 'The SQL delete failed.', 'error'); return end
    placements[id] = nil
    TriggerClientEvent('glowtext:client:delete', -1, id)
    notify(sourceId, ('Placement #%s deleted.'):format(id), 'success')
    print(('[%s] Deleted SQL placement #%s by %s.'):format(RESOURCE_NAME, id, playerIdentifier(sourceId)))
end)

RegisterCommand(Config.Command, function(sourceId)
    if sourceId == 0 then print(('[%s] /%s is an in-game command.'):format(RESOURCE_NAME, Config.Command)); return end
    TriggerEvent('glowtext:server:requestOpenInternal', sourceId)
end, false)

AddEventHandler('glowtext:server:requestOpenInternal', function(sourceId)
    if not isAdmin(sourceId) then notify(sourceId, 'You are not configured as a Glow Text admin.', 'error'); return end
    if not requireDatabase(sourceId) then return end
    TriggerClientEvent('glowtext:client:openAdmin', sourceId, publicPlacements())
end)

AddEventHandler('playerDropped', function() lastMutation[source] = nil end)

MySQL.ready(function()
    CreateThread(function()
        local ok, err = pcall(function()
            MySQL.query.await(CREATE_TABLE_SQL)
            loadDatabase()
        end)
        if not ok then print(('[%s] SQL startup failed: %s'):format(RESOURCE_NAME, tostring(err))); return end
        databaseReady = true
    end)
end)
