-- ===== Ready functions =======================================================

local function default_ready()
	-- only run while in a level, not paused and not exiting a stage
	return (gamestate == GS_LEVEL 
			and not paused 
			and not (consoleplayer == nil) 
			and not (consoleplayer.mo == nil) 
			and (consoleplayer.playerstate == PST_LIVE) 
			and not (consoleplayer.exiting > 0) 
			and not (consoleplayer.spectating))
end

-- unexposted constants
local IF_ITEMOUT = 1<<1
local IF_EGGMANOUT = 1<<2

local function itemcheck() 
	return (default_ready() 
			and consoleplayer.itemflags & (IF_ITEMOUT|IF_EGGMANOUT) == 0 
			and consoleplayer.curshield == KSHIELD_NONE
			and leveltime > starttime) --and not consoleplayer.itemroulette.eggman
end

-- ===== Effects ===============================================================

/*cc_effects["demo"] = CCEffect.New("demo", function(t)
	print("This is a demo!")
end, default_ready)*/

cc_effects["giverings"] = CCEffect.New("giverings", function(t, count)
	consoleplayer.superring = $ + count
end, default_ready)

cc_effects["takerings"] = CCEffect.New("takerings", function(t, count)
	P_GivePlayerRings(consoleplayer, -count)
	S_StartSound(consoleplayer.mo, sfx_itemup)
end, default_ready)

