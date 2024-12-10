local spb_mobj = nil
rawset(_G, "spb_timer", 0);

local spb_curwaypoint = nil
local spb_curwaypointID = -1
local spb_destwaypoint = nil
local spb_target = nil

local function SpawnSPB(x, y, z, player)
	spb_mobj = P_SpawnMobj(x, y, z, MT_SPB)
	spb_mobj.angle = player.mo.angle
	spb_target = player.mo
	spb_timer = TICRATE * 60 -- 1 minute
end
rawset(_G, "SpawnSPB", SpawnSPB);

local function K_IsSPBInGame()
	// is there an SPB chasing anyone?
	if spbplace != -1 then
		return true
	end

	// do any players have an SPB in their item slot?
	local i;
	for i=0,15 do
		if players[i] == nil or players[i].spectator then
			continue
		end
		if players[i].itemtype == KITEM_SPB then
			return true
		end
	end


	// spbplace is still -1 until a fired SPB finds a target, so look for an in-map SPB just in case
	for mobj in mobjs.iterate() do
		if mobj.type == MT_SPB then
			return true
		end
	end
	
	return false;
end
rawset(_G, "K_IsSPBInGame", K_IsSPBInGame);

local function on_map_changed(mapnum)
	spb_mobj = nil
	spb_curwaypoint = nil
	spb_destwaypoint = nil
end

addHook("MapChange", on_map_changed)

local function on_player_think(player)
	if spb_mobj != nil and spb_mobj.valid and spb_mobj.tracer == player.mo and spb_mobj.extravalue1 > 0 then
		player.pflags = $ | PF_RINGLOCK // No rings for you :3c
	end
end

addHook("PlayerThink", on_player_think)

local function P_GetMobjFeet(mobj)
	if (mobj.eflags & MFE_VERTICALFLIP == MFE_VERTICALFLIP) then
		return mobj.z + mobj.height
	else 
		return mobj.z
	end
end

local function P_GetMobjGround(mobj)
	if (mobj.eflags & MFE_VERTICALFLIP == MFE_VERTICALFLIP) then
		return mobj.ceilingz
	else 
		return mobj.floorz
	end
end

local function K_GetKartGameSpeedScalar(value)
	// Easy = 81.25%
	// Normal = 100%
	// Hard = 118.75%
	// Nightmare = 137.5% ?!?!

	// WARNING: This value is used instead of directly checking game speed in some
	// cases, where hard difficulty breakpoints are needed, but compatibility with
	// the "4th Gear" cheat seemed relevant. Sorry about the weird indirection!
	// At the time of writing:
	// K_UpdateOffroad (G3+ double offroad penalty speed)
	// P_ButteredSlope (G1- Slope Assist)

	/*if (cv_4thgear.value && !netgame && (!demo.playback || !demo.netgame) && !modeattacking) then
		value = 3;
	end*/

	return ((13 + (3*value)) << FRACBITS) / 16;
end

local function K_GetKartSpeedFromStat(kartspeed)
	local xspd = (3*FRACUNIT)/64
	local g_cc = K_GetKartGameSpeedScalar(gamespeed) + xspd
	local k_speed = 148
	local finalspeed

	k_speed = $ + kartspeed*4 // 152 - 184

	finalspeed = FixedMul(k_speed<<14, g_cc)
	return finalspeed
end

local function K_MomentumAngle(mo)
	if (FixedHypot(mo.momx, mo.momy) > 6 * mo.scale) then
		return R_PointToAngle2(0, 0, mo.momx, mo.momy)
	else
		return mo.angle // default to facing angle, rather than 0
	end
end

local function K_MatchGenericExtraFlags(mo, master)
	mo.eflags = (mo.eflags & ~MFE_VERTICALFLIP)|(master.eflags & MFE_VERTICALFLIP)
	mo.flags2 = (mo.flags2 & ~MF2_OBJECTFLIP)|(master.flags2 & MF2_OBJECTFLIP)

	if (mo.eflags & MFE_VERTICALFLIP)
		mo.z = $ + master.height - FixedMul(master.scale, mo.height)
	end
	
	mo.renderflags = (mo.renderflags & ~RF_DONTDRAW) | (master.renderflags & RF_DONTDRAW)
