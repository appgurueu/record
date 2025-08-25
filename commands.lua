local Box = modlib.mod.require("box")
local Recording = modlib.mod.require("recording")
local Replay = modlib.mod.require("replay")

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

local player_data = {}

core.register_on_joinplayer(function(player)
	player_data[player:get_player_name()] = {
		pos1 = nil,
		pos2 = nil,
		recordings = {},
		replays = {},
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

core.register_chatcommand("record_pos", {
	params = "1|2",
	description = "Set pos 1 or pos 2 for recording",
	func = function(pname, param)
		local player = core.get_player_by_name(pname)
		if not player then
			return false, "You must be an online player to use this command."
		end
		local pos = player:get_pos():round()
		local pdata = player_data[pname]
		if param == "1" then
			pdata.pos1 = pos
			return true, "Set pos 1 to " .. minetest.pos_to_string(pos)
		end
		if param == "2" then
			pdata.pos2 = pos
			return true, "Set pos 2 to " .. minetest.pos_to_string(pos)
		end
	end,
})

core.register_chatcommand("record", {
	privs = {record = true},
	params = "<name>",
	description = "Record in the range between your set pos 1 and pos 2",
	func = function(pname, param)
		local pdata = player_data[pname]
		if not (pdata and pdata.pos1 and pdata.pos2) then
			return false, "You must set both pos 1 and pos 2 using /record_pos before starting a recording."
		end

		local recording_name = param
		if not recording_name:match"^[a-zA-Z0-9_%-]+$" then
			return false, "Recording name must consist of letters, digits, underscores and hyphens."
		end

		local path = get_recording_path(pname, recording_name)
		if file_exists(path) then
			return false, 'A recording called "' .. path .. '" already exists (use /record_delete to delete it).'
		end
		local f, err = io.open(path, "wb")
		if err then
			return false, err
		end
		local box = Box.new(pdata.pos1, pdata.pos2)
		local recording = Recording.new(box, f)
		recording:start()
		pdata.recordings[recording_name] = recording
	end
})

core.register_chatcommand("record_delete", {
	params = "<name>",
	description = "Delete a saved recording",
	func = function(pname, recording_name)
		local path = get_recording_path(pname, recording_name)
		local success, err = os.remove(path)
		if success then
			return true, 'Deleted recording "' .. recording_name .. '".'
		end
		return false, 'Error deleting recording "' .. recording_name .. '": ' .. err
	end,
})

core.register_chatcommand("record_stop", {
	params = "[name]",
	description = "Stop a currently running recording",
	func = function(pname, recording_name)
		local pdata = player_data[pname]
		if not pdata then
			return false, "You must be an online player to use this command."
		end
		local recordings = pdata.recordings
		if recording_name ~= "" then
			if not recordings[recording_name] then
				local recording_names = modlib.table.keys(recordings)
				return false, 'No recording called "' .. recording_name .. '". Valid names are: '
						.. table.concat(recording_names, ", ") .. "."
			end
		else
			recording_name = next(recordings)
			if not recording_name then
				return false, "No currently running recordings."
			end
			if next(recordings, recording_name) then
				local recording_names = modlib.table.keys(recordings)
				return false, "Multiple running recordings: " .. table.concat(recording_names, ", ")
						.. ", please choose one."
			end
		end
		local recording = recordings[recording_name]
		recording:stop()
		return true, 'Recording "' .. recording_name .. '" stopped.'
	end,
})

core.register_chatcommand("replay", {
	privs = {record = true},
	params = "<name>",
	description = "Replay a saved recording at your current position",
	func = function(pname, recording_name)
		local path = get_recording_path(pname, recording_name)
		local f, err = io.open(path, "rb")
		if not f then
			return false, 'Error opening recording "' .. recording_name .. '": ' .. err
		end
		local player = core.get_player_by_name(pname)
		if not player then
			return false, "You must be an online player to use this command."
		end
		local pos = player:get_pos()
		local replay = Replay.new(pos, f)
		replay:start()
		return true, 'Replaying recording "' .. recording_name .. '".'
	end,
})
