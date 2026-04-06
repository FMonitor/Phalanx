#version 2

#include "script/include/player.lua"

vehicle = 0
baseBody = 0
turretBody = 0
gunBody = 0
yawJoint = 0
pitchJoint = 0

cameraTransform = Transform()
serverControlActive = false
debugPitchTarget = 0.0
debugPitchCurrent = 0.0
debugPitchError = 0.0
debugPitchVelDeg = 0.0
yawMotorVelDeg = 0.0
pitchMotorVelDeg = 0.0

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
	yawOffset = -90.0,
	yawSign = -1.0,
	pitchOffset = 0.0,
	pitchSign = -1.0,
	motorStopError = 1.0,
	motorStrength = 10000.0,
	yawSpeedDeg = 50.0,
	pitchSpeedDeg = 35.0,
	motorSlowdownDegPerSec = 120.0,
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

function moveTowards(current, target, maxDelta)
	if current < target then
		return math.min(current + maxDelta, target)
	end
	if current > target then
		return math.max(current - maxDelta, target)
	end
	return target
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

function dirToPitchFromX(dir)
	local d = VecNormalize(dir)
	return math.deg(math.atan2(d[2], d[1]))
end

function getGunMountedTransform(localPos, localRot)
	if gunBody == 0 then
		return nil
	end
	local gunTransform = GetBodyTransform(gunBody)
	local localTransform = Transform(localPos, localRot or Quat())
	return TransformToParentTransform(gunTransform, localTransform)
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

function server.setControlActive(active, controlledVehicle, controlledBody)
	serverControlActive = active
end

function server.tick(dt)
	if vehicle == 0 or baseBody == 0 or turretBody == 0 or gunBody == 0 then
		DebugWatch("CIWS SRV PitchState", "missing_handles")
		return
	end
	if yawJoint == 0 or pitchJoint == 0 then
		DebugWatch("CIWS SRV PitchState", "missing_joint")
		return
	end
	if IsBodyBroken(turretBody) or IsBodyBroken(gunBody) then
		DebugWatch("CIWS SRV PitchState", "broken")
		return
	end

	if not serverControlActive then
		local slow = jointConfig.motorSlowdownDegPerSec * dt
		yawMotorVelDeg = moveTowards(yawMotorVelDeg, 0.0, slow)
		pitchMotorVelDeg = moveTowards(pitchMotorVelDeg, 0.0, slow)
		SetJointMotor(yawJoint, math.rad(yawMotorVelDeg), jointConfig.motorStrength)
		SetJointMotor(pitchJoint, math.rad(pitchMotorVelDeg), jointConfig.motorStrength)
		DebugWatch("CIWS SRV PitchState", "inactive")
		return
	end

	local aimDir = TransformToParentVec(cameraTransform, Vec(0, 0, -1))
	aimDir = VecNormalize(aimDir)

	local baseTransform = GetBodyTransform(baseBody)
	local localYawDir = TransformToLocalVec(baseTransform, aimDir)
	local yawWrapped = select(1, dirToYawPitch(localYawDir))
	local rawTarget = wrapAngle(yawWrapped * jointConfig.yawSign + jointConfig.yawOffset)

	local turretTransform = GetBodyTransform(turretBody)
	local turretForwardWorld = TransformToParentVec(turretTransform, Vec(0, 0, 1))
	local turretForwardLocal = TransformToLocalVec(baseTransform, turretForwardWorld)
	local currentYaw = select(1, dirToYawPitch(turretForwardLocal))
	currentYaw = wrapAngle(currentYaw * jointConfig.yawSign)
	local yawError = wrapAngle(rawTarget - currentYaw)
	local desiredVelDeg = 0.0
	local desiredStrength = 0.0
	if math.abs(yawError) > jointConfig.motorStopError then
		if yawError > 0.0 then
			desiredVelDeg = jointConfig.yawSpeedDeg
		else
			desiredVelDeg = -jointConfig.yawSpeedDeg
		end
		desiredStrength = jointConfig.motorStrength
	end
	if IsBodyBroken(baseBody) then
		desiredVelDeg = desiredVelDeg * 0.5
	end
	yawMotorVelDeg = desiredVelDeg
	SetJointMotor(yawJoint, math.rad(yawMotorVelDeg), desiredStrength)

	local turretAimDir = TransformToLocalVec(turretTransform, aimDir)
	local rawPitchTarget = dirToPitchFromX(turretAimDir)
	rawPitchTarget = wrapAngle(rawPitchTarget * jointConfig.pitchSign + jointConfig.pitchOffset)
	debugPitchTarget = rawPitchTarget

	local gunTransform = GetBodyTransform(gunBody)
	local gunForwardWorld = TransformToParentVec(gunTransform, Vec(1, 0, 0))
	local gunForwardLocal = TransformToLocalVec(turretTransform, gunForwardWorld)
	local currentPitch = dirToPitchFromX(gunForwardLocal)
	currentPitch = wrapAngle(currentPitch * jointConfig.pitchSign)
	debugPitchCurrent = currentPitch
	local pitchError = wrapAngle(rawPitchTarget - currentPitch)
	debugPitchError = pitchError
	local desiredPitchVelDeg = 0.0
	local desiredPitchStrength = jointConfig.motorStrength
	if math.abs(pitchError) > jointConfig.motorStopError then
		if pitchError > 0.0 then
			desiredPitchVelDeg = jointConfig.pitchSpeedDeg
		else
			desiredPitchVelDeg = -jointConfig.pitchSpeedDeg
		end
	end
	if IsBodyBroken(turretBody) then
		desiredPitchVelDeg = desiredPitchVelDeg * 0.5
	end
	debugPitchVelDeg = desiredPitchVelDeg
	pitchMotorVelDeg = desiredPitchVelDeg
	SetJointMotor(pitchJoint, math.rad(pitchMotorVelDeg), desiredPitchStrength)

	DebugWatch("CIWS SRV PitchState", "active")
	DebugWatch("CIWS SRV PitchTarget", string.format("%.1f", debugPitchTarget))
	DebugWatch("CIWS SRV PitchCurrent", string.format("%.1f", debugPitchCurrent))
	DebugWatch("CIWS SRV PitchError", string.format("%.1f", debugPitchError))
	DebugWatch("CIWS SRV PitchVel", string.format("%.1f", debugPitchVelDeg))