end

local function SPB_DEFAULTSPEED()
	return FixedMul(mapobjectscale, K_GetKartSpeedFromStat(9) * 2)
end

local function SPB_Distance(spb, target)
	return P_AproxDistance(P_AproxDistance(spb.x - target.x, spb.y - target.y), spb.z - target.z)
end

local function SPB_Turn(dest_speed, dest_angle, src_speed, src_angle, lerp, src_sliptide)
	local delta = dest_angle - src_angle
	local dampen = FRACUNIT
	dampen = FixedDiv((180 * FRACUNIT) - AngleFixed(abs(delta)), 180 * FRACUNIT)
	src_speed = FixedMul(dest_speed, dampen)
	delta = FixedMul(delta, lerp)
	if src_sliptide != nil then
		local isSliptiding = (abs(delta) >= ANG1 * 3)
		local sliptide = 0

		if isSliptiding == true then
			if delta < 0 then
				sliptide = -1
			else
				sliptide = 1
			end
		end

		src_sliptide = sliptide
	end

	src_angle = $ + delta
	return src_speed, src_angle, src_sliptide
end

local function SetSPBSpeed(spb, xySpeed, zSpeed)
	spb.momx = FixedMul(FixedMul(xySpeed, cos(spb.angle)), cos(spb.movedir))
	spb.momy = FixedMul(FixedMul(xySpeed, sin(spb.angle)), cos(spb.movedir))
	spb.momz = FixedMul(zSpeed, sin(spb.movedir))
end

local function SpawnSPBDust(spb)
	// The easiest way to spawn a V shaped cone of dust from the SPB is simply to spawn 2 particles, and to both move them to the sides in opposite direction.
	local dust
	local sx, sy
	local sz = spb.floorz
	local sa = spb.angle - ANG1*60;

	if (spb.eflags & MFE_VERTICALFLIP) then
		sz = spb.ceilingz
	end

	if ((leveltime & 1) and abs(spb.z - sz) < FRACUNIT*64) then // Only every other frame. Also don't spawn it if we're way above the ground.
		// Determine spawning position next to the SPB:
		for i = 0,1 do
			sx = 96 * cos(sa)
			sy = 96 * sin(sa)

			dust = P_SpawnMobjFromMobj(spb, sx, sy, 0, MT_SPBDUST)
			dust.z = sz

			dust.momx = spb.momx/2
			dust.momy = spb.momy/2
			dust.momz = spb.momz/2 // Give some of the momentum to the dust

			P_SetScale(dust, spb.scale * 2)

			dust.color = SKINCOLOR_RED
			dust.colorized = true

			dust.angle = spb.angle - FixedAngle(FRACUNIT*90 - FRACUNIT*180*i) // The first one will spawn to the right of the spb, the second one to the left.
			P_Thrust(dust, dust.angle, 6*dust.scale)

			K_MatchGenericExtraFlags(dust, spb)

			sa = $ + ANG1*120;	// Add 120 degrees to get to mo.angle + ANG1*60
		end
	end
end

local function SpawnSPBSliptide(spb, dir)
	local newx, newy
	local spark
	local travelangle
	local sz = spb.floorz

	if (spb.eflags & MFE_VERTICALFLIP) then
		sz = spb.ceilingz
	end

	travelangle = K_MomentumAngle(spb)

	if ((leveltime & 1) and abs(spb.z - sz) < FRACUNIT*64) then
		newx = P_ReturnThrustX(spb, travelangle - (dir*ANGLE_45), 24*FRACUNIT)
		newy = P_ReturnThrustY(spb, travelangle - (dir*ANGLE_45), 24*FRACUNIT)

		spark = P_SpawnMobjFromMobj(spb, newx, newy, 0, MT_SPBDUST)
		spark.z = sz

		spark.state = S_KARTAIZDRIFTSTRAT
		spark.target = spb
		
		spark.colorized = true
		spark.color = SKINCOLOR_RED

		spark.angle = travelangle + (dir * ANGLE_90)
		spark.destscale = spb.scale*3/2
		P_SetScale(spark, spark.destscale)

		spark.momx = (6*spb.momx)/5
		spark.momy = (6*spb.momy)/5

		K_MatchGenericExtraFlags(spark, spb)
	end
