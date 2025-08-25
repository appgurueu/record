-- 3d range of (integer) positions. Both corners are included.

local Box = {}
Box.__index = Box

function Box.new(min, max)
	min = vector.copy(min)
	max = vector.copy(max)
	return setmetatable({
		min = min:combine(max, math.min),
		max = max:combine(min, math.max)
	}, Box)
end

function Box.from_extents(extents)
	return Box.new(vector.new(0, 0, 0), extents - vector.new(1, 1, 1))
end

function Box.cube(radius)
	return setmetatable({
		min = vector.new(-radius, -radius, -radius),
		max = vector.new(radius, radius, radius),
	}, Box)
end

function Box:offset(by)
	return Box.new(self.min + by, self.max + by)
end

function Box:scale(scalar)
	return Box.new(self.min * scalar, self.max * scalar)
end

function Box:unpack()
	return self.min, self.max
end

function Box:extents()
	return (self.max - self.min):offset(1, 1, 1)
end

function Box:intersection(other)
	local min = self.min:combine(other.min, math.max)
	local max = self.max:combine(other.max, math.min)
	if min.x > max.x or min.y > max.y or min.z > max.z then
		return
	end
	return Box.new(min, max)
end

function Box:__equals(other)
	return self.min == other.min and self.max == other.max
end

function Box:__tostring()
	return "(" .. tostring(self.min) .. ", " .. tostring(self.max) .. ")"
end

return Box
