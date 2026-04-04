#version 2

#include "script/include/player.lua"

-- Expected model file and object names:
--   MOD/vehicle/ciws/ciws.vox
--   object="base"
--   object="turret"
--   object="gun"

vehicle = 0
baseBody = 0
turretBody = 0
gunBody = 0
yawJoint = 0
pitchJoint = 0

cameraTransform = Transform()

cameraState = {
	initialized = false,
	yaw = 0.0,
	pitch = 10.0,
	distance = 7.0,
	targetDistance = 7.0,
	height = 0.4,
}

cameraConfig = {
	sensX = 5000.0,
	sensY = 5000.0,
	distMin = 0.0,
	distMax = 14.0,
	firstPersonThreshold = 0.65,
	pitchMin = -89.0,
	pitchMax = 89.0,
	radius = 0.25,
	smooth = 10.0,
	fov = 110,
}

jointConfig = {
	yawOffset = 0.0,
	pitchOffset = 0.0,
	yawSign = 1.0,
	pitchSign = 1.0,
	yawMin = -180.0,
	yawMax = 180.0,
	pitchMin = -15.0,
	pitchMax = 85.0,
	yawMaxVel = math.rad(180.0),
	pitchMaxVel = math.rad(120.0),
	yawStrength = 400.0,
	pitchStrength = 300.0,
}

function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function wrapAngle(a)
	while a > 180.0 do
		a = a - 360.0
	end
	while a < -180.0 do
		a = a + 360.0
	end
	return a
end

function lerp(a, b, t)
	return a + (b - a) * t
end

function dirToYawPitch(dir)
	local d = VecNormalize(dir)
	local yaw = math.deg(math.atan2(d[1], -d[3]))
	local pitch = math.deg(math.asin(clamp(d[2], -1.0, 1.0)))
	return yaw, pitch
end

function yawPitchToDir(yawDeg, pitchDeg)
	local yaw = math.rad(yawDeg)
	local pitch = math.rad(pitchDeg)
	local cp = math.cos(pitch)
	return Vec(
		math.sin(yaw) * cp,
		math.sin(pitch),
		-math.cos(yaw) * cp
	)
end

function findMountedVehicle()
	local v = FindVehicle()
	if v == 0 then
		v = FindVehicle("ciws_emplacement")
	end
	return v
end

function server.init()
	vehicle = findMountedVehicle()
	baseBody = FindBody("base")
	turretBody = FindBody("turret")
	gunBody = FindBody("gun")
	yawJoint = FindJoint("ciws_yaw")
	pitchJoint = FindJoint("ciws_pitch")
end

function server.setCameraTransform(t)
	cameraTransform = t
end

function server.tick(dt)
	if vehicle == 0 or baseBody == 0 or turretBody == 0 or gunBody == 0 then
		return
	end
	if yawJoint == 0 or pitchJoint == 0 then
		return
	end
	if IsBodyBroken(baseBody) or IsBodyBroken(turretBody) or IsBodyBroken(gunBody) then
		return
	end

	local driverId = 0
	for p in Players() do
		if GetPlayerVehicle(p) == vehicle then
			driverId = p
			break
		end
	end
	if driverId == 0 then
		return
	end

	local aimDir = TransformToParentVec(cameraTransform, Vec(0, 0, -1))
	aimDir = VecNormalize(aimDir)

	local baseTransform = GetBodyTransform(baseBody)
	local localYawDir = TransformToLocalVec(baseTransform, aimDir)
	local yaw, _ = dirToYawPitch(localYawDir)
	yaw = wrapAngle(yaw * jointConfig.yawSign + jointConfig.yawOffset)
	yaw = clamp(yaw, jointConfig.yawMin, jointConfig.yawMax)

	local turretTransform = GetBodyTransform(turretBody)
	local localPitchDir = TransformToLocalVec(turretTransform, aimDir)
	local _, pitch = dirToYawPitch(localPitchDir)
	pitch = wrapAngle(pitch * jointConfig.pitchSign + jointConfig.pitchOffset)
	pitch = clamp(pitch, jointConfig.pitchMin, jointConfig.pitchMax)

	SetJointMotorTarget(yawJoint, yaw, jointConfig.yawMaxVel, jointConfig.yawStrength)
	SetJointMotorTarget(pitchJoint, pitch, jointConfig.pitchMaxVel, jointConfig.pitchStrength)