end

// Used for seeking and when SPB is trailing its target from way too close!
local function SpawnSPBSpeedLines(spb)
	local fast = P_SpawnMobjFromMobj(spb,
		P_RandomRange(-24, 24) * FRACUNIT,
		P_RandomRange(-24, 24) * FRACUNIT,
		(spb.info.height / 2) + (P_RandomRange(-24, 24) * FRACUNIT),
		MT_FASTLINE
	)

	fast.target = spb
	fast.angle = K_MomentumAngle(spb)

	fast.color = SKINCOLOR_RED
	fast.colorized = true

	K_MatchGenericExtraFlags(fast, spb)
end

local function SPBMantaRings(spb)
	local vScale = INT32_MAX
	local spacing = INT32_MAX
	local finalDist = INT32_MAX
	local floatHeight = 24 * spb.scale
	local floorDist = INT32_MAX
	if (leveltime % 60 == 0) then
		spb.movecount = max(spb.movecount - 1, 100)
	end
	
	spacing = FixedMul(2750 * FRACUNIT, spb.scale)
	spacing = FixedMul(spacing, K_GetKartGameSpeedScalar(gamespeed))

	vScale = FixedDiv(spb.movecount * FRACUNIT, 100 * FRACUNIT)
	finalDist = FixedMul(spacing, vScale)
	
	floorDist = abs(P_GetMobjFeet(spb) - P_GetMobjGround(spb))
	
	spb.reactiontime = $ + P_AproxDistance(spb.momx, spb.momy)
	
	if (spb.reactiontime > finalDist and floorDist <= floatHeight) then
		spb.reactiontime = 0

		local manta = P_SpawnMobjFromMobj(spb, 0, 0, 0, MT_MANTARING)
		manta.color = SKINCOLOR_KETCHUP
		
		manta.destscale = FixedMul(2 * FRACUNIT, spb.scale)
		P_SetScale(manta, manta.destscale)
		
		manta.angle = R_PointToAngle2(0, 0, spb.momx, spb.momy) + ANGLE_90
		
		manta.extravalue1 = 40
		local delay = max(15, 90 / mapheaderinfo[gamemap].numlaps)
		if (mapheaderinfo[gamemap].levelflags & LF_SECTIONRACE) then
			delay = 60;
		end
		manta.fuse = delay * TICRATE
		manta.tracer = spb.tracer
		manta.extravalue2 = spb.tracer.player.laps
	end
end

