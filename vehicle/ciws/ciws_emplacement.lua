#version 2

#include "script/include/player.lua"
#include "../../shared/phalanx_weapon/phalanx_weapon_config.lua"
#include "../../shared/phalanx_weapon/phalanx_weapon_projectile.lua"
#include "../../shared/phalanx_weapon/phalanx_weapon_fx.lua"
#include "../../shared/phalanx_weapon/phalanx_weapon_spin.lua"
#include "../../shared/phalanx_weapon/phalanx_weapon_audio.lua"

vehicle = 0

function VecTempCopy(v)
        return Vec(v[1], v[2], v[3])
end
function QuatTempCopy(q)
        return Quat(q[1], q[2], q[3], q[4])
end

baseBody = 0
turretBody = 0
gunBody = 0
yawJoint = 0
pitchJoint = 0

cameraTransform = Transform()
serverControlActive = false
serverFireInput = false
autoFireEnabled = false
yawMotorVelDeg = 0.0
pitchMotorVelDeg = 0.0

ciwsWeaponConfig = phalanxWeaponMakeConfig({
	name = "phalanx_ciws",
	fireCooldown = 0.025,
	spread = 0.01,
})

weaponState = phalanxWeaponProjectile.createState()
ciwsFxState = phalanxWeaponFx.createState()

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
	pitchMin = -10.0,
	pitchMax = 85.0,
	radius = 0.25,
	smooth = 10.0,
	fov = 120,
}

jointConfig = {
	yawOffset = -90.0,
	yawSign = -1.0,
	pitchOffset = 0.0,
	pitchSign = -1.0,
	motorStopError = 1.0,
	motorStrength = 10000.0,
	yawSpeedDeg = 90.0,
	pitchSpeedDeg = 120.0,
	motorSlowdownDegPerSec = 40.0,
}

weaponOffsets = {
	muzzle = Vec(3, 0, -0.05),    -- 枪口开火生成点（即火光和子弹起�?
	spinPivot = Vec(0.0, 0.35, 0.35) -- 枪管旋转轴圆�?
}

barrelSpinState = nil
turretRotLoop = 0
turretRotVolume = 1.5
audioState = nil
shootHaptic = 0
reticle = 0
barrelHeat = 0.0
isOverheated = false
ciwsMode = {
	isAi = false,
	ignoreHeat = false,
	ignoreDamagePenalty = false,
	requiresSignal = false,
	targetBody = 0,
	targetPoint = Vec(),
	scanTimer = 0.0,
	fireTimer = 0.0,
}

aiConfig = {
	activationFlag = "level.phalanx.demo.raid_active",
	targetTag = "phalanx_ai_target",
	maxRange = 260.0,
	scanInterval = 1,
	leadFactor = 1.0,
	fireYawTolerance = 3.0,
	firePitchTolerance = 3.0,
	triggerHoldSeconds = 0.18,
}

local cachedModuleShapes = {}
local cachedModuleStatus = {}
local statusTimer = 0.0

function getModuleStatus(moduleBody, moduleJoint, moduleShapeTag, minVoxels)
	if moduleBody == 0 or not IsHandleValid(moduleBody) then return "Destroyed" end
	if moduleJoint ~= 0 and (not IsHandleValid(moduleJoint) or IsJointBroken(moduleJoint)) then return "Destroyed" end

	if moduleShapeTag and moduleShapeTag ~= "" then
		local cacheKey = moduleBody .. "_" .. moduleShapeTag
		if cachedModuleStatus[cacheKey] and cachedModuleStatus[cacheKey].time > GetTime() - 1 then
			return cachedModuleStatus[cacheKey].status
		end

		local shape = cachedModuleShapes[moduleShapeTag]
		if not shape or not IsHandleValid(shape) then
			local shapes = GetBodyShapes(moduleBody)
			if shapes ~= nil then
				for i=1, #shapes do
					if HasTag(shapes[i], moduleShapeTag) then
						shape = shapes[i]
						cachedModuleShapes[moduleShapeTag] = shape
						break
					end
				end
			end
		end

		local status = "Destroyed"
		if shape ~= nil and IsHandleValid(shape) then
			if GetShapeVoxelCount(shape) >= minVoxels then
				if IsShapeBroken(shape) then status = "Damaged" else status = "Good" end
			end
		end
		
		cachedModuleStatus[cacheKey] = { status = status, time = GetTime() }
		return status
	end
	if IsBodyBroken(moduleBody) then return "Damaged" end
	return "Good"
end

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

