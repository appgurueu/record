local Box = modlib.mod.require("box")
local Recording = modlib.mod.require("recording")
local Replay = modlib.mod.require("replay")
local add_box_marker = modlib.mod.require("add_box_marker")

local world_path = core.get_worldpath()
local recordings_path = world_path .. "/recordings"
core.mkdir(recordings_path)
local function get_recording_path(player_name, recording_name)
	local player_recordings_path = recordings_path .. "/" .. player_name
	core.mkdir(player_recordings_path)
	return player_recordings_path .. "/" .. recording_name .. ".rec"
end

-- Approximation of a file existence check.
-- If this returns false, we most probably won't be overwriting anything,
-- though there could be weird scenarios such as having write, but not read permission.
local function file_exists(name)
	local f = io.open(name, "rb")
	if not f then return false end
	return f
end

local function validate_recording_name(name)
	if not name:match"^[a-zA-Z0-9_%-]+$" then
		return false, "Recording name must consist of letters, digits, underscores and hyphens."
	end
	return true
end

local player_data = {}

core.register_on_joinplayer(function(player)
	player_data[player:get_player_name()] = {
		pos1 = nil,
		pos2 = nil,
		recordings = {},
		record_box_marker = nil,
		replays = {},
		replay_box_markers = {},
	}
end)
core.register_on_leaveplayer(function(player)
	player_data[player:get_player_name()] = nil
end)

core.register_privilege("record", {
    description = "Can make recordings of the world",
    give_to_singleplayer = true,
    give_to_admin = true,
})

local function keys_str(t)
	local keys = modlib.table.keys(t)
	table.sort(keys)
	return table.concat(keys, ", ")
end

cmdlib.register_chatcommand("record pos clear", {
	params = "",
	description = "Clear your set pos 1 and pos 2 for recording",
	func = function(pname)
		local pdata = player_data[pname]
		if not pdata then
			return false, "You must be an online player to use this command."
		end
		pdata.pos1 = nil
		pdata.pos2 = nil
		if pdata.record_box_marker then
			pdata.record_box_marker:remove()
			pdata.record_box_marker = nil
		end
		return true, "Cleared pos 1 and pos 2."
	end,
})

for i = 1, 2 do
	cmdlib.register_chatcommand(("record pos %d"):format(i), {
		params = "",
		description = ("Set pos %d for recording"):format(i),
		func = function(pname)
			local player = core.get_player_by_name(pname)
			if not player then
				return false, "You must be an online player to use this command."
			end
			local pos = player:get_pos():round()
			local pdata = player_data[pname]
			pdata[("pos%d"):format(i)] = pos
			if pdata.pos1 and pdata.pos2 then
				if pdata.record_box_marker then
					pdata.record_box_marker:remove()
				end
				pdata.record_box_marker = add_box_marker(Box.new(pdata.pos1, pdata.pos2))
			end
			return true, ("Set pos %d to %s."):format(i, minetest.pos_to_string(pos))
		end,
	})
end

cmdlib.register_chatcommand("record start", {
	privs = {record = true},
	params = "<name>",
	description = "Record the box between your set pos 1 and pos 2",
	func = function(pname, params)
		local recording_name = params.name
		local pdata = player_data[pname]
		if not (pdata and pdata.pos1 and pdata.pos2) then
			return false, "You must set both pos 1 and pos 2 using /record pos 1|2 before starting a recording."
		end

		do
			local valid, err = validate_recording_name(recording_name)
			if not valid then
				return false, err
			end
		end

		local path = get_recording_path(pname, recording_name)
		if file_exists(path) then
			return false, 'A recording called "' .. path .. '" already exists (use /record_delete to delete it).'
		end
		local file, err = io.open(path, "wb")
		if err then
			return false, err
		end
		local box = Box.new(pdata.pos1, pdata.pos2)
		local recording = Recording.new(box, file)
		recording:start()
		pdata.recordings[recording_name] = recording
	end
})

