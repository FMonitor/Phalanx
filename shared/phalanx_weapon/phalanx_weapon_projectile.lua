#version 2

phalanxWeaponProjectile = phalanxWeaponProjectile or {}

function phalanxWeaponProjectile.createState()
	return {
		projectiles = {}
	}
end

function phalanxWeaponProjectile.add(state, cfg, pos, dir, owner)
	dir = VecNormalize(dir)
	table.insert(state.projectiles, {
		pos = VecCopy(pos),
		vel = VecScale(dir, cfg.projectileSpeed),
		life = cfg.projectileLifetime,
		owner = owner,
	})
end

function phalanxWeaponProjectile.tick(state, cfg, dt, clientRpcName)
	for i = #state.projectiles, 1, -1 do
		local p = state.projectiles[i]
		local oldPos = p.pos
		local alive = true

		p.vel = VecAdd(p.vel, Vec(0, -cfg.projectileGravity * dt, 0))
		local newPos = VecAdd(oldPos, VecScale(p.vel, dt))
		local travel = VecSub(newPos, oldPos)
		local dist = VecLength(travel)

		if dist > 0 then
			local dir = VecScale(travel, 1 / dist)
			local hit, hitDist = QueryRaycast(oldPos, dir, dist)

			if hit then
				local hitPos = VecAdd(oldPos, VecScale(dir, hitDist))
				Explosion(hitPos, cfg.projectileBlast)
				table.remove(state.projectiles, i)
				alive = false
			else
				p.pos = newPos
				ClientCall(
					0,
					clientRpcName,
					p.pos[1], p.pos[2], p.pos[3],
					p.vel[1], p.vel[2], p.vel[3]
				)
			end
		end

		if alive then
			p.life = p.life - dt
			if p.life <= 0 then
				table.remove(state.projectiles, i)
			end
		end
	end
end