function vecLerp(a, b, t)
	return Vec(
		lerp(a[1], b[1], t),
		lerp(a[2], b[2], t),
		lerp(a[3], b[3], t)
	)
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

function dirToElevation(dir)
	local d = VecNormalize(dir)
	local horizontal = math.sqrt(d[1] * d[1] + d[3] * d[3])
	return math.deg(math.atan2(d[2], horizontal))
end

function findMountedVehicle()
	local v = FindVehicle()
	if v == 0 then
		v = FindVehicle("ciws_emplacement")
	end
	return v
end

function rndVec(length)
	local v = VecNormalize(Vec(math.random(-100, 100), math.random(-100, 100), math.random(-100, 100)))
	return VecScale(v, length)
end

function getGunMountedTransform(localPos, localRot)
	if gunBody == 0 then
		return nil
	end
	local gunTransform = GetBodyTransform(gunBody)
	local localTransform = Transform(localPos, localRot or Quat())
	return TransformToParentTransform(gunTransform, localTransform)
end

function getMuzzlePosAndDir()
	if gunBody == 0 then
		return Vec(), Vec(1, 0, 0)
	end
	local gunTransform = GetBodyTransform(gunBody)
	local gunDir = TransformToParentVec(gunTransform, Vec(1, 0, 0))
	local muzzleOffset = TransformToParentVec(gunTransform, weaponOffsets.muzzle)
	local muzzlePos = VecAdd(gunTransform.pos, muzzleOffset)
	return muzzlePos, VecNormalize(gunDir)
end

function spawnProjectileGlow(pos, vel)
	phalanxWeaponFx.spawnProjectileGlow(pos, vel, rndVec, ciwsWeaponConfig)
end

function createProjectile(pos, dir)
	phalanxWeaponProjectile.add(weaponState, ciwsWeaponConfig, pos, dir, 0)
end

function tickProjectiles(dt)
	phalanxWeaponProjectile.tick(weaponState, ciwsWeaponConfig, dt, "client.renderProjectileSmoke")
end

function ensureBarrelSpinState()
	barrelSpinState = barrelSpinState or phalanxWeaponSpin.createState()
	barrelSpinState.launcherShape = barrelSpinState.launcherShape or 0
	barrelSpinState.launcherLocalTransform = barrelSpinState.launcherLocalTransform or nil

	if barrelSpinState.launcherShape == 0 and gunBody ~= 0 then
		local shapes = GetBodyShapes(gunBody)
		if shapes ~= nil then
			for i = 1, #shapes do
				if HasTag(shapes[i], "ciws_barrel") then
					barrelSpinState.launcherShape = shapes[i]
					break
				end
			end
			if barrelSpinState.launcherShape ~= 0 then
				barrelSpinState.launcherLocalTransform = GetShapeLocalTransform(barrelSpinState.launcherShape)
			end
		end
	end

	return barrelSpinState
end

function animateBarrelSpin()
	local spin = ensureBarrelSpinState()
	if spin.launcherShape == 0 or spin.launcherLocalTransform == nil then
		return
	end

	local base = Transform(
		VecTempCopy(spin.launcherLocalTransform.pos),
		QuatTempCopy(spin.launcherLocalTransform.rot)
	)
	local pivot = weaponOffsets.spinPivot
	local pivotT = Transform(VecTempCopy(pivot))
	local unpivotT = Transform(VecScale(pivot, -1))
	local spinT = Transform(Vec(), QuatEuler(spin.angle, 0, 0))
	local t = TransformToParentTransform(pivotT, spinT)
	t = TransformToParentTransform(t, unpivotT)
	t = TransformToParentTransform(base, t)
	SetShapeLocalTransform(spin.launcherShape, t)
end

function getLocalYawErrorFromCamera()
	if baseBody == 0 or turretBody == 0 then
		return 0.0
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

	return wrapAngle(rawTarget - currentYaw)
end

