--[[
	Short rumble patterns on the active controller.

	Each pattern is a list of pulses: { at, motor, intensity, duration }, with
	times in seconds. Starting a pattern cancels the one before it, so rapid
	inputs (like holding speed up) stay crisp instead of smearing together.
	Pads without rumble, or with vibration turned off, are skipped silently.
]]

local HapticService = game:GetService("HapticService")

type Pulse = { number | string }

local PATTERNS: { [string]: { Pulse } } = {
	-- Rising double pulse: controller mode on, controller connected.
	on = { { 0, "Small", 0.55, 0.05 }, { 0.09, "Large", 0.75, 0.09 } },
	-- One soft, longer thump: controller mode off.
	off = { { 0, "Large", 0.5, 0.12 } },
	-- Camera shutter.
	shutter = { { 0, "Large", 1, 0.05 }, { 0, "Small", 0.7, 0.05 } },
	-- Speed step.
	tick = { { 0, "Small", 0.4, 0.03 } },
	-- Already at the limit, or nothing to act on.
	limit = { { 0, "Small", 0.55, 0.035 }, { 0.08, "Small", 0.55, 0.035 } },
	-- Profile switched, level movement on.
	switch = { { 0, "Small", 0.5, 0.04 }, { 0.08, "Small", 0.5, 0.04 } },
	-- Camera glide started (reset, frame selection).
	glide = { { 0, "Large", 0.35, 0.07 } },
	-- Something finished well (upload done, binding captured).
	confirm = { { 0, "Small", 0.5, 0.06 } },
}

local MOTORS = {
	Small = Enum.VibrationMotor.Small,
	Large = Enum.VibrationMotor.Large,
}

local Haptics = {}
Haptics.__index = Haptics
Haptics.Patterns = PATTERNS

function Haptics.new(gamepad: any, store: any)
	local self = setmetatable({}, Haptics)
	self._gamepad = gamepad
	self._store = store
	self._token = 0
	self._support = {} :: { [Enum.UserInputType]: { [string]: boolean } }
	self._running = nil :: Enum.UserInputType?
	return self
end

function Haptics:_motors(pad: Enum.UserInputType): { [string]: boolean }
	local support = self._support[pad]
	if not support then
		support = {}
		local ok, vibrates = pcall(HapticService.IsVibrationSupported, HapticService, pad)
		for name, motor in MOTORS do
			local motorOk, supported = pcall(HapticService.IsMotorSupported, HapticService, pad, motor)
			support[name] = ok and vibrates and motorOk and supported == true
		end
		self._support[pad] = support
	end
	return support
end

function Haptics:_set(pad: Enum.UserInputType, motor: string, intensity: number)
	if self:_motors(pad)[motor] then
		pcall(HapticService.SetMotor, HapticService, pad, MOTORS[motor], intensity)
	end
end

function Haptics:Stop()
	self._token += 1
	local pad = self._running
	self._running = nil
	if pad then
		for name in MOTORS do
			self:_set(pad, name, 0)
		end
	end
end

function Haptics:Play(name: string)
	local pattern = PATTERNS[name]
	local pad = self._gamepad.active
	if not pattern or not pad or not self._store:GetSetting("vibration") then
		return
	end
	self:Stop()
	local token = self._token
	local strength = (self._store:GetSetting("vibrationStrength") or 100) / 100
	self._running = pad
	for _, pulse in pattern do
		local at, motor, intensity, duration =
			pulse[1] :: number, pulse[2] :: string, pulse[3] :: number, pulse[4] :: number
		task.delay(at, function()
			if self._token ~= token then
				return
			end
			self:_set(pad, motor, math.clamp(intensity * strength, 0, 1))
			task.delay(duration, function()
				if self._token == token then
					self:_set(pad, motor, 0)
				end
			end)
		end)
	end
end

function Haptics:Destroy()
	self:Stop()
end

return Haptics