cmdlib.register_chatcommand("record stop", {
	params = "[name]",
	description = "Stop a currently running recording",
	func = function(pname, params)
		local recording_name = params.name
		local pdata = player_data[pname]
		if not pdata then
			return false, "You must be an online player to use this command."
		end
		local recordings = pdata.recordings
		if recording_name then
			if not recordings[recording_name] then
				return false, 'No recording called "' .. recording_name .. '".' ..
						' Valid names are: ' .. keys_str(recordings) .. "."
			end
		else
			recording_name = next(recordings)
			if not recording_name then
				return false, "No currently running recordings."
			end
			if next(recordings, recording_name) then
				return false, "Multiple running recordings: " .. keys_str(recordings)
						.. ", please choose one."
			end
		end
		local recording = recordings[recording_name]
		recording:stop()
		return true, 'Recording "' .. recording_name .. '" stopped.'
	end,
})

cmdlib.register_chatcommand("record delete", {
	params = "<name>",
	description = "Delete a saved recording",
	func = function(pname, params)
		local recording_name = params.name
		do
			local valid, err = validate_recording_name(recording_name)
			if not valid then
				return false, err
			end
		end
		local path = get_recording_path(pname, recording_name)
		local success, err = os.remove(path)
		if success then
			return true, 'Deleted recording "' .. recording_name .. '".'
		end
		return false, 'Error deleting recording "' .. recording_name .. '": ' .. err
	end,
})

-- Replay commands

cmdlib.register_chatcommand("replay box", {
	params = "<name>",
	description = "Show the extents of a saved recording",
	func = function(pname, params)
		local player = core.get_player_by_name(pname)
		if not player then
			return false, "You must be an online player to use this command."
		end
		local ppos = player:get_pos():round()

		local recording_name = params.name
		local path = get_recording_path(pname, recording_name)
		local file, err = io.open(path, "rb")
		if not file then
			return false, 'Error opening recording "' .. recording_name .. '": ' .. err
		end
		local pdata = assert(player_data[pname])
		local marker = pdata.replay_box_markers[recording_name]
		if marker then
			marker:remove()
			pdata.replay_box_markers[recording_name] = nil
			return true, 'Removed box marker for recording "' .. recording_name .. '". Repeat the command to add it again.'
		end

		local replay = Replay.new(ppos, file)
		local box = replay:get_box()
		replay:close()
		pdata.replay_box_markers[recording_name] = add_box_marker(box)

		return true, "Recording box: " .. tostring(replay:get_box()) .. ". Run the command again to remove the marker."
	end,
})

cmdlib.register_chatcommand("replay start", {
	privs = {record = true},
	params = "<name>",
	description = "Replay a saved recording at your current position",
	func = function(pname, params)
		local recording_name = params.name
		local path = get_recording_path(pname, recording_name)
		local file, err = io.open(path, "rb")
		if not file then
			return false, 'Error opening recording "' .. recording_name .. '": ' .. err
		end
		local player = core.get_player_by_name(pname)
		if not player then
			return false, "You must be an online player to use this command."
		end
		local pos = player:get_pos():round()
		local replay = Replay.new(pos, file)
		replay:start(function()
			local pdata = player_data[pname]
			if pdata then
				pdata.replays[recording_name] = nil
				core.chat_send_player(pname, 'Replay of "' .. recording_name .. '" finished.')
			end
		end)
		local pdata = assert(player_data[pname])
		pdata.replays[recording_name] = replay
		return true, 'Replaying recording "' .. recording_name .. '".'
	end,
})

