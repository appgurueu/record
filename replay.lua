-- A live replay

local Box = modlib.mod.require("box")
local ReplayStream = modlib.mod.require("replay_stream")

local Replay = {}
Replay.__index = Replay

function Replay.new(pos, in_file)
	local self = setmetatable({
		pos = pos,
		in_stream = ReplayStream.new(in_file),
		time = 0,
	}, Replay)
	local meta = self.in_stream:read_chunk()
	assert(meta.version == 0)
	self.extents = assert(meta.extents)
	return self
end

local function write_nodes_to_map(box, nodes)
	local pmin, pmax = box:unpack()
	local vm = VoxelManip()
	local va = VoxelArea(vm:read_from_map(pmin, pmax))
	local y_stride, z_stride = va.ystride, va.zstride
	local src_idx = 1
	local z_idx = va:indexp(pmin)
	local dst_content_ids, dst_param1s, dst_param2s = vm:get_data(), vm:get_light_data(), vm:get_param2_data()
	local src_content_ids, src_param1s, src_param2s = nodes.content_ids, nodes.param1s, nodes.param2s
	for _ = pmin.z, pmax.z do
		local y_idx = z_idx
		for _ = pmin.y, pmax.y do
			local dst_idx = y_idx
			for _ = pmin.x, pmax.x do
				dst_content_ids[dst_idx] = src_content_ids[src_idx]
				dst_param1s[dst_idx] = src_param1s[src_idx]
				dst_param2s[dst_idx] = src_param2s[src_idx]
				src_idx = src_idx + 1
				dst_idx = dst_idx + 1
			end
			y_idx = y_idx + y_stride
		end
		z_idx = z_idx + z_stride
	end
	vm:set_data(dst_content_ids)
	vm:set_light_data(dst_param1s)
	vm:set_param2_data(dst_param2s)
	vm:write_to_map() -- set light=false?
	vm:close()
end

local event_handlers = {}

local function unpack_node(packed_node)
	local content_id = bit.band(packed_node, 0xFFFF)
	local param1 = bit.band(bit.rshift(packed_node, 16), 0xFF)
	local param2 = bit.band(bit.rshift(packed_node, 24), 0xFF)
	return content_id, param1, param2
end

function event_handlers:sparse_nodes(evt)
	for pos_hash, packed_node in pairs(evt.diff) do
		local pos = core.get_position_from_hash(pos_hash)
		local content_id, param1, param2 = unpack_node(packed_node)
		core.set_node(pos, {
			name = core.get_name_from_content_id(content_id),
			param1 = param1,
			param2 = param2,
		})
	end
end

function event_handlers:nodes(evt)
	write_nodes_to_map(evt.box:offset(self.pos), evt.new_nodes)
end

do
	local running_replays = {}

	function Replay:start()
		local box = Box.from_extents(self.extents):offset(self.pos)
		local init = self.in_stream:read_init()
		write_nodes_to_map(box, init.nodes)
		running_replays[self] = true
	end

	function Replay:tick(dtime)
		self.time = self.time + dtime
		self.in_stream:read_events(self.time, function(evt)
			return event_handlers[evt.type](self, evt)
		end)
		-- TODO what to do when done?
	end

	function Replay:stop()
		running_replays[self] = nil
	end

	core.register_globalstep(function(dtime)
		for replay in pairs(running_replays) do
			replay:tick(dtime)
		end
	end)
end

return Replay
