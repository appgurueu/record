std = "lua51+luanti"

read_globals = {
    "modlib",
    "cmdlib",
    -- luacheck's luanti standard is slightly outdated
    core = {fields = {"objects_in_area"}},
}

globals = {
    "record",
}