cmdlib.register_chatcommand("replay speed", {
	params = "<factor> [name]",
	description = "Set replay speed factor (default: 1.0)",
	func = function(pname, params)
		local pdata = player_data[pname]
		if not pdata then
			return false, "You must be an online player to use this command."
		end
		local factor = tonumber(params.factor)
		if not factor or factor <= 0 or factor == math.huge then
			-- TODO speed = 0 to pause?
			return false, "Speed factor must be a positive number."
		end
		local replays = pdata.replays
		local replay_name = next(replays)
		if not replay_name then
			return false, "You have no running replays."
		end
		if next(replays, replay_name) then
			replay_name = params.name
		end
		if replay_name then
			local replay = replays[replay_name]
			if not replay then
				return false, 'No replay called "' .. replay_name .. '".' ..
					' Running replays: ' .. keys_str(replays) .. "."
			end
			replay.speed = factor
			return true, "Set speed to " .. factor .. ' for replay "' .. replay_name .. '".'
		end
		for _, replay in pairs(replays) do
			replay.speed = factor
		end
		return true, "Set speed to " .. factor .. " for running replays: " .. keys_str(replays) .. "."
	end,
})

-- replay_name is optional if there's only one running replay
local function get_running_replay(replays, replay_name)
	if not next(replays) then
		return nil, "You have no running replays."
	end
	if not replay_name then
		replay_name = next(replays)
		if next(replays, replay_name) then
			return nil, "You have multiple running replays: " .. keys_str(replays) .. ", please choose one."
		end
	end
	local replay = replays[replay_name]
	if not replay then
		return nil, 'No replay called "' .. replay_name .. '".' ..
			' Running replays: ' .. keys_str(replays) .. "."
	end
	return replay, replay_name
end

cmdlib.register_chatcommand("replay stop", {
	params = "[name]",
	description = "Stop a currently running replay",
	func = function(pname, params)
		local pdata = player_data[pname]
		if not pdata then
			return false, "You must be an online player to use this command."
		end
		local replay, replay_name_or_err = get_running_replay(pdata.replays, params.name)
		if not replay then
			return false, replay_name_or_err
		end
		local replay_name = replay_name_or_err
		replay:stop()
		pdata.replays[replay_name] = nil
		return true, 'Stopped replay "' .. replay_name .. '".'
	end,
})

local function parse_duration(str)
	local seconds = {}
	seconds.s = 1
	seconds.m = 60 * seconds.s
	seconds.h = 60 * seconds.m
	seconds.d = 24 * seconds.h

	local i = 1
	local total_seconds = 0
	while i < #str do
		local end_idx, num, unit = str:find("^(%d+%.?%d*)([smhd])", i)
		if not end_idx then
			return
		end
		total_seconds = total_seconds + tonumber(num) * seconds[unit]
		i = end_idx + 1
	end
	return total_seconds
end

local function parse_relative_duration(str, base_timestamp)
	local sign, tail = str:match"^([%-%+]?)(.+)"
	local relative_duration = parse_duration(tail)
	if not relative_duration then
		return
	end
	if sign == "-" then
		return base_timestamp - relative_duration
	end
	if sign == "+" then
		return base_timestamp + relative_duration
	end
	return relative_duration -- absolute
end

cmdlib.register_chatcommand("replay seek", {
	params = "<time> [name]",
	description = "Seek to a timestamp in seconds; jump forward or backward.\n" ..
			"Use a + or - prefix to seek relative to the current position.\n" ..
			"Supports suffixes s, m, h, d (seconds, minutes, hours, days); they can be combined, e.g. 1h30m.\n",
	func = function(pname, params)
		local pdata = player_data[pname]
		if not pdata then
			return false, "You must be an online player to use this command."
		end
		local replay, replay_name_or_err = get_running_replay(pdata.replays, params.name)
		if not replay then
			return false, replay_name_or_err
		end
		local replay_name = replay_name_or_err

		local target_timestamp = math.max(0, parse_relative_duration(params.time, replay.time))
		if not target_timestamp then
			return false, "Invalid time format."
		end
		replay:seek(target_timestamp)
		return true, ('Jumped to timestamp %.2f in replay "%s".'):format(target_timestamp, replay_name)
	end,
})