local function spb_seek(spb)
	local desired_speed = SPB_DEFAULTSPEED()
	local curwaypoint = nil
	local destwaypoint = nil
	
	local dist = INT32_MAX
	local active_dist = INT32_MAX
	
	local dest_x, dest_y, dest_z = spb.x, spb.y, spb.z
	local dest_angle = spb.angle
	local dest_pitch = 0
	
	local xy_speed, z_speed = desired_speed, desired_speed
	local sliptide = 0
	
	local steer_dist = INT32_MAX
	local steer_mobj = nil
	
	local circling = false
	
	spb.lastlook = -1
	if (not spb.tracer.valid or spb.tracer.health <= 0 or spb.tracer.player == nil) then
		// player invalid, let's end this
		P_KillMobj(spb)
	end
	dist = SPB_Distance(spb, spb.tracer)
	active_dist = FixedMul(1024 * FRACUNIT, spb.tracer.scale)
	if (dist <= active_dist) then
		S_StopSound(spb)
		S_StartSound(spb, spb.info.attacksound)

		spb.extravalue1 = 1 // TARGET ACQUIRED

		spb.extravalue2 = 2 * 35
		spb.cvmem = 35

		spb.movefactor = desired_speed
		return
	end
	
	if not (S_SoundPlaying(spb, sfx_spbska)
		or S_SoundPlaying(spb, sfx_spbskb)
		or S_SoundPlaying(spb, sfx_spbskc)) then
		if dist <= active_dist * 3 then
			S_StartSound(spb, sfx_spbskc)
		elseif dist <= active_dist * 6 then
			S_StartSound(spb, sfx_spbskb)
		else
			S_StartSound(spb, sfx_spbska)
		end
	end
	if spb_curwaypointID == -1 then
		spb_curwaypoint = K_GetBestWaypointForMobj(spb)
		spb_curwaypointID = K_GetWaypointHeapIndex(spb_curwaypoint)
	else
		spb_curwaypoint = K_GetWaypointFromIndex(spb_curwaypointID)
	end
	spb_destwaypoint = K_GetBestWaypointForMobj(spb.tracer)
	
	if spb_curwaypoint != nil then
		local wp_dist = INT32_MAX
		local wp_rad = INT32_MAX
		
		dest_x = spb_curwaypoint.mobj.x
		dest_y = spb_curwaypoint.mobj.y
		dest_z = spb_curwaypoint.mobj.z
		
		wp_dist = R_PointToDist2(spb.x, spb.y, dest_x, dest_y) / mapobjectscale
		wp_rad = max(spb_curwaypoint.mobj.radius / mapobjectscale, 384)
		if wp_dist < wp_rad then
			local pathfindsuccess, path = false, nil
			if spb_destwaypoint != nil then
				local useshortcuts = K_GetWaypointIsShortcut(spb_destwaypoint)
				pathfindsuccess, path = K_PathfindToWaypoint(
					spb_curwaypoint, spb_destwaypoint,
					useshortcuts, false
				)
				if (pathfindsuccess == true) then
					/*if #path.array > 1 then
						spb_curwaypoint = path.array[2].nodedata
					elseif #spb_destwaypoint.nextwaypoints > 0
						spb_curwaypoint = spb_destwaypoint.nextwaypoints[1]
					else
						circling = true
						spb_curwaypoint = spb_destwaypoint
					end*/
					local reverse_success, reverse_path = K_PathfindToWaypoint(
						spb_curwaypoint, spb_destwaypoint,
						useshortcuts, true
					)
					if reverse_success and reverse_path.totaldist < path.totaldist then
						circling = true
					elseif #path.array > 1 then
						spb_curwaypoint = path.array[2].nodedata
					elseif #spb_destwaypoint.nextwaypoints > 0
						spb_curwaypoint = spb_destwaypoint.nextwaypoints[1]
					else
						circling = true
						spb_curwaypoint = spb_destwaypoint
					end
				end
			end
			if pathfindsuccess and spb_curwaypoint != nil then
				spb_curwaypointID = K_GetWaypointHeapIndex(spb_curwaypoint)
				dest_x = spb_curwaypoint.mobj.x
				dest_y = spb_curwaypoint.mobj.y
				dest_z = spb_curwaypoint.mobj.z
			else
				spb_curwaypointID = -1
				dest_x = spb.x
				dest_y = spb.y
				dest_z = spb.z
			end
		end
	end
	dest_angle = R_PointToAngle2(spb.x, spb.y, dest_x, dest_y)
	dest_pitch = R_PointToAngle2(0, spb.z, P_AproxDistance(spb.x - dest_x, spb.y - dest_y), dest_z)
	
	xy_speed, spb.angle, sliptide = SPB_Turn(desired_speed, dest_angle, xy_speed, spb.angle, FRACUNIT/8, sliptide)
	z_speed, spb.movedir = SPB_Turn(desired_speed, dest_pitch, z_speed, spb.movedir, FRACUNIT/8, nil)
	
	SetSPBSpeed(spb, xy_speed, z_speed)
	
	if (sliptide != 0) then
		// 1 if turning left, -1 if turning right.
		// Angles work counterclockwise, remember!
		SpawnSPBSliptide(spb, sliptide)
	else
		// if we're mostly going straight, then spawn the V dust cone!
		SpawnSPBDust(spb)
	end

	// Always spawn speed lines while seeking
	SpawnSPBSpeedLines(spb)

	// Don't run this while we're circling around one waypoint intentionally.
	if (circling == false) then
		// Spawn a trail of rings behind the SPB!
		SPBMantaRings(spb)
	end
