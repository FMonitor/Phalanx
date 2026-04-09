#version 2

raidConfig = {
	activationFlag = "level.phalanx.demo.raid_active",
	dronePrefab = "MOD/demo/drone_target.xml",
	targetTag = "phalanx_ai_target",
	targetCenter = Vec(0.0, 8.0, 0.0),
	spawnJitterHorizontal = 5.0,
	spawnJitterVertical = 2.5,
	clearDelay = 0.75,
}

raidState = {
	buttonShape = 0,
	spawnLocations = {},
	activeDroneBodies = {},
	spawnCursor = 1,
	lastSpawnTime = -100.0,
	autoSpawnActive = false,
}

spawnConfig = {
	manualSpawnCooldown = 1.0,
}

DebugPrint("CIWS demo script parsed")

function init()
	raidState.buttonShape = FindShape("raid_button", true)
	raidState.spawnLocations = FindLocations("phalanx_drone_spawn", true) or {}
	raidState.activeDroneBodies = {}
	raidState.spawnCursor = 1
	raidState.lastSpawnTime = -100.0
	SetBool(raidConfig.activationFlag, false)
	DebugPrint("CIWS demo init: button=" .. tostring(raidState.buttonShape) .. " spawns=" .. tostring(#raidState.spawnLocations))
end

function isDroneBodyAlive(bodyOrVehicle)
	if GetEntityType(bodyOrVehicle) == "vehicle" then
		return bodyOrVehicle ~= 0 and IsHandleValid(bodyOrVehicle) and not IsVehicleBroken(bodyOrVehicle)
	end
	return bodyOrVehicle ~= 0 and IsHandleValid(bodyOrVehicle) and not IsBodyBroken(bodyOrVehicle)
end

function makeSpawnTransform(location)
	local spawnTransform = GetLocationTransform(location)
	local jitter = Vec(
		(math.random() - 0.5) * raidConfig.spawnJitterHorizontal,
		(math.random() - 0.5) * raidConfig.spawnJitterVertical,
		(math.random() - 0.5) * raidConfig.spawnJitterHorizontal
	)
	local spawnPos = VecAdd(spawnTransform.pos, jitter)
	local aimOffset = Vec(
		(math.random() - 0.5) * 12.0,
		(math.random() - 0.5) * 4.0,
		(math.random() - 0.5) * 12.0
	)
	local aimPos = VecAdd(raidConfig.targetCenter, aimOffset)
	return Transform(spawnPos, QuatLookAt(spawnPos, aimPos))
end

function registerSpawnedDrone(entities)
	if entities == nil then
		return
	end

	for i = 1, #entities do
		local ent = entities[i]
		if (GetEntityType(ent) == "body" or GetEntityType(ent) == "vehicle") and HasTag(ent, "phalanx_drone") then
			raidState.activeDroneBodies[#raidState.activeDroneBodies + 1] = ent
		end
	end
end

function compactActiveDrones()
	local activeBodies = {}
	for i = 1, #raidState.activeDroneBodies do
		local body = raidState.activeDroneBodies[i]
		if isDroneBodyAlive(body) then
			activeBodies[#activeBodies + 1] = body
		end
	end

	if #activeBodies == 0 then
		local sceneVehicles = FindVehicles("phalanx_drone", true) or {}
		for i = 1, #sceneVehicles do
			local veh = sceneVehicles[i]
			if isDroneBodyAlive(veh) then
				activeBodies[#activeBodies + 1] = veh
			end
		end

		local sceneBodies = FindBodies("phalanx_drone", true) or {}
		for i = 1, #sceneBodies do
			local body = sceneBodies[i]
			if isDroneBodyAlive(body) then
				activeBodies[#activeBodies + 1] = body
			end
		end
	end

	raidState.activeDroneBodies = activeBodies
end

function hasLiveAiTargets()
	local vehicleTargets = FindVehicles(raidConfig.targetTag, true) or {}
	for i = 1, #vehicleTargets do
		if isDroneBodyAlive(vehicleTargets[i]) then
			return true
		end
	end
	
	local targets = FindBodies(raidConfig.targetTag, true) or {}
	for i = 1, #targets do
		if isDroneBodyAlive(targets[i]) then
			return true
		end
	end
	return false
end

function spawnSingleDrone()
	if #raidState.spawnLocations == 0 then
		DebugPrint("CIWS demo spawn skipped: no spawn locations")
		return
	end

	local spawnLocation = raidState.spawnLocations[raidState.spawnCursor]
	local entities = Spawn(raidConfig.dronePrefab, makeSpawnTransform(spawnLocation))
	local entityCount = 0
	if entities ~= nil then
		entityCount = #entities
	end
	DebugPrint("CIWS demo spawn request: prefab=" .. raidConfig.dronePrefab .. " locationIndex=" .. tostring(raidState.spawnCursor) .. " entities=" .. tostring(entityCount))
	registerSpawnedDrone(entities)
	compactActiveDrones()
	DebugPrint("CIWS demo live drones after spawn=" .. tostring(#raidState.activeDroneBodies))
	raidState.lastSpawnTime = GetTime()
	raidState.spawnCursor = raidState.spawnCursor + 1
	if raidState.spawnCursor > #raidState.spawnLocations then
		raidState.spawnCursor = 1
	end
end

function tick(dt)
	compactActiveDrones()
	local interactShape = GetPlayerInteractShape()
	local buttonHovered = interactShape ~= 0 and HasTag(interactShape, "raid_button")
	local liveTargets = hasLiveAiTargets()
	SetBool(raidConfig.activationFlag, liveTargets)

	DebugWatch("CIWS Demo", "button=" .. tostring(raidState.buttonShape) .. " hover=" .. tostring(buttonHovered) .. " targets=" .. tostring(#raidState.activeDroneBodies) .. " next=" .. tostring(raidState.spawnCursor))

	if buttonHovered and InputPressed("interact") then
		raidState.autoSpawnActive = not raidState.autoSpawnActive
		DebugPrint("CIWS Demo toggled: auto spawn is now " .. tostring(raidState.autoSpawnActive))
	end
	
	if raidState.autoSpawnActive then
		if GetTime() > raidState.lastSpawnTime + spawnConfig.manualSpawnCooldown then
			spawnSingleDrone()
		end
	end
end
