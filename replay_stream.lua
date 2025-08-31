local Box = modlib.mod.require("box")

-- File-based replay stream reader

local binary = modlib.mod.require("binary")
local serializer = modlib.mod.require("serializer")

local ReplayStream = {}
ReplayStream.__index = ReplayStream

function ReplayStream.new(in_file)
	local self = setmetatable({in_file = in_file}, ReplayStream)
	assert(self.in_file:read(4) == "REC\0")
	return self
end

function ReplayStream:close()
	self.in_file:close()
end

function ReplayStream:get_pos()
	return self.in_file:seek()
end

function ReplayStream:set_pos(pos)
	self.in_file:seek("set", pos)
end

function ReplayStream:unread_chunk(chunk)
	self.buffered_chunk = chunk
end

function ReplayStream:read_chunk()
	if self.buffered_chunk then
		local chunk = self.buffered_chunk
		self.buffered_chunk = nil
		return chunk
	end
	local len_str = self.in_file:read(4)
	if not len_str then
		return
	end
	local len = binary.unpack_u32(len_str)
	local data = self.in_file:read(len)
	assert(#data == len)
	return serializer.deserialize(core.decompress(data, "zstd"))
end

local function unpack_nodes(packed_nodes)
	return {
		content_ids = binary.unpack_shorts(packed_nodes.content_ids),
		param1s = binary.unpack_bytes(packed_nodes.param1s),
		param2s = binary.unpack_bytes(packed_nodes.param2s),
	}
end

function ReplayStream:read_init()
	local init = self:read_chunk()
	init.nodes = unpack_nodes(init.nodes)
	return init
end

local function id(x) return x end

local unpack_event = {
	objects = id,
	particles = id,
	sparse_nodes = id,
}

function unpack_event.nodes(evt)
	evt.box = Box.new(evt.box.min, evt.box.max)
	assert(type(evt.new_nodes.content_ids) == "string")
	evt.new_nodes = unpack_nodes(evt.new_nodes)
	return evt
end

function ReplayStream:read_events(max_timestamp, process_event)
	local event = self:read_chunk()
	if not event then
		return true
	end
	if event.timestamp > max_timestamp then
		self:unread_chunk(event)
		return false
	end
	process_event(unpack_event[event.type](event))
	return self:read_events(max_timestamp, process_event)
end

return ReplayStream
