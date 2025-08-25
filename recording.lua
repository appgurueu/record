local Box = modlib.mod.require("box")
local RecordingStream = modlib.mod.require("recording_stream")

local Recording = {}
Recording.__index = Recording

local get_timestamp

function Recording.new(box, out_file)
	-- TODO dump content id mapping!!
	local self = setmetatable({
		box = box,
		out_stream = RecordingStream.new(box:extents(), out_file),
		start_timestamp = get_timestamp(),
	}, Recording)
	return self
end

local function read_nodes_from_map(box)
	local pmin, pmax = box:unpack()
	local vm = VoxelManip()
	local emin, emax = vm:read_from_map(pmin, pmax)
	local va = VoxelArea(emin, emax)
	local y_stride, z_stride = va.ystride, va.zstride
	local src_cids, src_p1s, src_p2s = vm:get_data(), vm:get_light_data(), vm:get_param2_data()
	vm:close()
	local dst_cids, dst_p1s, dst_p2s = {}, {}, {}
	local dst_idx = 1
	local z_idx = va:indexp(pmin)
	for _ = pmin.z, pmax.z do
		local y_idx = z_idx
		for _ = pmin.y, pmax.y do
			local src_idx = y_idx
			for _ = pmin.x, pmax.x do
				dst_cids[dst_idx] = src_cids[src_idx]
				dst_p1s[dst_idx] = src_p1s[src_idx]
				dst_p2s[dst_idx] = src_p2s[src_idx]
				src_idx = src_idx + 1
				dst_idx = dst_idx + 1
			end
			y_idx = y_idx + y_stride
		end
		z_idx = z_idx + z_stride
	end
	return {
		content_ids = dst_cids,
		param1s = dst_p1s,
		param2s = dst_p2s,
	}
end

function Recording:write_init()
	local nodes = read_nodes_from_map(self.box)
	self.out_stream:write_init(nodes)
	self.nodes = nodes
end

local function pack_node(content_id, param1, param2)
	return content_id + bit.rshift(param1, 16) + bit.rshift(param2, 24)
end

function Recording:update_nodes(timestamp, box, new_nodes)
	local pmin, pmax = box:unpack()
	local diff = {}
	local n_sparse = math.floor(#new_nodes.content_ids / 16)
	local old_cids, old_p1s, old_p2s = self.nodes.content_ids, self.nodes.param1s, self.nodes.param2s
	local new_cids, new_p1s, new_p2s = new_nodes.content_ids, new_nodes.param1s, new_nodes.param2s
	local extents = self.box:extents()
	local y_stride, z_stride = extents.x, extents.x * extents.y
	local new_idx = 1
	local z_idx = 1 + vector.new(1, y_stride, z_stride):dot(pmin - self.box.min)
	for z = pmin.z, pmax.z do
		local y_idx = z_idx
		for y = pmin.y, pmax.y do
			local old_idx = y_idx
			for x = pmin.x, pmax.x do
				if
					old_cids[old_idx] ~= new_cids[new_idx]
					or old_p1s[old_idx] ~= new_p1s[new_idx]
					or old_p2s[old_idx] ~= new_p2s[new_idx]
				then
					if n_sparse >= 1 then
						diff[core.hash_node_position(vector.new(x, y, z))] = pack_node(
								new_cids[new_idx], new_p1s[new_idx], new_p2s[new_idx])
					end
					n_sparse = n_sparse - 1
				end
				new_idx = new_idx + 1
				old_idx = old_idx + 1
			end
			y_idx = y_idx + y_stride
		end
		z_idx = z_idx + z_stride
	end
	if n_sparse >= 0 then -- yay, sparse node budget sufficed!
		self.out_stream:write_sparse_nodes(timestamp, diff)
	else
		self.out_stream:write_nodes(timestamp, box:offset(-self.box.min), new_nodes)
	end
end

local block_size = core.MAP_BLOCKSIZE

function Recording:record_mapblock_changed(block_pos)
	local block_box = Box.from_extents(vector.new(block_size, block_size, block_size)):offset(block_pos * block_size)
	local intersection = self.box:intersection(block_box)
	if not intersection then
		return
	end
	local timestamp = get_timestamp() - self.start_timestamp
	local nodes = read_nodes_from_map(intersection)
	self:update_nodes(timestamp, intersection, nodes)
end

do
	local running_recordings = {}

	function Recording:start()
		self:write_init()
		running_recordings[self] = true
	end

	function Recording:tick()
		for obj in core.objects_in_area(self.box:unpack()) do
			-- TODO poll entities
		end
		-- TODO beloved particlespawners and particles; we'll have to hook the core functions probably.
	end

	function Recording:stop()
		running_recordings[self] = nil
	end

	function Recording:close()
		self.out_stream.file:close()
	end

	local current_timestamp = 0
	function get_timestamp()
		return current_timestamp
	end

	core.register_globalstep(function(dtime)
		current_timestamp = current_timestamp + dtime
		for recording in pairs(running_recordings) do
			recording:tick()
		end
	end)

	core.register_on_mapblocks_changed(function(modified_blocks)
		for recording in pairs(running_recordings) do -- TODO if we end up with many recordings, might want to optimize this
			for hash in pairs(modified_blocks) do
				local bpos = core.get_position_from_hash(hash)
				recording:record_mapblock_changed(bpos)
			end
		end
	end)
end

return Recording
