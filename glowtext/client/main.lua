local DRAW_GIZMO_NATIVE = 0xEB2EDCA2

local placements = {}
local spawned = {}
local uiOpen = false
local editorActive = false
local editingId
local editorEntities = {}
local editorGlyphs = {}
local editorMatrix
local editorSettings
local editorCamera
local cursorMode = false
local glyphModelHashes = {}
local punctuationGlyphs = {
    ['.'] = { name = 'period', advance = 0.35 },
    [','] = { name = 'comma', advance = 0.35 },
    ['!'] = { name = 'exclamation', advance = 0.40 },
    ['?'] = { name = 'question', advance = 0.60 },
    ["'"] = { name = 'apostrophe', advance = 0.35 },
    ['"'] = { name = 'quote', advance = 0.45 },
    [':'] = { name = 'colon', advance = 0.35 },
    [';'] = { name = 'semicolon', advance = 0.35 },
    ['-'] = { name = 'hyphen', advance = 0.55 },
    ['_'] = { name = 'underscore', advance = 0.72 },
    ['/'] = { name = 'slash', advance = 0.60 },
    ['\\'] = { name = 'backslash', advance = 0.60 },
    ['('] = { name = 'left_paren', advance = 0.45 },
    [')'] = { name = 'right_paren', advance = 0.45 },
    ['&'] = { name = 'ampersand', advance = 0.75 },
    ['+'] = { name = 'plus', advance = 0.72 },
    ['='] = { name = 'equals', advance = 0.72 },
    ['@'] = { name = 'at', advance = 0.90 },
    ['#'] = { name = 'hash', advance = 0.72 },
    ['%'] = { name = 'percent', advance = 0.80 },
    ['*'] = { name = 'asterisk', advance = 0.55 },
    ['<'] = { name = 'less_than', advance = 0.72 },
    ['>'] = { name = 'greater_than', advance = 0.72 },
    ['←'] = { name = 'arrow_left', advance = 1.00 },
    ['→'] = { name = 'arrow_right', advance = 1.00 },
    ['↑'] = { name = 'arrow_up', advance = 0.80 },
    ['↓'] = { name = 'arrow_down', advance = 0.80 },
}

for characterCode = string.byte('A'), string.byte('Z') do
    local character = string.char(characterCode):lower()
    local upperModel = 'glowglyph_upper_' .. character
    local lowerModel = 'glowglyph_lower_' .. character
    glyphModelHashes[joaat(upperModel .. '_v4')] = true
    glyphModelHashes[joaat(upperModel .. '_v3')] = true
    glyphModelHashes[joaat(upperModel)] = true
    glyphModelHashes[joaat(upperModel .. '_matte')] = true
    glyphModelHashes[joaat(lowerModel .. '_v4')] = true
    glyphModelHashes[joaat(lowerModel .. '_v3')] = true
    glyphModelHashes[joaat(lowerModel)] = true
    glyphModelHashes[joaat(lowerModel .. '_matte')] = true
end
for number = 0, 9 do
    local numberModel = 'glowglyph_num_' .. number
    glyphModelHashes[joaat(numberModel .. '_v4')] = true
    glyphModelHashes[joaat(numberModel .. '_v3')] = true
    glyphModelHashes[joaat(numberModel)] = true
    glyphModelHashes[joaat(numberModel .. '_matte')] = true
end
for _, glyph in pairs(punctuationGlyphs) do
    local punctuationModel = 'glowglyph_punct_' .. glyph.name
    glyphModelHashes[joaat(punctuationModel .. '_v4')] = true
    glyphModelHashes[joaat(punctuationModel .. '_matte')] = true
end

local function notify(message, kind)
    if uiOpen then
        SendNUIMessage({ action = 'notify', message = message, kind = kind or 'info' })
        return
    end

    TriggerEvent('chat:addMessage', {
        color = kind == 'error' and { 220, 70, 70 } or { 217, 119, 6 },
        args = { 'Glow Text', message }
    })
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
        if characters[i] ~= ' ' and characters[i] ~= '\n' and characters[i] ~= '\r' then
            count = count + 1
        end
    end
    return count
end

