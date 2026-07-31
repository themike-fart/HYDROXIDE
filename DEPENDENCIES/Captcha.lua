--massive credits to https://github.com/krakow10/rbx_mesh
--https://github.com/krakow10/rbx_mesh/tree/master/src/union_physics/v8

local EncodingService = cloneref(game:GetService("EncodingService"))

local CSGPHS8 = {}
local newVector3 = Vector3.new
local createTable = table.create
local min = math.min
local max = math.max

local function u32(r)
	local value = buffer.readu32(r.data, r.at)
	r.at += 4
	return value
end

local function f32(r)
	local value = buffer.readf32(r.data, r.at)
	r.at += 4
	return value
end

local function vec3(r)
	return newVector3(f32(r), f32(r), f32(r))
end

local function readRawHulls(r)
	local faceRangeCount = u32(r)
	local faceRanges = createTable(faceRangeCount)
	for i = 1, faceRangeCount do
		faceRanges[i] = u32(r)
	end

	local faceValueCount = faceRanges[#faceRanges] or 0
	local faces = createTable(faceValueCount)
	for i = 1, faceValueCount do
		faces[i] = u32(r)
	end

	local posRangeCount = u32(r)
	local posRanges = createTable(posRangeCount)
	for i = 1, posRangeCount do
		posRanges[i] = u32(r)
	end

	local positionValueCount = posRanges[#posRanges] or 0
	local positions = createTable(positionValueCount)
	for i = 1, positionValueCount do
		positions[i] = f32(r)
	end

	return faceRanges, faces, posRanges, positions
end

local function bitReader(data, at, byteCount, bitCount)
	local cache, cached = 0, 0
	local finish = at + byteCount

	return function(count)
		local value = 0
		while count > 0 do
			if cached == 0 then
				cache = buffer.readu32(data, at)
				at += 4
				cached = min(bitCount, 32)
				bitCount -= cached
			end

			local take = min(count, cached)
			cached -= take
			value = value * 2 ^ take + bit32.extract(cache, cached, take)
			count -= take
		end
		return value
	end
end

local function decodeFaces(data, at, byteCount, bitCount, hullCount, faceCount)
	local bits = bitReader(data, at, byteCount, bitCount)
	local adjacency = createTable(faceCount * 3, -3)
	local indices = createTable(faceCount * 3, 0)
	local faceRanges, posRanges = { 0 }, { 0 }
	local currentFace, vertexOffset = 0, 0

	local function nextEdge(edge)
		return math.floor(edge / 3) * 3 + (edge + 1) % 3
	end

	local function prevEdge(edge)
		return math.floor(edge / 3) * 3 + (edge + 2) % 3
	end

	local function zipBoundary(current)
		while adjacency[current + 1] == -2 do
			local candidate = nextEdge(current)
			while adjacency[candidate + 1] >= 0 do
				candidate = nextEdge(adjacency[candidate + 1])
			end
			if adjacency[candidate + 1] ~= -1 then
				break
			end

			adjacency[current + 1], adjacency[candidate + 1] = candidate, current
			current = prevEdge(current)
			local previous = current
			local candidatePrevious = prevEdge(candidate)
			indices[prevEdge(current) + 1] = indices[candidatePrevious + 1]

			local connected = adjacency[current + 1]
			while connected >= 0 and candidate ~= previous do
				previous = prevEdge(connected)
				indices[prevEdge(previous) + 1] = indices[candidatePrevious + 1]
				connected = adjacency[previous + 1]
			end
			while adjacency[current + 1] >= 0 and current ~= candidate do
				current = prevEdge(adjacency[current + 1])
			end
		end
	end

	for _ = 1, hullCount do
		local firstEdge = currentFace * 3
		adjacency[firstEdge + 1], adjacency[firstEdge + 2], adjacency[firstEdge + 3] = -1, -3, -1
		indices[firstEdge + 1], indices[firstEdge + 2], indices[firstEdge + 3] = 0, 1, 2
		currentFace += 1
		local vertexCount = 3

		local decode
		function decode(cursor)
			while true do
				local edge0 = currentFace * 3
				local edge1, edge2 = edge0 + 1, edge0 + 2
				adjacency[edge0 + 1], adjacency[edge1 + 1], adjacency[edge2 + 1] = cursor, -3, -3
				currentFace += 1
				adjacency[cursor + 1] = edge0
				indices[edge1 + 1] = indices[prevEdge(cursor) + 1]
				indices[edge2 + 1] = indices[nextEdge(cursor) + 1]
				cursor = edge1

				local symbol
				if bits(1) == 0 then
					symbol = 0 -- Continue
				else
					symbol = bits(2) + 1 -- Split, Left, Right, End
				end

				if symbol == 0 then
					indices[edge0 + 1] = vertexCount
					adjacency[nextEdge(cursor) + 1] = -1
					vertexCount += 1
				elseif symbol == 1 then
					decode(cursor)
					cursor = nextEdge(cursor)
				elseif symbol == 2 then
					adjacency[cursor + 1] = -2
					cursor = nextEdge(cursor)
				elseif symbol == 3 then
					local next = nextEdge(cursor)
					adjacency[next + 1] = -2
					zipBoundary(next)
				else
					adjacency[cursor + 1] = -2
					local next = nextEdge(cursor)
					adjacency[next + 1] = -2
					zipBoundary(next)
					return
				end
			end
		end

		decode(firstEdge + 1)
		vertexOffset += vertexCount
		faceRanges[#faceRanges + 1] = currentFace * 3
		posRanges[#posRanges + 1] = vertexOffset * 3
	end

	return faceRanges, indices, posRanges
end

local function appendHulls(output, faceRanges, faces, posRanges, positions)
	for hullIndex = 1, min(#faceRanges, #posRanges) - 1 do
		local vertices = {}
		local minX, minY, minZ = math.huge, math.huge, math.huge
		local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

		for i = posRanges[hullIndex] + 1, posRanges[hullIndex + 1], 3 do
			local x, y, z = positions[i], positions[i + 1], positions[i + 2]
			vertices[#vertices + 1] = newVector3(x, y, z)
			minX, minY, minZ = min(minX, x), min(minY, y), min(minZ, z)
			maxX, maxY, maxZ = max(maxX, x), max(maxY, y), max(maxZ, z)
		end

		local triangles = {}
		for i = faceRanges[hullIndex] + 1, faceRanges[hullIndex + 1], 3 do
			triangles[#triangles + 1] = { faces[i] + 1, faces[i + 1] + 1, faces[i + 2] + 1 }
		end

		output[#output + 1] = {
			vertices = vertices,
			triangles = triangles,
			center = newVector3((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2),
			size = newVector3(maxX - minX, maxY - minY, maxZ - minZ),
			bounds = {
				min = newVector3(minX, minY, minZ),
				max = newVector3(maxX, maxY, maxZ),
			},
		}
	end
end

local function distance2(a, b)
	local x, y, z = a.X - b.X, a.Y - b.Y, a.Z - b.Z
	return x * x + y * y + z * z
end

local function makeGroup(hulls, hullIndices)
	local group = {
		hulls = createTable(#hullIndices),
		hullIndices = hullIndices,
	}
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

	for _, hullIndex in hullIndices do
		local hull = hulls[hullIndex]
		group.hulls[#group.hulls + 1] = hull
		minX = min(minX, hull.bounds.min.X)
		minY = min(minY, hull.bounds.min.Y)
		minZ = min(minZ, hull.bounds.min.Z)
		maxX = max(maxX, hull.bounds.max.X)
		maxY = max(maxY, hull.bounds.max.Y)
		maxZ = max(maxZ, hull.bounds.max.Z)
	end

	group.bounds = {
		min = newVector3(minX, minY, minZ),
		max = newVector3(maxX, maxY, maxZ),
	}
	group.center = newVector3((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
	group.size = newVector3(maxX - minX, maxY - minY, maxZ - minZ)
	return group
end

local function buildConnectedGroups(hulls, epsilon)
	local parents = createTable(#hulls)
	for i = 1, #hulls do
		parents[i] = i
	end

	local function find(index)
		local root = index
		while parents[root] ~= root do
			root = parents[root]
		end
		while parents[index] ~= index do
			local nextIndex = parents[index]
			parents[index] = root
			index = nextIndex
		end
		return root
	end

	local function overlaps(a, b)
		return a.bounds.max.X >= b.bounds.min.X - epsilon
			and b.bounds.max.X >= a.bounds.min.X - epsilon
			and a.bounds.max.Y >= b.bounds.min.Y - epsilon
			and b.bounds.max.Y >= a.bounds.min.Y - epsilon
			and a.bounds.max.Z >= b.bounds.min.Z - epsilon
			and b.bounds.max.Z >= a.bounds.min.Z - epsilon
	end

	for i = 1, #hulls - 1 do
		for j = i + 1, #hulls do
			if overlaps(hulls[i], hulls[j]) then
				local rootI, rootJ = find(i), find(j)
				if rootI ~= rootJ then
					parents[rootJ] = rootI
				end
			end
		end
	end

	local componentsByRoot = {}
	local components = {}
	for i = 1, #hulls do
		local root = find(i)
		local indices = componentsByRoot[root]
		if not indices then
			indices = {}
			componentsByRoot[root] = indices
			components[#components + 1] = indices
		end
		indices[#indices + 1] = i
	end

	local groups = createTable(#components)
	for i, indices in components do
		groups[i] = makeGroup(hulls, indices)
	end
	return groups
end

local function mergeExtraGroups(hulls, groups)
	table.sort(groups, function(a, b)
		return #a.hullIndices > #b.hullIndices
	end)
	local assignments = { {}, {} }
	for _, hullIndex in groups[1].hullIndices do
		assignments[1][#assignments[1] + 1] = hullIndex
	end
	for _, hullIndex in groups[2].hullIndices do
		assignments[2][#assignments[2] + 1] = hullIndex
	end

	local centers = { groups[1].center, groups[2].center }
	for i = 3, #groups do
		local target = if distance2(groups[i].center, centers[1]) <= distance2(groups[i].center, centers[2])
			then 1
			else 2
		for _, hullIndex in groups[i].hullIndices do
			assignments[target][#assignments[target] + 1] = hullIndex
		end
	end
	return {
		makeGroup(hulls, assignments[1]),
		makeGroup(hulls, assignments[2]),
	}
end

local function kMeansFallback(hulls)
	local farthestA, farthestB, farthestDistance = 1, 2, -1
	for i = 1, #hulls - 1 do
		for j = i + 1, #hulls do
			local distance = distance2(hulls[i].center, hulls[j].center)
			if distance > farthestDistance then
				farthestA, farthestB, farthestDistance = i, j, distance
			end
		end
	end

	local centers = { hulls[farthestA].center, hulls[farthestB].center }
	local assignments = createTable(#hulls, 0)
	for _ = 1, 50 do
		local changed = false
		local sums = {
			{ x = 0, y = 0, z = 0, count = 0 },
			{ x = 0, y = 0, z = 0, count = 0 },
		}
		for i, hull in hulls do
			local target = if distance2(hull.center, centers[1]) <= distance2(hull.center, centers[2]) then 1 else 2
			if assignments[i] ~= target then
				assignments[i], changed = target, true
			end
			local sum = sums[target]
			sum.x += hull.center.X
			sum.y += hull.center.Y
			sum.z += hull.center.Z
			sum.count += 1
		end
		for i, sum in sums do
			if sum.count > 0 then
				centers[i] = newVector3(sum.x / sum.count, sum.y / sum.count, sum.z / sum.count)
			end
		end
		if not changed then
			break
		end
	end

	local indices = { {}, {} }
	for i, target in assignments do
		indices[target][#indices[target] + 1] = i
	end
	return {
		makeGroup(hulls, indices[1]),
		makeGroup(hulls, indices[2]),
	}
end

function CSGPHS8.separateHulls(hulls)
	for _, epsilon in { 0.001, 0.0001, 0 } do
		local groups = buildConnectedGroups(hulls, epsilon)
		if #groups == 2 then
			return groups
		elseif #groups > 2 then
			return mergeExtraGroups(hulls, groups)
		end
	end

	return kMeansFallback(hulls)
end

local MOB_SIGNATURES = {
	{
		answer = "Golem",
		sizes = {
			{ 6.943143, 17.124934, 21.22445 },
			{ 10.667896, 18.130379, 21.711119 },
			{ 15.624678, 21.078442, 28.866095 },
		},
	},
	{
		answer = "Arocknid",
		sizes = {
			{ 6.219869, 11.576576, 11.729338 },
			{ 7.006574, 9.840628, 10.988729 },
			{ 6.529219, 11.507332, 11.690758 },
		},
	},
	{
		answer = "Evil Eye",
		sizes = {
			{ 4.927636, 6.635971, 11.829517 },
			{ 4.709663, 6.538452, 11.92519 },
			{ 4.927637, 6.635971, 11.829517 },
			{ 2.082426, 2.256552, 6.635970 },
		},
	},
	{
		answer = "Howler",
		sizes = {
			{ 3.138939, 6.833188, 6.838859 },
			{ 4.069223, 6.587232, 6.974196 },
		},
	},
	{
		answer = "Zombie Scroom",
		sizes = {
			{ 4.99328, 5.078253, 5.08746 },
			{ 4.82093, 4.855397, 4.899997 },
			{ 4.400224, 4.714131, 4.793147 },
		},
	},
}

local function classifyGroup(group)
	local dimensions = { group.size.X, group.size.Y, group.size.Z }
	table.sort(dimensions)
	local bestAnswer, bestScore = nil, math.huge

	for _, mob in MOB_SIGNATURES do
		for _, signature in mob.sizes do
			local score = 0
			for axis = 1, 3 do
				local ratio = dimensions[axis] / signature[axis]
				score += math.log(ratio) ^ 2
			end
			if score < bestScore then
				bestAnswer, bestScore = mob.answer, score
			end
		end
	end
	return bestAnswer, bestScore
end

function CSGPHS8.solve(result, unionCFrame, cameraCFrame)
	assert(#result.groups == 2, "need 2 mob groups, got " .. #result.groups)

	local visibleGroup, visibleIndex, smallestRayError = nil, nil, math.huge
	for index, group in result.groups do
		local worldCenter = unionCFrame:PointToWorldSpace(group.center)
		local offset = worldCenter - cameraCFrame.Position
		local depth = offset:Dot(cameraCFrame.LookVector)
		local rayError = math.huge
		if depth > 0 then
			local perpendicularSquared = max(offset:Dot(offset) - depth * depth, 0)
			rayError = math.sqrt(perpendicularSquared) / depth
		end
		if rayError < smallestRayError then
			visibleGroup, visibleIndex, smallestRayError = group, index, rayError
		end
	end

	assert(visibleGroup, "no mob infront of the camera")
	local answer, signatureScore = classifyGroup(visibleGroup)
	return answer, visibleIndex, smallestRayError, signatureScore
end

function CSGPHS8.decodePayload(payload, geomType)
	local r = { data = payload, at = 0 }
	local hullCount, positionCount, faceCount = u32(r), u32(r), u32(r)
	u32(r) -- first hull position count
	u32(r) -- first hull face count
	local rawLength = u32(r)
	local clersBitCount, clersLength = u32(r), u32(r)
	u32(r) -- positions byte length
	local bounds = { min = vec3(r), max = vec3(r) }

	local rawFaceRanges, rawFaces, rawPosRanges, rawPositions
	if rawLength ~= 0 then
		rawFaceRanges, rawFaces, rawPosRanges, rawPositions = readRawHulls(r)
	end

	local clersAt = r.at
	r.at += clersLength
	local positionValueCount = positionCount * 3
	local positions = createTable(positionValueCount)
	for i = 1, positionValueCount do
		positions[i] = f32(r)
	end

	local faceRanges, faces, posRanges = decodeFaces(payload, clersAt, clersLength, clersBitCount, hullCount, faceCount)

	local hulls = {}
	if rawFaceRanges then
		appendHulls(hulls, rawFaceRanges, rawFaces, rawPosRanges, rawPositions)
	end
	local rawHullCount = #hulls
	appendHulls(hulls, faceRanges, faces, posRanges, positions)
	local groups = CSGPHS8.separateHulls(hulls)

	return {
		version = 8,
		geomType = geomType,
		bounds = bounds,
		rawHullCount = rawHullCount,
		hulls = hulls,
		groups = groups,
		models = groups,
	}
end

function CSGPHS8.decode(rawData: string)
	local rawData: buffer = buffer.fromstring(rawData)

	assert(buffer.readstring(rawData, 0, 10) == "CSGPHS\8\0\0\0", "only v8 implemented")

	local compressed = buffer.create(buffer.len(rawData) - 12)
	buffer.copy(compressed, 0, rawData, 12)
	local payload = EncodingService:DecompressBuffer(compressed, Enum.CompressionAlgorithm.Zstd)
	return CSGPHS8.decodePayload(payload, buffer.readu8(rawData, 10))
end

return CSGPHS8