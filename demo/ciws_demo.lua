#version 2

switch = nil
lamp = nil
on = false
spawnLocations = nil
spawnCooldown = 0.0
pressFeedbackUntil = 0.0
activationFlag = "level.phalanx.demo.raid_active"
dronePrefab = "MOD/demo/drone_target.xml"
targetTag = "phalanx_ai_target"

function hasLiveTargets()
	local vehicles = FindVehicles(targetTag, true)
	if vehicles ~= nil then
		for i = 1, #vehicles do
			if vehicles[i] ~= 0 and IsHandleValid(vehicles[i]) and not IsVehicleBroken(vehicles[i]) then
				return true
			end
		end
	end

	local bodies = FindBodies(targetTag, true)
	if bodies ~= nil then
		for i = 1, #bodies do
			if bodies[i] ~= 0 and IsHandleValid(bodies[i]) and not IsBodyBroken(bodies[i]) then
				return true
			end
		end
	end

	return false
end

function makeSpawnTransform(location)
	local t = GetLocationTransform(location)
	local jitter = Vec(
		(math.random() - 0.5) * 5.0,
		(math.random() - 0.5) * 2.5,
		(math.random() - 0.5) * 5.0
	)
	local pos = VecAdd(t.pos, jitter)
	local aimPos = Vec(
		(math.random() - 0.5) * 12.0,
		8.0 + (math.random() - 0.5) * 4.0,
		(math.random() - 0.5) * 12.0
	)
	return Transform(pos, QuatLookAt(pos, aimPos))
end

function spawnDroneWave()
	if spawnLocations == nil or #spawnLocations == 0 then
		DebugPrint("CIWS demo spawn skipped: no spawn locations")
		return false
	end

	local totalSpawned = 0
	for i = 1, #spawnLocations do
		local entities = Spawn(dronePrefab, makeSpawnTransform(spawnLocations[i]))
		if entities ~= nil and #entities > 0 then
			totalSpawned = totalSpawned + 1
		end
	end

	DebugPrint("CIWS demo spawned drones at " .. tostring(totalSpawned) .. "/" .. tostring(#spawnLocations) .. " locations")
	return totalSpawned > 0
end

function server.init()
	switch = FindShape("raid_button")
	lamp = FindLight("raid_button_light")
	spawnLocations = FindLocations("phalanx_drone_spawn", true)
	if spawnLocations == nil then
		spawnLocations = {}
	end
	spawnCooldown = 0.0
	pressFeedbackUntil = 0.0

	if lamp ~= 0 then
		SetLightEnabled(lamp, true)
		SetLightColor(lamp, 0.2, 1.0, 0.2)
	end

	if switch ~= 0 then
		SetTag(switch, "interact", "Spawn drone wave")
		SetShapeEmissiveScale(switch, 1.0)
	end

	SetBool(activationFlag, false)
end

function server.tick(dt)
	if switch ~= 0 then
		SetTag(switch, "interact", "Spawn drone wave")
	end

	local hovered = switch ~= 0 and GetPlayerInteractShape() == switch
	local liveTargets = hasLiveTargets()
	SetBool(activationFlag, liveTargets)

	if spawnCooldown > 0.0 then
		spawnCooldown = math.max(0.0, spawnCooldown - dt)
	end
	
	if hovered and InputPressed("interact") and spawnCooldown <= 0.0 then
		on = spawnDroneWave()
		spawnCooldown = 1.0
		pressFeedbackUntil = GetTime() + 0.35

		if lamp ~= 0 then
			if on then
				SetLightEnabled(lamp, true)
				SetLightColor(lamp, 1.0, 0.8, 0.2)
			else
				SetLightEnabled(lamp, true)
				SetLightColor(lamp, 0.2, 1.0, 0.2)
			end
		end
	end

	if lamp ~= 0 and GetTime() > pressFeedbackUntil then
		if liveTargets then
			SetLightEnabled(lamp, true)
			SetLightColor(lamp, 0.2, 0.7, 1.0)
		else
			SetLightEnabled(lamp, true)
			SetLightColor(lamp, 0.2, 1.0, 0.2)
		end
	end
end
