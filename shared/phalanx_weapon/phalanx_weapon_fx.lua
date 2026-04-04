#version 2

phalanxWeaponFx = phalanxWeaponFx or {}

function phalanxWeaponFx.spawnProjectileTrail(pos, vel)
	local dir = VecNormalize(vel)
	local v = VecScale(dir, -4) -- Trail particle initial velocity; negative means drag smoke behind the bullet.

	ParticleType("smoke")
	ParticleColor(1.0, 0.7, 0.25) -- RGB tint of the trail; warmer values look more like hot tracer smoke.
	ParticleRadius(0.06, 0.1) -- Start/end size of each particle; larger values make the trail thicker.
	ParticleAlpha(1, 0.0) -- Start/end opacity; controls how visible the trail is and how fast it fades.
	ParticleDrag(0.2) -- Air resistance on particles; higher values make smoke slow down faster.
	ParticleGravity(-0.1) -- Negative gravity makes smoke drift slightly upward.
	SpawnParticle(pos, v, 3) -- Spawn one trail particle at pos, with velocity v, lifetime 1.2 seconds.
end

function phalanxWeaponFx.spawnProjectileGlow(pos, vel, rndVec)
	local cfg = phalanxWeaponConfig
	local speed = VecLength(vel)
	local glow = math.min(1.0, speed / cfg.projectileSpeed) -- Normalized brightness factor based on projectile speed.

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
	SpawnParticle(pos, rv, 0.08) -- Very short-lived glow particle.

	PointLight(pos, 1.0, 0.78, 0.35, cfg.projectileLightRadius * glow) -- Dynamic light color and radius for tracer glow.
end
