--[[
	Controller detection and per-frame sampling.

	Input is polled with GetGamepadState every frame instead of relying on
	InputBegan, which keeps the plugin's view of the pad consistent no matter
	which Studio panel has focus. With the "Auto" preference the active pad is
	whichever connected pad was used most recently.

	The controller family (Xbox / PlayStation / Generic) comes from the glyph
	Roblox picks for the connected pad, so button names and icons follow the
	hardware without any per-device tables.
]]

local UserInputService = game:GetService("UserInputService")

local Inputs = require(script.Parent.Inputs)
local Signal = require(script.Parent.Parent.Util.Signal)

local TRIGGER_DOWN = 0.55
local TRIGGER_UP = 0.35
local STICK_ACTIVITY = 0.35
local TRIGGER_ACTIVITY = 0.2

export type Frame = {
	gamepad: Enum.UserInputType?,
	values: { [string]: number },
	sticks: { [string]: Vector2 },
	down: { [string]: boolean },
	pressed: { [string]: boolean },
	released: { [string]: boolean },
	active: boolean,
}

local GAMEPADS = {
	Enum.UserInputType.Gamepad1,
	Enum.UserInputType.Gamepad2,
	Enum.UserInputType.Gamepad3,
	Enum.UserInputType.Gamepad4,
	Enum.UserInputType.Gamepad5,
	Enum.UserInputType.Gamepad6,
	Enum.UserInputType.Gamepad7,
	Enum.UserInputType.Gamepad8,
}

local Gamepad = {}
Gamepad.__index = Gamepad
Gamepad.Slots = GAMEPADS

local function familyFromImage(image: string): string
	if string.find(image, "PlayStation", 1, true) then
		return "PlayStation"
	elseif string.find(image, "Xbox", 1, true) then
		return "Xbox"
	end
	return "Generic"
end

function Gamepad.new()
	local self = setmetatable({}, Gamepad)
	self.preference = "Auto" -- "Auto" or a Gamepad enum name
	self.active = nil :: Enum.UserInputType?
	self.connected = {} :: { Enum.UserInputType }
	self.family = "Generic"
	self._down = {}
	self._glyphCache = {}
	-- Fired when the connected set, active pad or family changes.
	self.Changed = Signal.new()
	self._connections = {
		UserInputService.GamepadConnected:Connect(function()
			self:Refresh()
		end),
		UserInputService.GamepadDisconnected:Connect(function()
			self:Refresh()
		end),
		UserInputService.LastInputTypeChanged:Connect(function()
			self:_refreshFamily()
		end),
	}
	self:Refresh()
	return self
end

function Gamepad:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self.Changed:Destroy()
end

function Gamepad:_refreshFamily()
	local ok, image = pcall(UserInputService.GetImageForKeyCode, UserInputService, Enum.KeyCode.ButtonA)
	local family = if ok and type(image) == "string" then familyFromImage(image) else "Generic"
	if family ~= self.family then
		self.family = family
		table.clear(self._glyphCache)
		self.Changed:Fire()
	end
end

function Gamepad:Refresh()
	local connected = {}
	local ok, pads = pcall(UserInputService.GetConnectedGamepads, UserInputService)
	if ok then
		for _, slot in GAMEPADS do
			if table.find(pads, slot) then
				table.insert(connected, slot)
			end
		end
	end
	self.connected = connected

	local previous = self.active
	if self.preference ~= "Auto" then
		local preferred = (Enum.UserInputType :: any)[self.preference]
		self.active = if table.find(connected, preferred) then preferred else nil
	elseif not (self.active and table.find(connected, self.active)) then
		self.active = connected[1]
	end
	if self.active ~= previous then
		table.clear(self._down)
	end
	self:_refreshFamily()
	self.Changed:Fire()
end

function Gamepad:SetPreference(preference: string)
	if preference ~= "Auto" and not pcall(function()
		return (Enum.UserInputType :: any)[preference]
	end) then
		preference = "Auto"
	end
	self.preference = preference
	self.active = nil
	self:Refresh()
end

function Gamepad:IsConnected(): boolean
	return self.active ~= nil
