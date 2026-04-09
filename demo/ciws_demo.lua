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
	buttonLight = 0,
	spawnLocations = {},
	activeDroneBodies = {},
	spawnCursor = 1,
	lastSpawnTime = -100.0,
	autoSpawnActive = false,
	pendingSpawns = 0,
	pressFeedbackUntil = 0.0,
}

spawnConfig = {
	manualSpawnCooldown = 1.0,
}

buttonVisuals = {
	idleEmissive = 0.0,
	hoverEmissive = 0.8,
	activeEmissive = 1.6,
	idleColor = {1.0, 0.20, 0.12},
	hoverColor = {1.0, 0.72, 0.18},
	activeColor = {0.18, 0.72, 1.0},
}

DebugPrint("CIWS demo script parsed")

function init()
	raidState.buttonShape = FindShape("raid_button", true)
	if raidState.buttonShape == 0 then
		raidState.buttonShape = FindShape("raid_button")
	end
	raidState.buttonLight = FindLight("raid_button_light", true)
	if raidState.buttonLight == 0 then
		raidState.buttonLight = FindLight("raid_button_light")
	end
	raidState.spawnLocations = FindLocations("phalanx_drone_spawn", true) or {}
	raidState.activeDroneBodies = {}
	raidState.spawnCursor = 1
	raidState.lastSpawnTime = -100.0
	raidState.pendingSpawns = 0
	raidState.pressFeedbackUntil = 0.0
	SetBool(raidConfig.activationFlag, false)
	if raidState.buttonShape ~= 0 then
		SetTag(raidState.buttonShape, "interact", "Spawn drone wave")
		SetShapeEmissiveScale(raidState.buttonShape, buttonVisuals.idleEmissive)
	end
	if raidState.buttonLight ~= 0 then
		SetLightEnabled(raidState.buttonLight, true)
		SetLightColor(raidState.buttonLight, buttonVisuals.idleColor[1], buttonVisuals.idleColor[2], buttonVisuals.idleColor[3])
	end
	raidState.buttonOnSound = LoadSound("screen-on.ogg")
	raidState.buttonOffSound = LoadSound("screen-off.ogg")
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

function isRaidButtonPressed()
	return raidState.buttonShape ~= 0
		and GetPlayerInteractShape() == raidState.buttonShape
		and InputPressed("interact")
end

function setButtonVisuals(isHovered, isActive)
	if raidState.buttonShape ~= 0 then
		local emissive = buttonVisuals.idleEmissive
		if isActive then
			emissive = buttonVisuals.activeEmissive
		elseif isHovered then
			emissive = buttonVisuals.hoverEmissive
		end
		SetShapeEmissiveScale(raidState.buttonShape, emissive)
	end

	if raidState.buttonLight ~= 0 then
		local color = buttonVisuals.idleColor
		if isActive then
			color = buttonVisuals.activeColor
		elseif isHovered then
			color = buttonVisuals.hoverColor
		end
		SetLightColor(raidState.buttonLight, color[1], color[2], color[3])
	end
end

function tick(dt)
	compactActiveDrones()
	local buttonHovered = raidState.buttonShape ~= 0 and GetPlayerInteractShape() == raidState.buttonShape
	local liveTargets = hasLiveAiTargets()
	SetBool(raidConfig.activationFlag, liveTargets)

	DebugWatch("CIWS Demo", "button=" .. tostring(raidState.buttonShape) .. " hover=" .. tostring(buttonHovered) .. " targets=" .. tostring(#raidState.activeDroneBodies) .. " next=" .. tostring(raidState.spawnCursor))

	if raidState.buttonShape ~= 0 then
		SetTag(raidState.buttonShape, "interact", "Spawn drone wave")
	end

	if isRaidButtonPressed() then
		raidState.pendingSpawns = 6
		raidState.pressFeedbackUntil = GetTime() + 0.35
		if raidState.buttonOnSound ~= nil then
			PlaySound(raidState.buttonOnSound, GetShapeWorldTransform(raidState.buttonShape).pos)
		end
		DebugPrint("CIWS Demo: Spawning 6 drones wave")
	end

	if raidState.pendingSpawns > 0 then
		if GetTime() > raidState.lastSpawnTime + spawnConfig.manualSpawnCooldown then
			spawnSingleDrone()
			raidState.pendingSpawns = raidState.pendingSpawns - 1
			if raidState.pendingSpawns == 0 and raidState.buttonOffSound ~= nil and raidState.buttonShape ~= 0 then
				PlaySound(raidState.buttonOffSound, GetShapeWorldTransform(raidState.buttonShape).pos)
			end
		end
	end

	setButtonVisuals(buttonHovered, raidState.pendingSpawns > 0 or GetTime() < raidState.pressFeedbackUntil)
end
