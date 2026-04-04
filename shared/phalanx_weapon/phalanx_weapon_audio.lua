#version 2

phalanxWeaponAudio = phalanxWeaponAudio or {}

function phalanxWeaponAudio.loadState()
	local state = {
		spinSnd = LoadLoop("MOD/snd/spin.ogg"),
		shootSnd = {},
	}

	for i = 1, 8 do
		local snd = LoadSound("MOD/snd/fire" .. i .. ".ogg")
		if snd ~= 0 then
			table.insert(state.shootSnd, snd)
		end
	end

	if #state.shootSnd == 0 then
		for i = 0, 7 do
			local snd = LoadSound("tools/gun" .. i .. ".ogg")
			if snd ~= 0 then
				table.insert(state.shootSnd, snd)
			end
		end
	end

	return state
end

function phalanxWeaponAudio.playShot(state, pos)
	if state == nil or state.shootSnd == nil or #state.shootSnd == 0 then
		return false
	end

	PlaySound(state.shootSnd[math.random(1, #state.shootSnd)], pos, phalanxWeaponConfig.shootVolume)
	return true
end

function phalanxWeaponAudio.playSpin(state, pos)
	if state == nil or state.spinSnd == nil or state.spinSnd == 0 then
		return false
	end

	PlayLoop(state.spinSnd, pos, phalanxWeaponConfig.spinVolume)
	return true
end
