--[[
	Per-profile tuning values and the global (non-profile) settings, with the
	ranges the UI and importer clamp to.
]]

export type Spec = {
	key: string,
	label: string,
	description: string?,
	section: string,
	kind: "number" | "bool",
	default: any,
	min: number?,
	max: number?,
	step: number?,
	suffix: string?,
	decimals: number?,
}

local Tuning = {}

Tuning.Sections = { "Movement", "Look", "Field of view", "Sticks" }

Tuning.Profile = {
	{
		key = "moveSpeed",
		label = "Move speed",
		description = "Studs per second at 1× speed",
		section = "Movement",
		kind = "number",
		default = 32,
		min = 4,
		max = 200,
		step = 1,
		suffix = " st/s",
	},
	{
		key = "boostMultiplier",
		label = "Boost multiplier",
		section = "Movement",
		kind = "number",
		default = 3,
		min = 1.5,
		max = 10,
		step = 0.5,
		suffix = "×",
		decimals = 1,
	},
	{
		key = "precisionMultiplier",
		label = "Precision multiplier",
		section = "Movement",
		kind = "number",
		default = 0.25,
		min = 0.05,
		max = 0.9,
		step = 0.05,
		suffix = "×",
		decimals = 2,
	},
	{
		key = "moveSmoothing",
		label = "Movement smoothing",
		description = "Higher values ease in and out of motion",
		section = "Movement",
		kind = "number",
		default = 0.5,
		min = 0,
		max = 0.95,
		step = 0.05,
		decimals = 2,
	},
	{
		key = "worldVertical",
		label = "Ascend along world up",
		description = "Off: ascend relative to where the camera faces",
		section = "Movement",
		kind = "bool",
		default = true,
	},
	{
		key = "levelMovement",
		label = "Level movement",
		description = "Like shift lock: moving stays parallel to the ground, so looking down doesn't dive",
		section = "Movement",
		kind = "bool",
		default = false,
	},
	{
		key = "lookSpeed",
		label = "Look sensitivity",
		description = "Degrees per second at full stick",
		section = "Look",
		kind = "number",
		default = 140,
		min = 20,
		max = 400,
		step = 5,
		suffix = "°/s",
	},
	{
		key = "lookSmoothing",
		label = "Look smoothing",
		section = "Look",
		kind = "number",
		default = 0.35,
		min = 0,
		max = 0.95,
		step = 0.05,
		decimals = 2,
	},
	{
		key = "rollSpeed",
		label = "Roll speed",
		section = "Look",
		kind = "number",
		default = 60,
		min = 5,
		max = 180,
		step = 5,
		suffix = "°/s",
	},
	{
		key = "invertY",
		label = "Invert look Y",
		section = "Look",
		kind = "bool",
		default = false,
	},
	{
		key = "invertX",
		label = "Invert look X",
		section = "Look",
		kind = "bool",
		default = false,
	},
	{
		key = "fovSpeed",
		label = "FOV change speed",
		section = "Field of view",
		kind = "number",
		default = 30,
		min = 5,
		max = 120,
		step = 5,
		suffix = "°/s",
	},
	{
		key = "defaultFov",
		label = "Default FOV",
		description = "Used by Reset FOV and Reset camera",
		section = "Field of view",
		kind = "number",
		default = 70,
		min = 10,
		max = 120,
		step = 1,
		suffix = "°",
	},
	{
		key = "deadzone",
		label = "Stick deadzone",
		description = "Ignore stick drift below this amount",
		section = "Sticks",
		kind = "number",
		default = 0.12,
		min = 0,
		max = 0.45,
		step = 0.01,
		decimals = 2,
	},
	{
		key = "curve",
		label = "Response curve",
		description = "1 is linear; higher gives finer control near center",
		section = "Sticks",
		kind = "number",
		default = 1.6,
		min = 1,
		max = 3,
		step = 0.1,
		decimals = 1,
	},
} :: { Spec }

Tuning.Global = {
	{
		key = "hudEnabled",
		label = "Show HUD",
		description = "Status and notifications over the viewport",
		section = "General",
		kind = "bool",
		default = true,
	},
	{
		key = "listenWhileOff",
		label = "Toggle from controller while off",
		description = "Listen for the Toggle controller mode binding at all times",
		section = "General",
		kind = "bool",
		default = true,
	},
	{
		key = "levelOnExit",
		label = "Level horizon when turning off",
		description = "Studio's own camera doesn't expect a rolled view",
		section = "General",
		kind = "bool",
		default = true,
	},
	{
		key = "autoStar",
		label = "Upload every screenshot",
		description = "Skips the confirmation. Each screenshot is uploaded to your account and gets a plane in ServerStorage",
		section = "General",
		kind = "bool",
		default = false,
	},
	{
		key = "vibration",
		label = "Vibration",
		description = "Rumble for toggles, screenshots, speed steps and profile switches",
		section = "General",
		kind = "bool",
		default = true,
	},
	{
		key = "vibrationStrength",
		label = "Vibration strength",
		section = "General",
		kind = "number",
		default = 70,
		min = 10,
		max = 100,
		step = 10,
		suffix = "%",
	},
	{
		key = "enableOnStart",
		label = "Turn on when Studio opens",
		section = "General",
		kind = "bool",
		default = false,
	},
} :: { Spec }

Tuning.ByKey = {} :: { [string]: Spec }
for _, spec in Tuning.Profile do
	Tuning.ByKey[spec.key] = spec
end
Tuning.GlobalByKey = {} :: { [string]: Spec }
for _, spec in Tuning.Global do
	Tuning.GlobalByKey[spec.key] = spec
end

function Tuning.Sanitize(spec: Spec, value: any): any
	if spec.kind == "bool" then
		if type(value) == "boolean" then
			return value
		end
		return spec.default
	end
	if type(value) ~= "number" or value ~= value then
		return spec.default
	end
	return math.clamp(value, spec.min :: number, spec.max :: number)
end

function Tuning.Defaults(overrides: { [string]: any }?): { [string]: any }
	local values = {}
	for _, spec in Tuning.Profile do
		values[spec.key] = spec.default
	end
	if overrides then
		for key, value in overrides do
			values[key] = value
		end
	end
	return values
end

function Tuning.GlobalDefaults(): { [string]: any }
	local values = {}
	for _, spec in Tuning.Global do
		values[spec.key] = spec.default
	end
	return values
end

function Tuning.Format(spec: Spec, value: number): string
	local decimals = spec.decimals or 0
	local text = if decimals > 0 then string.format("%." .. decimals .. "f", value) else tostring(math.round(value))
	return text .. (spec.suffix or "")
end

return Tuning
