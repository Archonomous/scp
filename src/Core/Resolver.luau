--[[
	Turns a raw Gamepad frame into action outputs for the active profile.

	Combos: a binding with `mod` only fires while the modifier is held. While a
	modifier is held, plain bindings on the same key are suppressed, so
	View+D-Pad Right can coexist with a plain D-Pad Right binding.

	Modifier keys keep their own plain binding: a button used as a modifier
	anywhere fires its press action on release, and only if no combo used it
	("tap"). Buttons that are never modifiers fire instantly on press.
]]

local Actions = require(script.Parent.Actions)
local Inputs = require(script.Parent.Inputs)

local REPEAT_DELAY = 0.38
local REPEAT_INTERVAL = 0.09
local ANALOG_TRIGGER_FLOOR = 0.06

export type Output = {
	sticks: { [string]: Vector2 },
	analog: { [string]: number },
	held: { [string]: boolean },
	fired: { string },
}

type Entry = { actionId: string, kind: string, key: string, mod: string? }

local Resolver = {}
Resolver.__index = Resolver

function Resolver.new()
	local self = setmetatable({}, Resolver)
	self._entries = {} :: { Entry }
	self._modifierKeys = {} :: { [string]: boolean }
	self._modifierUsed = {} :: { [string]: boolean }
	self._repeatTimers = {} :: { [string]: number }
	return self
end

function Resolver:SetBindings(bindings: { [string]: any })
	local entries = {}
	local modifierKeys = {}
	for _, action in Actions.List do
		local binding = bindings[action.id]
		if binding then
			table.insert(entries, { actionId = action.id, kind = action.kind, key = binding.key, mod = binding.mod })
			if binding.mod then
				modifierKeys[binding.mod] = true
			end
		end
	end
	self._entries = entries
	self._modifierKeys = modifierKeys
	self:Reset()
end

function Resolver:Reset()
	table.clear(self._modifierUsed)
	table.clear(self._repeatTimers)
end

-- True when a combo on this key is currently live (its modifier is held).
function Resolver:_comboOwnsKey(key: string, down: { [string]: boolean }): boolean
	for _, entry in self._entries do
		if entry.key == key and entry.mod and down[entry.mod] then
			return true
		end
	end
	return false
end

-- `onlyActions`, when given, limits which actions can fire (used while
-- controller mode is off so only "alwaysOn" actions respond).
function Resolver:Resolve(frame: any, dt: number, onlyActions: { [string]: boolean }?): Output
	local output: Output = { sticks = {}, analog = {}, held = {}, fired = {} }
	local down, pressed, released = frame.down, frame.pressed, frame.released
	local modifierUsed = self._modifierUsed

	-- Record combo usage first so a modifier tap can't fire on the same frame
	-- its combo fires.
	for _, entry in self._entries do
		if entry.mod and down[entry.mod] and down[entry.key] then
			modifierUsed[entry.mod] = true
		end
	end

	for _, entry in self._entries do
		local actionId = entry.actionId
		if onlyActions and not onlyActions[actionId] then
			continue
		end
		local key, mod, kind = entry.key, entry.mod, entry.kind

		if kind == "stick" then
			if not mod or down[mod] then
				output.sticks[actionId] = frame.sticks[key] or Vector2.zero
			end
			continue
		end

		local modOk = mod == nil or down[mod] == true
		local suppressed = mod == nil and self:_comboOwnsKey(key, down)
		local isModifierKey = mod == nil and self._modifierKeys[key] == true

		if kind == "analog" or kind == "hold" then
			if not modOk or suppressed or (isModifierKey and modifierUsed[key]) then
				continue
			end
			local value = frame.values[key] or 0
			local info = Inputs.ByKey[key]
			local active = down[key] or (info.kind == "trigger" and value > ANALOG_TRIGGER_FLOOR)
			if active then
				if kind == "analog" then
					local current = output.analog[actionId] or 0
					output.analog[actionId] = math.max(current, if info.kind == "trigger" then value else 1)
				else
					output.held[actionId] = true
				end
			end
		elseif isModifierKey then
			-- Tap semantics: fire on release if this hold never became a combo.
			if released[key] and not modifierUsed[key] then
				table.insert(output.fired, actionId)
			end
		elseif kind == "press" then
			-- Combos fire whichever of the two buttons lands last, so chords
			-- like clicking both sticks don't depend on exact timing.
			local justPressed = pressed[key] or (mod ~= nil and pressed[mod] and down[key])
			if justPressed and modOk and not suppressed then
				table.insert(output.fired, actionId)
			end
		elseif kind == "repeat" then
			if down[key] and modOk and not suppressed then
				local timer = self._repeatTimers[actionId]
				if pressed[key] or timer == nil then
					self._repeatTimers[actionId] = REPEAT_DELAY
					table.insert(output.fired, actionId)
				else
					timer -= dt
					while timer <= 0 do
						timer += REPEAT_INTERVAL
						table.insert(output.fired, actionId)
					end
					self._repeatTimers[actionId] = timer
				end
			else
				self._repeatTimers[actionId] = nil
			end
		end
	end

	for key in released do
		modifierUsed[key] = nil
	end

	return output
end

return Resolver
