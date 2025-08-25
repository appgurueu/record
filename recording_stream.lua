-- File-based recording stream writer

local binary = modlib.mod.require"binary"
local serializer = modlib.mod.require"serializer"

local RecordingStream = {}
RecordingStream.__index = RecordingStream

function RecordingStream.new(extents, file)
	local self = setmetatable({
		extents = extents,
		file = file,
	}, RecordingStream)
	self.file:write"REC\0"
	-- metadata gets a separate chunk
	self:write_chunk{
		version = 0,
		extents = self.extents,
	}
	return self
end

function RecordingStream:write_chunk(data)
	local str = core.compress(serializer.serialize(data), "zstd")
	local packed_len = binary.pack_u32(#str)
	self.file:write(packed_len)
	self.file:write(str)
	self.file:write(packed_len)
	-- by writing the length again at the end,
	-- the stream can be read bidirectionally
end

local function pack_nodes(nodes)
	return {
		content_ids = binary.pack_shorts(nodes.content_ids),
		param1s = binary.pack_bytes(nodes.param1s),
		param2s = binary.pack_bytes(nodes.param2s),
	}
end

function RecordingStream:write_init(nodes)
	self:write_chunk{
		nodes = pack_nodes(nodes),
	}
end

function RecordingStream:write_event(event)
	assert(event.timestamp)
	return self:write_chunk(event)
end

function RecordingStream:write_sparse_nodes(timestamp, diff)
	return self:write_event{
		type = "sparse_nodes",
		timestamp = timestamp,
		diff = diff,
	}
end

function RecordingStream:write_nodes(timestamp, box, new_nodes)
	return self:write_event{
		type = "nodes",
		timestamp = timestamp,
		box = box,
		new_nodes = pack_nodes(new_nodes),
	}
end

function RecordingStream:close()
	self.file:close()
end

return RecordingStream
