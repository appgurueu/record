local tex = "record_box_marker.png"
core.register_entity("record:box_marker", {
    initial_properties = {
        physical = false,
        pointable = false,
        static_save = false,
        backface_culling = false,
        visual = "cube",
        textures = {tex, tex, tex, tex, tex, tex},
    },
})

return function(box)
    local obj = assert(core.add_entity(box:center(), "record:box_marker"))
    obj:set_properties({
        visual_size = box:extents()
    })
    return obj
end