end

local function spb_chase(spb)
	local base_speed = 0
	local max_speed = 0
	local desired_speed = 0

	local range = INT32_MAX
	local cx, cy = 0, 0

	local dist = INT32_MAX
	local dest_angle = spb.angle
	local dest_pitch = 0
	local xy_speed = 0
	local z_speed = 0

	local chase = spb.tracer
	local chasePlayer = nil

	spb_curwaypoint = nil
	spb_curwaypointID = -1
	
	if (not spb.tracer.valid or spb.tracer.health <= 0 or spb.tracer.player == nil) then
		// player invalid, let's end this
		P_KillMobj(spb)
	end
	
	if (chase.hitlag > 0) then
		// If the player is frozen, the SPB should be too.
		spb.hitlag = max(spb.hitlag, chase.hitlag)
		return
	end
	
	spb.watertop = $ + 1
	
	base_speed = SPB_DEFAULTSPEED()
	range = (160 * chase.scale)
	range = max(range, FixedMul(range, K_GetKartGameSpeedScalar(gamespeed)))
	
	if (S_SoundPlaying(spb, spb.info.activesound) == false) then
		S_StartSound(spb, spb.info.activesound)
	end
	
	dist = SPB_Distance(spb, chase)
	chasePlayer = chase.player
	
	if (chasePlayer != nil) then
		local fracmax = 32
		local spark = ((10 - chasePlayer.kartspeed) + chasePlayer.kartweight) / 2
		local easiness = ((chasePlayer.kartspeed + (10 - spark)) << FRACBITS) / 2
		local scaleAdjust = FRACUNIT
		if (chase.scale > mapobjectscale) then
			scaleAdjust = 3*FRACUNIT/2
		elseif (chase.scale < mapobjectscale) then
			scaleAdjust = 3*FRACUNIT/4
		end
		
		spb.lastlook = #chase.player
		chasePlayer.pflags = $ | PF_RINGLOCK // No rings for you :3c
		
		if (P_IsObjectOnGround(chase) == false) then
			// In the air you have no control; basically don't hit unless you make a near complete stop
			base_speed = (7 * chasePlayer.speed) / 8
		else
			// 7/8ths max speed for Knuckles, 3/4ths max speed for min accel, exactly max speed for max accel
			base_speed = FixedMul(
				((fracmax+1) << FRACBITS) - easiness,
				FixedMul(K_GetKartSpeed(chasePlayer, false, false), scaleAdjust)
			) / fracmax
		end

		if (chasePlayer.carry == CR_SLIDING)
			base_speed = chasePlayer.speed/2
		end
		
		cx = chasePlayer.cmomx
		cy = chasePlayer.cmomy
		
		chasePlayer.SPBdistance = dist
	end
	
	desired_speed = FixedMul(base_speed, FRACUNIT + FixedDiv(dist - range, range))

	if (desired_speed < base_speed) then
		desired_speed = base_speed
	end

	max_speed = (base_speed * 3) / 2
	if (desired_speed > max_speed) then
		desired_speed = max_speed
	end

	if (desired_speed < 20 * chase.scale) then
		desired_speed = 20 * chase.scale
	end
	
	if (chasePlayer != nil) then
		if (chasePlayer.carry == CR_SLIDING)
			// Hack for current sections to make them fair.
			desired_speed = min(desired_speed, chasePlayer.speed / 2)
		end

		
		local wp_dist = INT32_MAX
		local waypoint = K_GetBestWaypointForMobj(spb.tracer).mobj
		// thing_args[3]: SPB speed (0-100)
		if (waypoint and waypoint.spawnpoint.args[3]) then // 0 = default speed (unchanged)
			desired_speed = desired_speed * waypoint.spawnpoint.args[3] / 100;
		end
	end
	
	dest_angle = R_PointToAngle2(spb.x, spb.y, chase.x, chase.y)
	dest_pitch = R_PointToAngle2(0, spb.z, P_AproxDistance(spb.x - chase.x, spb.y - chase.y), chase.z)
	
	if (desired_speed > spb.movefactor) then
		spb.movefactor = $ + (desired_speed - spb.movefactor) / TICRATE
	else
		spb.movefactor = desired_speed;
	end
	
	xy_speed, spb.angle = SPB_Turn(spb.movefactor, dest_angle, xy_speed, spb.angle, FRACUNIT/4, nil)
	z_speed, spb.movedir = SPB_Turn(spb.movefactor, dest_pitch, z_speed, spb.movedir, FRACUNIT/4, nil)
	
	SetSPBSpeed(spb, xy_speed, z_speed)
	spb.momx = $ + cx
	spb.momy = $ + cy
	
	// Spawn a trail of rings behind the SPB!
	SPBMantaRings(spb)
	
	// Red speed lines for when it's gaining on its target. A tell for when you're starting to lose too much speed!
	if (R_PointToDist2(0, 0, spb.momx, spb.momy) > (16 * R_PointToDist2(0, 0, chase.momx, chase.momy)) / 15 // Going faster than the target
		and xy_speed > 20 * mapobjectscale) then // Don't display speedup lines at pitifully low speeds
		SpawnSPBSpeedLines(spb)
	end
