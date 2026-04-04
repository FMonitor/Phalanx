#version 2

phalanxWeaponFx = phalanxWeaponFx or {}

function phalanxWeaponFx.spawnProjectileTrail(pos, vel)
	local dir = VecNormalize(vel)
	local v = VecScale(dir, -4)

	ParticleType("smoke")
	ParticleColor(1.0, 0.7, 0.25)
	ParticleRadius(0.1, 0.11)
	ParticleAlpha(1, 0.0)
	ParticleDrag(0.2)
	ParticleGravity(-0.1)
	SpawnParticle(pos, v, 1.2)
end

function phalanxWeaponFx.spawnProjectileGlow(pos, vel, rndVec)
	local cfg = phalanxWeaponConfig
	local speed = VecLength(vel)
	local glow = math.min(1.0, speed / cfg.projectileSpeed)

	ParticleType("smoke")
	ParticleColor(1.0, 0.9, 0.55)
	ParticleRadius(0.05, 0.02)
	ParticleAlpha(0.95, 0.0)
	ParticleDrag(0.05)
	ParticleGravity(0.0)

	local rv = Vec(0, 0, 0)
	if rndVec ~= nil then
		rv = rndVec(0.05)
	end
	SpawnParticle(pos, rv, 0.08)

	PointLight(pos, 1.0, 0.78, 0.35, cfg.projectileLightRadius * glow)
end
