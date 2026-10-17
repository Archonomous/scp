--[[
	Catalog of every gamepad input the plugin understands.

	kind:
	  "button"  digital, value is 0 or 1
	  "trigger" analog 0..1 (Position.Z), also usable as a button past a threshold
	  "stick"   Vector2 (Position.X / Position.Y)
]]

export type InputKind = "button" | "trigger" | "stick"

export type InputInfo = {
	key: string,
	keyCode: Enum.KeyCode,
	kind: InputKind,
	names: { [string]: string },
}

local Inputs = {}

local function define(key: string, kind: InputKind, xbox: string, playStation: string, generic: string?): InputInfo
	return {
		key = key,
		keyCode = (Enum.KeyCode :: any)[key],
		kind = kind,
		names = { Xbox = xbox, PlayStation = playStation, Generic = generic or xbox },
	}
end

-- Display order matters: it's the order used by the tester and the button guide.
Inputs.List = {
	define("ButtonA", "button", "A", "Cross", "South"),
	define("ButtonB", "button", "B", "Circle", "East"),
	define("ButtonX", "button", "X", "Square", "West"),
	define("ButtonY", "button", "Y", "Triangle", "North"),
	define("ButtonL1", "button", "LB", "L1"),
	define("ButtonR1", "button", "RB", "R1"),
	define("ButtonL2", "trigger", "LT", "L2"),
	define("ButtonR2", "trigger", "RT", "R2"),
	define("ButtonL3", "button", "LS Click", "L3"),
	define("ButtonR3", "button", "RS Click", "R3"),
	define("DPadUp", "button", "D-Pad Up", "D-Pad Up"),
	define("DPadDown", "button", "D-Pad Down", "D-Pad Down"),
	define("DPadLeft", "button", "D-Pad Left", "D-Pad Left"),
	define("DPadRight", "button", "D-Pad Right", "D-Pad Right"),
	define("ButtonSelect", "button", "View", "Create", "Select"),
	define("ButtonStart", "button", "Menu", "Options", "Start"),
	define("Thumbstick1", "stick", "Left Stick", "Left Stick"),
	define("Thumbstick2", "stick", "Right Stick", "Right Stick"),
}

Inputs.ByKey = {} :: { [string]: InputInfo }
Inputs.ByKeyCode = {} :: { [Enum.KeyCode]: InputInfo }

for _, info in Inputs.List do
	Inputs.ByKey[info.key] = info
	Inputs.ByKeyCode[info.keyCode] = info
end

function Inputs.IsValid(key: any): boolean
	return type(key) == "string" and Inputs.ByKey[key] ~= nil
end

function Inputs.DisplayName(key: string, family: string?): string
	local info = Inputs.ByKey[key]
	if not info then
		return key
	end
	return info.names[family or "Xbox"] or info.names.Xbox
end

return Inputs