end

local function spb_wait(spb)
end

local function spb_thinker(mobj)
	if (not mobj.valid) or (mobj != spb_mobj) then
		return false
	end
	
	if mobj.threshold > 0 then
		mobj.lastlook = -1
		mobj.curwaypoint = nil
		mobj.watertop = 0
		mobj.reactiontime = 0
		mobj.movecount = 150
		P_InstaThrust(mobj, mobj.angle, SPB_DEFAULTSPEED())
		mobj.threshold = $ - 1
	else
		if mobj.extravalue1 == 0 then -- seek
			spb_seek(mobj)
		elseif mobj.extravalue1 == 1 then -- chase
			spb_chase(mobj)
		elseif mobj.extravalue1 == 2 then -- wait (do we need this?)
			spb_wait(mobj)
		end
	end
	
	// Flash on/off when intangible.
	if mobj.cvmem > 0 then
		mobj.cvmem = $ - 1
		if mobj.cvmem & 1 then
			mobj.renderflags = $ | RF_DONTDRAW
		else
			mobj.renderflags = $ & ~RF_DONTDRAW
		end
	end
	
	// Flash white when about to explode!
	if mobj.fuse > 0 then
		if mobj.fuse & 1 then
			mobj.color = SKINCOLOR_INVINCFLASH
			mobj.colorized = true
		else
			mobj.color = SKINCOLOR_NONE
			mobj.colorized = false
		end
	end
	
	// Clamp within level boundaries.
	if mobj.z < mobj.floorz then
		mobj.z = mobj.floorz
	elseif mobj.z > mobj.ceilingz - mobj.height then
		mobj.z = mobj.ceilingz - mobj.height
	end
	if spb_timer > 0 then
		spb_timer = $ - 1
		--print(spb_timer)
		if spb_timer == 0 then
			P_RemoveMobj(mobj)
			spb_mobj = nil
			print("Survived the S.P.B. attack!")
			return true
		end
	end
	if mobj.valid then
		P_XYMovement(mobj)
		if mobj.valid then
			P_ZMovement(mobj)
		end
	end
	return true
end

local function spb_death(target, inflictor, source, damagetype)
	if (not target.valid) or (target != spb_mobj) then
		return false
	end
	spb_timer = 0
	spb_mobj = nil
	print("S.P.B. exploded!")
	return false
end

local function spb_spawn(mobj)
	if (not mobj.valid) or (mobj != spb_mobj) then
		return false
	end
	spb_curwaypoint = nil
	spb_destwaypoint = nil
	spb_curwaypointID = -1
	spb.target = spb_target
	spb.tracer = spb_target
	return false
end

addHook("MobjThinker", spb_thinker, MT_SPB)
addHook("MobjDeath", spb_death, MT_SPB)
addHook("MobjSpawn", spb_spawn, MT_SPB)