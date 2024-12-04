local WAYPOINT_VERSION = {0, 0, 1}
local LOADED_VERSION = rawget(_G, "WAYPOINT_LIB_VERSION")

if LOADED_VERSION != nil then
	local numlength = max(#WAYPOINT_VERSION, #LOADED_VERSION);
	local outdated = false
	
	for i = 1,numlength 
		local num1 = WAYPOINT_VERSION[i]
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

rawset(_G, "WAYPOINT_LIB_VERSION", WAYPOINT_VERSION)

local Waypoint = {}

Waypoint.Get = function(wp, key)
	if key == "mobj" then
		return rawget(wp, key)
	elseif key == "nextwaypoints" then
		return rawget(wp, key)
	elseif key == "prevwaypoints" then
		return rawget(wp, key)
	elseif key == "nextwaypointsdistances" then
		return rawget(wp, key)
	elseif key == "prevwaypointsdistances" then
		return rawget(wp, key)
	end
end

Waypoint.Set = function(wp, key, value)
	if key == "mobj" then
		if ((type(value) == "userdata" and userdataType(value) == "mobj_t") 
				or type(value) == "nil") then
			rawset(wp, key, value)
		end
	end
end

Waypoint.New = function(mobj)
	local wp = {}
	wp.mobj = mobj
	wp.nextwaypoints = {}
	wp.prevwaypoints = {}
	wp.nextwaypointsdistances = {}
	wp.prevwaypointsdistances = {}
	setmetatable(wp, Waypoint.Meta)
	return wp
end

Waypoint.Meta = {
	__index = Waypoint.Get,
	__newindex = Waypoint.Set
}

Waypoint.ClassMeta = {
	__call = function(class, ...)
		return Waypoint.New(...)
	end
}

setmetatable(Waypoint, Waypoint.ClassMeta)

local waypoints = {}
local waypointheap = nil
local firstwaypoint = nil
local finishline = nil

rawset(_G, "K_GetFinishLineWaypoint", function()
	return finishline
end)

rawset(_G, "K_GetWaypointIsFinishline", function(waypoint)
	if waypoint == nil or not getmetatable(waypoint) == Waypoint.Meta or waypoint.mobj == nil or not waypoint.mobj.valid then
		return false
	end
	return waypoint.mobj.extravalue2 == 1
end)

rawset(_G, "K_GetWaypointIsShortcut", function(waypoint)
	if waypoint == nil or not getmetatable(waypoint) == Waypoint.Meta or waypoint.mobj == nil or not waypoint.mobj.valid then
		return false
	end
	return waypoint.mobj.lastlook == 1
end)

rawset(_G, "K_GetWaypointIsEnabled", function(waypoint)
	if waypoint == nil or not getmetatable(waypoint) == Waypoint.Meta or waypoint.mobj == nil or not waypoint.mobj.valid then
		return false
	end
	return waypoint.mobj.extravalue1 == 1
end)

rawset(_G, "K_GetWaypointIsSpawnpoint", function(waypoint)
	if waypoint == nil or not getmetatable(waypoint) == Waypoint.Meta or waypoint.mobj == nil or not waypoint.mobj.valid then
		return false
	end
	return waypoint.mobj.reactiontime == 1
end)

rawset(_G, "K_GetWaypointIsOnLine", function(waypoint)
	local x = waypoint.mobj.x;
	local y = waypoint.mobj.y;

	for i,line in ipairs(waypoint.mobj.subsector.sector.lines) do
		local p_x, p_y = P_ClosestPointOnLine(x, y, line)
		if (x == p_x and y == p_y) then
			return true
		end
	end

	return false
end)

rawset(_G, "K_GetWaypointNextID", function(waypoint)
	if waypoint == nil or not getmetatable(waypoint) == Waypoint.Meta or waypoint.mobj == nil or not waypoint.mobj.valid then
		return -1
	end
	return waypoint.mobj.threshold
end)

rawset(_G, "K_GetWaypointID", function(waypoint)
	if waypoint == nil or not getmetatable(waypoint) == Waypoint.Meta or waypoint.mobj == nil or not waypoint.mobj.valid then
		return -1
	end
	return waypoint.mobj.movecount
end)

rawset(_G, "K_GetWaypointFromID", function(waypointID)
	for i,wp in ipairs(waypointheap) do
		if K_GetWaypointID(wp) == waypointID then
			return wp
		end
	end
	return nil
end)

rawset(_G, "K_GetClosestWaypointToMobj", function(mobj)
	if mobj == nil or not mobj.valid then
		return nil
	end
	local x, y, z = mobj.x / FRACUNIT, mobj.y / FRACUNIT, mobj.z / FRACUNIT
	local closestwaypoint = nil
	local closestdist = INT32_MAX
	for i,wp in ipairs(waypointheap) do
		local checkdist = P_AproxDistance(x - (wp.mobj.x / FRACUNIT), y - (wp.mobj.y / FRACUNIT))
		checkdist = P_AproxDistance(checkdist, z - (wp.mobj.z / FRACUNIT))
		if (checkdist < closestdist) then
			closestwaypoint = wp
			closestdist = checkdist
		end
	end
	return closestwaypoint
end)

local function K_CompareOverlappingWaypoint(checkwaypoint, bestwaypoint, bestfinddist)
	local useshortcuts = false
	local huntbackwards = false
	local pathfindsuccess = false
	local pathtofinish = {}

	if (K_GetWaypointIsShortcut(bestwaypoint) == false
		and K_GetWaypointIsShortcut(checkwaypoint) == true) then
		// If it's a shortcut, don't use it.
		return;
	end
	pathfindsuccess, pathtofinish = K_PathfindToWaypoint(checkwaypoint, finishline, useshortcuts, huntbackwards)

	if (pathfindsuccess == true) then
		if ((pathtofinish.totaldist) < bestfinddist) then
			bestwaypoint = checkwaypoint
			bestfinddist = pathtofinish.totaldist
		end
	end
	return bestwaypoint, bestfinddist
end

rawset(_G, "K_GetBestWaypointForMobj", function(mobj, hint)
	if mobj == nil or not mobj.valid then
		return nil
	end
	local bestwaypoint = nil
	local closestdist = INT32_MAX
	local bestfindist = INT32_MAX
	local x, y, z = mobj.x / FRACUNIT, mobj.y / FRACUNIT, mobj.z / FRACUNIT
	
	local sort_waypoint = function(wp)
		if not K_GetWaypointIsEnabled(wp) then
			return bestwaypoint, closestdist, bestfindist
		end
		local checkdist = P_AproxDistance(x - (wp.mobj.x / FRACUNIT), y - (wp.mobj.y / FRACUNIT))
		local zMultiplier = 4
		if hint != nil then
			local connected = wp == hint
			if (not connected and #hint.nextwaypoints > 0) then
				for i,n_wp in ipairs(hint.nextwaypoints) do
					if n_wp == wp then
						connected = true
						break
					end
				end
			end
			if (not connected and #hint.prevwaypoints > 0) then
				for i,p_wp in ipairs(hint.prevwaypoints) do
					if p_wp == wp then
						connected = true
						break
					end
				end
			end
			
			if connected then
				zMultiplier = 0
			end
		end

		if (zMultiplier > 0) then
			checkdist = P_AproxDistance(checkdist, (z - (wp.mobj.z / FRACUNIT)) * zMultiplier)
		end
		
		local rad = (wp.mobj.radius / FRACUNIT)
		if (closestdist <= rad and checkdist <= rad and finishline != nil) then
			if (not P_CheckSight(mobj, wp.mobj)) then
				// Save sight checks when all of the other checks pass, so we only do it if we have to
				return bestwaypoint, closestdist, bestfindist
			end

			// If the mobj is touching multiple waypoints at once,
			// then solve ties by taking the one closest to the finish line.
			// Prevents position from flickering wildly when taking turns.

			// For the first couple overlapping, check the previous best too.
			if (bestfindist == INT32_MAX) then
				K_CompareOverlappingWaypoint(bestwaypoint, bestwaypoint, bestfindist)
			end

			bestwaypoint, bestfindist = K_CompareOverlappingWaypoint(wp, bestwaypoint, bestfindist)
		elseif (checkdist < closestdist and bestfindist == INT32_MAX)
			if (not P_CheckSight(mobj, wp.mobj))
				// Save sight checks when all of the other checks pass, so we only do it if we have to
				return bestwaypoint, closestdist, bestfindist
			end
			bestwaypoint = wp
			closestdist = checkdist
		end
		return bestwaypoint, closestdist, bestfindist
	end
	
	if (hint != nil) then
		sort_waypoint(hint)
	end
	
	for i,wp in ipairs(waypointheap) do
		sort_waypoint(wp)
	end
	return bestwaypoint
end)

rawset(_G, "K_GetWaypointHeapIndex", function(waypoint)
	for i,wp in ipairs(waypointheap) do
		if wp == waypoint then
			return i
		end
	end
	return -1
end)

rawset(_G, "K_GetNumWaypoints", function()
	return #waypointheap
end)

rawset(_G, "K_GetWaypointFromIndex", function(waypointindex)
	return waypointheap[waypointindex]
end)

rawset(_G, "K_DistanceBetweenWaypoints", function(waypoint1, waypoint2)
	assert(waypoint1 != nil and waypoint2 != nil, "Can only calculate distance of non-null waypoints")
	local xydist = P_AproxDistance(waypoint1.mobj.x - waypoint2.mobj.x, waypoint1.mobj.y - waypoint2.mobj.y)
	local xyzdist = P_AproxDistance(xydist, waypoint1.mobj.z - waypoint2.mobj.z)
	return xyzdist >> FRACBITS
end)

rawset(_G, "K_PathfindToWaypoint", function(sourcewaypoint, destinationwaypoint, useshortcuts, huntbackwards)
	local pathfound = false
	local path = {}
	if (sourcewaypoint == nil) then
		print("NULL source waypoint in K_PathfindToWaypoint")
	elseif (destinationwaypoint == nil) then
		print("NULL destination waypoint in K_PathfindToWaypoint")
	elseif (not huntbackwards == false and (#sourcewaypoint.nextwaypoints == 0))
		or (huntbackwards and (#sourcewaypoint.prevwaypoints == 0)) then
		print("source waypoint in K_PathfindToWaypoint has no next waypoint")
	elseif (not huntbackwards and (#destinationwaypoint.prevwaypoints == 0))
		or (huntbackwards and (#destinationwaypoint.nextwaypoints == 0)) then
		print("desitination waypoint in K_PathfindToWaypoint has no next waypoint")
	else
		local pathsetup = {
			get_next = function(wp)
				return wp.nextwaypoints
			end,
			get_next_costs = function(wp)
				return wp.nextwaypointsdistances
			end,
			get_heuristic = K_DistanceBetweenWaypoints,
			traverseable = function(wp, p_wp)
				return K_GetWaypointIsEnabled(wp) and (not K_GetWaypointIsShortcut(wp) or K_GetWaypointIsShortcut(p_wp))
			end,
			finished = function(node, setup)
				return node.nodedata == setup.end_wp
			end,
			end_wp = destinationwaypoint,
			start_wp = sourcewaypoint
		}
		if huntbackwards then
			pathsetup.get_next = function(wp)
				return wp.prevwaypoints
			end
			pathsetup.get_next_costs = function(wp)
				return wp.prevwaypointsdistances
			end
		end
		
		if useshortcuts then
			pathsetup.traverseable = function(wp, p_wp)
				return K_GetWaypointIsEnabled(wp)
			end
		end
		
		pathfound, path = K_PathfindAStar(pathsetup)
	end
	return pathfound, path
end)

rawset(_G, "K_CheckWaypointForMobj", function(waypoint, mobj)
	if mobj == nil or not mobj.valid or mobj.type != MT_WAYPOINT or waypoint == nil then
		return false
	end
	return waypoint.mobj == mobj
end)

rawset(_G, "K_SearchWaypointHeap", function(check, value)
	if check == nil or waypointheap == nil then
		return
	end
	for i,wp in ipairs(waypointheap) do
		if check(wp, value) then
			return wp
		end
	end
	return nil
end)

rawset(_G, "K_SearchWaypointHeapForMobj", function(mobj)
	if mobj == nil or not mobj.valid or mobj.type != MT_WAYPOINT then
		return
	end
	return K_SearchWaypointHeap(K_CheckWaypointForMobj, mobj)
end)

local function K_MakeWaypoint(mobj)
	if mobj == nil or not mobj.valid or mobj.type != MT_WAYPOINT then
		return
	end
	local wp = Waypoint(mobj)
	table.insert(waypointheap, wp)
	if (mobj.threshold != mobj.movecount) then
		local current = waypoints[1]
		while current != nil do
			if (mobj.threshold == current.movecount) then
				table.insert(wp.nextwaypoints, {})
				table.insert(wp.nextwaypointsdistances, INT32_MAX)
			end
			current = current.tracer
		end
	end
	return wp
end

local function K_SetupWaypoint(mobj)
	if mobj == nil or not mobj.valid or mobj.type != MT_WAYPOINT then
		return
	end
	local this_waypoint = nil
	if (firstwaypoint != nil) then
		this_waypoint = K_SearchWaypointHeapForMobj(mobj)
	end
	
	if this_waypoint == nil then
		this_waypoint = K_MakeWaypoint(mobj)
		if this_waypoint != nil then
			if firstwaypoint == nil then
				firstwaypoint = this_waypoint
			end
			
			if K_GetWaypointIsFinishline(this_waypoint) and finishline == nil then
				finishline = this_waypoint
			end
			local nextindex = 1
			if #this_waypoint.nextwaypoints > 0 then
				local next_waypoint = nil
				local current = waypoints[1]
				while current != nil do
					if (mobj.threshold == current.movecount) then
						next_waypoint = K_SetupWaypoint(current)
						this_waypoint.nextwaypoints[nextindex] = next_waypoint
						this_waypoint.nextwaypointsdistances[nextindex] = K_DistanceBetweenWaypoints(this_waypoint, next_waypoint)
						next_waypoint.prevwaypoints[#next_waypoint.prevwaypoints + 1] = this_waypoint
						next_waypoint.prevwaypointsdistances[#next_waypoint.prevwaypoints] = this_waypoint.nextwaypointsdistances[nextindex]
						nextindex = $ + 1
					end
					current = current.tracer
				end
			end
		end
	end
	
	return this_waypoint
end

local function K_SetupWaypointList()
	waypointheap = {}
	local current = waypoints[1]
	local count = 1
	while current != nil do
		current.cusval = #waypointheap
		K_SetupWaypoint(current)
		current = current.tracer
		count = $ + 1
	end
end

local function on_map_changed(mapnum)
	waypoints = {}
	firstwaypoint = nil
	finishline = nil
end

addHook("MapChange", on_map_changed)

local function on_map_loaded(mapnum)
	local temp = {}
	for i,wp in ipairs(waypoints) do
		table.insert(temp, wp)
	end
	waypoints = {}
	for i=1,#temp do
		local added = false
		for j,wp in ipairs(waypoints) do
			if wp == temp[i].tracer
				table.insert(waypoints, j, temp[i])
				added = true
				break
			end
		end
		if not added then
			table.insert(waypoints, temp[i])
		end
	end
	K_SetupWaypointList()
end

addHook("MapLoad", on_map_loaded)

local function on_waypoint_spawned(mobj, mthing)
	table.insert(waypoints, mobj)
end

addHook("MapThingSpawn", on_waypoint_spawned, MT_WAYPOINT)