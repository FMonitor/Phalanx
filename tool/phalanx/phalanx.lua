--Phalanx custom tool example

#version 2

#include "script/include/player.lua"
#include "script/toolanimation.lua"
#include "shared/phalanx_weapon/phalanx_weapon_config.lua"
#include "shared/phalanx_weapon/phalanx_weapon_projectile.lua"
#include "shared/phalanx_weapon/phalanx_weapon_fx.lua"
#include "shared/phalanx_weapon/phalanx_weapon_spin.lua"
#include "shared/phalanx_weapon/phalanx_weapon_audio.lua"

players = {}
toolPhalanxConfig = phalanxWeaponMakeConfig({
	name = "phalanx_tool",
	fireCooldown = 0.12,
	spread = 0.012,
	ejectRightOffset = 0.1,
	ejectUpOffset = -0.1,
	ejectForwardOffset = -0.5, -- 改为负数让抛壳口靠后
	ejectRightSpeed = 4.0,
	ejectUpSpeed = 2.0,
	ejectAngularSpeed = 25.0,
	ejectLifetime = 2.5,
})
weaponState = phalanxWeaponProjectile.createState()
toolFxState = phalanxWeaponFx.createState()

function createPlayerData()
	local data = phalanxWeaponSpin.createState()
	data.body = nil
	data.barrel = nil
	data.barrelTransform = nil
	data.toolAnimator = ToolAnimator()
	return data
end

function server.init()
	RegisterTool("phalanx", "Phalanx", "MOD/tool/phalanx/phalanx.xml", 6)
	SetToolAmmo("phalanx", 100)
	SetToolAmmoPickupAmount("phalanx", 20)
end

function rndVec(length)
	local v = VecNormalize(Vec(math.random(-100, 100), math.random(-100, 100), math.random(-100, 100)))
	return VecScale(v, length)
end

function rnd(mi, ma)
	return math.random(1000) / 1000 * (ma - mi) + mi
end

function spawnProjectileGlow(pos, vel)
	phalanxWeaponFx.spawnProjectileGlow(pos, vel, rndVec, toolPhalanxConfig)
end

function createPhalanxProjectile(pos, dir, owner)
	phalanxWeaponProjectile.add(weaponState, toolPhalanxConfig, pos, dir, owner)
end

function tickPhalanxProjectiles(dt)
	phalanxWeaponProjectile.tick(weaponState, toolPhalanxConfig, dt, "client.renderProjectileSmoke")
end

function server.tick(dt)
	tickPhalanxProjectiles(dt)
	phalanxWeaponFx.tickEjectedBodies(toolFxState, dt)

	for p in PlayersAdded() do
		players[p] = createPlayerData()
		SetToolEnabled("phalanx", true, p)
		SetToolAmmo("phalanx", 100, p)
	end

	for p in PlayersRemoved() do
		players[p] = nil
	end

	for p in Players() do
		server.tickPlayer(p, dt)
	end
end

function server.tickPlayer(p, dt)
	if GetPlayerTool(p) ~= "phalanx" then
		return
	end

	local ammo = GetToolAmmo("phalanx", p)
	local data = players[p]

	if InputDown("usetool", p) and ammo > 0 and GetPlayerVehicle(p) == 0 then
		local mt = GetToolLocationWorldTransform("muzzle", p)

		if mt == nil then
			return
		end

		phalanxWeaponSpin.tickSpin(data, dt, true)
		if phalanxWeaponSpin.tryFire(data, toolPhalanxConfig) then
			SetToolAmmo("phalanx", ammo - 1, p)
			local _, _, _, dir = GetPlayerAimInfo(mt.pos, 100, p)
			dir = VecAdd(dir, rndVec(toolPhalanxConfig.spread))
			local pos = TransformToParentPoint(mt, Vec(0.05, -0.2, 1))
			pos = VecAdd(pos, VecScale(dir, 0.8))
			createPhalanxProjectile(pos, dir, p)
			local shellRight = TransformToParentVec(mt, Vec(1, 0, 0))
			local shellUp = TransformToParentVec(mt, Vec(0, 1, 0))
			local shellForward = TransformToParentVec(mt, Vec(0, 0, -1))
			phalanxWeaponFx.spawnEjectedBullet(toolFxState, toolPhalanxConfig, mt.pos, shellRight, shellUp, shellForward, rndVec)
		end
	else
		phalanxWeaponSpin.tickSpin(data, dt, false)
	end
