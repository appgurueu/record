-- A live replay

local Box = modlib.mod.require("box")
local ReplayStream = modlib.mod.require("replay_stream")

local Replay = {}
Replay.__index = Replay

function Replay.new(pos, in_file)
	-- Very bad things happen if it is not
	assert(pos:floor() == pos)
	local self = setmetatable({
		pos = pos,
		in_stream = ReplayStream.new(in_file),
		time = 0,
		speed = 1,
		objrefs_by_id = {},
		-- [id] = {id = luanti id, expiration_job = core.after job}
		particle_spawners = {},
	}, Replay)
	local meta = self.in_stream:read_chunk()
	assert(meta.version == 0)
	self.extents = assert(meta.extents)
	self.init_pos = self.in_stream:get_pos()
	return self
end

function Replay:close()
	self.in_stream:close()
end

function Replay:get_box()
	return Box.from_extents(self.extents):offset(self.pos)
end

local function write_nodes_to_map(box, nodes, content_id_map)
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
				dst_content_ids[dst_idx] = assert(content_id_map[src_content_ids[src_idx]])
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

function Replay:write_nodes_to_map(box, nodes)
	return write_nodes_to_map(box, nodes, self.content_id_map)
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
		core.set_node(pos + self.pos, {
			name = core.get_name_from_content_id(content_id),
			param1 = param1,
			param2 = param2,
		})
	end
end

function event_handlers:nodes(evt)
	self:write_nodes_to_map(evt.box:offset(self.pos), evt.new_nodes)
end

-- Objects
do
	local Replayer = {}
	-- TODO do something proper about persisting entities
	local replayer_to_replay = setmetatable({}, {__mode = "kv"})
	function Replayer:on_deactivate()
		local replay = replayer_to_replay[self]
		if replay then
			replay.objrefs_by_id[self._id] = nil
			replayer_to_replay[self] = nil
		end
	end
	core.register_entity("record:replayer", Replayer)

	function Replay:add_replayer(id, pos)
		local obj = core.add_entity(pos, "record:replayer")
		assert(not self.objrefs_by_id[id])
		self.objrefs_by_id[id] = obj
		local ent = obj:get_luaentity()
		ent._id = id
		replayer_to_replay[ent] = self
		return obj
	end

	function Replay:upsert_replay_object(id, update, updates)
		local obj = self.objrefs_by_id[id]
		if not obj then
			obj = self:add_replayer(id, update.pos + self.pos)
		elseif update.pos then
			local abs_pos = update.pos + self.pos
			if update.pos_teleport then
				obj:set_pos(abs_pos)
			else
				obj:move_to(abs_pos)
			end
		end
		if update.velocity then
			obj:set_velocity(update.velocity)
		end
		if update.acceleration then
			obj:set_acceleration(update.acceleration)
		end
		if update.rotation then
			obj:set_rotation(update.rotation)
		end
		if update.properties then
			obj:set_properties(update.properties) -- note: incremental
		end
		if update.animation then
			-- frame_range, frame_speed, frame_blend, frame_loop
			obj:set_animation(unpack(update.animation, 1, 4))
		end
		if update.set_sprite then
			-- start_frame, num_frames, framelength, select_x_by_camera
			obj:set_sprite(unpack(update.set_sprite, 1, 4))
		end
		for bonename, override in pairs(update.bone_overrides or {}) do
			obj:set_bone_override(bonename, override)
		end
		if update.texture_mod then
			obj:set_texture_mod(update.texture_mod)
		end
		if update.attach then
			local parent_id = update.attach[1]
			local parent = self.objrefs_by_id[parent_id] or
					self:upsert_replay_object(parent_id, assert(updates[parent_id]), updates)
			if parent then
				obj:set_attach(parent, unpack(update.attach, 2))
			end -- else warn?
		end
		updates[id] = nil -- mark as done
		return obj
	end

	function event_handlers:objects(evt)
		for id, update in pairs(evt.diff) do
			if update == false then -- delete
				local obj = self.objrefs_by_id[id]
				if obj then
					obj:remove()
				end -- else warn?
			else
				-- note: sets some fields to nil to process parents first
				-- HACK probably cleaner to topo sort explicitly in a first pass
				self:upsert_replay_object(id, update, evt.diff)
			end
		end
	end
end

function event_handlers:particles(evt)
	for _, def in ipairs(evt.new_particles) do
		def.pos = vector.add(def.pos, self.pos)
		core.add_particle(def)
	end

	for _, id in ipairs(evt.deleted_particle_spawners or {}) do
		local spawner = self.particle_spawners[id]
		core.delete_particlespawner(spawner.id)
		if spawner.expiration_job then
			spawner.expiration_job:cancel()
		end
		self.particle_spawners[id] = nil
	end

	for id, def in pairs(evt.new_particle_spawners or {}) do
		local spawner = {id = core.add_particlespawner(def)}
		self.particle_spawners[id] = spawner
		local time = def.time or 1
		if time > 0 then
			spawner.expiration_job = core.after(time, function()
				self.particle_spawners[id] = nil
			end)
		end
	end
end

do
	local running_replays = {}

	local function convert_cid_map(content_ids)
		local res = {}
		for cid, name in pairs(content_ids) do
			res[cid] = core.get_content_id(name)
		end
		res[core.CONTENT_AIR] = core.CONTENT_AIR
		res[core.CONTENT_IGNORE] = core.CONTENT_IGNORE
		res[core.CONTENT_UNKNOWN] = core.CONTENT_UNKNOWN
		return res
	end

	function Replay:start(on_done)
		local box = Box.from_extents(self.extents):offset(self.pos)
		local init = self.in_stream:read_init()
		self.content_id_map = convert_cid_map(init.content_ids)
		self:write_nodes_to_map(box, init.nodes)
		for id, obj in pairs(assert(init.objects)) do
			self:upsert_replay_object(id, obj, init.objects)
		end
		running_replays[self] = on_done or function() end
		self:tick(0) -- process any events at time 0
	end

	function Replay:seek(timestamp)
		-- Simple (but inefficient) restart and fast-forward
		self.time = 0
		self.in_stream:set_pos(self.init_pos)
		self:start()
		self:tick(timestamp)
	end

	function Replay:tick(dtime)
		-- TODO if the speed is adjusted, we ought to adjust
		-- object velocities, accelerations, and particle (spawner) times accordingly.
		self.time = self.time + self.speed * dtime
		local done = self.in_stream:read_events(self.time, function(evt)
			return event_handlers[evt.type](self, evt)
		end)
		return done
	end

	function Replay:stop()
		-- Remove particle spawners?
		running_replays[self] = nil
	end

	core.register_globalstep(function(dtime)
		for replay, on_done in pairs(running_replays) do
			if replay:tick(dtime) then
				if not on_done() then
					replay:stop()
					replay:close()
				end
			end
		end
	end)
end

return Replay
