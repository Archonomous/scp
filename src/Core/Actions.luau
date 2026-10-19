--[[
	Everything a controller input can be bound to.

	kind:
	  "stick"   reads a thumbstick as a Vector2 (only sticks can be bound)
	  "analog"  0..1 while held (triggers give partial values, buttons give 1)
	  "hold"    true while held
	  "press"   fires once per press
	  "repeat"  fires on press, then repeats while held

	`default` is the binding used by the Default profile. `mod` is an optional
	button that must be held first (a combo). `alwaysOn` actions keep working
	while controller mode is off, so the plugin can be toggled from the pad.
]]

export type ActionKind = "stick" | "analog" | "hold" | "press" | "repeat"

export type Binding = { key: string, mod: string? }

export type Action = {
	id: string,
	name: string,
	description: string,
	category: string,
	kind: ActionKind,
	default: Binding?,
	alwaysOn: boolean?,
}

local Actions = {}

Actions.Categories = { "Movement", "Look", "Camera", "Plugin" }

Actions.List = {
	-- Movement
	{
		id = "move",
		name = "Move",
		description = "Fly forward, back and sideways",
		category = "Movement",
		kind = "stick",
		default = { key = "Thumbstick1" },
	},
	{
		id = "ascend",
		name = "Ascend",
		description = "Rise; pressure-sensitive on triggers",
		category = "Movement",
		kind = "analog",
		default = { key = "ButtonR2" },
	},
	{
		id = "descend",
		name = "Descend",
		description = "Sink; pressure-sensitive on triggers",
		category = "Movement",
		kind = "analog",
		default = { key = "ButtonL2" },
	},
	{
		id = "boost",
		name = "Boost",
		description = "Hold to move faster",
		category = "Movement",
		kind = "hold",
		default = { key = "ButtonL3" },
	},
	{
		id = "precision",
		name = "Precision",
		description = "Hold to slow movement and look for fine framing",
		category = "Movement",
		kind = "hold",
		default = { key = "ButtonB" },
	},
	{
		id = "toggleLevelMovement",
		name = "Toggle level movement",
		description = "Keep moving parallel to the ground, like shift lock",
		category = "Movement",
		kind = "press",
		default = { key = "ButtonY", mod = "ButtonSelect" },
	},

	-- Look
	{
		id = "look",
		name = "Look",
		description = "Yaw and pitch the camera",
		category = "Look",
		kind = "stick",
		default = { key = "Thumbstick2" },
	},
	{
		id = "rollLeft",
		name = "Roll left",
		description = "Bank counter-clockwise",
		category = "Look",
		kind = "analog",
		default = { key = "ButtonL1" },
	},
	{
		id = "rollRight",
		name = "Roll right",
		description = "Bank clockwise",
		category = "Look",
		kind = "analog",
		default = { key = "ButtonR1" },
	},
	{
		id = "resetRoll",
		name = "Reset roll",
		description = "Smoothly level the horizon",
		category = "Look",
		kind = "press",
		default = { key = "ButtonR3" },
	},
	{
		id = "levelView",
		name = "Level view",
		description = "Reset pitch and roll, keep heading",
		category = "Look",
		kind = "press",
	},

	-- Camera
	{
		id = "speedUp",
		name = "Speed up",
		description = "Step camera speed up",
		category = "Camera",
		kind = "repeat",
		default = { key = "DPadUp" },
	},
	{
		id = "speedDown",
		name = "Speed down",
		description = "Step camera speed down",
		category = "Camera",
		kind = "repeat",
		default = { key = "DPadDown" },
	},
	{
		id = "resetSpeed",
		name = "Reset speed",
		description = "Return to 1× speed",
		category = "Camera",
		kind = "press",
	},
	{
		id = "fovWider",
		name = "Widen FOV",
		description = "Zoom out by widening the field of view",
		category = "Camera",
		kind = "analog",
		default = { key = "DPadLeft" },
	},
	{
		id = "fovNarrower",
		name = "Narrow FOV",
		description = "Zoom in by narrowing the field of view",
		category = "Camera",
		kind = "analog",
		default = { key = "DPadRight" },
	},
	{
		id = "resetFov",
		name = "Reset FOV",
		description = "Return to the default field of view",
		category = "Camera",
		kind = "press",
	},
	{
		id = "resetCamera",
		name = "Reset camera",
		description = "Reset roll, FOV and speed together",
		category = "Camera",
		kind = "press",
		default = { key = "ButtonY" },
	},
	{
		id = "focusSelection",
		name = "Frame selection",
		description = "Glide to frame the selected objects",
		category = "Camera",
		kind = "press",
		default = { key = "ButtonA" },
	},
	{
		id = "returnToStart",
		name = "Return to start",
		description = "Glide back to where controller mode was turned on",
		category = "Camera",
		kind = "press",
	},
	{
		id = "screenshot",
		name = "Take screenshot",
		description = "Capture the viewport to the Captures tab",
		category = "Camera",
		kind = "press",
		default = { key = "ButtonX" },
	},

	-- Plugin
	{
		id = "toggleController",
		name = "Toggle controller mode",
		description = "Click both sticks. Works even while off",
		category = "Plugin",
		kind = "press",
		default = { key = "ButtonR3", mod = "ButtonL3" },
		alwaysOn = true,
	},
	{
		id = "toggleHud",
		name = "Toggle HUD",
		description = "Show or hide the on-screen status",
		category = "Plugin",
		kind = "press",
		default = { key = "ButtonSelect" },
	},
	{
		id = "toggleGuide",
		name = "Toggle button guide",
		description = "Show the current layout on screen",
		category = "Plugin",
		kind = "press",
		default = { key = "ButtonStart" },
	},
	{
		id = "nextProfile",
		name = "Next profile",
		description = "Switch to the next saved profile",
		category = "Plugin",
		kind = "press",
		default = { key = "DPadRight", mod = "ButtonSelect" },
	},
	{
		id = "prevProfile",
		name = "Previous profile",
		description = "Switch to the previous saved profile",
		category = "Plugin",
		kind = "press",
		default = { key = "DPadLeft", mod = "ButtonSelect" },
	},
} :: { Action }

Actions.ById = {} :: { [string]: Action }
for _, action in Actions.List do
	Actions.ById[action.id] = action
end

function Actions.DefaultBindings(): { [string]: Binding | false }
	local bindings = {}
	for _, action in Actions.List do
		bindings[action.id] = if action.default then table.clone(action.default) else false
	end
	return bindings
end

return Actions