end

function client.init()
	audioState = phalanxWeaponAudio.loadState()
	DebugPrint("Phalanx: loaded gun sounds = " .. #audioState.shootSnd)
	shootHaptic = LoadHaptic("MOD/haptic/gun_fire.xml")
	local toolHaptic = LoadHaptic("MOD/haptic/background.xml")
	SetToolHaptic("phalanx", toolHaptic)
end

function client.renderProjectileSmoke(px, py, pz, vx, vy, vz)
	local pos = Vec(px, py, pz)
	local vel = Vec(vx, vy, vz)
	spawnProjectileGlow(pos, vel)
end

function client.tick(dt)
	for p in PlayersAdded() do
		players[p] = createPlayerData()
	end

	for p in PlayersRemoved() do
		players[p] = nil
	end

	for p in Players() do
		client.tickPlayer(p, dt)
	end
end

function client.tickPlayer(p, dt)
	if GetPlayerTool(p) ~= "phalanx" then
		return
	end

	local pt = GetPlayerTransform(p)
	local mt = GetToolLocationWorldTransform("muzzle", p)
	local ammo = GetToolAmmo("phalanx", p)

	if mt == nil then
		return
	end

	local data = players[p]

	if InputDown("usetool", p) and ammo > 0 and GetPlayerVehicle(p) == 0 then
		phalanxWeaponSpin.tickSpin(data, dt, true)
		if phalanxWeaponSpin.tryFire(data, toolPhalanxConfig) then
			phalanxWeaponAudio.playShot(audioState, toolPhalanxConfig, pt.pos)
			data.smoke = math.min(1.0, data.smoke + 0.1)
		end
		phalanxWeaponAudio.playSpin(audioState, toolPhalanxConfig, pt.pos)

		if IsPlayerLocal(p) then
			PlayHaptic(shootHaptic, 1)
		end
	else
		phalanxWeaponSpin.tickSpin(data, dt, false)
	end

	if not InputDown("usetool", p) and data.smoke > 0 and data.particleTimer < 0.0 then
		data.particleTimer = dt + (1.0 - data.smoke) * 0.05
		local vel = VecScale(VecSub(mt.pos, data.oldPipePos), 0.5 / dt)
		vel = VecAdd(vel, Vec(0, rnd(0, 2), 0))
		ParticleType("smoke")
		ParticleRadius(0.08, 0.15)
		ParticleAlpha(data.smoke * 0.4, 0)
		ParticleDrag(1.0)
		SpawnParticle(mt.pos, VecAdd(vel, rndVec(0.1)), 2.0)
	end

	data.oldPipePos = mt.pos

	local recoil = math.max(0, data.coolDown)
	data.toolAnimator.offsetTransform = Transform(Vec(0, recoil, 0))
	tickToolAnimator(data.toolAnimator, dt, nil, p)

	local b = GetToolBody(p)
	local voxSize = 0.05
	local attach = Transform(Vec(0.5 * voxSize, 0.5 * voxSize, 0))
	if data.body ~= b then
		data.body = b
		local shapes = GetBodyShapes(b)
		data.barrel = shapes[1]
		data.barrelTransform = TransformToLocalTransform(attach, GetShapeLocalTransform(data.barrel))
	end
	if data.barrel then
		attach.rot = QuatEuler(0, 0, data.angle)
		local t = TransformToParentTransform(attach, data.barrelTransform)
		SetShapeLocalTransform(data.barrel, t)
	end
	phalanxWeaponSpin.tickSmoke(data, dt)
end