end

function client.init()
	vehicle = findMountedVehicle()
	baseBody = FindBody("base")
	turretBody = FindBody("turret")
	gunBody = FindBody("gun")
	cameraState.initialized = false
end

function client.tick(dt)
	if GetPlayerVehicle() ~= vehicle then
		cameraState.initialized = false
		return
	end

	local cfg = cameraConfig
	local pivot = GetVehicleLocationWorldTransform(vehicle, "camera")
	if pivot == nil then
		pivot = GetBodyTransform(baseBody)
	end

	local currentCamera = GetCameraTransform()
	local currentForward = TransformToParentVec(currentCamera, Vec(0, 0, -1))

	if not cameraState.initialized then
		local yaw, pitch = dirToYawPitch(currentForward)
		cameraState.yaw = yaw
		cameraState.pitch = pitch

		local toCam = VecSub(currentCamera.pos, pivot.pos)
		local dist = VecLength(toCam)
		if dist > 0.1 then
			cameraState.distance = clamp(dist, cfg.distMin, cfg.distMax)
			cameraState.targetDistance = cameraState.distance
		end

		cameraState.initialized = true
	end

	cameraState.yaw = wrapAngle(cameraState.yaw + InputValue("camerax") * cfg.sensX * dt)
	cameraState.pitch = clamp(cameraState.pitch - InputValue("cameray") * cfg.sensY * dt, cfg.pitchMin, cfg.pitchMax)
	cameraState.targetDistance = clamp(cameraState.targetDistance - InputValue("mousewheel") * 1.5, cfg.distMin, cfg.distMax)
	cameraState.distance = lerp(cameraState.distance, cameraState.targetDistance, clamp(dt * cfg.smooth, 0.0, 1.0))

	local forward = yawPitchToDir(cameraState.yaw, cameraState.pitch)
	local upHint = Vec(0, 1, 0)
	local right = VecCross(upHint, forward)
	if VecLength(right) < 0.001 then
		right = Vec(1, 0, 0)
	end
	right = VecNormalize(right)
	local up = VecNormalize(VecCross(forward, right))
	local target = VecAdd(pivot.pos, VecScale(forward, 100.0))
	local useFirstPerson = cameraState.distance <= cfg.firstPersonThreshold

	RequestThirdPerson(not useFirstPerson)
	if gunBody ~= 0 then
		SetPivotClipBody(gunBody, 0)
	end

	if useFirstPerson then
		local fpPivot = GetVehicleLocationWorldTransform(vehicle, "player")
		if fpPivot == nil then
			fpPivot = pivot
		end
		local camPos = VecAdd(fpPivot.pos, VecScale(forward, 0.1))
		cameraTransform = Transform(camPos, QuatLookAt(camPos, target))
	else
		local idealPos = VecAdd(pivot.pos, VecScale(forward, -cameraState.distance))
		idealPos = VecAdd(idealPos, VecScale(up, cameraState.height))

		local toCamera = VecSub(idealPos, pivot.pos)
		local toCameraDist = VecLength(toCamera)
		local camPos = idealPos
		if toCameraDist > 0.001 then
			local toCameraDir = VecScale(toCamera, 1.0 / toCameraDist)
			QueryRejectVehicle(vehicle)
			if baseBody ~= 0 then
				QueryRejectBody(baseBody)
			end
			if turretBody ~= 0 then
				QueryRejectBody(turretBody)
			end
			if gunBody ~= 0 then
				QueryRejectBody(gunBody)
			end
			local hit, hitDist = QueryRaycast(pivot.pos, toCameraDir, toCameraDist, cfg.radius)
			if hit then
				local safeDist = math.max(0.3, hitDist - cfg.radius)
				camPos = VecAdd(pivot.pos, VecScale(toCameraDir, safeDist))
			end
		end

		cameraTransform = Transform(camPos, QuatLookAt(camPos, target))
	end

	if baseBody ~= 0 then
		local baseTransform = GetBodyTransform(baseBody)
		local cameraLocalTransform = TransformToLocalTransform(baseTransform, cameraTransform)
		AttachCameraTo(baseBody, false)
		SetCameraOffsetTransform(cameraLocalTransform)
	else
		SetCameraTransform(cameraTransform, cfg.fov)
	end

	ServerCall("server.setCameraTransform", cameraTransform)
end
