--Phalanx custom tool example

#version 2

#include "script/include/player.lua"
#include "script/toolanimation.lua"


players = {}
projectiles = {}

PHALANX_PROJECTILE_SPEED = 100.0
PHALANX_PROJECTILE_GRAVITY = 9.8
PHALANX_PROJECTILE_LIFETIME = 10.0
PHALANX_PROJECTILE_BLAST = 0.5
PHALANX_PROJECTILE_LIGHT_RADIUS = 2

PHALANX_SHOOT_VOLUME = 1.0
PHALANX_SPIN_VOLUME = 1.0

function createPlayerData()
	return {
		angle = 0.0,
		angVel = 0.0,
		coolDown = 0.0,
		smoke = 0.0,
		body = nil,
		barrel = nil,
		barrelTransform = nil,
		toolAnimator = ToolAnimator(),
		oldPipePos = Vec(),
		particleTimer = 0.0,
	}
end

function server.init()
	RegisterTool("phalanx", "Phalanx", "MOD/tool/prefab/phalanx.xml", 6)
	SetToolAmmoPickupAmount("phalanx", 100)
end

function rndVec(length)
	local v = VecNormalize(Vec(math.random(-100, 100), math.random(-100, 100), math.random(-100, 100)))
	return VecScale(v, length)
end

function rnd(mi, ma)
	return math.random(1000) / 1000 * (ma - mi) + mi
end

function spawnProjectileTrail(pos, vel)
	local dir = VecNormalize(vel)
	local v = VecAdd(VecScale(dir, -4), rndVec(0.3))

	ParticleType("smoke")
	ParticleColor(1.0, 0.7, 0.25)
	ParticleRadius(0.1, 0.11)
	ParticleAlpha(1, 0.0)
	ParticleDrag(0.2)
	ParticleGravity(-0.1)
	SpawnParticle(pos, v, 1.2)
end

function spawnProjectileGlow(pos, vel)
	local speed = VecLength(vel)
	local glow = math.min(1.0, speed / PHALANX_PROJECTILE_SPEED)

	ParticleType("smoke")
	ParticleColor(1.0, 0.9, 0.55)
	ParticleRadius(0.05, 0.02)
	ParticleAlpha(0.95, 0.0)
	ParticleDrag(0.05)
	ParticleGravity(0.0)
	SpawnParticle(pos, rndVec(0.05), 0.08)

	PointLight(pos, 1.0, 0.78, 0.35, PHALANX_PROJECTILE_LIGHT_RADIUS * glow)
end

function createPhalanxProjectile(pos, dir, owner)
	dir = VecNormalize(dir)
	table.insert(projectiles, {
		pos = pos,
		vel = VecScale(dir, PHALANX_PROJECTILE_SPEED),
		life = PHALANX_PROJECTILE_LIFETIME,
		owner = owner,
	})
end

function tickPhalanxProjectiles(dt)
	for i = #projectiles, 1, -1 do
		local p = projectiles[i]
		local oldPos = p.pos
		local alive = true

		p.vel = VecAdd(p.vel, Vec(0, -PHALANX_PROJECTILE_GRAVITY * dt, 0))
		local newPos = VecAdd(oldPos, VecScale(p.vel, dt))
		local travel = VecSub(newPos, oldPos)
		local dist = VecLength(travel)

		if dist > 0 then
			local dir = VecScale(travel, 1 / dist)
			local hit, hitDist = QueryRaycast(oldPos, dir, dist)

			if hit then
				local hitPos = VecAdd(oldPos, VecScale(dir, hitDist))
				Explosion(hitPos, PHALANX_PROJECTILE_BLAST)
				table.remove(projectiles, i)
				alive = false
			else
				p.pos = newPos
				ClientCall(
					0,
					"client.renderProjectileSmoke",
					p.pos[1], p.pos[2], p.pos[3],
					p.vel[1], p.vel[2], p.vel[3]
				)
			end
		end

		if alive then
			p.life = p.life - dt
			if p.life <= 0 then
				table.remove(projectiles, i)
			end
		end
	end
end

function server.tick(dt)
	tickPhalanxProjectiles(dt)

	for p in PlayersAdded() do
		players[p] = createPlayerData()
		SetToolEnabled("phalanx", true, p)
		SetToolAmmo("phalanx", -1, p)
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

	if InputDown("usetool", p) and ammo > -2 and GetPlayerVehicle(p) == 0 then
		local mt = GetToolLocationWorldTransform("muzzle", p)

		if mt == nil then
			return
		end

		data.angVel = math.min(1000, data.angVel + dt * 2000)
		if data.angVel == 1000 and data.coolDown < 0 then
			local _, _, _, dir = GetPlayerAimInfo(mt.pos, 100, p)
			dir = VecAdd(dir, rndVec(0.015))
			local pos = TransformToParentPoint(mt, Vec(0.05, -0.2, 1))
			pos = VecAdd(pos, VecScale(dir, 0.8))
			createPhalanxProjectile(pos, dir, p)
			data.coolDown = 0.025
		end
	else
		data.angVel = math.max(0, data.angVel - dt * 1000)
	end
	data.coolDown = data.coolDown - dt
end

function client.init()
	spinSnd = LoadLoop("MOD/snd/spin.ogg")
	shootSnd = {}
	for i = 1, 8 do
		local snd = LoadSound("MOD/snd/fire" .. i .. ".ogg")
		if snd ~= 0 then
			table.insert(shootSnd, snd)
		end
	end

	if #shootSnd == 0 then
		for i = 0, 7 do
			local snd = LoadSound("tools/gun" .. i .. ".ogg")
			if snd ~= 0 then
				table.insert(shootSnd, snd)
			end
		end
	end

	DebugPrint("Phalanx: loaded gun sounds = " .. #shootSnd)

	shootHaptic = LoadHaptic("MOD/tool/haptic/gun_fire.xml")
	local toolHaptic = LoadHaptic("MOD/tool/haptic/background.xml")
	SetToolHaptic("phalanx", toolHaptic)
end

function client.renderProjectileSmoke(px, py, pz, vx, vy, vz)
	local pos = Vec(px, py, pz)
	local vel = Vec(vx, vy, vz)
	spawnProjectileTrail(pos, vel)
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

	if InputDown("usetool", p) and ammo > -2 and GetPlayerVehicle(p) == 0 then
		data.angVel = math.min(1000, data.angVel + dt * 2000)
		if data.angVel == 1000 and data.coolDown < 0 then
			PointLight(mt.pos, 1, 0.7, 0.5, 3)
			if #shootSnd > 0 then
				PlaySound(shootSnd[math.random(1, #shootSnd)], pt.pos, PHALANX_SHOOT_VOLUME)
			end

			data.coolDown = 0.025
			data.smoke = math.min(1.0, data.smoke + 0.1)
		end
		PlayLoop(spinSnd, pt.pos, PHALANX_SPIN_VOLUME)

		if IsPlayerLocal(p) then
			PlayHaptic(shootHaptic, 1)
		end
	else
		data.angVel = math.max(0, data.angVel - dt * 1000)
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

	data.particleTimer = data.particleTimer - dt
	data.oldPipePos = mt.pos

	data.coolDown = data.coolDown - dt
	data.angle = data.angle + data.angVel * dt

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
	data.smoke = math.max(0.0, data.smoke - dt / 3)
end