function getShootDir()
	local muzzlePos, fallbackDir = getMuzzlePosAndDir()
	if gunBody == 0 then
		return fallbackDir
	end

	if ciwsMode.isAi and not serverControlActive and ciwsMode.targetBody ~= 0 and IsHandleValid(ciwsMode.targetBody) then
		return VecNormalize(VecSub(ciwsMode.targetPoint, muzzlePos))
	end

	local gunTransform = GetBodyTransform(gunBody)
	local gunDir = TransformToParentVec(gunTransform, Vec(1, 0, 0))
	if baseBody ~= 0 then
		QueryRejectBody(baseBody)
	end
	if turretBody ~= 0 then
		QueryRejectBody(turretBody)
	end
	if gunBody ~= 0 then
		QueryRejectBody(gunBody)
	end
	local rayHit, rayDist = QueryRaycast(cameraTransform.pos, TransformToParentVec(cameraTransform, Vec(0, 0, -1)), 500)
	if rayHit then
		local hitPos = VecAdd(cameraTransform.pos, VecScale(TransformToParentVec(cameraTransform, Vec(0, 0, -1)), rayDist))
		return VecNormalize(VecSub(hitPos, muzzlePos))
	end
	return VecNormalize(gunDir)
end

function readCiwsMode()
	local tagCarrier = vehicle
	if tagCarrier == 0 then
		tagCarrier = baseBody
	end

	ciwsMode.isAi = tagCarrier ~= 0 and HasTag(tagCarrier, "ciws_ai")
	ciwsMode.ignoreHeat = tagCarrier ~= 0 and HasTag(tagCarrier, "ciws_ai_noheat")
	ciwsMode.ignoreDamagePenalty = tagCarrier ~= 0 and HasTag(tagCarrier, "ciws_ai_ignore_damage")
	ciwsMode.requiresSignal = tagCarrier ~= 0 and HasTag(tagCarrier, "ciws_ai_requires_signal")
	ciwsMode.targetBody = 0
	ciwsMode.targetPoint = Vec()
	ciwsMode.scanTimer = 0.0
	ciwsMode.fireTimer = 0.0
	
	if ciwsMode.isAi then
		DebugWatch("CIWS AI Mode initialized for vehicle/body: " .. tostring(tagCarrier))
	end
end


function isAiTargetValid(bodyOrVehicle)
	if GetEntityType(bodyOrVehicle) == "vehicle" then
		return bodyOrVehicle ~= 0 and IsHandleValid(bodyOrVehicle) and GetVehicleHealth(bodyOrVehicle) > 0.0
	end
	return bodyOrVehicle ~= 0 and IsHandleValid(bodyOrVehicle) and not IsBodyBroken(bodyOrVehicle)
end

function getAiAimPivot()
	local pivot = getGunMountedTransform(Vec(0.0, 1.8, -0.6))
	if pivot ~= nil then
		return pivot
	end
	if turretBody ~= 0 then
		return GetBodyTransform(turretBody)
	end
	return GetBodyTransform(baseBody)
end

function getAiTargetPoint(bodyOrVehicle, origin)
        local aimPos
        local vel
        
        if GetEntityType(bodyOrVehicle) == 'vehicle' then
                local b = GetVehicleBody(bodyOrVehicle)
                if b ~= 0 then 
                        local tf = GetBodyTransform(b)
                        aimPos = VecTempCopy(tf.pos)
                        vel = GetBodyVelocity(b) 
                else 
                        local tf = GetVehicleTransform(bodyOrVehicle)
                        aimPos = VecTempCopy(tf.pos)
                        vel = Vec() 
                end
        else
                local tf = GetBodyTransform(bodyOrVehicle)
                aimPos = VecTempCopy(tf.pos)
                vel = GetBodyVelocity(bodyOrVehicle)
        end

        local distance = VecLength(VecSub(aimPos, origin))
        local projectileSpeed = math.max(1.0, ciwsWeaponConfig.projectileSpeed or 100.0)
        local travelTime = clamp(distance / projectileSpeed, 0.0, 2.5)

        -- Gravity compensation
        local projGravity = ciwsWeaponConfig.projectileGravity or 9.8
        local heightOffset = (0.5 * projGravity * travelTime * travelTime) + 1.2 -- +1.2m offset to hit upper body

        if vel then
                local predictedPos = VecAdd(aimPos, VecScale(vel, travelTime * aiConfig.leadFactor))
                predictedPos[2] = predictedPos[2] + heightOffset
                aimPos = predictedPos
        else
                aimPos[2] = aimPos[2] + heightOffset
        end
        return aimPos
end


function canAiSeePoint(origin, point, targetBodyOrVehicle)
        local toPoint = VecSub(point, origin)
        local dist = VecLength(toPoint)
        if dist < 0.001 then
                return true
        end

        if baseBody ~= 0 then
                QueryRejectBody(baseBody)
        end
        if turretBody ~= 0 then
                QueryRejectBody(turretBody)
        end
        if gunBody ~= 0 then
                QueryRejectBody(gunBody)
        end

        local dir = VecScale(toPoint, 1.0 / dist)
        local hit, hitDist, normal, shape = QueryRaycast(origin, dir, dist, 0.1)
        
        if not hit then
                return true
        end
        
        local hitBody = GetShapeBody(shape)
        if hitBody ~= 0 then
                if hitBody == targetBodyOrVehicle or GetBodyVehicle(hitBody) == targetBodyOrVehicle then
                        return true
                end
        end

        return hitDist >= dist - 1.0