cc_effects["changerandom"] = CCEffect.New("changerandom", function(t)
	local skin = skins[P_RandomKey(#skins)]
	while not (skin.valid) or (oldskin == skin) or not R_SkinUsable(consoleplayer, skin.name) do
		skin = skins[P_RandomKey(#skins)]
	end
	consoleplayer.mo.skin = skin.name
	R_SetPlayerSkin(consoleplayer, skin.name)
end, default_ready)

-- ===== Items =================================================================

local function GiveItem(player, item, count)
	K_StripItems(player)
	consoleplayer.itemtype = item
	consoleplayer.itemamount = count
	if item != KITEM_NONE then
		consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
	end
end

cc_effects["nothing"] = CCEffect.New("nothing", function(t)
	GiveItem(consoleplayer, KITEM_NONE, 0)
end, function() 
	return default_ready() and consoleplayer.itemtype != KITEM_NONE
end)

cc_effects["sneakers"] = CCEffect.New("sneakers", function(t)
	GiveItem(consoleplayer, KITEM_SNEAKER, 1)
end, function()
	return itemcheck()
end)

cc_effects["dualsneakers"] = CCEffect.New("dualsneakers", function(t)
	GiveItem(consoleplayer, KITEM_SNEAKER, 2)
end, function()
	return itemcheck()
end)

cc_effects["triplesneakers"] = CCEffect.New("triplesneakers", function(t)
	GiveItem(consoleplayer, KITEM_SNEAKER, 3)
end, function()
	return itemcheck()
end)

cc_effects["rocketsneakers"] = CCEffect.New("rocketsneakers", function(t)
	GiveItem(consoleplayer, KITEM_ROCKETSNEAKER, 1)
end, function()
	return itemcheck()
end)

cc_effects["invincibility"] = CCEffect.New("invincibility", function(t)
	GiveItem(consoleplayer, KITEM_INVINCIBILITY, 1)
end, function()
	return itemcheck()
end)

cc_effects["banana"] = CCEffect.New("banana", function(t)
	GiveItem(consoleplayer, KITEM_BANANA, 1)
end, function()
	return itemcheck()
end)

cc_effects["triplebanana"] = CCEffect.New("triplebanana", function(t)
	GiveItem(consoleplayer, KITEM_BANANA, 3)
end, function()
	return itemcheck()
end)

cc_effects["eggman"] = CCEffect.New("eggman", function(t)
	GiveItem(consoleplayer, KITEM_EGGMAN, 1)
end, function()
	return itemcheck()
end)

cc_effects["orbinaut"] = CCEffect.New("orbinaut", function(t)
	GiveItem(consoleplayer, KITEM_ORBINAUT, 1)
end, function()
	return itemcheck()
end)

cc_effects["tripleorbinaut"] = CCEffect.New("tripleorbinaut", function(t)
	GiveItem(consoleplayer, KITEM_ORBINAUT, 3)
end, function()
	return itemcheck()
end)

cc_effects["quadorbinaut"] = CCEffect.New("quadorbinaut", function(t)
	GiveItem(consoleplayer, KITEM_ORBINAUT, 4)
end, function()
	return itemcheck()
end)

cc_effects["jawz"] = CCEffect.New("jawz", function(t)
	GiveItem(consoleplayer, KITEM_JAWZ, 1)
end, function()
	return itemcheck()
end)

cc_effects["dualjawz"] = CCEffect.New("dualjawz", function(t)
	GiveItem(consoleplayer, KITEM_JAWZ, 2)
end, function()
	return itemcheck()
end)

cc_effects["mine"] = CCEffect.New("mine", function(t)
	GiveItem(consoleplayer, KITEM_MINE, 1)
end, function()
	return itemcheck()
end)

cc_effects["landmine"] = CCEffect.New("landmine", function(t)
	GiveItem(consoleplayer, KITEM_LANDMINE, 1)
end, function()
	return itemcheck()
end)

cc_effects["ballhog"] = CCEffect.New("ballhog", function(t)
	GiveItem(consoleplayer, KITEM_BALLHOG, 5)
end, function()
	return itemcheck()
end)

cc_effects["spb"] = CCEffect.New("spb", function(t)
	GiveItem(consoleplayer, KITEM_SPB, 1)
end, function()
	return itemcheck() and not K_IsSPBInGame()
end)

cc_effects["grow"] = CCEffect.New("grow", function(t)
	GiveItem(consoleplayer, KITEM_GROW, 1)
end, function() 
	return itemcheck()
end)

cc_effects["shrink"] = CCEffect.New("shrink", function(t)
	GiveItem(consoleplayer, KITEM_SHRINK, 1)
end, function() 
	return itemcheck()
end)

local shield_data = {
	[KITEM_LIGHTNINGSHIELD] = {
		item = KITEM_LIGHTNINGSHIELD,
		shield = KSHIELD_LIGHTNING,
		mobjtype = MT_LIGHTNINGSHIELD,
		sound = sfx_s3k41
	},
	[KITEM_BUBBLESHIELD] = {
		item = KITEM_BUBBLESHIELD,
		shield = KSHIELD_BUBBLE,
		mobjtype = MT_BUBBLESHIELD,
		sound = sfx_s3k3f
	},
	[KITEM_FLAMESHIELD] = {
		item = KITEM_FLAMESHIELD,
		shield = KSHIELD_FLAME,
		mobjtype = MT_FLAMESHIELD,
		sound = sfx_s3k3e
	},
}

local function SpawnShield(player, item)
	local shield_d = shield_data[item]
	if shield_d == nil then
		return
	end
	GiveItem(consoleplayer, shield_d.item, 1)
	player.curshield = shield_d.shield
	local shield = P_SpawnMobjFromMobj(player.mo, 0, 0, 0, shield_d.mobjtype)
	shield.destscale = (5*shield.destscale)>>2
	shield.scale = shield.destscale
	shield.target = player.mo
	S_StartSound(player.mo, shield_d.sound)
end

cc_effects["lightningshield"] = CCEffect.New("lightningshield", function(t)
	SpawnShield(consoleplayer, KITEM_LIGHTNINGSHIELD)
end, function()
	return itemcheck() and consoleplayer.curshield != KSHIELD_TOP
end)

cc_effects["bubbleshield"] = CCEffect.New("bubbleshield", function(t)
	SpawnShield(consoleplayer, KITEM_BUBBLESHIELD)
end, function()
	return itemcheck() and consoleplayer.curshield != KSHIELD_TOP
end)

cc_effects["flameshield"] = CCEffect.New("flameshield", function(t)
	SpawnShield(consoleplayer, KITEM_FLAMESHIELD)
end, function()
	return itemcheck() and consoleplayer.curshield != KSHIELD_TOP
end)

cc_effects["hyudoro"] = CCEffect.New("hyudoro", function(t)
	GiveItem(consoleplayer, KITEM_HYUDORO, 1)
end, function() 
	return itemcheck()
end)

cc_effects["pogospring"] = CCEffect.New("pogospring", function(t)
	GiveItem(consoleplayer, KITEM_POGOSPRING, 1)
end, function() 
	return itemcheck()
end)

cc_effects["superring"] = CCEffect.New("superring", function(t)
	GiveItem(consoleplayer, KITEM_SUPERRING, 1)
end, function() 
	return itemcheck()
end)

cc_effects["kitchensink"] = CCEffect.New("kitchensink", function(t)
	GiveItem(consoleplayer, KITEM_KITCHENSINK, 1)
end, function() 
	return itemcheck()
end)

cc_effects["bumper"] = CCEffect.New("bumper", function(t)
	GiveItem(consoleplayer, KITEM_DROPTARGET, 1)
end, function() 
	return itemcheck()
end)

cc_effects["gardentop"] = CCEffect.New("gardentop", function(t)
	GiveItem(consoleplayer, KITEM_GARDENTOP, 1)
	consoleplayer.curshield = KSHIELD_TOP
	local top = P_SpawnMobjFromMobj(consoleplayer.mo, 0, 0, 0, MT_GARDENTOP)
	
	top.extravalue1 = 0
	top.lastlook = 0
	//top.extravalue2 = sfx_None
	top.movedir = 0
	top.cusval = 1
	top.cvmem = 0
	
	top.flags = $ | MF_NOCLIPHEIGHT
	top.shadowscale = 0
	
	top.target = consoleplayer.mo
	consoleplayer.mo.target = top
	local itemscale = consoleplayer.itemscale
	local scale = mapobjectscale
	if itemscale == 1 then
		scale = FixedMul(2*FRACUNIT, mapobjectscale)
	elseif itemscale == 2 then
		scale = FixedMul(FRACUNIT/2, mapobjectscale)
	end
	top.destscale = scale
	top.scale = scale
	
	local a = ANGLE_MAX / 6
	for i=0,(6-1) do
		local spark = P_SpawnMobjFromMobj(top, 0, 0, 0, MT_GARDENTOPSPARK)
		spark.target = top
		spark.movedir = a * i
		spark.color = SKINCOLOR_ROBIN
		spark.spriteyscale = 3*FRACUNIT/4
	end
	
	local arrow = P_SpawnMobjFromMobj(top, 0, 0, 0, MT_GARDENTOPARROW)

	arrow.target = top

	arrow.destcale = 3*arrow.scale/4
	arrow.scale = arrow.destscale
end, function()
	return itemcheck() and consoleplayer.curshield != KSHIELD_TOP
end)

cc_effects["gachabom"] = CCEffect.New("gachabom", function(t)
	GiveItem(consoleplayer, KITEM_GACHABOM, 1)
end, function() 
	return itemcheck()
end)

cc_effects["triplegachabom"] = CCEffect.New("triplegachabom", function(t)
	GiveItem(consoleplayer, KITEM_GACHABOM, 3)
end, function() 
	return itemcheck()
end)

-- ===== Trigger effects =======================================================

cc_effects["triggersneaker"] = CCEffect.New("triggersneaker", function(t)
	K_DoSneaker(consoleplayer, 1)
	K_PlayBoostTaunt(consoleplayer.mo)
end, default_ready)

cc_effects["triggerbanana"] = CCEffect.New("triggerbanana", function(t)
	local banana = P_SpawnMobjFromMobj(consoleplayer.mo, consoleplayer.mo.momx, consoleplayer.mo.momy, consoleplayer.mo.momz, MT_BANANA)
	banana.destscale = mapobjectscale
	banana.scale = mapobjectscale
	banana.health = 1
end, default_ready)

cc_effects["triggergrow"] = CCEffect.New("triggergrow", function(t)
	if consoleplayer.growshrinktimer < 0 then
		S_StartSound(consoleplayer.mo, sfx_kc5a)
		consoleplayer.mo.scalespeed = mapobjectscale/TICRATE
		consoleplayer.mo.destscale = mapobjectscale
		if consoleplayer.pflags & PF_SHRINKACTIVE then
			consoleplayer.mo.destscale = FixedMul(consoleplayer.mo.destscale, FRACUNIT/2)
		end
		consoleplayer.growshrinktimer = 0
	end
	K_PlayPowerGloatSound(consoleplayer.mo)
	consoleplayer.mo.scalespeed = mapobjectscale/TICRATE
	consoleplayer.mo.destscale = FixedMul(consoleplayer.mo.destscale, 2*FRACUNIT)
	if consoleplayer.pflags & PF_SHRINKACTIVE then
		consoleplayer.mo.destscale = FixedMul(consoleplayer.mo.destscale, FRACUNIT/2)
	end
	if consoleplayer.invincibilitytimer == 0 then
		S_StartSound(consoleplayer.mo, sfx_alarmg)
	end
	
	consoleplayer.growshrinktimer = max(0, consoleplayer.growshrinktimer)
	local secs = 12
	/*if gametypes[gametype].rules & GTR_CLOSERPLAYERS then
		secs = 8
	end*/
	consoleplayer.growshrinktimer = $ + secs * TICRATE

	S_StartSound(consoleplayer.mo, sfx_kc5a)
end, function() 
	return default_ready() and consoleplayer.growshrinktimer == 0
end)

cc_effects["triggershrink"] = CCEffect.New("triggershrink", function(t)
	consoleplayer.growshrinktimer = $ - FixedInt(FRACUNIT*5*TICRATE)
	S_StartSound(consoleplayer.mo, sfx_kc59)
	consoleplayer.mo.scalespeed = mapobjectscale/TICRATE
	consoleplayer.mo.destscale = FixedMul(mapobjectscale, FRACUNIT/2)

	if consoleplayer.pflags & PF_SHRINKACTIVE then
		consoleplayer.mo.destscale = FixedMul(consoleplayer.mo.destscale, FRACUNIT/2)
	end
end, function() 
	return default_ready() and consoleplayer.growshrinktimer == 0
end)

cc_effects["eggmark"] = CCEffect.New("eggmark", function(t)
	K_AddHitLag(consoleplayer.mo, 5, false)
	K_DropItems(consoleplayer)
	consoleplayer.eggmanexplode = 6*TICRATE
	S_StartSound(consoleplayer.mo, sfx_itrole)
end, default_ready)

cc_effects["spbattack"] = CCEffect.New("spbattack", function(t)
	local wp = K_GetClosestWaypointToMobj(consoleplayer.mo)
	if wp != nil then
		wp = wp.prevwaypoints[1] // ensure we are behind the player
	end
	while wp != nil and P_AproxDistance(consoleplayer.mo.x - wp.mobj.x, consoleplayer.mo.y - wp.mobj.y) < 4096 do
		wp = wp.prevwaypoints[1]
	end
	local x, y, z = 0, 0, 0
	if wp == nil then
		local dir_x = cos(consoleplayer.mo.angle)
		local dir_y = sin(consoleplayer.mo.angle)
		x = consoleplayer.mo.x + FixedMul(-(dir_x * 4096), mapobjectscale)
		y = consoleplayer.mo.y + FixedMul(-(dir_y * 4096), mapobjectscale)
		z = consoleplayer.mo.z + FixedMul(consoleplayer.mo.height/2, mapobjectscale)
	else
		x = wp.mobj.x
		y = wp.mobj.y
		z = wp.mobj.z
	end
	SpawnSPB(x, y, z, consoleplayer)
end, function()
	return itemcheck() and not K_IsSPBInGame()
end)

cc_effects["invertcontrols"] = CCEffect.New("invertcontrols", function(t)
	// dummy function as the hook runs too late
	--consoleplayer.cmd.turning = -consoleplayer.cmd.turning
	--consoleplayer.cmd.aiming = -consoleplayer.cmd.aiming
end, default_ready, 15 * TICRATE, "INVCICON")

cc_effects["swapbuttons"] = CCEffect.New("swapbuttons", function(t)
	consoleplayer.cmd.forwardmove = -consoleplayer.cmd.forwardmove
end, default_ready, 15 * TICRATE, "SWBTICON")

cc_effects["ringlock"] = CCEffect.New("ringlock", function(t)
	// dummy function as the hook runs too early
end, function()
	if spb_timer != 0 then
		return false, "Can't activate ring lock during S.P.B attack"
	end
	return default_ready()
end, 15 * TICRATE)

-- ===== Extras ================================================================

cc_effects["remotecontrol"] = CCEffect.New("remotecontrol", function(t)
	// dummy function as the hook runs too late
end, default_ready, 15 * TICRATE, "RMCTICON")

cc_effects["playerlapplus"] = CCEffect.New("playerlapplus", function(t)
	consoleplayer.laps = $ + 1
end, default_ready)

cc_effects["playerlapminus"] = CCEffect.New("playerlapminus", function(t)
	consoleplayer.laps = $ - 1
end, default_ready)

-- ===== LUA HOOKS =============================================================

local function on_map_changed(mapnum)
	spb_timer = 0
end

addHook("MapChange", on_map_changed)

local function on_player_think(player)
	if cc_running_effects["ringlock"] != nil and cc_running_effects["ringlock"]["was_ready"] then
		player.pflags = $ | PF_RINGLOCK // No rings for you :3c
	end
end

addHook("PlayerThink", on_player_think)

local BT_LOOKBACK = 1<<5
local direction_lock = 0
local last_delta = 0

local start_wp = nil
local start_marker = nil
local end_wp = nil
local end_marker = nil
local spawned = false

local function on_player_cmd(player, cmd)
	if cc_running_effects["invertcontrols"] != nil and cc_running_effects["invertcontrols"]["was_ready"] then
		cmd.aiming = -cmd.aiming
		cmd.turning = -cmd.turning
	end
	if cc_running_effects["remotecontrol"] != nil and cc_running_effects["remotecontrol"]["was_ready"] then
		cmd.forwardmove = 50
		cmd.turning = 0
		cmd.throwdir = 0
		cmd.aiming = 0
		cmd.buttons = cmd.buttons & (BT_ATTACK|BT_LOOKBACK)
		local waypoint = K_GetBestWaypointForMobj(consoleplayer.mo)
		if waypoint == nil then
			waypoint = K_GetClosestWaypointToMobj(consoleplayer.mo)
			--print("Failed to get best, try closest")
		end
		if waypoint == K_GetFinishLineWaypoint() then
			waypoint = waypoint.nextwaypoints[1]
		end
		if waypoint != nil
			start_wp = waypoint.nextwaypoints[1]
			local success, path = K_PathfindToWaypoint(waypoint.nextwaypoints[1], K_GetFinishLineWaypoint(), consoleplayer.tripwirepass != 0, false)
			local next_waypoint = nil
			if success then
				--print(#path.array)
				if #path.array > 1 then
					next_waypoint = path.array[2].nodedata
					--print("following path")
				elseif #waypoint.nextwaypoints > 0
					next_waypoint = waypoint.nextwaypoints[1]
					--print("no path")
				else
					next_waypoint = K_GetFinishLineWaypoint()
					--print("no next, assuming finish")
				end
				next_waypoint = next_waypoint.nextwaypoints[1]
				local dest_angle = R_PointToAngle2(consoleplayer.mo.x, consoleplayer.mo.y, next_waypoint.mobj.x, next_waypoint.mobj.y)
				local delta = dest_angle - consoleplayer.mo.angle
				local delta_rate = FixedDiv((180 * FRACUNIT) - AngleFixed(delta), 180 * FRACUNIT)
				if abs(delta) < 3*ANG1 then
					delta_rate = 0
				end
				cmd.turning = max(-800, min(800, (delta_rate * 800) / FRACUNIT))
				if delta > 5*ANG1 then
					cmd.buttons = $ | BT_DRIFT
				end
				end_wp = next_waypoint
			end
		end
	end
end

addHook("PlayerCmd", on_player_cmd)