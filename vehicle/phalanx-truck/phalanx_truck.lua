#version 2

#include "script/include/player.lua"
#include "../../shared/phalanx_weapon/phalanx_weapon_config.lua"
#include "../../shared/phalanx_weapon/phalanx_weapon_projectile.lua"
#include "../../shared/phalanx_weapon/phalanx_weapon_fx.lua"
#include "../../shared/phalanx_weapon/phalanx_weapon_spin.lua"
#include "../../shared/phalanx_weapon/phalanx_weapon_audio.lua"

vehiclePhalanxConfig = phalanxWeaponMakeConfig({
	name = "phalanx_vehicle",
	fireCooldown = 0.06,
	spread = 0.01,
	ejectRightOffset = 0.4,
	ejectUpOffset = 0,
	ejectForwardOffset = -1.3, -- 原来是-0.1，现在改得更大负数让子弹生成位置更靠后
	ejectRightSpeed = 5.5,
	ejectUpSpeed = 3.0,
	ejectAngularSpeed = 30.0,
	ejectLifetime =2.5,
})

weaponState = phalanxWeaponProjectile.createState()
vehicleFxState = phalanxWeaponFx.createState()
muzzle = Vec(0, 0, 0)
reach = 500
cameraTransform = Transform(Vec(0, 0, 0), Quat(0, 0, 0, 1))
PHALANX_BARREL_SPIN_PIVOT = Vec(0.25, 0, 0.25)
cameraState = {
	initialized = false,
	yaw = 0.0,
	pitch = 10.0,
	distance = 10.0,
	targetDistance = 10.0,
	height = 0.6
}
autoFireState = {
	enabled = false,
	synced = false,
}
serverSpinState = {
	activeUntil = 0.0,
}

cameraConfig = {
	sensX = 5000.0,
	sensY = 5000.0,
	distMin = 0.0,
	distMax = 18.0,
	pitchMin = -89.0,
	pitchMax = 89.0,
	turretPitchMin = -20.0,
	turretPitchMax = 95.0,
	firstPersonThreshold = 0.75,
	radius = 0.25,
	smooth = 10.0,
	fov = 120
}

function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function wrapAngle(a)
	while a > 180 do
		a = a - 360
	end
	while a < -180 do
		a = a + 360
	end
	return a
end

function lerp(a, b, t)
	return a + (b - a) * t
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

function dirToYawPitch(dir)
	local d = VecNormalize(dir)
	local yaw = math.deg(math.atan2(d[1], -d[3]))
	local pitch = math.deg(math.asin(clamp(d[2], -1.0, 1.0)))
	return yaw, pitch
end

function findMountedVehicle()
	local v = FindVehicle()
	if v == 0 then
		v = FindVehicle("phalanx_truck")
	end
	return v
end

function spawnProjectileGlow(pos, vel)
	phalanxWeaponFx.spawnProjectileGlow(pos, vel, rndVec, vehiclePhalanxConfig)
end

function createPhalanxProjectile(pos, dir, owner)
	phalanxWeaponProjectile.add(weaponState, vehiclePhalanxConfig, pos, dir, owner)
end

function tickPhalanxProjectiles(dt)
	phalanxWeaponProjectile.tick(weaponState, vehiclePhalanxConfig, dt, "client.renderProjectileSmoke")
end

function ensureGunSpinState()
	gunSpin = gunSpin or phalanxWeaponSpin.createState()
	gunSpin.launcherShape = gunSpin.launcherShape or 0
	gunSpin.launcherLocalTransform = gunSpin.launcherLocalTransform or nil

	if gunSpin.launcherShape == 0 then
		if gun ~= 0 then
			local shapes = GetBodyShapes(gun)
			if shapes ~= nil and #shapes > 0 then
				for i = 1, #shapes do
					if HasTag(shapes[i], "phalanx_barrel_spin") then
						gunSpin.launcherShape = shapes[i]
						break
					end
				end

				if gunSpin.launcherShape == 0 then
					gunSpin.launcherShape = shapes[1]
				end

				gunSpin.launcherLocalTransform = GetShapeLocalTransform(gunSpin.launcherShape)
			end
		end
	end

	return gunSpin
end

function animateGunSpin(dt)
	local spin = ensureGunSpinState()

	if spin.launcherShape ~= 0 and spin.launcherLocalTransform ~= nil then
		local base = Transform(VecCopy(spin.launcherLocalTransform.pos), QuatCopy(spin.launcherLocalTransform.rot))
		local pivot = PHALANX_BARREL_SPIN_PIVOT
		local pivotT = Transform(VecCopy(pivot))
		local unpivotT = Transform(VecScale(pivot, -1))
		local spinT = Transform(Vec(), QuatEuler(0, spin.angle, 0))
		local t = TransformToParentTransform(pivotT, spinT)
		t = TransformToParentTransform(t, unpivotT)
		t = TransformToParentTransform(base, t)
		SetShapeLocalTransform(spin.launcherShape, t)
	end