end

function acquireAiTarget(origin)
        local bestBody = 0
        local bestPoint = Vec()
        local bestScore = aiConfig.maxRange + 1.0

        local function checkTargets(targets)
                if targets == nil then return end
                for i = 1, #targets do
                        local target = targets[i]
                        if target ~= baseBody and target ~= turretBody and target ~= gunBody then
                                local isValid = isAiTargetValid(target)
                                if isValid then
                                        local point = getAiTargetPoint(target, origin)
                                        local dist = VecLength(VecSub(point, origin))
						if point[2] < origin[2] - 1.0 then dist = aiConfig.maxRange + 10.0 end
                                        
                                        if dist <= aiConfig.maxRange and dist < bestScore then
                                                local canSee = canAiSeePoint(origin, point, target)
                                                if canSee then
                                                        bestScore = dist
                                                        bestBody = target
                                                        bestPoint = point
                                                end
                                        end
                                end
                        end
                end
        end

        local scanTags = {'drone', 'phalanx_drone', 'plane', 'helicopter', 'phalanx_ai_target'}
        local validTargets = {}
        for t = 1, #scanTags do
                local tagVehicles = FindVehicles(scanTags[t], true)
                if tagVehicles ~= nil then
                        for i = 1, #tagVehicles do
                                validTargets[#validTargets + 1] = tagVehicles[i]
                        end
                end
        end
        checkTargets(validTargets)
        
        local bodies = FindBodies(aiConfig.targetTag, true)
        if bodies ~= nil then
                for i=1, #bodies do
                        validTargets[#validTargets+1] = bodies[i]
                end
        end

        return bestBody, bestPoint
end


function updateAiTracking(dt)
	if not ciwsMode.isAi then
		ciwsMode.targetBody = 0
		ciwsMode.fireTimer = 0.0
		return false
	end

	local muzzlePos, _ = getMuzzlePosAndDir()
	local hasTarget = false

	if isAiTargetValid(ciwsMode.targetBody) then
		ciwsMode.trackUpdateTimer = (ciwsMode.trackUpdateTimer or 0.0) - dt

		if ciwsMode.trackUpdateTimer <= 0.0 then
			local point = getAiTargetPoint(ciwsMode.targetBody, muzzlePos)
			local dist = VecLength(VecSub(point, muzzlePos))
			if point[2] < muzzlePos[2] - 1.0 then dist = aiConfig.maxRange + 10.0 end
			
			ciwsMode.hasLos = canAiSeePoint(muzzlePos, point, ciwsMode.targetBody)
			
			if dist <= aiConfig.maxRange and ciwsMode.hasLos then
				ciwsMode.targetPoint = point
				hasTarget = true
				ciwsMode.lastValidTarget = true
			else
				ciwsMode.targetBody = 0
				ciwsMode.hasLos = nil
				ciwsMode.lastValidTarget = false
			end
			-- Update interval: 10Hz to save performance since servo smoothing handles the rest
			ciwsMode.trackUpdateTimer = 0.3
		else
			hasTarget = ciwsMode.lastValidTarget
		end
	end
	ciwsMode.scanTimer = ciwsMode.scanTimer - dt
	if ciwsMode.scanTimer <= 0.0 then
		ciwsMode.scanTimer = aiConfig.scanInterval
		local targetBody, targetPoint = acquireAiTarget(muzzlePos)
		if targetBody ~= 0 then
			ciwsMode.targetBody = targetBody
			ciwsMode.targetPoint = targetPoint
			hasTarget = true
			ciwsMode.hasLos = true
		elseif not hasTarget then
			ciwsMode.targetBody = 0
		end
	end

	if not hasTarget then
		ciwsMode.fireTimer = math.max(0.0, ciwsMode.fireTimer - dt)
		return false
	end

	local pivot = getAiAimPivot()
	cameraTransform = Transform(pivot.pos, QuatLookAt(pivot.pos, ciwsMode.targetPoint))
	return true
end

function server.init()
	DebugWatch("CIWS server.init started")
	vehicle = findMountedVehicle()
	DebugWatch("CIWS server findMountedVehicle returned: " .. tostring(vehicle))
	
	baseBody = FindBody("base")
	turretBody = FindBody("turret")
	gunBody = FindBody("gun")
	yawJoint = FindJoint("ciws_yaw")
	pitchJoint = FindJoint("ciws_pitch")
	
	DebugWatch("CIWS bodies: base=" .. tostring(baseBody) .. " turret=" .. tostring(turretBody) .. " gun=" .. tostring(gunBody))
	
	ensureBarrelSpinState()
	readCiwsMode()
	DebugWatch("CIWS server.init completed")
end

function server.setCameraTransform(t)
	cameraTransform = t
end

function server.setControlState(active, firing)
	serverControlActive = active == true
	serverFireInput = firing == true
end

function server.setAutoFire(enabled)
	autoFireEnabled = enabled == true
end

function server.tick(dt)
	tickProjectiles(dt)

	if vehicle == 0 or baseBody == 0 or turretBody == 0 or gunBody == 0 then
		return
	end
	if yawJoint == 0 or pitchJoint == 0 then
		return
	end

	local spin = ensureBarrelSpinState()

	local gunStatus = getModuleStatus(gunBody, pitchJoint, "ciws_barrel", 5)
	local turretStatus = getModuleStatus(turretBody, yawJoint, "ciws_turret", 10)
	local radarStatus = getModuleStatus(gunBody, 0, "ciws_radar", 10)
	local mountStatus = getModuleStatus(gunBody, pitchJoint, "ciws_mount", 10)
	local ignoreHeat = ciwsMode.isAi and ciwsMode.ignoreHeat
	local ignoreDamagePenalty = ciwsMode.isAi and ciwsMode.ignoreDamagePenalty
	local aiTrackingActive = false

	if ignoreHeat then
		barrelHeat = 0.0
		isOverheated = false
	else
		local heatConfig = ciwsWeaponConfig
		local heatCoolingDynamic = heatConfig.heatCoolingDynamic or 0.1
		local heatCoolingBase = heatConfig.heatCoolingBase or 0.1
		local coolRate = heatCoolingBase + (1.0 - barrelHeat) * heatCoolingDynamic
		barrelHeat = math.max(0.0, barrelHeat - dt * coolRate)
		
		if isOverheated and barrelHeat <= (heatConfig.heatRecoverThreshold or 0.0) then
			isOverheated = false
		end
	end

	if ciwsMode.isAi and not serverControlActive and radarStatus ~= "Destroyed" then
		aiTrackingActive = updateAiTracking(dt)
	end

	if not serverControlActive and not autoFireEnabled and not aiTrackingActive then
		local slow = jointConfig.motorSlowdownDegPerSec * dt
		yawMotorVelDeg = moveTowards(yawMotorVelDeg, 0.0, slow)
		pitchMotorVelDeg = moveTowards(pitchMotorVelDeg, 0.0, slow)
		SetJointMotor(yawJoint, math.rad(yawMotorVelDeg), jointConfig.motorStrength)
		SetJointMotor(pitchJoint, math.rad(pitchMotorVelDeg), jointConfig.motorStrength)
		phalanxWeaponSpin.tickSpin(spin, dt, false)
		animateBarrelSpin()
		return
	end

	local aimDir = TransformToParentVec(cameraTransform, Vec(0, 0, -1))
	aimDir = VecNormalize(aimDir)

	local baseTransform = GetBodyTransform(baseBody)
	local localYawDir = TransformToLocalVec(baseTransform, aimDir)
	local yawWrapped = select(1, dirToYawPitch(localYawDir))
	local rawYawTarget = wrapAngle(yawWrapped * jointConfig.yawSign + jointConfig.yawOffset)

	local turretTransform = GetBodyTransform(turretBody)
	local turretForwardWorld = TransformToParentVec(turretTransform, Vec(0, 0, 1))
	local turretForwardLocal = TransformToLocalVec(baseTransform, turretForwardWorld)
	local currentYaw = select(1, dirToYawPitch(turretForwardLocal))
	currentYaw = wrapAngle(currentYaw * jointConfig.yawSign)
	local yawError = wrapAngle(rawYawTarget - currentYaw)

	local desiredYawVelDeg = 0.0
	local desiredYawStrength = 0.0
	if math.abs(yawError) > jointConfig.motorStopError then
		if yawError > 0.0 then
			desiredYawVelDeg = jointConfig.yawSpeedDeg
		else
			desiredYawVelDeg = -jointConfig.yawSpeedDeg
		end
		desiredYawStrength = jointConfig.motorStrength
	end
	if turretStatus == "Destroyed" then
		desiredYawVelDeg = 0.0
	elseif turretStatus == "Damaged" and not ignoreDamagePenalty then
		desiredYawVelDeg = desiredYawVelDeg * 0.5
	end
	yawMotorVelDeg = desiredYawVelDeg
	SetJointMotor(yawJoint, math.rad(yawMotorVelDeg), desiredYawStrength)

	local rawPitchTarget = dirToElevation(localYawDir)
	rawPitchTarget = wrapAngle(rawPitchTarget * jointConfig.pitchSign + jointConfig.pitchOffset)

	local gunTransform = GetBodyTransform(gunBody)
	local gunForwardWorld = TransformToParentVec(gunTransform, Vec(1, 0, 0))
	local gunForwardLocal = TransformToLocalVec(turretTransform, gunForwardWorld)
	local currentPitch = dirToPitchFromX(gunForwardLocal)
	currentPitch = wrapAngle(currentPitch * jointConfig.pitchSign)
	local pitchError = wrapAngle(rawPitchTarget - currentPitch)

	local desiredPitchVelDeg = 0.0
	local desiredPitchStrength = jointConfig.motorStrength
	if math.abs(pitchError) > jointConfig.motorStopError then
		if pitchError > 0.0 then
			desiredPitchVelDeg = jointConfig.pitchSpeedDeg
		else
			desiredPitchVelDeg = -jointConfig.pitchSpeedDeg
		end
	end
	if mountStatus == "Destroyed" then
		desiredPitchVelDeg = 0.0
	elseif mountStatus == "Damaged" and not ignoreDamagePenalty then
		desiredPitchVelDeg = desiredPitchVelDeg * 0.5
	end
	pitchMotorVelDeg = desiredPitchVelDeg
	SetJointMotor(pitchJoint, math.rad(pitchMotorVelDeg), desiredPitchStrength)

	local canFire = gunStatus ~= "Destroyed" and mountStatus ~= "Destroyed" and (ignoreHeat or not isOverheated)
	local requestedFire = serverFireInput or autoFireEnabled
	if aiTrackingActive then
		local aligned = math.abs(yawError) <= aiConfig.fireYawTolerance and math.abs(pitchError) <= aiConfig.firePitchTolerance
		if aligned then
			ciwsMode.fireTimer = aiConfig.triggerHoldSeconds
		else
			ciwsMode.fireTimer = math.max(0.0, ciwsMode.fireTimer - dt)
		end
		requestedFire = ciwsMode.fireTimer > 0.0
	end

	local currentlyFiring = canFire and requestedFire
	phalanxWeaponSpin.tickSpin(spin, dt, currentlyFiring)
	if currentlyFiring and phalanxWeaponSpin.tryFire(spin, ciwsWeaponConfig) then
		if not ignoreHeat then
			local heatPerShot = ciwsWeaponConfig.heatPerShot or 0.015
			barrelHeat = math.min(1.0, barrelHeat + heatPerShot)
			if barrelHeat >= (ciwsWeaponConfig.heatOverheatThreshold or 1.0) then
				isOverheated = true
			end
		end

		local currentSpread = ciwsWeaponConfig.spread
		if gunStatus == "Damaged" and not ignoreDamagePenalty then
			currentSpread = currentSpread * 5.0
		end
		local muzzlePos, _ = getMuzzlePosAndDir()
		local shootDir = VecNormalize(VecAdd(getShootDir(), rndVec(currentSpread)))
		local projectilePos = VecAdd(muzzlePos, VecScale(shootDir, 0.6))
		createProjectile(projectilePos, shootDir)

		ClientCall(0, "client.playGunShot", muzzlePos[1], muzzlePos[2], muzzlePos[3])
	end

	SetFloat("vehicle."..vehicle..".barrelHeat", barrelHeat)
	SetBool("vehicle."..vehicle..".isOverheated", isOverheated)

	animateBarrelSpin()
end

function client.init()
	DebugWatch("CIWS client.init started")
	vehicle = findMountedVehicle()
	baseBody = FindBody("base")
	turretBody = FindBody("turret")
	gunBody = FindBody("gun")
	yawJoint = FindJoint("ciws_yaw")
	pitchJoint = FindJoint("ciws_pitch")
	cameraState.initialized = false
	audioState = phalanxWeaponAudio.loadState()
	turretRotLoop = LoadLoop("MOD/snd/turret-rot.ogg")
	shootHaptic = LoadHaptic("MOD/haptic/gun_fire.xml")
	reticle = LoadSprite("gfx/reticle4.png")
	readCiwsMode()
	DebugWatch("CIWS client.init completed. AI Mode: " .. tostring(ciwsMode.isAi))

	autoFireState = {
		enabled = false,
		synced = true,
	}
end

function client.renderProjectileSmoke(px, py, pz, vx, vy, vz)
	local pos = Vec(px, py, pz)
	local vel = Vec(vx, vy, vz)
	spawnProjectileGlow(pos, vel)
end

function client.playGunShot(px, py, pz)
	local pos = Vec(px, py, pz)
	if GetPlayerVehicle() == vehicle and cameraTransform ~= nil and cameraTransform.pos ~= nil then
		pos = cameraTransform.pos
	end
	phalanxWeaponAudio.playShot(audioState, ciwsWeaponConfig, pos)
	if shootHaptic ~= 0 and GetPlayerVehicle() == vehicle then
		PlayHaptic(shootHaptic, 1)
	end
end

function client.draw(dt)
	if GetPlayerVehicle() ~= vehicle or GetString("level.state") ~= "" then
		return
	end

	if gunBody == 0 then
		return
	end

	local gunStatus = getModuleStatus(gunBody, pitchJoint, "ciws_barrel", 5)
	local turretStatus = getModuleStatus(turretBody, yawJoint, "ciws_turret", 10)
	local radarStatus = getModuleStatus(gunBody, 0, "ciws_radar", 10)
	local mountStatus = getModuleStatus(gunBody, pitchJoint, "ciws_mount", 10)	

	barrelHeat = GetFloat("vehicle."..vehicle..".barrelHeat")
	isOverheated = GetBool("vehicle."..vehicle..".isOverheated")

	UiPush()
		UiTranslate(UiWidth() - 550, UiHeight() - 200)
		UiAlign("left top")
		UiColor(0.06, 0.07, 0.09, 0.78)
		UiRect(240, 165)

		UiPush()
			UiColor(1, 1, 1, 0.3)
			UiRect(240, 2)
			UiRect(2, 165)
			UiTranslate(0, 163)
			UiRect(240, 2)
			UiTranslate(338, -163)
			UiRect(2, 165)
		UiPop()

		UiTranslate(20, 20)
		UiFont("bold.ttf", 22)
		if gunStatus == "Destroyed" or mountStatus == "Destroyed" or turretStatus == "Destroyed" then
			UiColor(1, 0.2, 0.2, 1)
			UiText("SYSTEM CRITICAL")
		else
			UiColor(1, 1, 1, 1)
			UiText("CIWS STATUS")
		end

		UiTranslate(0, 32)
		UiFont("regular.ttf", 18)
		
		local function drawStatus(label, status, yOffset)
			UiPush()
			UiTranslate(0, yOffset)
			UiColor(0.8, 0.8, 0.8, 1)
			UiText(label)
			UiTranslate(80, 0)
			if status == "Good" then UiColor(0.2, 0.8, 0.2, 1)
			elseif status == "Damaged" then UiColor(1, 0.5, 0, 1)
			else UiColor(1, 0.2, 0.2, 1) end
			UiText(status)
			UiPop()
		end

		drawStatus("Barrel:", gunStatus, 0)
		drawStatus("Mount:", mountStatus, 20)
		drawStatus("Turret:", turretStatus, 40)
		drawStatus("Radar:", radarStatus, 60)

		UiPush()
			UiTranslate(160, -20) -- right side
			UiColor(0.2, 0.2, 0.2, 1)
			UiRect(20, 100) -- empty bar wrapper
			
			UiTranslate(2, 2)
			UiColor(0.1, 0.1, 0.1, 1)
			UiRect(16, 96) -- inner wrapper
			
			if barrelHeat > 0.0 then
				local heatH = barrelHeat * 96
				UiTranslate(0, 96 - heatH)
				if isOverheated then
					UiColor(1, 0.2, 0.2, 1)
				else
					UiColor(lerp(0.2, 1.0, barrelHeat), lerp(0.8, 0.2, barrelHeat), 0.2, 1)
				end
				UiRect(16, heatH)
				UiTranslate(0, -(96 - heatH))
			end
			
			if isOverheated then
				UiTranslate(-30, 107)
				UiColor(1, 0.1, 0.1, 1)
				UiFont("bold.ttf", 16)
				UiText("OVERHEAT")
			end
		UiPop()
		
		UiTranslate(0, 88)
		if autoFireState.enabled then
			UiColor(0.2, 0.8, 0.2, 1)
		else
			UiColor(0.8, 0.8, 0.8, 1)
		end
		UiText("Auto Fire [Q]: " .. (autoFireState.enabled and "ON" or "OFF"))
	UiPop()

	if gunStatus == "Destroyed" or mountStatus == "Destroyed" then
		return
	end
	local muzzlePos, muzzleDir = getMuzzlePosAndDir()
	QueryRejectBody(baseBody)
	QueryRejectBody(turretBody)
	QueryRejectBody(gunBody)
	local hit, dist = QueryRaycast(muzzlePos, muzzleDir, 500)
	if hit and reticle ~= 0 then
		local hitPos = VecAdd(muzzlePos, VecScale(muzzleDir, dist))
		local t = Transform()
		t.pos = hitPos
		t.rot = QuatLookAt(t.pos, cameraTransform.pos)
		DrawSprite(reticle, t, 2.5, 1.2, 0.5, 0, 0, 1, false, false)
		DrawSprite(reticle, t, 2.5, 1.2, 0.5, 0, 0, 1, true, false)
	end
end

function client.tick(dt)
	local currentVehicle = GetPlayerVehicle()
	local currentVehicleBody = 0
	if currentVehicle ~= 0 then
		currentVehicleBody = GetVehicleBody(currentVehicle)
	end

	if currentVehicle == 0 or currentVehicleBody ~= baseBody then
		cameraState.initialized = false
		ServerCall("server.setControlState", false, false)
		return
	end

	if InputPressed("q") then
		autoFireState.enabled = not autoFireState.enabled
		autoFireState.synced = false
	end
	if not autoFireState.synced then
		ServerCall("server.setAutoFire", autoFireState.enabled)
		autoFireState.synced = true
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

	local gunStatus = getModuleStatus(gunBody, pitchJoint, "ciws_barrel", 5)
	local turretStatus = getModuleStatus(turretBody, yawJoint, "ciws_turret", 10)
	local mountStatus = getModuleStatus(gunBody, pitchJoint, "ciws_mount", 10)

	local yawError = getLocalYawErrorFromCamera()
	if turretStatus ~= "Destroyed" and turretRotLoop ~= 0 and math.abs(yawError) > jointConfig.motorStopError then
		local soundPos = cameraTransform.pos
		if turretBody ~= 0 then
			soundPos = GetBodyTransform(turretBody).pos
		end
		PlayLoop(turretRotLoop, soundPos, turretRotVolume)
	end

	barrelHeat = GetFloat("vehicle."..vehicle..".barrelHeat")
	isOverheated = GetBool("vehicle."..vehicle..".isOverheated")

	local firing = InputDown("vehicleraise") or InputDown("usetool") or autoFireState.enabled
	if firing and gunStatus ~= "Destroyed" and mountStatus ~= "Destroyed" and not isOverheated then
		phalanxWeaponAudio.playSpin(audioState, ciwsWeaponConfig, cameraTransform.pos)
	end
	
	if barrelHeat > 0.01 and gunStatus ~= "Destroyed" and gunBody ~= 0 then
		local smokeChance = barrelHeat * dt * 35.0
		if firing and not isOverheated then
			smokeChance = smokeChance * 1.5 -- Extra smoke pressure when actively firing
		end
		
		if math.random() < smokeChance then
			local muzzlePos, muzzleDir = getMuzzlePosAndDir()
			local pushMuzzle = 0.5
			if firing and not isOverheated then 
				pushMuzzle = 3.0 -- Push smoke further out when gun is blasting
			end
			local vel = VecAdd(Vec(0, 1.0, 0), VecScale(muzzleDir, pushMuzzle + barrelHeat * 0.5))
			vel = VecAdd(vel, rndVec(0.6))
			
			ParticleReset()
			ParticleType("smoke")
			ParticleColor(0.9, 0.9, 0.9)
			ParticleAlpha(0.5 * barrelHeat, 0.0) -- Cap the alpha nicely
			ParticleRadius(0.1 + barrelHeat * 0.2, 0.6 + barrelHeat * 1.2)
			ParticleGravity(0.8) -- Slightly lighter gravity so hot smoke goes up faster
			ParticleDrag(1.5)
			
			SpawnParticle(muzzlePos, vel, 1.0 + barrelHeat * 2.0)
		end
	end

	ServerCall("server.setControlState", true, firing)
	ServerCall("server.setCameraTransform", cameraTransform)
end
