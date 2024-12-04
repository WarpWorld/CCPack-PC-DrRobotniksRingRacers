local ready_path = "client/crowd_control/connector.txt"
local input_path = "client/crowd_control/input.txt"
local output_path = "client/crowd_control/output.txt"
local log_path = "client/crowd_control/latest-log.txt"

local state_file
local input_file
local output_file
local log_file

local started = false
local effects = {} -- <string, effect>
local running_effects = {} -- list<(timer, id, was_ready)>

local keepalive_timer = 0
local id = 0

local message_queue = {}

local deaths = 0
local input_dirty = false -- if this flag is set, input parsing is deferred a tic

local SUCCESS = 0
local FAILED = 1
local UNAVAILABLE = 2
local RETRY = 3
local PAUSED = 6
local RESUMED = 7
local FINISHED = 8

local clock = 0

// CV vars are bugged atm
local cc_debug = {
	value = 1
}/*CV_RegisterVar({
	name = "cc_debug",
	defaultvalue = 0,
	flags = CV_NOTINNET,
	PossibleValue = CV_OnOff,
	func = nil
})*/

local function log_msg_silent(...)
	if (cc_debug.value ~= 0) and (io.type(log_file) == "file") then
		log_file:write("["..tostring(clock).."] ", ...)
		log_file:write("\n")
		log_file:flush()
	end
end

local function log_msg(...)
	print(...)
	log_msg_silent(...)
end

-- these functions are for simple error logging
-- For error handling they return the same values returned by the function they call
local function open_local(path, mode)
	local file, err = io.openlocal(path, mode)
	if err ~= nil then
		log_msg_silent(err)
	end
	return file, err
end

local function write_file(file, ...)
	local success,err,err_code = file:write(...)
	if not success then
		log_msg("[ERROR:",tostring(err_code),"] ", err)
	end
	return success,err,err_code
end