end

function Gamepad:DisplayName(): string
	if not self.active then
		return "No controller"
	end
	if self.family == "PlayStation" then
		return "PlayStation controller"
	elseif self.family == "Xbox" then
		return "Xbox controller"
	end
	return "Controller"
end

function Gamepad:SlotNumber(slot: Enum.UserInputType?): number?
	slot = slot or self.active
	return slot and table.find(GAMEPADS, slot) or nil
end

-- Content id for the button glyph of the connected controller family, or "".
function Gamepad:Glyph(key: string): string
	local cached = self._glyphCache[key]
	if cached then
		return cached
	end
	local info = Inputs.ByKey[key]
	local image = ""
	if info then
		local ok, result = pcall(UserInputService.GetImageForKeyCode, UserInputService, info.keyCode)
		if ok and type(result) == "string" then
			image = result
		end
	end
	self._glyphCache[key] = image
	return image
end

function Gamepad:InputName(key: string): string
	return Inputs.DisplayName(key, self.family)
end

local function readState(slot: Enum.UserInputType, values: { [string]: number }, sticks: { [string]: Vector2 })
	local ok, state = pcall(UserInputService.GetGamepadState, UserInputService, slot)
	if not ok then
		return false
	end
	for _, input in state do
		local info = Inputs.ByKeyCode[input.KeyCode]
		if info then
			if info.kind == "stick" then
				sticks[info.key] = Vector2.new(input.Position.X, input.Position.Y)
			elseif info.kind == "trigger" then
				values[info.key] = math.clamp(input.Position.Z, 0, 1)
			else
				local held = input.UserInputState == Enum.UserInputState.Begin
					or input.UserInputState == Enum.UserInputState.Change
				values[info.key] = if held then 1 else 0
			end
		end
	end
	return true
end

local function hasActivity(values: { [string]: number }, sticks: { [string]: Vector2 }): boolean
	for key, value in values do
		local threshold = if Inputs.ByKey[key].kind == "trigger" then TRIGGER_ACTIVITY else 0.5
		if value > threshold then
			return true
		end
	end
	for _, stick in sticks do
		if stick.Magnitude > STICK_ACTIVITY then
			return true
		end
	end
	return false
end

-- Reads the active pad and returns this frame's state with press/release
-- edges. `suspended` (window unfocused, text box focused) releases everything.
function Gamepad:Sample(suspended: boolean?): Frame
	local values: { [string]: number } = {}
	local sticks: { [string]: Vector2 } = {}

	if not suspended then
		if self.preference == "Auto" and #self.connected > 1 then
			-- Follow whichever pad is being used.
			for _, slot in self.connected do
				if slot ~= self.active then
					local otherValues, otherSticks = {}, {}
					if readState(slot, otherValues, otherSticks) and hasActivity(otherValues, otherSticks) then
						self.active = slot
						table.clear(self._down)
						self.Changed:Fire()
						break
					end
				end
			end
		end
		if self.active then
			readState(self.active, values, sticks)
		end
	end

	local down: { [string]: boolean } = {}
	local pressed: { [string]: boolean } = {}
	local released: { [string]: boolean } = {}
	local previous = self._down
	local active = false

	for _, info in Inputs.List do
		local key = info.key
		local isDown: boolean
		if info.kind == "stick" then
			local stick = sticks[key] or Vector2.zero
			sticks[key] = stick
			isDown = stick.Magnitude > 0.7
		elseif info.kind == "trigger" then
			local value = values[key] or 0
			values[key] = value
			isDown = if previous[key] then value > TRIGGER_UP else value > TRIGGER_DOWN
		else
			local value = values[key] or 0
			values[key] = value
			isDown = value > 0.5
		end
		if isDown then
			down[key] = true
			active = true
			if not previous[key] then
				pressed[key] = true
			end
		elseif previous[key] then
			released[key] = true
		end
	end
	self._down = down

	return {
		gamepad = self.active,
		values = values,
		sticks = sticks,
		down = down,
		pressed = pressed,
		released = released,
		active = active,
	}
end

return Gamepad
