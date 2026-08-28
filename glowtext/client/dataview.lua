-- MIT-licensed DataView helper derived from the CitizenFX Lua implementation:
-- https://github.com/citizenfx/lua/blob/luaglm-dev/cfx/lua.h

DataView = setmetatable({
    EndBig = '>',
    EndLittle = '<',
    Types = {
        Int8 = { code = 'i1' },
        Uint8 = { code = 'I1' },
        Int16 = { code = 'i2' },
        Uint16 = { code = 'I2' },
        Int32 = { code = 'i4' },
        Uint32 = { code = 'I4' },
        Int64 = { code = 'i8' },
        Uint64 = { code = 'I8' },
        Float32 = { code = 'f', size = 4 },
        Float64 = { code = 'd', size = 8 },
        LuaInt = { code = 'j' },
        UluaInt = { code = 'J' },
        LuaNum = { code = 'n' },
        String = { code = 'z', size = -1 },
    },
    FixedTypes = {
        String = { code = 'c' },
        Int = { code = 'i' },
        Uint = { code = 'I' },
    },
}, {
    __call = function(_, length)
        return DataView.ArrayBuffer(length)
    end,
})

DataView.__index = DataView

function DataView.ArrayBuffer(length)
    return setmetatable({
        blob = string.blob(length),
        length = length,
        offset = 1,
        cangrow = true,
    }, DataView)
end

function DataView.Wrap(blob)
    return setmetatable({
        blob = blob,
        length = blob:len(),
        offset = 1,
        cangrow = true,
    }, DataView)
end

function DataView:Buffer()
    return self.blob
end

function DataView:ByteLength()
    return self.length
end

function DataView:ByteOffset()
    return self.offset
end

function DataView:SubView(offset, length)
    return setmetatable({
        blob = self.blob,
        length = length or self.length,
        offset = 1 + offset,
        cangrow = false,
    }, DataView)
end

local function endianFormat(big)
    return (big and DataView.EndBig) or DataView.EndLittle
end

local function packBlob(self, offset, value, code)
    local packed = self.blob:blob_pack(offset, code, value)
    if self.cangrow or packed == self.blob then
        self.blob = packed
        self.length = packed:len()
        return true
    end
    return false
end

for label, datatype in pairs(DataView.Types) do
    if not datatype.size then
        datatype.size = string.packsize(datatype.code)
    elseif datatype.size >= 0 and string.packsize(datatype.code) ~= datatype.size then
        error(('Pack size of %s does not match the expected size.'):format(label))
    end

    DataView['Get' .. label] = function(self, offset, bigEndian)
        offset = offset or 0
        if offset < 0 then return nil end
        local value = self.blob:blob_unpack(self.offset + offset, endianFormat(bigEndian) .. datatype.code)
        return value
    end

    DataView['Set' .. label] = function(self, offset, value, bigEndian)
        if offset < 0 or value == nil then return self end
        local absoluteOffset = self.offset + offset
        local valueSize = datatype.size < 0 and value:len() or datatype.size
        if not self.cangrow and (absoluteOffset + valueSize - 1) > self.length then
            error('cannot grow dataview')
        end
        if not packBlob(self, absoluteOffset, value, endianFormat(bigEndian) .. datatype.code) then
            error('cannot grow subview')
        end
        return self
    end
end

for label in pairs(DataView.FixedTypes) do
    DataView['GetFixed' .. label] = function(self, offset, length, bigEndian)
        if offset < 0 or (self.offset + offset + length - 1) > self.length then return nil end
        local value = self.blob:blob_unpack(self.offset + offset, endianFormat(bigEndian) .. 'c' .. tostring(length))
        return value
    end

    DataView['SetFixed' .. label] = function(self, offset, length, value, bigEndian)
        if offset < 0 or value == nil then return self end
        local absoluteOffset = self.offset + offset
        if not self.cangrow and (absoluteOffset + length - 1) > self.length then
            error('cannot grow dataview')
        end
        if not packBlob(self, absoluteOffset, value, endianFormat(bigEndian) .. 'c' .. tostring(length)) then
            error('cannot grow subview')
        end
        return self
    end
end
