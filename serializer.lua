local bluon = modlib.bluon.new()

local serializer = {}

local function stream_write(stream, str)
	table.insert(stream, str)
end

function serializer.serialize(value)
	local stream = {write = stream_write}
	bluon:write(value, stream)
	return table.concat(stream)
end

function serializer.deserialize(str)
	local value = bluon:read(modlib.text.inputstream(str))
	return value
end

return serializer