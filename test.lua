-- For testing purposes only.
-- This will immediately start recording around a player when they join,
-- then after a few seconds stop and replay it.

local Box = modlib.mod.require("box")
local Recording = modlib.mod.require("recording")
local Replay = modlib.mod.require("replay")

local path = core.get_worldpath() .. "/recordings/test.rec"

core.register_on_joinplayer(function(player)
	local f = assert(io.open(path, "wb"))
	local pos = player:get_pos():round()
	local box = Box.cube(20):offset(pos)
	local recording = Recording.new(box, f)
	recording:start()
    local pname = player:get_player_name()
    core.after(1, function()
        core.set_node(player:get_pos(), {name = "default:dirt"})
    end)
    core.after(2, function()
        core.set_node(player:get_pos(), {name = "default:stone"})
    end)
    core.after(10, function()
        core.chat_send_player(pname, "Stopping & replaying recording.")
        recording:stop()
        recording:close()
        local file = assert(io.open(path, "rb"))
        local replay = Replay.new(box.min, file)
        replay:start()
    end)
end)