end

function client.init()
	vehicle = findMountedVehicle()
	baseBody = FindBody("base")
	turretBody = FindBody("turret")
	gunBody = FindBody("gun")
	pitchJoint = FindJoint("ciws_pitch")
	cameraState.initialized = false
end

function client.tick(dt)
	local currentVehicle = GetPlayerVehicle()
	local currentVehicleBody = 0
	if currentVehicle ~= 0 then
		currentVehicleBody = GetVehicleBody(currentVehicle)
	end

	if currentVehicle == 0 or currentVehicleBody ~= baseBody then
		cameraState.initialized = false
		ServerCall("server.setControlActive", false, currentVehicle, currentVehicleBody)
		return
	end

	SetPlayerHidden()

	local cfg = cameraConfig
	local pivot = getGunMountedTransform(Vec(0.0, 2.9, -0.2))
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

	RequestThirdPerson(false)
	if gunBody ~= 0 then
		SetPivotClipBody(gunBody, 0)
	end
	if turretBody ~= 0 then
		SetPivotClipBody(turretBody, 0)
	end

	if useFirstPerson then
		local fpPivot = getGunMountedTransform(Vec(0.8, 0.7, -0.05), QuatEuler(0.0, 180.0, 0.0))
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

	local cameraAttachBody = gunBody
	if cameraAttachBody == 0 then
		cameraAttachBody = baseBody
	end

	if cameraAttachBody ~= 0 then
		local attachTransform = GetBodyTransform(cameraAttachBody)
		local cameraLocalTransform = TransformToLocalTransform(attachTransform, cameraTransform)
		AttachCameraTo(cameraAttachBody, false)
		SetCameraOffsetTransform(cameraLocalTransform)
	else
		SetCameraTransform(cameraTransform, cfg.fov)
	end

	ServerCall("server.setControlActive", true, currentVehicle, currentVehicleBody)
	ServerCall("server.setCameraTransform", cameraTransform)
end
