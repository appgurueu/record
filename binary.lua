-- Some utilities for dealing with little endian binary data

local binary = {}

function binary.pack_u32(n)
	return string.char(
		bit.band(n, 0xFF),
		bit.band(bit.rshift(n, 8), 0xFF),
		bit.band(bit.rshift(n, 16), 0xFF),
		bit.band(bit.rshift(n, 24), 0xFF)
	)
end

function binary.unpack_u32(str)
	local a, b, c, d = str:byte(1, 4)
	return a + bit.lshift(b, 8) + bit.lshift(c, 16) + bit.lshift(d, 24)
end

function binary.pack_shorts(t)
	local shorts = {}
	for i = 1, #t do
		shorts[i] = string.char(bit.band(t[i], 0xFF), bit.rshift(t[i], 8)) -- little endian!
	end
	return table.concat(shorts)
end

function binary.unpack_shorts(str)
	local t = {}
	assert(#str % 2 == 0)
	for i = 1, #str / 2 do
		local lo, hi = str:byte(2*i - 1, 2*i)
		t[i] = lo + bit.rshift(hi, 8)
	end
	return t
end

function binary.pack_bytes(t)
	local bytes = {}
	for i = 1, #t do
		bytes[i] = string.char(t[i])
	end
	return table.concat(bytes)
end

function binary.unpack_bytes(str)
	local nums = {}
	for i = 1, #str do
		nums[i] = str:byte(i)
	end
	return nums
end

return binary
