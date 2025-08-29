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

-- Objects
local diff_objref_table
do
	local get_objref_id
	do
		local objref_to_id = setmetatable({}, {__mode = "k"})
		local next_id = 1
		function get_objref_id(objref)
			local id = objref_to_id[objref]
			if not id then
				id = next_id
				next_id = next_id + 1
				objref_to_id[objref] = id
			end
			return id
		end
	end

	local function get_rotation(objref)
		if objref:is_player() then
			return vector.new(0, objref:get_look_horizontal(), 0)
		end
		return objref:get_rotation()
	end

	-- TODO:
	-- * punches
	-- * hook set_animation
	-- * hook set_sprite: there is no get_sprite
	-- * hook set_properties, get_properties to cache properties and reduce potentially expensive get_properties calls
	-- * players only: local animations
	local function objref_to_table(obj)
		assert(obj:is_valid())
		local attach = {obj:get_attach()}
		return {
			pos = obj:get_pos(),
			velocity = obj:get_velocity(),
			acceleration = obj:get_acceleration(), -- nil for players
			rotation = get_rotation(obj),
			properties = obj:get_properties(),
			animation = {obj:get_animation()},
			bone_overrides = obj:get_bone_overrides(),
			texture_mod = obj:get_texture_mod(),
			attach = attach[1] and {get_objref_id(attach[1]), unpack(attach, 2)} or nil,
		}
	end

	local function shallow_diff(old, new)
		if old == new then
			return
		end
		local diff = {}
		for k, v in pairs(new) do
			if not modlib.table.equals(old[k], v) then
				diff[k] = v
			end
		end
		if next(diff) ~= nil then
			return diff
		end
	end

	function diff_objref_table(old, new, dtime)
		local diff = {}
		if old.acceleration ~= new.acceleration then
			diff.acceleration = new.acceleration
		end
		if old.rotation ~= new.rotation then
			diff.rotation = new.rotation
		end
		if old.texture_mod ~= new.texture_mod then
			diff.texture_mod = new.texture_mod
		end

		-- Velocity and position warrant special consideration:
		-- If the prediction based on acceleration, velocity and dtime
		-- is close enough to the new value, we do not want to update as to avoid jank.
		-- (This is a tradeoff, of course: Too much tolerance and we incur jank from missing small changes.)
		assert((old.acceleration == nil) == (new.acceleration == nil))
		if old.acceleration then
			local predicted_velocity = old.velocity + dtime * old.acceleration
			if predicted_velocity:distance(new.velocity) > 0.05 then -- TODO experiment a bit
				diff.velocity = new.velocity
			end
		end

		local predicted_pos = old.pos + dtime * old.velocity -- approximation; luanti is not accurate either
		if predicted_pos:distance(new.pos) > 0.05 then -- TODO experiment a bit
			diff.pos = new.pos
		end

		diff.properties = shallow_diff(old.properties, new.properties)
		local new_bone_overrides = {}
		for bone in pairs(old.bone_overrides) do
			-- Trick to represent deleted bone overrides; empty table means delete.
			new_bone_overrides[bone] = new.bone_overrides[bone] or {}
		end
		diff.bone_overrides = shallow_diff(old.bone_overrides, new_bone_overrides)

		if not modlib.table.equals(old.animation, new.animation) then
			diff.animation = new.animation
		end

		if next(diff) ~= nil then
			return diff
		end
	end

	local function get_objects_in_area(box)
		local objs = {}
		for obj in core.objects_in_area(box:unpack()) do
			objs[obj] = true
			-- Add all parents
			local cur_obj = obj
			while true do
				cur_obj = cur_obj:get_attach()
				if (not cur_obj) or objs[cur_obj] then
					break
				end
				objs[cur_obj] = true
			end
		end

		local res = {}
		for obj in pairs(objs) do
			res[get_objref_id(obj)] = objref_to_table(obj)
		end
		return res
	end

	function Recording:get_objects_in_area()
		local res = get_objects_in_area(self.box)
		for _, obj in pairs(res) do
			obj.pos = obj.pos - self.box.min
		end
		return res
	end
end

function Recording:write_init()
	local nodes = read_nodes_from_map(self.box)
	local objects = self:get_objects_in_area()
	-- Dump the entire content id mapping for portability.
	-- This is a bit wasteful, but there's a good chance we can get away with it
	-- because Luanti only allows ~30k nodes, and games hopefully use far fewer.
	-- At worst this results in something < 1 MB, which probably compresses well.
	local content_ids = {}
	for name in pairs(core.registered_nodes) do
		content_ids[core.get_content_id(name)] = name
	end
	self.out_stream:write_init(nodes, objects, content_ids)
	self.nodes = nodes
	self.objects = objects
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
						diff[core.hash_node_position(vector.new(x, y, z) - self.box.min)] = pack_node(
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
	local timestamp = self:get_timestamp()
	local nodes = read_nodes_from_map(intersection)
	self:update_nodes(timestamp, intersection, nodes)
end

do
	local running_recordings = {}

	function Recording:start()
		self:write_init()
		running_recordings[self] = true
	end

	function Recording:tick(dtime)
		local new_objects = self:get_objects_in_area()
		local diff = {}
		for id, new_object in pairs(new_objects) do
			local old_object = self.objects[id]
			if old_object then
				diff[id] = diff_objref_table(old_object, new_object, dtime)
			else
				diff[id] = new_object
			end
		end
		for id in pairs(self.objects) do
			if not new_objects[id] then
				diff[id] = false -- mark as removed
			end
		end
		if next(diff) ~= nil then
			self.out_stream:write_objects(self:get_timestamp(), diff)
		end
		self.objects = new_objects
		-- TODO particlespawners and particles; we'll have to hook.
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

	function Recording:get_timestamp()
		return get_timestamp() - self.start_timestamp
	end

	core.register_globalstep(function(dtime)
		current_timestamp = current_timestamp + dtime
		for recording in pairs(running_recordings) do
			recording:tick(dtime)
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
