assert(modlib.version >= 104, "record requires modlib version rolling-104 or later")

-- Public API
record = {
    Recording = modlib.mod.require"recording",
    Replay = modlib.mod.require"replay",
}

modlib.mod.require"commands"

-- Quick and dirty in-game tests
modlib.mod.require"test"