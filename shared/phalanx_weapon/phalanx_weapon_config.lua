#version 2

phalanxWeaponConfigDefaults = phalanxWeaponConfigDefaults or {
	name = "phalanx_weapon",
	projectileSpeed = 100.0,
	projectileGravity = 9.8,
	projectileLifetime = 10.0,
	projectileBlast = 0.5,
	projectileLightRadius = 2.0,
	shootVolume = 1.0,
	spinVolume = 1.0,
	spread = 0.01,
	fireCooldown = 0.05,
	ejectLifetime = 5.0,
	ejectRightOffset = 0.18,
	ejectUpOffset = 0.05,
	ejectForwardOffset = 0.02,
	ejectRightSpeed = 5.0,
	ejectUpSpeed = 1.5,
	ejectForwardSpeed = 0.6,
	ejectRandomSpeed = 1.2,
	ejectAngularSpeed = 25.0,
}

function phalanxWeaponMakeConfig(overrides)
	local cfg = {}

	for k, v in pairs(phalanxWeaponConfigDefaults) do
		cfg[k] = v
	end

	if overrides ~= nil then
		for k, v in pairs(overrides) do
			cfg[k] = v
		end
	end

	return cfg
end
