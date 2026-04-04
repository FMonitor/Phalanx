#version 2

phalanxWeaponFx = phalanxWeaponFx or {}

function phalanxWeaponFx.createState()
	return {
		ejectedBodies = {}
	}
end

function phalanxWeaponFx.tickEjectedBodies(state, dt)
	if state == nil or state.ejectedBodies == nil then
		return
	end

	for i = #state.ejectedBodies, 1, -1 do
		local item = state.ejectedBodies[i]
		item.life = item.life - dt
		if item.life <= 0 then
			if item.body ~= nil and item.body ~= 0 and IsHandleValid(item.body) then
				Delete(item.body)
			end
			table.remove(state.ejectedBodies, i)
		end
	end
end

function phalanxWeaponFx.spawnEjectedBullet(state, cfg, origin, rightDir, upDir, forwardDir, rndVec)
	if state == nil or cfg == nil or origin == nil then
		return 0
	end

	rightDir = VecNormalize(rightDir or Vec(1, 0, 0))
	upDir = VecNormalize(upDir or Vec(0, 1, 0))
	forwardDir = VecNormalize(forwardDir or Vec(0, 0, 1))

	local spawnPos = VecCopy(origin)
	spawnPos = VecAdd(spawnPos, VecScale(rightDir, cfg.ejectRightOffset or 0.0))
	spawnPos = VecAdd(spawnPos, VecScale(upDir, cfg.ejectUpOffset or 0.0))
	spawnPos = VecAdd(spawnPos, VecScale(forwardDir, cfg.ejectForwardOffset or 0.0))

	local spawnRot = QuatLookAt(spawnPos, VecAdd(spawnPos, forwardDir))
	local entities = Spawn("MOD/shared/phalanx_weapon/bullet.xml", Transform(spawnPos, spawnRot))
	if entities == nil or #entities == 0 then
		return 0
	end

	local shellBody = 0
	for i = 1, #entities do
		local ent = entities[i]
		if GetEntityType(ent) == "body" then
			shellBody = ent
		elseif GetEntityType(ent) == "shape" and HasTag(ent, "bullet_physics") then
			SetTag(ent, "invisible")
		end
	end

	if shellBody == 0 then
		return 0
	end
	SetBodyDynamic(shellBody, true)

	local ejectVel = Vec()
	ejectVel = VecAdd(ejectVel, VecScale(rightDir, cfg.ejectRightSpeed or 4.0))
	ejectVel = VecAdd(ejectVel, VecScale(upDir, cfg.ejectUpSpeed or 3.0))
	ejectVel = VecAdd(ejectVel, VecScale(forwardDir, cfg.ejectForwardSpeed or 0.0))
	if rndVec ~= nil then
		ejectVel = VecAdd(ejectVel, rndVec(cfg.ejectRandomSpeed or 1.5))
	end
	SetBodyVelocity(shellBody, ejectVel)

	local angVel = VecScale(rightDir, cfg.ejectAngularSpeed or 20.0)
	if rndVec ~= nil then
		angVel = VecAdd(angVel, rndVec((cfg.ejectAngularSpeed or 20.0) * 0.3))
	end
	SetBodyAngularVelocity(shellBody, angVel)

	table.insert(state.ejectedBodies, {
		body = shellBody,
		life = cfg.ejectLifetime or 3,
	})

	return shellBody
end

function phalanxWeaponFx.spawnProjectileTrail(pos, vel)
	local dir = VecNormalize(vel)
	local v = VecScale(dir, -4) -- Trail particle initial velocity; negative means drag smoke behind the bullet.

	ParticleType("smoke")
	ParticleColor(1.0, 0.7, 0.25) -- RGB tint of the trail; warmer values look more like hot tracer smoke.
	ParticleRadius(0.06, 0.1) -- Start/end size of each particle; larger values make the trail thicker.
	ParticleAlpha(1, 0.0) -- Start/end opacity; controls how visible the trail is and how fast it fades.
	ParticleDrag(0.2) -- Air resistance on particles; higher values make smoke slow down faster.
	ParticleGravity(-0.1) -- Negative gravity makes smoke drift slightly upward.
	SpawnParticle(pos, v, 0.2) -- Spawn one trail particle at pos, with velocity v, lifetime 1.2 seconds.
end

function phalanxWeaponFx.spawnProjectileGlow(pos, vel, rndVec, cfg)
	local speed = VecLength(vel)
	local glow = 2 -- Normalized brightness factor based on projectile speed.

	ParticleType("smoke")
	ParticleColor(1.0, 0.9, 0.55) -- Brighter muzzle/tracer tint for the glowing ember particle.
	ParticleRadius(0.05, 0.02) -- Small shrinking glow puff; first value is initial size, second is final size.
	ParticleAlpha(0.95, 0.0) -- Nearly opaque at spawn, then fades out completely.
	ParticleDrag(0.05) -- Low drag keeps the glow particle from stopping too abruptly.
	ParticleGravity(0.0) -- No gravity so the glow stays centered on the projectile path.

	local rv = Vec(0, 0, 0)
	if rndVec ~= nil then
		rv = rndVec(0.05) -- Small random velocity variation to break up perfectly uniform particles.
	end
	SpawnParticle(pos, rv, 0.1) -- Very short-lived glow particle.

	PointLight(pos, 1.0, 0.78, 0.35, cfg.projectileLightRadius * glow) -- Dynamic light color and radius for tracer glow.
end
