local PATHFINDER_VERSION = {0, 0, 1}
local LOADED_VERSION = rawget(_G, "PATHFINDER_LIB_VERSION")

if LOADED_VERSION != nil then
	local numlength = max(#PATHFINDER_VERSION, #LOADED_VERSION);
	local outdated = false
	
	for i = 1,numlength 
		local num1 = PATHFINDER_VERSION[i]
		local num2 = LOADED_VERSION[i]
		-- We shouldn't be adding more numbers but just to make sure
		if num1 == nil then
			num1 = 0
		end
		if num2 == nil then
			num2 = 0
		end
		if num2 < num1 then
			// loaded version is outdated
			outdated = true
		elseif num1 < num2 then
			break
		end
	end
	if not outdated then
		return
	end
end

rawset(_G, "PATHFINDER_LIB_VERSION", PATHFINDER_VERSION)

local PathfindNode = {}

PathfindNode.Get = function(wp, key)
	if key == "camefrom" then
		return rawget(wp, key)
	elseif key == "nextnode" then
		return rawget(wp, key)
	elseif key == "nodedata" then
		return rawget(wp, key)
	/*elseif key == "heapindex" then
		return rawget(wp, key)*/
	elseif key == "hcost" then
		return rawget(wp, key)
	elseif key == "gcost" then
		return rawget(wp, key)
	end
end

PathfindNode.Set = function(wp, key, value)
	if key == "camefrom" and (type(value) == "nil" or getmetatable(value) == PathfindNode.Meta) then
		return rawset(wp, key, value)
	elseif key == "nextnode" and (type(value) == "nil" or getmetatable(value) == PathfindNode.Meta) then
		return rawset(wp, key, value)
	elseif key == "nodedata" then
		return rawset(wp, key, value)
	/*elseif key == "heapindex" and type(value) == "number" then
		return rawset(wp, key, value)*/
	elseif key == "hcost" and type(value) == "number" then
		return rawset(wp, key, value)
	elseif key == "gcost" and type(value) == "number" then
		return rawset(wp, key, value)
	end
end

PathfindNode.New = function(nodedata, camefrom)
	local node = {}
	node.nodedata = nodedata
	node.camefrom = camefrom
	node.nextnode = nil
	//node.heapindex = INT32_MAX
	node.hcost = 0
	node.gcost = 0
	setmetatable(node, PathfindNode.Meta)
	return node
end

PathfindNode.Meta = {
	__index = PathfindNode.Get,
	__newindex = PathfindNode.Set
}

PathfindNode.ClassMeta = {
	__call = function(class, ...)
		return PathfindNode.New(...)
	end
}

setmetatable(PathfindNode, PathfindNode.ClassMeta)

local function sort_heap(a, b)
	return a.hcost + a.gcost > b.hcost + b.gcost
end

local function K_ReconstructPath(dest_node)
	local path = {
		array = {},
		totaldist = 0
	}
	local current = dest_node
	while current != nil do
		table.insert(path.array, 1, current)
		current = current.camefrom
	end
	for i,n in ipairs(path.array) do
		if i != 1 then
			n.nextnode = path.array[i - 1]
		end
	end
	if dest_node != nil then
		path.totaldist = dest_node.gcost
	end
	return dest_node != nil, path
end

rawset(_G, "K_PathfindAStar", function(pathsetup)
	local success = false
	local singlenode = PathfindNode(pathsetup.start_wp)
	local path = {}
	if (pathsetup.finished(singlenode, pathsetup))
		success, path = K_ReconstructPath(singlenode)
		success = true
	else
		local openset = {}
		local closedset = {}
		local nodes = {}
		local newnode = PathfindNode(pathsetup.start_wp)
		newnode.hcost = pathsetup.get_heuristic(newnode.nodedata, pathsetup.end_wp)
		table.insert(openset, newnode)
		table.insert(nodes, newnode)
		table.sort(openset, sort_heap)
		while #openset > 0 do
			local current = table.remove(openset)
			if (pathsetup.finished(current, pathsetup))
				success, path = K_ReconstructPath(singlenode)
				break
			end
			closedset[current] = true
			
			local connectingnodes = pathsetup.get_next(current.nodedata)
			local connectingnodecosts = pathsetup.get_next_costs(current.nodedata)
			for i,n in ipairs(connectingnodes) do
				if not pathsetup.traverseable(current.nodedata, connectingnodes) then
					continue
				end
				local temp_cost = current.gcost + connectingnodecosts[i]
				local found = false
				local found_node = nil
				for j,n2 in ipairs(nodes) do
					if n2.nodedata == n then
						found = true
						found_node = n2
						break
					end
				end
				if found then
					if closedset[found_node] then
						continue
					elseif temp_cost < found_node.gcost then
						found_node.gcost = temp_cost
						found_node.camefrom = current
						table.sort(openset, sort_heap)
					end
				else
					newnode = PathfindNode(n, current)
					newnode.gcost = temp_cost
					newnode.hcost = pathsetup.get_heuristic(newnode.nodedata, pathsetup.end_wp)
					table.insert(openset, newnode)
					table.insert(nodes, newnode)
				end
			end
		end
	end
	return success, path
end)