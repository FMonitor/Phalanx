#version 2

local function initBeamGlow()
	local shapes = FindShapes("beam_glow", true)
	for i = 1, #shapes do
		SetShapeEmissiveScale(shapes[i], 2.0)
	end
end

function server.init()
	initBeamGlow()
end

function client.init()
	initBeamGlow()
end
