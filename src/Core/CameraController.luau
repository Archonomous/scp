--[[
	Six-degree-of-freedom fly camera for the edit-mode viewport.

	Each frame starts from the camera's *current* CFrame, so mouse and keyboard
	navigation keep working alongside the controller. The camera is only
	written when the controller is actually doing something (input, residual
	smoothed velocity, or a transition), so it never fights Studio's own
	camera while idle.

	Orientation is handled as YXZ euler angles: yaw about world up, pitch
	about the camera's right axis, roll last. Pitch is clamped short of
	straight up/down so yaw stays well-defined.
]]

local Selection = game:GetService("Selection")

local Signal = require(script.Parent.Parent.Util.Signal)

local SPEED_STEPS = { 0.0625, 0.125, 0.25, 0.5, 1, 2, 4, 8, 16, 32 }
local DEFAULT_SPEED_INDEX = 5
local MAX_PITCH = math.rad(89)
local MIN_FOV, MAX_FOV = 1, 120
local EPSILON = 1e-3
local TRANSITION_TIME = 0.45
local ORBIT_ZOOM_RATE = 1.2
local ORBIT_MIN_DISTANCE = 1
local ORBIT_MAX_DISTANCE = 5000

local CameraController = {}
CameraController.__index = CameraController
CameraController.SpeedSteps = SPEED_STEPS
CameraController.DefaultSpeedIndex = DEFAULT_SPEED_INDEX

-- Frame-rate independent exponential approach. smoothing 0 is near-instant,
-- 0.95 takes most of a second to settle.
local function approachAlpha(smoothing: number, dt: number): number
	local rate = 1 + 60 * (1 - smoothing) ^ 1.5
	return 1 - math.exp(-rate * dt)
end

local function easeOutCubic(t: number): number
	return 1 - (1 - t) ^ 3
end

local function wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Radial deadzone with rescaling so output still reaches 1, then a power curve.
function CameraController.ShapeStick(raw: Vector2, deadzone: number, curve: number): Vector2
	local magnitude = raw.Magnitude
	if magnitude <= deadzone or magnitude < EPSILON then
		return Vector2.zero
	end
	local scaled = math.clamp((magnitude - deadzone) / (1 - deadzone), 0, 1)
	return raw.Unit * scaled ^ curve
end

function CameraController.new()
	local self = setmetatable({}, CameraController)
	self.speedIndex = DEFAULT_SPEED_INDEX
	self.velocity = Vector3.zero
	self.lookRate = Vector2.zero
	self.rollRate = 0
	self.fovRate = 0
	self.zoomRate = 0
	self.transition = nil
	self.startCFrame = nil :: CFrame?
	-- While set, the right stick orbits this point instead of turning in place.
	-- Set by framing or flying to a target; moving clears it.
	self.orbitCenter = nil :: Vector3?
	self.startFov = nil :: number?
	-- Fired with (kind, value) for HUD feedback: "speed", "fov", "roll".
	self.Feedback = Signal.new()
	return self
end

function CameraController:GetSpeedMultiplier(): number
	return SPEED_STEPS[self.speedIndex]
end

