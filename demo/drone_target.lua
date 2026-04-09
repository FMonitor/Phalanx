
#version 2

droneBody = 0
droneState = {
	spawnTime = 0.0,
	baseForward = Vec(0, 0, -1),
	cruiseHeight = 0.0,
	speed = 23.0,
	swaySeed = 0.0,
	lifeTime = 40.0,
	crashing = false,
	crashStartedTime = 0.0,
	crashDuration = 6.0,
	crashGravity = 16.0,
	crashForwardPush = 3.5,
	crashMinFallSpeed = 8.0,
	crashSmokeTimer = 0.0,
	crashCleanupHeight = -25.0,
	explosionRadius = 1.2,
	crashAngularVelocity = Vec(0, 0, 0),
}

function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function lerp(a, b, t)
	return a + (b - a) * t
end

function vecLerp(a, b, t)
	return Vec(
		lerp(a[1], b[1], t),
		lerp(a[2], b[2], t),
		lerp(a[3], b[3], t)
	)
end

function rndRange(lo, hi)
	return lo + (hi - lo) * math.random()
end

function spawnCrashSmoke(pos, vel)
	ParticleReset()
	ParticleType("smoke")
	ParticleColor(0.18, 0.18, 0.18)
	ParticleAlpha(0.7, 0.0)
	ParticleRadius(0.25, 1.2)
	ParticleDrag(0.4)
	ParticleGravity(-0.2)
	SpawnParticle(pos, VecAdd(vel, Vec(rndRange(-1.5, 1.5), rndRange(0.5, 2.5), rndRange(-1.5, 1.5))), rndRange(0.8, 1.5))
end

function startCrash()
        if droneState.crashing or droneBody == 0 or not IsHandleValid(droneBody) then
                return
        end

        droneState.crashing = true
        droneState.crashStartedTime = GetTime()
        droneState.crashSmokeTimer = 0.0

        local bodyTransform = GetBodyTransform(droneBody)
        Explosion(bodyTransform.pos, droneState.explosionRadius)
end

function tickCrash(dt)
        if droneBody == 0 or not IsHandleValid(droneBody) then
                return
        end

        local bodyTransform = GetBodyTransform(droneBody)
        local currentVel = GetBodyVelocity(droneBody)

        droneState.crashSmokeTimer = droneState.crashSmokeTimer - dt
        if droneState.crashSmokeTimer <= 0.0 then
                droneState.crashSmokeTimer = rndRange(0.03, 0.08)
                spawnCrashSmoke(bodyTransform.pos, currentVel)
        end

        if bodyTransform.pos[2] < droneState.crashCleanupHeight or GetTime() > droneState.crashStartedTime + droneState.crashDuration then
                Delete(droneBody)
                droneBody = 0
        end
end


droneVehicle = 0
function server.init()
    droneVehicle = FindVehicle('drone')
    if droneVehicle == 0 then droneVehicle = FindVehicle() end
    droneBody = FindBody('drone_body')
    if droneBody == 0 and droneVehicle ~= 0 then droneBody = GetVehicleBody(droneVehicle) end
    DebugPrint('Drone Init: Veh='..tostring(droneVehicle)..' Body='..tostring(droneBody))
    droneState.spawnTime = GetTime()
	droneState.swaySeed = math.random() * 10.0

	if droneBody ~= 0 then
		local t = GetBodyTransform(droneBody)
		droneState.baseForward = VecNormalize(TransformToParentVec(t, Vec(0, 0, 1)))
		droneState.baseForward[2] = droneState.baseForward[2] * 0.15
		droneState.baseForward = VecNormalize(droneState.baseForward)
		droneState.cruiseHeight = t.pos[2]
	end
end

function server.tick(dt)
    DebugWatch('MyDrone_'..tostring(droneBody), 'Veh='..tostring(droneVehicle)..' Body='..tostring(droneBody))
    if droneBody == 0 or not IsHandleValid(droneBody) then return end


	DebugWatch("CustomDroneTarget", "Body="..tostring(droneBody))
	if IsBodyBroken(droneBody) then
		if not droneState.crashing then
			startCrash()
		end
		tickCrash(dt)
		return
	end

	local bodyTransform = GetBodyTransform(droneBody)
	local age = GetTime() - droneState.spawnTime
	if age > droneState.lifeTime or bodyTransform.pos[2] < -20.0 or VecLength(bodyTransform.pos) > 500.0 then
		Delete(droneBody)
		droneBody = 0
		return
	end

	local altitudeError = droneState.cruiseHeight - bodyTransform.pos[2]
	local currentVel = GetBodyVelocity(droneBody)
	local lateral = Vec(-droneState.baseForward[3], 0, droneState.baseForward[1])
	local sway = math.sin(GetTime() * 1.8 + droneState.swaySeed) * 2.0
	local desiredForward = VecNormalize(VecAdd(droneState.baseForward, Vec(0, altitudeError * 0.03, 0)))
	local desiredVel = VecAdd(VecScale(desiredForward, droneState.speed), VecScale(lateral, sway))
	desiredVel[2] = desiredVel[2] + altitudeError * 1.6

	local blend = clamp(dt * 2.8, 0.0, 1.0)
	SetBodyVelocity(droneBody, vecLerp(currentVel, desiredVel, blend))
	
	-- 计算偏航和俯仰以实现倾斜
	local roll = -sway * 15.0 -- 左右倾斜
	local pitch = -altitudeError * 15.0 -- 上下倾斜
	
        local lookAtPos = VecAdd(bodyTransform.pos, desiredForward)
        local baseRot = QuatLookAt(bodyTransform.pos, lookAtPos)
	
        local baseTransform = Transform(bodyTransform.pos, baseRot)
	local tiltLocalTransform = Transform(Vec(0, 0, 0), QuatEuler(pitch, 0, roll))
	local finalTransform = TransformToParentTransform(baseTransform, tiltLocalTransform)
	
        SetBodyAngularVelocity(droneBody, Vec(0, 0, 0))
	SetBodyTransform(droneBody, finalTransform)
end