//https://stackoverflow.com/questions/1426954/split-string-in-lua
local function split (inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t={}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
            table.insert(t, str)
    end
    return t
end

local function create_response(msg_id, result, time_remaining, message)
	if not (type(time_remaining) == "number") then
		time_remaining = 0
	end
	if not (type(message) == "string") then
		message = ""
	end
	local response = {
		["id"] = msg_id,
		["status"] = result,
		["timeRemaining"] = (time_remaining * 1000) / TICRATE,
		["message"] = message,
		["type"] = 0
	}
	table.insert(message_queue, response)
end

local function setup_cc_effects()
	started = true
	log_file = open_local(log_path, "w")
	for k,v in pairs(effects) do
		log_msg(k)
	end
	log_msg("Effects loaded")
	state_file = open_local(ready_path, "w")
	write_file(state_file, "READY")
	state_file:close()
end

local function handle_message(msg)
	if not (msg == nil) then
		id = msg["id"]
		local msg_type = msg["type"]
		-- test or start
		if msg_type == 0 or msg_type == 1 then
			local code = msg["code"]
			local effect = effects[code]
			if effect == nil or not (getmetatable(effect) == CCEffect.Meta) then
				log_msg("Couldn't find effect '"..code.."'!")
				create_response(id, UNAVAILABLE)
			elseif effect.ready() and (not effect.is_timed or (effect.is_timed and (running_effects[effect.code] == nil))) then
				local quantity = msg["quantity"]
				if (quantity == nil) or (quantity == 0) then
					quantity = 1
				end
				local result, out_msg = effect.update(0, quantity, msg["parameters"]) -- parameters may be nil
				if result == nil then
					result = SUCCESS
				end
				if effect.is_timed then
					effect.duration = ((msg["duration"] * TICRATE) / 1000)
					running_effects[effect.code] = {["timer"] = 0, ["id"] = id, ["was_ready"] = true}
				end
				create_response(id, result, effect.duration, out_msg)
				if result == SUCCESS then
					if (cc_debug.value ~= 0) then
						log_msg(tostring(msg["viewer"]).." activated effect '"..code.."' ("..tostring(id)..")!")
					else
						log_msg(tostring(msg["viewer"]).." activated effect '"..code.."'!")
					end
				end
			else
				create_response(id, RETRY)
			end
		-- stop
		elseif msg_type == 2 then
			local code = msg["code"]
			local effect = effects[code]
			if effect == nil or not (getmetatable(effect) == CCEffect.Meta) then
				log_msg("Couldn't find effect '"..code.."'!")
				create_response(id, UNAVAILABLE)
			end
			running_effects[code] = nil
			create_response(id, SUCCESS)
		-- keepalive
		elseif msg_type == 255 then
			log_msg_silent("PONG")
			table.insert(message_queue, {["id"] = 0, ["type"] = 255})
		end
	else
		log_msg("Received empty message!")
	end
end

local function main_loop()
	clock = $ + 1
	if (gamestate == GS_INTERMISSION 
			or gamestate == GS_TITLESCREEN 
			or gamestate == GS_CONTINUING 
			or gamestate == GS_MENU 
			or gamestate == GS_EVALUATING 
			or gamestate == GS_CREDITS 
			or gamestate == GS_INTRO 
			or gamestate == GS_CUTSCENE) then
		state_file = open_local(ready_path, "w")
		write_file(state_file, "MENU")
		state_file:close()
	elseif gamestate == GS_LEVEL then
		state_file = open_local(ready_path, "w")
		write_file(state_file, "READY")
		state_file:close()
	elseif paused then
		state_file = open_local(ready_path, "w")
		write_file(state_file, "PAUSED")
		state_file:close()
	end
	for k,v in pairs(running_effects) do
		local effect = effects[k]
		if not (v == nil) then
			if effect.ready() then
				running_effects[k]["timer"] = v["timer"] + 1
				effect.update(v["timer"] + 1)
				if not v["was_ready"] then
					create_response(v["id"], RESUMED)
				end
			else
				if v["was_ready"] then
					create_response(v["id"], PAUSED)
				end
			end
		end
		v["was_ready"] = effect.ready()
		if v["timer"] + 1 > effect.duration then
			create_response(v["id"], FINISHED, 0, "'"..effect.code.."' finished!")
			running_effects[k] = nil
		end
	end
	if input_dirty then
		input_file = open_local(input_path,"w")
		if not (input_file == nil)
			input_file:close() -- clear the file
			input_dirty = false
		end
	else
		input_file = open_local(input_path, "r")
		if not (input_file == nil) then
			local content = input_file:read("*a")
			if not (content == "") then
				for i,msg in ipairs(split(content, "%c")) do -- This is a bad assumption, but all control codes should be escaped
					log_msg_silent(msg)
					handle_message(parseJSON(msg))
				end
				input_file:close()
				input_file = open_local(input_path,"w")
				-- in rare cases handling the messages took too long and CC grabbed the file already
				if not (input_file == nil) then
					input_file:close() -- clear the file
				else
					input_dirty = true
				end
			else
				input_file:close()
			end
		end
	end
	if not (#message_queue == 0) then
		output_file = open_local(output_path,"w")
		if not (output_file == nil) then
			local out = stringify(message_queue[1])
			write_file(output_file, out.."\0")
			log_msg_silent(">", out)
			table.remove(message_queue, 1)
		else
			log_msg_silent("Failed to open output file!")
		end
	end
	keepalive_timer = $ + 1
	if keepalive_timer >= TICRATE then
		if io.type(output_file) ~= "file" then
			output_file = open_local(output_path,"w")
		end
		if not (output_file == nil) then
			write_file(output_file, '{"id":0,"type":255}\0')
			keepalive_timer = 0
		else
			log_msg_silent("Failed to send keepalive!")
		end
	end
	if io.type(output_file) == "file" then
		output_file:close()
	end
end

addHook("PreThinkFrame", main_loop)

-- quitting: true if the application is exiting, false if returning to titlescreen
local function on_game_quit(quitting)
	deaths = 0
	if quitting then
		open_local(ready_path, "w"):close()
	end
end

addHook("GameQuit", on_game_quit)

local function on_map_changed(mapnum)
	spb_timer = 0
end

addHook("MapChange", on_map_changed)

local function on_player_think(player)
	if running_effects["ringlock"] != nil and running_effects["ringlock"]["was_ready"] then
		player.pflags = $ | PF_RINGLOCK // No rings for you :3c
	end
end

addHook("PlayerThink", on_player_think)

-- HUD Drawer ==================================================================

local function drawRunningEffects(drawer, player, cam)
	local timers = {}
	for k,v in pairs(running_effects) do
		if not (v == nil) then
			local timeleft = (effects[k].duration - v["timer"]) + 1 --just to make sure this won't become zero
			if (timers[timeleft] == nil) then
				timers[timeleft] = {
					["time"]=timeleft, 
					["effects"]={k}
				}
			else
				table.insert(timers[timeleft]["effects"], k)
			end
		end
	end
	local times = {}
	for i,v in pairs(timers)
		table.insert(times, i)
	end
	table.sort(times, function(a, b)
		return a > b --inverse order
	end)
	local offset = 32
	for _,i in ipairs(times) do
		for j,code in ipairs(timers[i]["effects"]) do
			local gfx = ""
			if (code == "invertcontrols") then
				gfx = "INVCICON"
			end
			if (code == "swapbuttons") then
				gfx = "SWBTICON"
			end
			if drawer.patchExists(gfx) then
				if not((i < 3 * TICRATE) and (i % 2 == 0)) then
					local patch = drawer.cachePatch(gfx)
					drawer.drawScaled((320 - offset) * FRACUNIT, (200 - 44) * FRACUNIT, FRACUNIT/2, patch)
					drawer.drawString(320 - offset + 16, 200 - 36, i/TICRATE, 0, "thin-right")
				end
				offset = $ + 4 + 16
			end
		end
	end
end


customhud.SetupItem("cc_debuffs", "crowd_control", drawRunningEffects, "game");


-- Effects =====================================================================

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

/*effects["demo"] = CCEffect.New("demo", function(t)
	print("This is a demo!")
end, default_ready)*/
effects["giverings"] = CCEffect.New("giverings", function(t, count)
	consoleplayer.superring = $ + count
end, default_ready)

effects["takerings"] = CCEffect.New("takerings", function(t, count)
	P_GivePlayerRings(consoleplayer, -count)
	S_StartSound(consoleplayer.mo, sfx_itemup)
end, default_ready)

effects["playerlapplus"] = CCEffect.New("playerlapplus", function(t)
	consoleplayer.laps = $ + 1
end, default_ready)

effects["playerlapminus"] = CCEffect.New("playerlapminus", function(t)
	consoleplayer.laps = $ - 1
end, default_ready)

-- unexposted constants
local IF_ITEMOUT = 1<<1
local IF_EGGMANOUT = 1<<2

local function itemcheck() 
	return (default_ready() 
			and consoleplayer.itemflags & (IF_ITEMOUT|IF_EGGMANOUT) == 0 
			and consoleplayer.curshield == KSHIELD_NONE) --and not consoleplayer.itemroulette.eggman
end

effects["nothing"] = CCEffect.New("nothing", function(t)
	K_StripItems(consoleplayer)
end, function() 
	return itemcheck()
end)

effects["sneakers"] = CCEffect.New("sneakers", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_SNEAKER
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, default_ready)

effects["triggersneaker"] = CCEffect.New("triggersneaker", function(t)
	K_DoSneaker(consoleplayer, 1)
	K_PlayBoostTaunt(consoleplayer.mo)
end, function()
	return itemcheck()
end)

effects["dualsneakers"] = CCEffect.New("dualsneakers", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_SNEAKER
	consoleplayer.itemamount = 2
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function()
	return itemcheck()
end)

effects["triplesneakers"] = CCEffect.New("triplesneakers", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_SNEAKER
	consoleplayer.itemamount = 3
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function()
	return itemcheck()
end)

effects["rocketsneakers"] = CCEffect.New("rocketsneakers", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_ROCKETSNEAKER
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function()
	return itemcheck()
end)

effects["invincibility"] = CCEffect.New("invincibility", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_INVINCIBILITY
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function()
	return default_ready()
end)

effects["banana"] = CCEffect.New("banana", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_BANANA
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function()
	return itemcheck()
end)

effects["triggerbanana"] = CCEffect.New("triggerbanana", function(t)
	local banana = P_SpawnMobjFromMobj(consoleplayer.mo, 0, 0, 0, MT_BANANA)
	banana.destscale = mapobjectscale
	banana.scale = mapobjectscale
	banana.health = 0
end, default_ready)

effects["triplebanana"] = CCEffect.New("triplebanana", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_BANANA
	consoleplayer.itemamount = 3
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function()
	return itemcheck()
end)

effects["eggman"] = CCEffect.New("eggman", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_EGGMAN
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function()
	return default_ready()
end)

effects["orbinaut"] = CCEffect.New("orbinaut", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_ORBINAUT
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function()
	return default_ready()
end)

effects["tripleorbinaut"] = CCEffect.New("tripleorbinaut", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_ORBINAUT
	consoleplayer.itemamount = 3
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function()
	return default_ready()
end)

effects["quadorbinaut"] = CCEffect.New("quadorbinaut", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_ORBINAUT
	consoleplayer.itemamount = 4
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function()
	return default_ready()
end)

effects["jawz"] = CCEffect.New("jawz", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_JAWZ
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function()
	return itemcheck()
end)

effects["dualjawz"] = CCEffect.New("dualjawz", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_JAWZ
	consoleplayer.itemamount = 2
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function()
	return itemcheck()
end)

effects["mine"] = CCEffect.New("mine", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_MINE
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function()
	return itemcheck()
end)

effects["landmine"] = CCEffect.New("landmine", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_LANDMINE
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function()
	return itemcheck()
end)

effects["ballhog"] = CCEffect.New("ballhog", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_BALLHOG
	consoleplayer.itemamount = 5
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function()
	return itemcheck()
end)

effects["spb"] = CCEffect.New("spb", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_SPB
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function()
	return itemcheck() and not K_IsSPBInGame()
end)

effects["grow"] = CCEffect.New("grow", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_GROW
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function() 
	return itemcheck()
end)

effects["triggergrow"] = CCEffect.New("triggergrow", function(t)
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

effects["shrink"] = CCEffect.New("shrink", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_SHRINK
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function() 
	return itemcheck()
end)

effects["triggershrink"] = CCEffect.New("triggershrink", function(t)
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

effects["lightningshield"] = CCEffect.New("lightningshield", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_LIGHTNINGSHIELD
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
	consoleplayer.curshield = KSHIELD_LIGHTNING
	local shield = P_SpawnMobjFromMobj(consoleplayer.mo, 0, 0, 0, MT_LIGHTNINGSHIELD)
	shield.destscale = (5*shield.destscale)>>2
	shield.scale = shield.destscale
	shield.target = consoleplayer.mo
	S_StartSound(consoleplayer.mo, sfx_s3k3e)
end, function()
	return default_ready() and consoleplayer.curshield != KSHIELD_TOP
end)

effects["bubbleshield"] = CCEffect.New("bubbleshield", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_BUBBLESHIELD
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
	consoleplayer.curshield = KSHIELD_BUBBLE
	local shield = P_SpawnMobjFromMobj(consoleplayer.mo, 0, 0, 0, MT_BUBBLESHIELD)
	shield.eflags = $ & ~MFE_VERTICALFLIP
	shield.destscale = (5*shield.destscale)>>2
	shield.scale = shield.destscale
	shield.target = consoleplayer.mo
	S_StartSound(consoleplayer.mo, sfx_s3k3f)
end, function()
	return default_ready() and consoleplayer.curshield != KSHIELD_TOP
end)

effects["flameshield"] = CCEffect.New("flameshield", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_FLAMESHIELD
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
	consoleplayer.curshield = KSHIELD_FLAME
	local shield = P_SpawnMobjFromMobj(consoleplayer.mo, 0, 0, 0, MT_FLAMESHIELD)
	shield.destscale = (5*shield.destscale)>>2
	shield.scale = shield.destscale
	shield.target = consoleplayer.mo
	S_StartSound(consoleplayer.mo, sfx_s3k3e)
end, function()
	return default_ready() and consoleplayer.curshield != KSHIELD_TOP
end)

effects["hyudoro"] = CCEffect.New("hyudoro", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_HYUDORO
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function() 
	return itemcheck()
end)

effects["pogospring"] = CCEffect.New("pogospring", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_POGOSPRING
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function() 
	return itemcheck()
end)

effects["superring"] = CCEffect.New("superring", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_SUPERRING
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function() 
	return itemcheck()
end)

effects["kitchensink"] = CCEffect.New("kitchensink", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_KITCHENSINK
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function() 
	return itemcheck()
end)

effects["bumper"] = CCEffect.New("bumper", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_DROPTARGET
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function() 
	return itemcheck()
end)

effects["gardentop"] = CCEffect.New("gardentop", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_GARDENTOP
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
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
	return default_ready() and consoleplayer.curshield != KSHIELD_TOP
end)

effects["gachabom"] = CCEffect.New("gachabom", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_GACHABOM
	consoleplayer.itemamount = 1
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function() 
	return itemcheck()
end)

effects["triplegachabom"] = CCEffect.New("triplegachabom", function(t)
	K_StripItems(consoleplayer)
	consoleplayer.itemtype = KITEM_GACHABOM
	consoleplayer.itemamount = 3
	consoleplayer.itemflags = $ & ~(IF_ITEMOUT|IF_EGGMANOUT)
end, function() 
	return itemcheck()
end)

effects["invertcontrols"] = CCEffect.New("invertcontrols", function(t)
	consoleplayer.cmd.turning = -consoleplayer.cmd.turning
	consoleplayer.cmd.aiming = -consoleplayer.cmd.aiming
end, default_ready, 15 * TICRATE)

effects["swapbuttons"] = CCEffect.New("swapbuttons", function(t)
	consoleplayer.cmd.forwardmove = -consoleplayer.cmd.forwardmove
end, default_ready, 15 * TICRATE)

effects["ringlock"] = CCEffect.New("ringlock", function(t)
	// dummy function as the hook runs too early
end, function()
	return default_ready() and consoleplayer.pflags & PF_RINGLOCK != PF_RINGLOCK
end, 15 * TICRATE)

effects["spbattack"] = CCEffect.New("spbattack", function(t)
	local dir_x = cos(consoleplayer.mo.angle)
	local dir_y = sin(consoleplayer.mo.angle)
	local x = consoleplayer.mo.x + FixedMul(-(dir_x * 4096), mapobjectscale)
	local y = consoleplayer.mo.y + FixedMul(-(dir_y * 4096), mapobjectscale)
	local z = consoleplayer.mo.z + FixedMul(consoleplayer.mo.height/2, mapobjectscale)
	SpawnSPB(x, y, z, consoleplayer)
end, function()
	return itemcheck() and not K_IsSPBInGame()
end)

local function check_skin(skin)
	if not R_SkinUsable(consoleplayer, skin) then
		create_response(id, UNAVAILABLE)
		return false
	end
	return default_ready()
end

effects["changerandom"] = CCEffect.New("changerandom", function(t)
	local skin = skins[P_RandomKey(#skins)]
	while not (skin.valid) or (oldskin == skin) or not R_SkinUsable(consoleplayer, skin.name) do
		skin = skins[P_RandomKey(#skins)]
	end
	consoleplayer.mo.skin = skin.name
	R_SetPlayerSkin(consoleplayer, skin.name)
end, default_ready)

-- the title map isn't constantly active anymore, so we launch as soon as the mod is loaded
setup_cc_effects()