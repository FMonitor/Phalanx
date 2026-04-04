#version 2

phalanxWeaponSpin = phalanxWeaponSpin or {}

function phalanxWeaponSpin.createState()
	return {
		angle = 0.0,
		angVel = 0.0,
		coolDown = 0.0,
		smoke = 0.0,
		particleTimer = 0.0,
		oldPipePos = Vec(),
	}
end

function phalanxWeaponSpin.tickSpin(state, dt, firing)
	if firing then
		state.angVel = math.min(1000, state.angVel + dt * 2000)
	else
		state.angVel = math.max(0, state.angVel - dt * 1000)
	end

	state.coolDown = state.coolDown - dt
	state.angle = state.angle + state.angVel * dt
end

function phalanxWeaponSpin.tryFire(state)
	if state.angVel == 1000 and state.coolDown < 0 then
		state.coolDown = phalanxWeaponConfig.fireCooldown
		return true
	end
	return false
end

function phalanxWeaponSpin.tickSmoke(state, dt)
	state.particleTimer = state.particleTimer - dt
	state.smoke = math.max(0.0, state.smoke - dt / 3)
end
