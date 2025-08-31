std = "lua51+luanti"

read_globals = {
    "modlib",
    cmdlib = {
        fields = {
            register_chatcommand = {},
        },
    },
    -- luacheck's luanti standard is slightly outdated
    core = {
        fields = {
            objects_in_area = {},
            add_particle = {read_only = false},
            add_particlespawner = {read_only = false},
            delete_particlespawner = {read_only = false},
        },
    },
}

globals = {
    "record",
}