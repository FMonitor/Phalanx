#version 2

CIWS_VARIANT = "player"

function ciwsConfigureMode(tagCarrier)
	ciwsMode.isAi = false
	ciwsMode.ignoreHeat = false
	ciwsMode.ignoreDamagePenalty = false
end

function ciwsInitializeServerModeState()
	autoFireEnabled = false
end

function ciwsInitializeClientModeState()
	autoFireState.enabled = false
	autoFireState.synced = true
end

function ciwsCanToggleAutoMode()
	return true
end

function ciwsHandleClientModeInput()
	if InputPressed("q") then
		autoFireState.enabled = not autoFireState.enabled
		autoFireState.synced = false
	end
end

function ciwsGetClientRequestedFire()
	return InputDown("vehicleraise") or InputDown("usetool")
end

function ciwsShouldUseTrackedTarget()
	return autoFireEnabled
end

function ciwsIsTrackingEnabled(radarStatus)
	return radarStatus ~= "Destroyed" and autoFireEnabled
end

function ciwsHandleServerRadarDestroyed(radarStatus)
	if radarStatus == "Destroyed" and autoFireEnabled then
		autoFireEnabled = false
	end
end

function ciwsResolveRequestedFire(dt, aiTrackingActive, yawError, pitchError)
	return serverFireInput
end

function ciwsGetLockLabel()
	return "Auto Lock [Q]: "
end

function ciwsHandleClientRadarDestroyed(radarStatus)
	if radarStatus == "Destroyed" and autoFireState.enabled then
		autoFireState.enabled = false
		autoFireState.synced = false
	end
end

function ciwsShouldRenderHud()
	return true
end

#include "ciws_emplacement_core.lua"
