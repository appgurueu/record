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
end

local function pack_nodes(nodes)
	return {
		content_ids = binary.pack_shorts(nodes.content_ids),
		param1s = binary.pack_bytes(nodes.param1s),
		param2s = binary.pack_bytes(nodes.param2s),
	}
end

function RecordingStream:write_init(nodes, objects, content_ids)
	self:write_chunk{
		nodes = pack_nodes(nodes),
		objects = assert(objects),
		content_ids = assert(content_ids),
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

function RecordingStream:write_objects(timestamp, diff)
	return self:write_event{
		type = "objects",
		timestamp = timestamp,
		diff = diff,
	}
end

function RecordingStream:write_particles(timestamp, new_particles)
	return self:write_event{
		type = "particles",
		timestamp = timestamp,
		new_particles = new_particles,
	}
end

function RecordingStream:close()
	self.file:close()
end

return RecordingStream
