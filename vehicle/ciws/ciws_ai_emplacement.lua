#version 2

CIWS_VARIANT = "ai"

function ciwsConfigureMode(tagCarrier)
	ciwsMode.isAi = true
	ciwsMode.ignoreHeat = tagCarrier ~= 0 and HasTag(tagCarrier, "ciws_ai_noheat")
	ciwsMode.ignoreDamagePenalty = false
end

function ciwsInitializeServerModeState()
	autoFireEnabled = true
end

function ciwsInitializeClientModeState()
	autoFireState.enabled = true
	autoFireState.synced = true
end

function ciwsCanToggleAutoMode()
	return false
end

function ciwsHandleClientModeInput()
end

function ciwsGetClientRequestedFire()
	return false
end

function ciwsShouldUseTrackedTarget()
	return true
end

function ciwsResolveManualShootDir(muzzlePos, gunDir)
	return VecNormalize(gunDir)
end

function ciwsIsTrackingEnabled(radarStatus)
	return radarStatus ~= "Destroyed"
end

function ciwsHandleServerRadarDestroyed(radarStatus)
end

function ciwsResolveRequestedFire(dt, aiTrackingActive, yawError, pitchError)
	if not aiTrackingActive then
		ciwsMode.fireTimer = math.max(0.0, ciwsMode.fireTimer - dt)
		return false
	end

	local aligned = math.abs(yawError) <= aiConfig.fireYawTolerance and math.abs(pitchError) <= aiConfig.firePitchTolerance
	if aligned then
		ciwsMode.fireTimer = aiConfig.triggerHoldSeconds
	else
		ciwsMode.fireTimer = math.max(0.0, ciwsMode.fireTimer - dt)
	end

	return ciwsMode.fireTimer > 0.0
end

function ciwsGetLockLabel()
	return "Auto Fire [AI]: "
end

function ciwsHandleClientRadarDestroyed(radarStatus)
end

function ciwsShouldRenderHud()
	return false
end

function ciwsShouldSyncHeatState()
	return false
end

function server.init()
	ciwsCommonServerInit()
end

function server.tick(dt)
	ciwsCommonServerTick(dt)
end

function client.init()
	ciwsCommonRemoteClientInit()
end

function client.tick(dt)
	ciwsCommonRemoteClientTick(dt)
end

#include "ciws_emplacement_core.lua"
