#version 2

#include "script/include/player.lua"
#include "../../shared/phalanx_weapon/phalanx_weapon_config.lua"
#include "../../shared/phalanx_weapon/phalanx_weapon_projectile.lua"
#include "../../shared/phalanx_weapon/phalanx_weapon_fx.lua"
#include "../../shared/phalanx_weapon/phalanx_weapon_spin.lua"
#include "../../shared/phalanx_weapon/phalanx_weapon_audio.lua"

vehicle = 0
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
	fireCooldown = 0.015,
	spread = 0.008,
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
	pitchMin = -89.0,
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
	pitchSpeedDeg = 90.0,
	motorSlowdownDegPerSec = 40.0,
}

-- x轴(第一个数字)为前后，正数往前延伸
-- y轴(第二个数字)为上下，正数向上走
-- z轴(第三个数字)为左右，正数向右偏移
weaponOffsets = {
	muzzle = Vec(3, 0, -0.05),    -- 【枪口开火生成点】（即火光和子弹起点）
	spinPivot = Vec(0.0, 0.35, 0.35) -- 【枪管旋转轴圆心】
}

barrelSpinState = nil
turretRotLoop = 0
turretRotVolume = 1.5
audioState = nil
shootHaptic = 0
reticle = 0

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
		VecCopy(spin.launcherLocalTransform.pos),
		QuatCopy(spin.launcherLocalTransform.rot)
	)
	local pivot = weaponOffsets.spinPivot
	local pivotT = Transform(VecCopy(pivot))
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

	local gunTransform = GetBodyTransform(gunBody)
	local gunDir = TransformToParentVec(gunTransform, Vec(1, 0, 0))
	local rayHit, rayDist = QueryRaycast(cameraTransform.pos, TransformToParentVec(cameraTransform, Vec(0, 0, -1)), 500)
	if rayHit then
		local hitPos = VecAdd(cameraTransform.pos, VecScale(TransformToParentVec(cameraTransform, Vec(0, 0, -1)), rayDist))
		return VecNormalize(VecSub(hitPos, muzzlePos))
	end
	return VecNormalize(gunDir)
end

function server.init()
	vehicle = findMountedVehicle()
	baseBody = FindBody("base")
	turretBody = FindBody("turret")
	gunBody = FindBody("gun")
	yawJoint = FindJoint("ciws_yaw")
	pitchJoint = FindJoint("ciws_pitch")
	ensureBarrelSpinState()
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
	if IsBodyBroken(turretBody) or IsBodyBroken(gunBody) then
		return
	end

	local spin = ensureBarrelSpinState()

	local currentlyFiring = serverFireInput or autoFireEnabled

	if not serverControlActive and not autoFireEnabled then
		local slow = jointConfig.motorSlowdownDegPerSec * dt
		yawMotorVelDeg = moveTowards(yawMotorVelDeg, 0.0, slow)
		pitchMotorVelDeg = moveTowards(pitchMotorVelDeg, 0.0, slow)
		SetJointMotor(yawJoint, math.rad(yawMotorVelDeg), jointConfig.motorStrength)
		SetJointMotor(pitchJoint, math.rad(pitchMotorVelDeg), jointConfig.motorStrength)
		phalanxWeaponSpin.tickSpin(spin, dt, currentlyFiring)
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
	if IsBodyBroken(baseBody) then
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
	if IsBodyBroken(turretBody) then
		desiredPitchVelDeg = desiredPitchVelDeg * 0.5
	end
	pitchMotorVelDeg = desiredPitchVelDeg
	SetJointMotor(pitchJoint, math.rad(pitchMotorVelDeg), desiredPitchStrength)

	phalanxWeaponSpin.tickSpin(spin, dt, currentlyFiring)
	if currentlyFiring and phalanxWeaponSpin.tryFire(spin, ciwsWeaponConfig) then
		local muzzlePos, _ = getMuzzlePosAndDir()
		local shootDir = VecNormalize(VecAdd(getShootDir(), rndVec(ciwsWeaponConfig.spread)))
		local projectilePos = VecAdd(muzzlePos, VecScale(shootDir, 0.6))
		createProjectile(projectilePos, shootDir)

		ClientCall(0, "client.playGunShot", muzzlePos[1], muzzlePos[2], muzzlePos[3])
	end

	animateBarrelSpin()
end

function client.init()
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
	if cameraTransform ~= nil and cameraTransform.pos ~= nil then
		pos = cameraTransform.pos
	end
	phalanxWeaponAudio.playShot(audioState, ciwsWeaponConfig, pos)
	if shootHaptic ~= 0 then
		PlayHaptic(shootHaptic, 1)
	end
end

function client.draw(dt)
	if GetPlayerVehicle() ~= vehicle or GetString("level.state") ~= "" then
		return
	end

	if gunBody == 0 or IsBodyBroken(gunBody) then
		return
	end
	
	local uiStr = "Auto Fire: " .. (autoFireState.enabled and "ON" or "OFF") .. " [Press Q]"
	SetString("hud.bottom", uiStr)

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

	local yawError = getLocalYawErrorFromCamera()
	if turretRotLoop ~= 0 and math.abs(yawError) > jointConfig.motorStopError then
		local soundPos = cameraTransform.pos
		if turretBody ~= 0 then
			soundPos = GetBodyTransform(turretBody).pos
		end
		PlayLoop(turretRotLoop, soundPos, turretRotVolume)
	end

	local firing = InputDown("vehicleraise") or InputDown("usetool") or autoFireState.enabled
	if firing then
		phalanxWeaponAudio.playSpin(audioState, ciwsWeaponConfig, cameraTransform.pos)
	end

	ServerCall("server.setControlState", true, firing)
	ServerCall("server.setCameraTransform", cameraTransform)
end