end

function server.init()
	body = FindBody("body")
	vehicle = findMountedVehicle()
	gun = FindBody("gun")
	autoFireEnabled = false
	autoFirePlayerId = 0

	upright = true
	ensureGunSpinState()
end

function server.setCameraTransform(t)
	cameraTransform = t
end

function server.setAutoFire(enabled, playerId)
	autoFireEnabled = enabled == true
	autoFirePlayerId = playerId or 0
end

function server.tick(dt)
	tickPhalanxProjectiles(dt)
	phalanxWeaponFx.tickEjectedBodies(vehicleFxState, dt)

	local playerId = -1
	for p in Players() do
		if GetPlayerVehicle(p) == vehicle then
			playerId = p
			break
		end
	end

	if playerId == -1 then
		if not autoFireEnabled then
			local spin = ensureGunSpinState()
			phalanxWeaponSpin.tickSpin(spin, dt, false)
			animateGunSpin(dt)
			return
		end
		playerId = autoFirePlayerId
	end

	if gun == 0 or IsBodyBroken(gun) then
		return
	end

	local health = GetVehicleHealth(vehicle)
	if health <= 0 then
		return
	end

	local t = GetBodyTransform(body)
	local gt = GetBodyTransform(gun)

	local gunDirection = TransformToParentVec(gt, Vec(0, 0, -1))
	muzzle = TransformToParentVec(gt, Vec(0, 0.4, 0))
	muzzle = VecAdd(muzzle, VecAdd(gt.pos, VecScale(gunDirection, 0.3)))

	checkUpright()

	local shootDir = getShootDir()
	local spin = ensureGunSpinState()

	if upright then
		local nt = Transform()
		local lookDir = VecAdd(gt.pos, VecScale(shootDir, 10))
		nt.rot = QuatLookAt(gt.pos, lookDir)
		nt.pos = VecCopy(gt.pos)
		nt.rot = QuatSlerp(gt.rot, nt.rot, 0.04)
		SetBodyTransform(gun, nt)
		shoot(dt, playerId, shootDir)
	else
		local spin = ensureGunSpinState()
		phalanxWeaponSpin.tickSpin(spin, dt, false)
	end

	if playerId ~= nil and playerId > 0 then
		ClientCall(playerId, "client.setSpinActive", spin.angVel > 0)
	end

	animateGunSpin(dt)
end

function checkUpright()
	local t = GetBodyTransform(body)
	upright = true
	if t.rot[1] > 0.3 or t.rot[1] < -0.3 then
		upright = false
	end
	if t.rot[3] > 0.3 or t.rot[3] < -0.3 then
		upright = false
	end
end

function rndVec(length)
	local v = VecNormalize(Vec(math.random(-100, 100), math.random(-100, 100), math.random(-100, 100)))
	return VecScale(v, length)
end

function shoot(dt, playerId, shootDir)
	local spin = ensureGunSpinState()
	local manualFire = false
	if playerId ~= nil and playerId > 0 then
		manualFire = InputDown("vehicleraise", playerId) or InputDown("usetool", playerId)
	end
	local firing = manualFire or autoFireEnabled

	phalanxWeaponSpin.tickSpin(spin, dt, firing)

	if firing and phalanxWeaponSpin.tryFire(spin, vehiclePhalanxConfig) then
		local dir = VecAdd(shootDir, rndVec(vehiclePhalanxConfig.spread))
		dir = VecNormalize(dir)
		local pos = VecAdd(muzzle, VecScale(dir, 0.8))
		createPhalanxProjectile(pos, dir, playerId)
		local gt = GetBodyTransform(gun)
		local shellRight = TransformToParentVec(gt, Vec(1, 0, 0))
		local shellUp = TransformToParentVec(gt, Vec(0, 1, 0))
		local shellForward = TransformToParentVec(gt, Vec(0, 0, -1))
		phalanxWeaponFx.spawnEjectedBullet(vehicleFxState, vehiclePhalanxConfig, muzzle, shellRight, shellUp, shellForward, rndVec)
		ClientCall(playerId, "client.playGunShot", muzzle[1], muzzle[2], muzzle[3])
	end
end