function CameraController:SetSpeedIndex(index: number)
	index = math.clamp(math.floor(index), 1, #SPEED_STEPS)
	self.speedIndex = index
	self.Feedback:Fire("speed", SPEED_STEPS[index])
end

-- Returns false when already at the slowest / fastest step.
function CameraController:StepSpeed(direction: number): boolean
	local previous = self.speedIndex
	self:SetSpeedIndex(self.speedIndex + direction)
	return self.speedIndex ~= previous
end

function CameraController:Begin()
	local camera = workspace.CurrentCamera
	self.orbitCenter = nil
	self.velocity = Vector3.zero
	self.lookRate = Vector2.zero
	self.rollRate = 0
	self.fovRate = 0
	self.zoomRate = 0
	self.transition = nil
	if camera then
		self.startCFrame = camera.CFrame
		self.startFov = camera.FieldOfView
	end
end

-- Called when controller mode turns off. Optionally levels the horizon
-- immediately, since Studio's camera has no notion of roll.
function CameraController:End(levelHorizon: boolean)
	self.orbitCenter = nil
	self.velocity = Vector3.zero
	self.lookRate = Vector2.zero
	self.rollRate = 0
	self.fovRate = 0
	self.zoomRate = 0
	self.transition = nil
	local camera = workspace.CurrentCamera
	if levelHorizon and camera then
		local rx, ry, rz = camera.CFrame:ToEulerAnglesYXZ()
		if math.abs(rz) > EPSILON then
			local focusDistance = (camera.Focus.Position - camera.CFrame.Position).Magnitude
			local cframe = CFrame.new(camera.CFrame.Position) * CFrame.fromEulerAnglesYXZ(rx, ry, 0)
			camera.CFrame = cframe
			camera.Focus = cframe * CFrame.new(0, 0, -math.clamp(focusDistance, 4, 500))
		end
	end
end

-- Transitions ----------------------------------------------------------------

function CameraController:_startTransition(fields: { cframe: CFrame?, roll: number?, fov: number? })
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	self.orbitCenter = nil
	local rx, ry, rz = camera.CFrame:ToEulerAnglesYXZ()
	self.transition = {
		elapsed = 0,
		duration = TRANSITION_TIME,
		fromCFrame = camera.CFrame,
		toCFrame = fields.cframe,
		fromRoll = rz,
		toRoll = fields.roll,
		fromFov = camera.FieldOfView,
		toFov = fields.fov,
		fromPitchYaw = { rx, ry },
	}
	self.velocity = Vector3.zero
	self.lookRate = Vector2.zero
	self.rollRate = 0
	self.fovRate = 0
end

function CameraController:ResetRoll()
	self:_startTransition({ roll = 0 })
	self.Feedback:Fire("roll", 0)
end

function CameraController:ResetFov(defaultFov: number)
	self:_startTransition({ fov = defaultFov })
	self.Feedback:Fire("fov", defaultFov)
end

function CameraController:ResetAll(defaultFov: number)
	self:_startTransition({ roll = 0, fov = defaultFov })
	self:SetSpeedIndex(DEFAULT_SPEED_INDEX)
end

function CameraController:LevelView()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local _, ry = camera.CFrame:ToEulerAnglesYXZ()
	self:_startTransition({ cframe = CFrame.new(camera.CFrame.Position) * CFrame.fromEulerAnglesYXZ(0, ry, 0) })
end

-- Glides to an exact saved view (e.g. a screenshot's camera).
function CameraController:GoToView(cframe: CFrame, fov: number)
	self:_startTransition({ cframe = cframe, fov = math.clamp(fov, 1, 120) })
	self.Feedback:Fire("fov", fov)
end

function CameraController:ReturnToStart(): boolean
	if not self.startCFrame then
		return false
	end
	self:_startTransition({ cframe = self.startCFrame, fov = self.startFov })
	return true
end

local function selectionBounds(): (Vector3?, number?)
	local minV, maxV = nil, nil
	local function include(cframe: CFrame, size: Vector3)
		local half = size / 2
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, z in { -1, 1 } do
					local corner = cframe:PointToWorldSpace(half * Vector3.new(x, y, z))
					minV = if minV then minV:Min(corner) else corner
					maxV = if maxV then maxV:Max(corner) else corner
				end
			end
		end
	end
	for _, instance in Selection:Get() do
		if instance:IsA("BasePart") then
			include(instance.CFrame, instance.Size)
		elseif instance:IsA("Model") then
			local ok, cframe, size = pcall(instance.GetBoundingBox, instance)
			if ok and size.Magnitude > 0 then
				include(cframe, size)
			end
		elseif instance:IsA("Attachment") then
			include(CFrame.new(instance.WorldPosition), Vector3.one)
		elseif instance:IsA("Folder") or instance:IsA("WorldModel") then
			for _, descendant in instance:GetDescendants() do
				if descendant:IsA("BasePart") then
					include(descendant.CFrame, descendant.Size)
				end
			end
		end
	end
	if not minV then
		return nil, nil
	end
	return (minV + maxV) / 2, math.max(((maxV - minV) / 2).Magnitude, 0.5)
end

-- Glides to frame the selection while keeping the current viewing direction.
function CameraController:FrameSelection(): boolean
	local camera = workspace.CurrentCamera
	local center, radius = selectionBounds()
	if not camera or not center then
		return false
	end
	local halfFov = math.rad(camera.FieldOfView) / 2
	local distance = (radius :: number) / math.sin(math.max(halfFov, math.rad(5))) * 1.1
	local look = camera.CFrame.LookVector
	local position = center - look * distance
	local rx, ry, rz = camera.CFrame:ToEulerAnglesYXZ()
	self:_startTransition({ cframe = CFrame.new(position) * CFrame.fromEulerAnglesYXZ(rx, ry, rz) })
	self.transition.focus = center
	self.orbitCenter = center
	return true
end

-- Glides toward a point, stopping `standoff` studs short of it horizontally
-- and `height` studs above it. The view arrives level: the focus (and orbit
-- centre) is the point raised to the camera's height, so the camera plane
-- stays parallel with the horizon. Returns false when already there.
function CameraController:FlyTo(point: Vector3, standoff: number, height: number?): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	local from = camera.CFrame.Position
	local flat = Vector3.new(point.X - from.X, 0, point.Z - from.Z)
	if flat.Magnitude < EPSILON then
		-- Straight above or below: keep the current heading.
		local _, heading = camera.CFrame:ToEulerAnglesYXZ()
		flat = CFrame.fromEulerAnglesYXZ(0, heading, 0).LookVector
	end
	local focus = point + Vector3.yAxis * (height or 0)
	local position = focus - flat.Unit * standoff
	if (position - from).Magnitude < 0.5 then
		return false
	end
	self:_startTransition({ cframe = CFrame.lookAt(position, focus) })
	self.transition.focus = focus
	self.orbitCenter = focus
	return true
end

-- Per-frame update ------------------------------------------------------------

export type StepInput = {
	move: Vector2,
	look: Vector2,
	vertical: number,
	roll: number,
	fov: number,
	boost: boolean,
	precision: boolean,
}

function CameraController:_stepTransition(camera: Camera, dt: number): boolean
	local transition = self.transition
	if not transition then
		return false
	end
	transition.elapsed += dt
	local t = easeOutCubic(math.clamp(transition.elapsed / transition.duration, 0, 1))

	local cframe: CFrame
	if transition.toCFrame then
		cframe = transition.fromCFrame:Lerp(transition.toCFrame, t)
	else
		cframe = camera.CFrame
	end
	if transition.toRoll ~= nil then
		local rx, ry = cframe:ToEulerAnglesYXZ()
		local roll = transition.fromRoll + wrapAngle(transition.toRoll - transition.fromRoll) * t
		cframe = CFrame.new(cframe.Position) * CFrame.fromEulerAnglesYXZ(rx, ry, roll)
	end

	local focusDistance = (camera.Focus.Position - camera.CFrame.Position).Magnitude
	camera.CFrame = cframe
	if transition.focus then
		camera.Focus = CFrame.new(transition.focus)
	else
		camera.Focus = cframe * CFrame.new(0, 0, -math.clamp(focusDistance, 4, 500))
	end
	if transition.toFov then
		camera.FieldOfView = transition.fromFov + (transition.toFov - transition.fromFov) * t
	end

	if transition.elapsed >= transition.duration then
		self.transition = nil
	end
	return true
end

-- Returns true when the camera was written this frame.
function CameraController:Step(dt: number, input: StepInput, tuning: { [string]: any }): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	dt = math.min(dt, 0.1)

	local hasInput = input.move.Magnitude > 0
		or input.look.Magnitude > 0
		or math.abs(input.vertical) > 0
		or math.abs(input.roll) > 0
		or math.abs(input.fov) > 0

	-- Moving leaves orbit and goes back to flying.
	if self.orbitCenter and input.move.Magnitude > 0 then
		self.orbitCenter = nil
	end

	if self.transition then
		-- While orbiting, the glide into place finishes first so the orbit
		-- starts with the target dead centre.
		if hasInput and not self.orbitCenter then
			-- Any deliberate input takes over from a running transition.
			self.transition = nil
		else
			return self:_stepTransition(camera, dt)
		end
	end

	-- If the view was turned some other way (e.g. with the mouse), the centre is
	-- no longer in the middle; drop it rather than jump the camera back.
	local orbitCenter = self.orbitCenter
	if orbitCenter then
		local offset = orbitCenter - camera.CFrame.Position
		if offset.Magnitude < EPSILON or camera.CFrame.LookVector:Dot(offset.Unit) < 0.995 then
			self.orbitCenter = nil
		end
	end

	local precision = if input.precision then tuning.precisionMultiplier else 1
	local lookPrecision = if input.precision then math.sqrt(tuning.precisionMultiplier) else 1
	local speed = tuning.moveSpeed
		* SPEED_STEPS[self.speedIndex]
		* (if input.boost then tuning.boostMultiplier else 1)
		* precision

	local cframe = camera.CFrame
	local up = if tuning.worldVertical then Vector3.yAxis else cframe.UpVector
	local forward, right = cframe.LookVector, cframe.RightVector
	if tuning.levelMovement then
		-- Heading only, so pitch and roll never tip movement off the ground plane.
		local _, heading = cframe:ToEulerAnglesYXZ()
		local flat = CFrame.fromEulerAnglesYXZ(0, heading, 0)
		forward, right = flat.LookVector, flat.RightVector
		up = Vector3.yAxis
	end
	-- While orbiting, up / down zooms toward or away from the centre instead.
	local vertical = if self.orbitCenter then 0 else input.vertical
	local targetVelocity = (right * input.move.X + forward * input.move.Y + up * vertical) * speed

	local moveAlpha = approachAlpha(tuning.moveSmoothing, dt)
	local lookAlpha = approachAlpha(tuning.lookSmoothing, dt)

	self.velocity = self.velocity:Lerp(targetVelocity, moveAlpha)
	if targetVelocity.Magnitude == 0 and self.velocity.Magnitude < 0.01 then
		self.velocity = Vector3.zero
	end

	local rx, ry, rz = cframe:ToEulerAnglesYXZ()

	-- Rotate the look input by the current roll so "stick up" means "toward the
	-- top of the screen" even when the horizon is tilted.
	local look = input.look
	if math.abs(rz) > EPSILON then
		local c, s = math.cos(rz), math.sin(rz)
		look = Vector2.new(look.X * c - look.Y * s, look.X * s + look.Y * c)
	end
	local lookSign = Vector2.new(if tuning.invertX then -1 else 1, if tuning.invertY then -1 else 1)
	local targetLookRate = look * lookSign * tuning.lookSpeed * lookPrecision
	self.lookRate = self.lookRate:Lerp(targetLookRate, lookAlpha)
	if targetLookRate.Magnitude == 0 and self.lookRate.Magnitude < 0.05 then
		self.lookRate = Vector2.zero
	end

	local targetRollRate = input.roll * tuning.rollSpeed * lookPrecision
	self.rollRate += (targetRollRate - self.rollRate) * lookAlpha
	if targetRollRate == 0 and math.abs(self.rollRate) < 0.05 then
		self.rollRate = 0
	end

	-- Fraction of the orbit distance closed per second, so zoom feels the same
	-- near and far. Boost and precision scale it like movement.
	local targetZoomRate = if self.orbitCenter
		then input.vertical * ORBIT_ZOOM_RATE * (if input.boost then 2 else 1) * precision
		else 0
	self.zoomRate += (targetZoomRate - self.zoomRate) * moveAlpha
	if targetZoomRate == 0 and math.abs(self.zoomRate) < 0.01 then
		self.zoomRate = 0
	end

	local targetFovRate = input.fov * tuning.fovSpeed
	self.fovRate += (targetFovRate - self.fovRate) * moveAlpha
	if targetFovRate == 0 and math.abs(self.fovRate) < 0.05 then
		self.fovRate = 0
	end

	local moving = self.velocity.Magnitude > 0
		or self.lookRate.Magnitude > 0
		or self.rollRate ~= 0
		or self.fovRate ~= 0
		or self.zoomRate ~= 0
	if not moving then
		return false
	end

	local yaw = ry - math.rad(self.lookRate.X) * dt
	local pitch = math.clamp(rx + math.rad(self.lookRate.Y) * dt, -MAX_PITCH, MAX_PITCH)
	local roll = wrapAngle(rz - math.rad(self.rollRate) * dt)

	local rotation = CFrame.fromEulerAnglesYXZ(pitch, yaw, roll)
	local center = self.orbitCenter
	if center then
		-- Same yaw / pitch as looking around, but the camera swings around the
		-- centre so it stays in the middle of the view. Up / down zooms in and out.
		local distance = (cframe.Position - center).Magnitude
		distance = math.clamp(distance * math.exp(-self.zoomRate * dt), ORBIT_MIN_DISTANCE, ORBIT_MAX_DISTANCE)
		camera.CFrame = CFrame.new(center - rotation.LookVector * distance) * rotation
		camera.Focus = CFrame.new(center)
	else
		local focusDistance = (camera.Focus.Position - cframe.Position).Magnitude
		local newCFrame = CFrame.new(cframe.Position + self.velocity * dt) * rotation
		camera.CFrame = newCFrame
		camera.Focus = newCFrame * CFrame.new(0, 0, -math.clamp(focusDistance, 4, 500))
	end

	if self.fovRate ~= 0 then
		local fov = math.clamp(camera.FieldOfView + self.fovRate * dt, MIN_FOV, MAX_FOV)
		camera.FieldOfView = fov
		self.Feedback:Fire("fov", fov)
	end
	if self.rollRate ~= 0 then
		self.Feedback:Fire("roll", math.deg(roll))
	end
	return true
end

function CameraController:Destroy()
	self.Feedback:Destroy()
end

return CameraController