local function modelForCharacter(character, glowing)
    local model
    if character:match('%u') then model = 'glowglyph_upper_' .. character:lower() end
    if character:match('%l') then model = 'glowglyph_lower_' .. character end
    if character:match('%d') then model = 'glowglyph_num_' .. character end
    if punctuationGlyphs[character] then model = 'glowglyph_punct_' .. punctuationGlyphs[character].name end
    if not model then return nil end
    return model .. (glowing and '_v4' or '_matte')
end

local function advanceForCharacter(character)
    if character == ' ' then return Config.SpaceAdvance end
    return punctuationGlyphs[character] and punctuationGlyphs[character].advance or Config.GlyphAdvance
end

local function splitLines(text)
    local lines = {}
    local start = 1
    while true do
        local position = text:find('\n', start, true)
        if not position then
            lines[#lines + 1] = text:sub(start)
            break
        end
        lines[#lines + 1] = text:sub(start, position - 1)
        start = position + 1
    end
    return lines
end

local function tintForGlyph(record, glyphIndex)
    local glyphTints = type(record.glyphTints) == 'table' and record.glyphTints or nil
    local value = glyphTints and glyphTints[glyphIndex] or record.tint
    return math.max(0, math.min(15, math.floor(tonumber(value) or tonumber(record.tint) or 0)))
end

local function boundedNumber(value, minimum, maximum, fallback)
    value = tonumber(value) or fallback
    if value ~= value or value == math.huge or value == -math.huge then value = fallback end
    return math.max(minimum, math.min(maximum, value))
end

local function rgbTintForGlyph(record, glyphIndex, timeMs)
    if record.rgbEnabled ~= true then return nil end
    local settings = Config.RgbEffect
    local palette = settings and settings.palette
    if type(palette) ~= 'table' or #palette == 0 then return nil end

    local frequency = boundedNumber(
        record.rgbFrequency,
        settings.minFrequency,
        settings.maxFrequency,
        Config.Defaults.rgbFrequency
    )
    local spread = boundedNumber(
        record.rgbSpread,
        settings.minSpread,
        settings.maxSpread,
        Config.Defaults.rgbSpread
    )
    local cycle = ((timeMs / 1000.0) * frequency) + (((glyphIndex - 1) * spread) / 360.0)
    local paletteIndex = math.floor((cycle % 1.0) * #palette) + 1
    return palette[paletteIndex]
end

local function spinAxisForGlyph(record, glyphIndex)
    local axis = type(record.glyphSpinAxes) == 'table' and record.glyphSpinAxes[glyphIndex] or nil
    if axis == 'x' or axis == 'y' or axis == 'z' then return axis end
    if type(record.glyphSpins) == 'table' and record.glyphSpins[glyphIndex] == true then return 'x' end
    return nil
end

local function spinAxisForGroup(record)
    if record.spinAxis == 'x' or record.spinAxis == 'y' or record.spinAxis == 'z' then
        return record.spinAxis
    end
    local axes = type(record.glyphSpinAxes) == 'table' and record.glyphSpinAxes or record.glyphSpins
    if type(axes) ~= 'table' then return nil end
    for i = 1, #axes do
        local axis = spinAxisForGlyph(record, i)
        if axis then return axis end
    end
    return nil
end

local function buildGlyphLayout(record)
    local result = {}
    local spacing = tonumber(record.spacing) or Config.Defaults.spacing
    local glyphIndex = 0

    if record.layout == 'vertical' then
        local lines = splitLines(record.text)
        local advance = Config.VerticalAdvance + spacing
        local columnAdvance = 1.0 + (tonumber(record.lineSpacing) or Config.Defaults.lineSpacing)
        for lineIndex = 1, #lines do
            local line = lines[lineIndex]
            local characters = utf8Characters(line) or {}
            local top = (#characters - 1) * advance * 0.5
            local x = ((lineIndex - 1) - ((#lines - 1) * 0.5)) * columnAdvance
            for characterIndex = 1, #characters do
                local character = characters[characterIndex]
                local model = modelForCharacter(character, record.lightEnabled == true)
                if model then
                    glyphIndex = glyphIndex + 1
                    result[#result + 1] = {
                        character = character,
                        model = model,
                        tint = tintForGlyph(record, glyphIndex),
                        x = x,
                        y = 0.0,
                        z = top - ((characterIndex - 1) * advance),
                    }
                end
            end
        end
        return result
    end

    local lines = splitLines(record.text)
    local lineAdvance = 1.0 + (tonumber(record.lineSpacing) or Config.Defaults.lineSpacing)
    for lineIndex = 1, #lines do
        local line = lines[lineIndex]
        local characters = utf8Characters(line) or {}
        local cursor = 0.0
        local entries = {}
        for i = 1, #characters do
            local character = characters[i]
            local advance = advanceForCharacter(character)
            entries[#entries + 1] = {
                character = character,
                center = cursor + (advance * 0.5),
                model = modelForCharacter(character, record.lightEnabled == true),
            }
            cursor = cursor + advance + spacing
        end

        local width = math.max(0.0, cursor - (#entries > 0 and spacing or 0.0))
        local alignmentOffset = 0.0
        if record.alignment == 'center' then alignmentOffset = -width * 0.5 end
        if record.alignment == 'right' then alignmentOffset = -width end
        local z = ((#lines - 1) * 0.5 - (lineIndex - 1)) * lineAdvance

        for i = 1, #entries do
            local entry = entries[i]
            if entry.model then
                glyphIndex = glyphIndex + 1
                result[#result + 1] = {
                    character = entry.character,
                    model = entry.model,
                    tint = tintForGlyph(record, glyphIndex),
                    x = entry.center + alignmentOffset,
                    y = 0.0,
                    z = z,
                }
            end
        end
    end
    return result
end

local function matrixFromArray(values)
    local view = DataView.ArrayBuffer(64)
    view:SetFloat32(0, values[1]):SetFloat32(4, values[2]):SetFloat32(8, values[3]):SetFloat32(12, 0)
        :SetFloat32(16, values[4]):SetFloat32(20, values[5]):SetFloat32(24, values[6]):SetFloat32(28, 0)
        :SetFloat32(32, values[7]):SetFloat32(36, values[8]):SetFloat32(40, values[9]):SetFloat32(44, 0)
        :SetFloat32(48, values[10]):SetFloat32(52, values[11]):SetFloat32(56, values[12]):SetFloat32(60, 1)
    return view
end

local function matrixToArray(view)
    return {
        view:GetFloat32(0), view:GetFloat32(4), view:GetFloat32(8),
        view:GetFloat32(16), view:GetFloat32(20), view:GetFloat32(24),
        view:GetFloat32(32), view:GetFloat32(36), view:GetFloat32(40),
        view:GetFloat32(48), view:GetFloat32(52), view:GetFloat32(56),
    }
end

local function initialMatrix(scale)
    local rotation = GetGameplayCamRot(2)
    local yaw = math.rad(rotation.z)
    local pitch = math.rad(rotation.x)
    local cosPitch = math.abs(math.cos(pitch))
    local direction = vector3(-math.sin(yaw) * cosPitch, math.cos(yaw) * cosPitch, math.sin(pitch))
    local cameraPosition = GetGameplayCamCoord()
    local position = cameraPosition + direction * 4.0
    local forward = vector3(-math.sin(yaw), math.cos(yaw), 0.0)
    local right = vector3(forward.y, -forward.x, 0.0)
    scale = tonumber(scale) or Config.Defaults.scale
    return matrixFromArray({
        right.x * scale, right.y * scale, right.z * scale,
        forward.x * scale, forward.y * scale, forward.z * scale,
        0.0, 0.0, scale,
        position.x, position.y, position.z,
    })
end

local function applyGlyphTransform(entity, glyph)
    if not DoesEntityExist(entity) or not glyph.baseOrigin then return end
    local angle = glyph.spinAngle or 0.0
    local cosine = math.cos(angle)
    local sine = math.sin(angle)
    local right = glyph.baseRight
    local forward = glyph.baseForward
    local up = glyph.baseUp

    if glyph.spinAxis == 'x' then
        forward = (glyph.baseForward * cosine) + (glyph.baseUp * sine)
        up = (glyph.baseUp * cosine) - (glyph.baseForward * sine)
    elseif glyph.spinAxis == 'y' then
        right = (glyph.baseRight * cosine) + (glyph.baseForward * sine)
        forward = (glyph.baseForward * cosine) - (glyph.baseRight * sine)
    elseif glyph.spinAxis == 'z' then
        right = (glyph.baseRight * cosine) + (glyph.baseUp * sine)
        up = (glyph.baseUp * cosine) - (glyph.baseRight * sine)
    end

    local position = glyph.baseOrigin
        + (right * glyph.spinX)
        + (forward * glyph.spinY)
        + (up * glyph.spinZ)

    SetEntityMatrix(entity,
        forward.x, forward.y, forward.z,
        right.x, right.y, right.z,
        up.x, up.y, up.z,
        position.x, position.y, position.z
    )
end

local function applyGroupMatrix(entities, glyphs, view)
    local right = vector3(view:GetFloat32(0), view:GetFloat32(4), view:GetFloat32(8))
    local forward = vector3(view:GetFloat32(16), view:GetFloat32(20), view:GetFloat32(24))
    local up = vector3(view:GetFloat32(32), view:GetFloat32(36), view:GetFloat32(40))
    local origin = vector3(view:GetFloat32(48), view:GetFloat32(52), view:GetFloat32(56))
    local minX, maxX, minY, maxY, minZ, maxZ

    for i = 1, #glyphs do
        local glyph = glyphs[i]
        if glyph then
            minX = not minX and glyph.x or math.min(minX, glyph.x)
            maxX = not maxX and glyph.x or math.max(maxX, glyph.x)
            minY = not minY and glyph.y or math.min(minY, glyph.y)
            maxY = not maxY and glyph.y or math.max(maxY, glyph.y)
            minZ = not minZ and glyph.z or math.min(minZ, glyph.z)
            maxZ = not maxZ and glyph.z or math.max(maxZ, glyph.z)
        end
    end

    local pivotX = minX and (minX + maxX) * 0.5 or 0.0
    local pivotY = minY and (minY + maxY) * 0.5 or 0.0
    local pivotZ = minZ and (minZ + maxZ) * 0.5 or 0.0
    local pivot = origin + (right * pivotX) + (forward * pivotY) + (up * pivotZ)

    for i = 1, #entities do
        local entity = entities[i]
        local glyph = glyphs[i]
        if DoesEntityExist(entity) and glyph then
            glyph.baseRight = right
            glyph.baseForward = forward
            glyph.baseUp = up
            glyph.baseOrigin = pivot
            glyph.spinX = glyph.x - pivotX
            glyph.spinY = glyph.y - pivotY
            glyph.spinZ = glyph.z - pivotZ
            applyGlyphTransform(entity, glyph)
        end
    end
end

local function deleteGlyphEntity(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    SetEntityDrawOutline(entity, false)
    SetEntityLights(entity, true)
    SetEntityCollision(entity, false, false)
    SetEntityVisible(entity, false, false)

    local deadline = GetGameTimer() + (Config.EntityDeleteTimeout or 1000)
    repeat
        SetEntityAsMissionEntity(entity, true, true)
        DeleteObject(entity)
        if DoesEntityExist(entity) then DeleteEntity(entity) end
        if DoesEntityExist(entity) then Wait(0) end
    until not DoesEntityExist(entity) or GetGameTimer() >= deadline

    if DoesEntityExist(entity) then
        print(('[glowtext] Could not delete local glyph entity %s before timeout; it was hidden and its lights were disabled.'):format(entity))
    end
end

local function removeEntities(entities)
    if not entities then return end
    for i = 1, #entities do
        deleteGlyphEntity(entities[i])
    end
end

local function cleanupOrphanGlyphs()
    local objects = GetGamePool('CObject')
    for i = 1, #objects do
        local entity = objects[i]
        if DoesEntityExist(entity) and glyphModelHashes[GetEntityModel(entity)] then
            deleteGlyphEntity(entity)
        end
    end
end

local function spawnedGroupExists(group)
    if not group then return false end
    if group.loading then return true end
    local entities = group.entities or {}
    local glyphs = group.glyphs or {}
    if #entities == 0 or #entities ~= #glyphs then return false end
    for i = 1, #entities do
        if not DoesEntityExist(entities[i]) then return false end
    end
    return true
end

local function removeSpawned(id)
    local group = spawned[id]
    if not group then return end
    removeEntities(group.entities)
    spawned[id] = nil
end

local function requestModel(model)
    local hash = joaat(model)
    if HasModelLoaded(hash) then return hash end
    RequestModel(hash)
    local deadline = GetGameTimer() + Config.ModelLoadTimeout
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

local function createGlyphGroup(record, preview)
    local glyphs = buildGlyphLayout(record)
    local entities = {}
    local matrix = matrixFromArray(record.matrix)
    local origin = vector3(record.matrix[10], record.matrix[11], record.matrix[12])
    local initialTime = GetGameTimer()

    for i = 1, #glyphs do
        local glyph = glyphs[i]
        local hash = requestModel(glyph.model)
        if not hash then
            removeEntities(entities)
            return nil, nil, ('Could not load model %s. Is glowglyphs started?'):format(glyph.model)
        end

        local entity = CreateObjectNoOffset(hash, origin.x, origin.y, origin.z, false, false, false)
        if entity == 0 then
            SetModelAsNoLongerNeeded(hash)
            removeEntities(entities)
            return nil, nil, ('Could not create model %s.'):format(glyph.model)
        end

        SetEntityAsMissionEntity(entity, true, true)
        SetEntityCollision(entity, false, false)
        SetEntityCanBeDamaged(entity, false)
        SetEntityLights(entity, true)
        FreezeEntityPosition(entity, true)
        SetEntityLodDist(entity, 500)
        local appliedTint = rgbTintForGlyph(record, i, initialTime) or glyph.tint
        SetObjectTextureVariation(entity, appliedTint)
        glyph.appliedTint = appliedTint
        if preview then
            SetEntityDrawOutlineColor(217, 119, 6, 220)
            SetEntityDrawOutline(entity, true)
        end
        entities[#entities + 1] = entity
        SetModelAsNoLongerNeeded(hash)
    end

    applyGroupMatrix(entities, glyphs, matrix)
    return entities, glyphs
end

local function updateRgbGroup(entities, glyphs, record, timeMs)
    if record.rgbEnabled ~= true then return false end
    for i = 1, #entities do
        local entity = entities[i]
        local glyph = glyphs[i]
        local tint = glyph and rgbTintForGlyph(record, i, timeMs) or nil
        if tint and DoesEntityExist(entity) and glyph.appliedTint ~= tint then
            SetObjectTextureVariation(entity, tint)
            glyph.appliedTint = tint
        end
    end
    return true
end

local function updateSpinGroup(entities, glyphs, record, timeMs)
    if type(record.glyphSpinAxes) ~= 'table' and type(record.glyphSpins) ~= 'table' then return false end
    local axis = spinAxisForGroup(record)
    local frequency = boundedNumber(
        record.spinFrequency,
        Config.SpinEffect.minFrequency,
        Config.SpinEffect.maxFrequency,
        Config.Defaults.spinFrequency
    )
    local angle = (((timeMs / 1000.0) * frequency) % 1.0) * math.pi * 2.0
    local active = false

    for i = 1, #entities do
        local entity = entities[i]
        local glyph = glyphs[i]
        if glyph and axis then
            active = true
            glyph.spinAxis = axis
            glyph.spinAngle = angle
            applyGlyphTransform(entity, glyph)
        elseif glyph and (glyph.spinAxis or (glyph.spinAngle and glyph.spinAngle ~= 0.0)) then
            glyph.spinAxis = nil
            glyph.spinAngle = 0.0
            applyGlyphTransform(entity, glyph)
        end
    end
    return active
end

local function spawnPlacement(id, record)
    if spawned[id] then return end
    local pending = { loading = true, entities = {} }
    spawned[id] = pending
    CreateThread(function()
        local entities, glyphs, errorMessage = createGlyphGroup(record, false)
        if not entities then
            if spawned[id] == pending then spawned[id] = nil end
            print(('[glowtext] Placement #%s failed to stream: %s'):format(id, errorMessage))
            return
        end
        if spawned[id] ~= pending then
            removeEntities(entities)
            return
        end
        spawned[id] = { entities = entities, glyphs = glyphs }
    end)
end

local function placementArray()
    local result = {}
    for _, record in pairs(placements) do result[#result + 1] = record end
    table.sort(result, function(a, b) return (tonumber(a.id) or 0) > (tonumber(b.id) or 0) end)
    return result
end

local function openAdmin(records)
    if editorActive then return end
    if records then placements = records end
    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        records = placementArray(),
        defaults = Config.Defaults,
        palette = Config.Palette,
        rgbEffect = Config.RgbEffect,
        spinEffect = Config.SpinEffect,
        limits = { maxTextLength = Config.MaxTextLength, maxGlyphs = Config.MaxGlyphs }
    })
end

local function closeAdmin()
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function beginCamera()
    local position = GetGameplayCamCoord()
    local rotation = GetGameplayCamRot(2)
    local fov = GetGameplayCamFov()
    editorCamera = CreateCameraWithParams(
        'DEFAULT_SCRIPTED_CAMERA',
        position.x, position.y, position.z,
        rotation.x, rotation.y, rotation.z,
        fov, true, 2
    )
    RenderScriptCams(true, false, 0, true, true)
    SetPlayerControl(PlayerId(), false, 0)
end

local function updateCamera()
    if not editorCamera or cursorMode then return end
    local position = GetCamCoord(editorCamera)
    local rotation = GetCamRot(editorCamera, 2)
    local yaw = math.rad(rotation.z)
    local pitch = math.rad(rotation.x)
    local forward = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    local right = vector3(math.cos(yaw), math.sin(yaw), 0.0)
    local speed = IsDisabledControlPressed(0, 21) and 0.45 or 0.12

    if IsDisabledControlPressed(0, 32) then position = position + forward * speed end
    if IsDisabledControlPressed(0, 33) then position = position - forward * speed end
    if IsDisabledControlPressed(0, 34) then position = position - right * speed end
    if IsDisabledControlPressed(0, 35) then position = position + right * speed end
    if IsDisabledControlPressed(0, 38) then position = position + vector3(0.0, 0.0, speed) end
    if IsDisabledControlPressed(0, 44) then position = position - vector3(0.0, 0.0, speed) end

    local lookX = GetDisabledControlNormal(0, 1)
    local lookY = GetDisabledControlNormal(0, 2)
    rotation = vector3(math.max(-89.0, math.min(89.0, rotation.x - lookY * 6.0)), 0.0, rotation.z - lookX * 6.0)
    SetCamCoord(editorCamera, position.x, position.y, position.z)
    SetCamRot(editorCamera, rotation.x, rotation.y, rotation.z, 2)
end

local function setCursorMode(enabled)
    enabled = enabled == true
    -- These natives are reference-counted. Never enter or leave twice for the
    -- same logical state, or later transitions require matching extra calls.
    if cursorMode == enabled then return false end

    cursorMode = enabled
    if enabled then EnterCursorMode() else LeaveCursorMode() end
    SendNUIMessage({ action = 'cursorMode', enabled = enabled })
    return true
end

local function stopEditor(save)
    if not editorActive then return end
    local finalMatrix = editorMatrix and matrixToArray(editorMatrix) or nil
    local settings = editorSettings
    local id = editingId

    editorActive = false
    setCursorMode(false)
    removeEntities(editorEntities)
    editorEntities = {}
    editorGlyphs = {}
    editorMatrix = nil
    editorSettings = nil
    editingId = nil

    if editorCamera then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(editorCamera, false)
        editorCamera = nil
    end
    SetPlayerControl(PlayerId(), true, 0)
    SendNUIMessage({ action = 'editor', visible = false })

    if save and settings and finalMatrix then
        settings.id = id
        settings.matrix = finalMatrix
        settings.scale = nil
        TriggerServerEvent('glowtext:server:save', settings)
    elseif id and placements[id] then
        local record = placements[id]
        local playerPosition = GetEntityCoords(PlayerPedId())
        local position = vector3(record.matrix[10], record.matrix[11], record.matrix[12])
        if #(playerPosition - position) <= Config.StreamDistance then spawnPlacement(id, record) end
    end
end

local function startEditor(settings)
    if editorActive then return false, 'The placement editor is already active.' end
    local editorText = tostring(settings.text or ''):gsub('\r', '')
    local glyphCount = visibleGlyphCount(editorText)
    if not glyphCount or glyphCount == 0 or glyphCount > Config.MaxGlyphs then
        return false, ('Enter between 1 and %d visible glyphs.'):format(Config.MaxGlyphs)
    end

    editingId = settings.id and tostring(settings.id) or nil
    if editingId and not placements[editingId] then return false, 'That placement no longer exists.' end
    if editingId then removeSpawned(editingId) end

    local fallbackTint = math.max(0, math.min(15, math.floor(tonumber(settings.tint) or 0)))
    local glyphTints = {}
    local glyphSpinAxes = {}
    for i = 1, glyphCount do
        local value = type(settings.glyphTints) == 'table' and settings.glyphTints[i] or fallbackTint
        glyphTints[i] = math.max(0, math.min(15, math.floor(tonumber(value) or fallbackTint)))
        local axis = type(settings.glyphSpinAxes) == 'table' and settings.glyphSpinAxes[i] or nil
        if axis ~= 'x' and axis ~= 'y' and axis ~= 'z' then
            axis = type(settings.glyphSpins) == 'table' and settings.glyphSpins[i] == true and 'x' or 'none'
        end
        glyphSpinAxes[i] = axis
    end

    editorSettings = {
        text = editorText,
        layout = settings.layout == 'vertical' and 'vertical' or 'horizontal',
        alignment = settings.alignment,
        spacing = tonumber(settings.spacing) or Config.Defaults.spacing,
        lineSpacing = tonumber(settings.lineSpacing) or Config.Defaults.lineSpacing,
        tint = fallbackTint,
        glyphTints = glyphTints,
        lightEnabled = settings.lightEnabled == true,
        rgbEnabled = settings.rgbEnabled == true,
        rgbFrequency = boundedNumber(
            settings.rgbFrequency,
            Config.RgbEffect.minFrequency,
            Config.RgbEffect.maxFrequency,
            Config.Defaults.rgbFrequency
        ),
        rgbSpread = boundedNumber(
            settings.rgbSpread,
            Config.RgbEffect.minSpread,
            Config.RgbEffect.maxSpread,
            Config.Defaults.rgbSpread
        ),
        glyphSpinAxes = glyphSpinAxes,
        spinFrequency = boundedNumber(
            settings.spinFrequency,
            Config.SpinEffect.minFrequency,
            Config.SpinEffect.maxFrequency,
            Config.Defaults.spinFrequency
        ),
    }

    if editingId then
        editorMatrix = matrixFromArray(placements[editingId].matrix)
    else
        editorMatrix = initialMatrix(tonumber(settings.scale) or Config.Defaults.scale)
    end
    editorSettings.matrix = matrixToArray(editorMatrix)
    local editorError
    editorEntities, editorGlyphs, editorError = createGlyphGroup(editorSettings, true)
    if not editorEntities then
        editorMatrix = nil
        editingId = nil
        editorSettings = nil
        return false, editorError or 'One or more glyph models could not be created.'
    end

    closeAdmin()
    editorActive = true
    beginCamera()
    setCursorMode(true)
    SendNUIMessage({ action = 'editor', visible = true })

    CreateThread(function()
        while editorActive do
            Wait(0)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 200, true)
            DisablePlayerFiring(PlayerId(), true)

            updateCamera()
            local ok, changed = pcall(function()
                return Citizen.InvokeNative(DRAW_GIZMO_NATIVE, editorMatrix:Buffer(), 'GlowTextEditor', Citizen.ReturnResultAnyway())
            end)
            if not ok then
                notify('The native gizmo failed to run.', 'error')
                stopEditor(false)
                break
            end
            if changed then applyGroupMatrix(editorEntities, editorGlyphs, editorMatrix) end

            if IsDisabledControlJustReleased(0, 19) then setCursorMode(not cursorMode) end
            if IsDisabledControlJustReleased(0, 191) then stopEditor(true); break end
            if IsDisabledControlJustReleased(0, 202) then stopEditor(false); break end
        end
    end)
    return true
end

RegisterNetEvent('glowtext:client:sync', function(records)
    placements = records or {}
end)

RegisterNetEvent('glowtext:client:openAdmin', function(records) openAdmin(records) end)
RegisterNetEvent('glowtext:client:notify', function(message, kind) notify(message, kind) end)

RegisterNetEvent('glowtext:client:upsert', function(record)
    local id = tostring(record.id)
    placements[id] = record
    removeSpawned(id)
    if uiOpen then SendNUIMessage({ action = 'records', records = placementArray() }) end
end)

RegisterNetEvent('glowtext:client:delete', function(id)
    id = tostring(id)
    placements[id] = nil
    removeSpawned(id)
    if editingId == id then stopEditor(false) end
    if uiOpen then SendNUIMessage({ action = 'records', records = placementArray() }) end
end)

RegisterNUICallback('close', function(_, callback)
    closeAdmin()
    callback({ ok = true })
end)

RegisterNUICallback('startPlacement', function(data, callback)
    local ok, errorMessage = startEditor(data or {})
    callback({ ok = ok, error = errorMessage })
end)

RegisterNUICallback('saveChanges', function(data, callback)
    data = type(data) == 'table' and data or {}
    local id = tostring(data.id or '')
    local existing = placements[id]
    if id == '' or not existing then
        callback({ ok = false, error = 'That placement no longer exists.' })
        return
    end

    data.id = id
    data.matrix = existing.matrix
    data.scale = nil
    TriggerServerEvent('glowtext:server:save', data)
    callback({ ok = true })
end)

RegisterNUICallback('deletePlacement', function(data, callback)
    local id = tostring(data and data.id or '')
    if id == '' or not placements[id] then
        callback({ ok = false, error = 'That placement no longer exists.' })
        return
    end
    TriggerServerEvent('glowtext:server:delete', id)
    callback({ ok = true })
end)

RegisterKeyMapping('+gizmoTranslation', 'Glow Text gizmo: move', 'keyboard', 'T')
RegisterKeyMapping('+gizmoRotation', 'Glow Text gizmo: rotate', 'keyboard', 'R')
RegisterKeyMapping('+gizmoScale', 'Glow Text gizmo: scale', 'keyboard', 'S')
RegisterKeyMapping('+gizmoSelect', 'Glow Text gizmo: select handle', 'MOUSE_BUTTON', 'MOUSE_LEFT')
RegisterKeyMapping('+gizmoLocal', 'Glow Text gizmo: local/world axes', 'keyboard', 'L')

CreateThread(function()
    while true do
        local rgbActive = false
        local spinActive = false
        local timeMs = GetGameTimer()
        for id, group in pairs(spawned) do
            local record = placements[id]
            if record and not group.loading then
                rgbActive = updateRgbGroup(group.entities or {}, group.glyphs or {}, record, timeMs) or rgbActive
                spinActive = updateSpinGroup(group.entities or {}, group.glyphs or {}, record, timeMs) or spinActive
            end
        end
        if editorActive and editorSettings then
            rgbActive = updateRgbGroup(editorEntities, editorGlyphs, editorSettings, timeMs) or rgbActive
            spinActive = updateSpinGroup(editorEntities, editorGlyphs, editorSettings, timeMs) or spinActive
        end
        if spinActive then
            Wait(Config.SpinEffect.updateInterval)
        elseif rgbActive then
            Wait(Config.RgbEffect.updateInterval)
        else
            Wait(250)
        end
    end
end)

CreateThread(function()
    -- Remove local glyph objects left behind by a previous script instance.
    cleanupOrphanGlyphs()
    Wait(1000)
    TriggerServerEvent('glowtext:server:requestSync')
    while true do
        Wait(1000)
        if not editorActive then
            local playerPosition = GetEntityCoords(PlayerPedId())
            for id, record in pairs(placements) do
                local position = vector3(record.matrix[10], record.matrix[11], record.matrix[12])
                local nearby = #(playerPosition - position) <= Config.StreamDistance
                local group = spawned[id]
                if nearby then
                    if group and not spawnedGroupExists(group) then
                        removeSpawned(id)
                        group = nil
                    end
                    if not group then spawnPlacement(id, record) end
                elseif group then
                    removeSpawned(id)
                end
            end
            for id in pairs(spawned) do
                if not placements[id] then removeSpawned(id) end
            end
        end
    end
end)

local resourceStopping = false

local function cleanupResource(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if resourceStopping then return end
    resourceStopping = true
    setCursorMode(false)
    SetNuiFocus(false, false)
    SetPlayerControl(PlayerId(), true, 0)
    if editorCamera then RenderScriptCams(false, false, 0, true, true); DestroyCam(editorCamera, false) end
    removeEntities(editorEntities)
    for id in pairs(spawned) do removeSpawned(id) end
    cleanupOrphanGlyphs()
end

-- onResourceStop matches the working snipe-menu cleanup path. Keep the
-- client-specific event as a compatibility fallback; cleanup is idempotent.
AddEventHandler('onResourceStop', cleanupResource)
AddEventHandler('onClientResourceStop', cleanupResource)