function client.init()
	vehicle = findMountedVehicle()
	gun = FindBody("gun")
	body = FindBody("body")
	reticle = LoadSprite("gfx/reticle4.png")
	cameraState.initialized = false
	audioState = phalanxWeaponAudio.loadState()
	local spinHandle = 0
	if audioState ~= nil and audioState.spinSnd ~= nil then
		spinHandle = audioState.spinSnd
	end
	DebugPrint("Phalanx Truck spin handle = " .. spinHandle)
	shootHaptic = LoadHaptic("MOD/haptic/gun_fire.xml")
	clientGunFx = {
		angle = 0.0,
		angVel = 0.0,
		coolDown = 0.0,
		smoke = 0.0,
		particleTimer = 0.0,
		oldPipePos = Vec(),
	}
end

function client.draw(dt)
	if GetPlayerVehicle() ~= vehicle or GetString("level.state") ~= "" then
		return
	end

	if gun == 0 or IsBodyBroken(gun) then
		return
	end

	local health = GetVehicleHealth(vehicle)
	if health <= 0 then
		return
	end

	drawTool()

	local shootDir = getShootDir()
	local gt = GetBodyTransform(gun)
	local gunDirection = TransformToParentVec(gt, Vec(0, 0, -1))

	muzzle = TransformToParentVec(gt, Vec(0, 0.8, 0))
	muzzle = VecAdd(muzzle, VecAdd(gt.pos, VecScale(gunDirection, 0.3)))

	local tmpDir = VecNormalize(VecCopy(shootDir))
	QueryRejectBody(body)
	QueryRejectBody(gun)
	local hit, dist = QueryRaycast(muzzle, tmpDir, reach)
	local projectileHitPos = VecAdd(muzzle, VecScale(tmpDir, dist))

	if hit then
		local t = Transform()
		t.pos = projectileHitPos
		drawReticleSprite(t)
	end
end

function client.renderProjectileSmoke(px, py, pz, vx, vy, vz)
	local pos = Vec(px, py, pz)
	local vel = Vec(vx, vy, vz)
	spawnProjectileGlow(pos, vel)
end

function client.runHaptic()
	PlayHaptic(shootHaptic, 1)
end

function client.playGunShot(px, py, pz)
	local soundPos = Vec(px, py, pz)
	if cameraTransform ~= nil and cameraTransform.pos ~= nil then
		soundPos = cameraTransform.pos
	end
	phalanxWeaponAudio.playShot(audioState, vehiclePhalanxConfig, soundPos)
	PlayHaptic(shootHaptic, 1)
end

function client.setSpinActive(active)
	if active then
		serverSpinState.activeUntil = GetTime() + 0.15
	end
end

function getShootDir()
	local forward = TransformToParentVec(cameraTransform, Vec(0, 0, -1))
	local yaw, pitch = dirToYawPitch(forward)
	pitch = clamp(pitch, cameraConfig.turretPitchMin, cameraConfig.turretPitchMax)
	return yawPitchToDir(yaw, pitch)
end

function client.tick(dt)
	if GetPlayerVehicle() == vehicle then
		if InputPressed("q") then
			autoFireState.enabled = not autoFireState.enabled
			autoFireState.synced = false
		end
		if not autoFireState.synced then
			ServerCall("server.setAutoFire", autoFireState.enabled)
			autoFireState.synced = true
		end

		local cfg = cameraConfig
		local pivot = GetVehicleLocationWorldTransform(vehicle, "camera")
		if pivot == nil then
			pivot = GetBodyTransform(body)
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

		-- Match engine third-person state to our custom camera mode so player
		-- body visibility stays stable when switching between first/third person.
		RequestThirdPerson(not useFirstPerson)
		if gun ~= 0 then
			SetPivotClipBody(gun, 0)
		end

		if useFirstPerson then
			local fpPivot = GetVehicleLocationWorldTransform(vehicle, "player")
			if fpPivot == nil then
				fpPivot = pivot
			end
			local camPos = VecAdd(fpPivot.pos, VecScale(forward, 0.1))
			cameraTransform = Transform(camPos, QuatLookAt(camPos, target))
			if body ~= 0 then
				local bodyTransform = GetBodyTransform(body)
				local cameraLocalTransform = TransformToLocalTransform(bodyTransform, cameraTransform)
				AttachCameraTo(body, false)
				SetCameraOffsetTransform(cameraLocalTransform)
			else
				SetCameraTransform(cameraTransform, cfg.fov)
			end
		else
			local idealPos = VecAdd(pivot.pos, VecScale(forward, -cameraState.distance))
			idealPos = VecAdd(idealPos, VecScale(up, cameraState.height))

			local toCamera = VecSub(idealPos, pivot.pos)
			local toCameraDist = VecLength(toCamera)
			local camPos = idealPos

			if toCameraDist > 0.001 then
				local toCameraDir = VecScale(toCamera, 1 / toCameraDist)
				QueryRejectVehicle(vehicle)
				if body ~= 0 then
					QueryRejectBody(body)
				end
				if gun ~= 0 then
					QueryRejectBody(gun)
				end
				local hit, hitDist = QueryRaycast(pivot.pos, toCameraDir, toCameraDist, cfg.radius)
				if hit then
					local safeDist = math.max(0.3, hitDist - cfg.radius)
					camPos = VecAdd(pivot.pos, VecScale(toCameraDir, safeDist))
				end
			end

			cameraTransform = Transform(camPos, QuatLookAt(camPos, target))
			if body ~= 0 then
				local bodyTransform = GetBodyTransform(body)
				local cameraLocalTransform = TransformToLocalTransform(bodyTransform, cameraTransform)
				AttachCameraTo(body, false)
				SetCameraOffsetTransform(cameraLocalTransform)
			else
				SetCameraTransform(cameraTransform, cfg.fov)
			end
		end

		ServerCall("server.setCameraTransform", cameraTransform)

		local canOperateGun = body ~= 0 and gun ~= 0 and not IsBodyBroken(body) and not IsBodyBroken(gun) and GetVehicleHealth(vehicle) > 0
		local firingInput = InputDown("vehicleraise") or InputDown("usetool") or autoFireState.enabled
		local firing = canOperateGun and firingInput
		local gt = GetBodyTransform(gun)
		local gunDirection = TransformToParentVec(gt, Vec(0, 0, -1))
		muzzle = TransformToParentVec(gt, Vec(0, 0.0, 0))
		muzzle = VecAdd(muzzle, VecAdd(gt.pos, VecScale(gunDirection, 0)))
		if firing then
			phalanxWeaponSpin.tickSpin(clientGunFx, dt, true)
			local localDidFire = phalanxWeaponSpin.tryFire(clientGunFx, vehiclePhalanxConfig)
			if localDidFire then
				clientGunFx.smoke = math.min(1.0, clientGunFx.smoke + 0.1)
			end
		else
			phalanxWeaponSpin.tickSpin(clientGunFx, dt, false)
		end

		local shouldPlaySpin = firing
		local spinHandle = 0
		if audioState ~= nil and audioState.spinSnd ~= nil then
			spinHandle = audioState.spinSnd
		end
		DebugWatch("Truck AutoFire", autoFireState.enabled)
		DebugWatch("Truck Spin", "f=" .. tostring(firing) .. " r=" .. tostring(audioState ~= nil) .. " h=" .. tostring(spinHandle) .. " p=" .. tostring(shouldPlaySpin))
		if shouldPlaySpin then
			local spinOk = phalanxWeaponAudio.playSpin(audioState, vehiclePhalanxConfig, cameraTransform.pos)
			DebugWatch("Truck SpinPlayOk", spinOk)
		end

		if not firing and clientGunFx.smoke > 0 and clientGunFx.particleTimer < 0.0 then
			clientGunFx.particleTimer = dt + (1.0 - clientGunFx.smoke) * 0.05
			local vel = VecScale(VecSub(muzzle, clientGunFx.oldPipePos), 0.5 / dt)
			vel = VecAdd(vel, Vec(0, math.random() * 2, 0))
			ParticleType("smoke")
			ParticleRadius(0.08, 0.15)
			ParticleAlpha(clientGunFx.smoke * 0.4, 0)
			ParticleDrag(1.0)
			SpawnParticle(muzzle, VecAdd(vel, rndVec(0.1)), 2.0)
		end

		clientGunFx.oldPipePos = VecCopy(muzzle)
		phalanxWeaponSpin.tickSmoke(clientGunFx, dt)
	else
		cameraState.initialized = false
	end
end

function drawReticleSprite(t)
	t.rot = QuatLookAt(t.pos, cameraTransform.pos)
	DrawSprite(reticle, t, 3, 1.5, 0.5, 0, 0, 1, false, false)
	DrawSprite(reticle, t, 3, 1.5, 0.5, 0, 0, 1, true, false)
end

function drawTool()
	UiPush()
	UiTranslate(UiCenter(), UiHeight() - 70)
	UiAlign("top left")
	UiPush()
	UiFont("bold.ttf", 26)
	UiAlign("center")
	UiScale(1)
	UiTextOutline(0, 0, 0, 1, 0.1)
	UiColor(1, 1, 1, 1)
	UiText("PHALANX")
	UiTranslate(0, -24)
	UiScale(1.6)
	UiText("TRUCK")
	UiPop()
	UiPop()
end
