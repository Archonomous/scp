--[[
	Studio Controller Pro
	Fly the edit-mode camera with a gamepad: custom bindings, combos, profiles,
	FOV, roll and screenshots.

	This script wires the pieces together and runs the per-frame loop:
	  Gamepad (sample) → Resolver (bindings → actions) → CameraController / actions
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Plugins also load inside Play-test data models; the game owns the
-- controller there, so only run in the edit data model.
if not plugin or not RunService:IsEdit() then
	return
end

local Actions = require(script.Core.Actions)
local CameraController = require(script.Core.CameraController)
local Captures = require(script.Core.Captures)
local Gamepad = require(script.Core.Gamepad)
local Resolver = require(script.Core.Resolver)
local Store = require(script.Core.Store)
local App = require(script.UI.App)
local Hud = require(script.UI.Hud)
local Theme = require(script.UI.Theme)
local Maid = require(script.Util.Maid)
local Signal = require(script.Util.Signal)

local maid = Maid.new()

-- Runtime ----------------------------------------------------------------------

local runtime = {}
runtime.store = Store.new(plugin)
runtime.gamepad = Gamepad.new()
runtime.captures = Captures.new()
runtime.camera = CameraController.new()
runtime.resolver = Resolver.new()
runtime.hud = Hud.new(runtime.gamepad)
runtime.StateChanged = Signal.new()
runtime._on = false
runtime._capture = nil

maid:Give(runtime.gamepad)
maid:Give(runtime.captures)
maid:Give(runtime.camera)
maid:Give(runtime.hud)
maid:Give(runtime.StateChanged)

local store = runtime.store
local gamepad = runtime.gamepad
local camera = runtime.camera
local resolver = runtime.resolver
local hud = runtime.hud

gamepad:SetPreference(store:GetRuntime("gamepad") or "Auto")
camera.speedIndex = math.clamp(store:GetRuntime("speedIndex") or 5, 1, #CameraController.SpeedSteps)

local ALWAYS_ON = {}
for _, action in Actions.List do
	if action.alwaysOn then
		ALWAYS_ON[action.id] = true
	end
end

local function activeProfile()
	return store:GetActiveProfile()
end

local function refreshHudStatus()
	local cam = workspace.CurrentCamera
	local roll = 0
	if cam then
		local _, _, rz = cam.CFrame:ToEulerAnglesYXZ()
		roll = math.deg(rz)
	end
	hud:SetStatus({
		profile = activeProfile().name,
		speed = camera:GetSpeedMultiplier(),
		fov = if cam then cam.FieldOfView else 70,
		roll = roll,
	})
end

local function refreshGuide()
	local profile = activeProfile()
	hud:RenderGuide(profile.name, profile.bindings)
end

function runtime:IsOn(): boolean
	return self._on
end

local toolbarButton: PluginToolbarButton? = nil

function runtime:SetOn(on: boolean)
	if self._on == on then
		return
	end
	self._on = on
	resolver:Reset()
	if on then
		camera:Begin()
		refreshHudStatus()
		hud:SetControllerOn(true)
		if gamepad:IsConnected() then
			hud:Toast("Controller mode on")
		else
			hud:Toast("Controller mode on · no controller connected")
		end
	else
		camera:End(store:GetSetting("levelOnExit"))
		hud:SetControllerOn(false)
	end
	if toolbarButton then
		toolbarButton:SetActive(on)
	end
	self.StateChanged:Fire(on)
end

function runtime:Toggle()
	self:SetOn(not self._on)
end

-- Binding capture: the panel asks for the next input; the frame loop feeds
-- frames here instead of running actions until it resolves.
function runtime:BeginCapture(kind: string, callback: (any) -> ())
	self._capture = {
		kind = kind,
		callback = callback,
		first = nil,
		started = os.clock(),
		armed = false,
	}
end

function runtime:CancelCapture()
	self._capture = nil
end

local CAPTURE_TIMEOUT = 10

local function finishCapture(binding: any)
	local capture = runtime._capture
	runtime._capture = nil
	if capture then
		task.spawn(capture.callback, binding)
	end
end

local function stepCapture(frame: Gamepad.Frame)
	local capture = runtime._capture
	if os.clock() - capture.started > CAPTURE_TIMEOUT then
		finishCapture(nil)
		return
	end
	-- Ignore anything already held when capture began (e.g. a button still
	-- down from an earlier action) until everything is released once.
	if not capture.armed then
		local anyDown = next(frame.down) ~= nil
		if not anyDown then
			capture.armed = true
		end
		return
	end
	if capture.kind == "stick" then
		for _, key in { "Thumbstick1", "Thumbstick2" } do
			if frame.sticks[key].Magnitude > 0.7 then
				finishCapture({ key = key })
				return
			end
		end
		return
	end
	for key in frame.pressed do
		if key == "Thumbstick1" or key == "Thumbstick2" then
			continue
		end
		if capture.first == nil then
			capture.first = key
		elseif key ~= capture.first and frame.down[capture.first] then
			finishCapture({ key = key, mod = capture.first })
			return
		end
	end
	if capture.first and frame.released[capture.first] then
		finishCapture({ key = capture.first })
	end
end

function runtime:TakeScreenshot()
	runtime.captures:Take(function(visible)
		hud:SetCaptureHidden(not visible)
	end, function(capture, err)
		if capture then
			hud:Flash()
			hud:Toast("Screenshot saved to Captures")
		else
			hud:Toast("Screenshot failed")
			warn("[Studio Controller Pro] Screenshot failed:", err)
		end
	end)
end

-- Actions ----------------------------------------------------------------------

local function glyphFor(actionId: string): string?
	local binding = activeProfile().bindings[actionId]
	return if binding then binding.key else nil
end

local function switchProfile(direction: number)
	local profile = store:CycleProfile(direction)
	hud:Toast("Profile: " .. profile.name)
end

local pressHandlers: { [string]: () -> () } = {
	toggleController = function()
		runtime:Toggle()
	end,
	speedUp = function()
		camera:StepSpeed(1)
	end,
	speedDown = function()
		camera:StepSpeed(-1)
	end,
	resetSpeed = function()
		camera:SetSpeedIndex(CameraController.DefaultSpeedIndex)
	end,
	resetRoll = function()
		camera:ResetRoll()
	end,
	levelView = function()
		camera:LevelView()
		hud:Toast("Level view")
	end,
	resetFov = function()
		camera:ResetFov(activeProfile().tuning.defaultFov)
	end,
	resetCamera = function()
		local defaultFov = activeProfile().tuning.defaultFov
		camera:ResetAll(defaultFov)
		hud:SetStatus({ fov = defaultFov, roll = 0 })
		hud:Toast("Camera reset", glyphFor("resetCamera"))
	end,
	focusSelection = function()
		if not camera:FrameSelection() then
			hud:Toast("Nothing selected to frame")
		end
	end,
	returnToStart = function()
		if camera:ReturnToStart() then
			hud:Toast("Returning to start")
		end
	end,
	screenshot = function()
		runtime:TakeScreenshot()
	end,
	toggleHud = function()
		local visible = not store:GetSetting("hudEnabled")
		store:SetSetting("hudEnabled", visible)
		if visible then
			hud:Toast("HUD shown")
		end
	end,
	toggleGuide = function()
		local open = not hud:IsGuideOpen()
		if open then
			refreshGuide()
		end
		hud:SetGuideOpen(open)
	end,
	nextProfile = function()
		switchProfile(1)
	end,
	prevProfile = function()
		switchProfile(-1)
	end,
}

-- Frame loop -------------------------------------------------------------------

local app: any = nil
local windowFocused = true

maid:Give(UserInputService.WindowFocused:Connect(function()
	windowFocused = true
end))
maid:Give(UserInputService.WindowFocusReleased:Connect(function()
	windowFocused = false
end))

local function axis(output: Resolver.Output, positive: string, negative: string): number
	return (output.analog[positive] or 0) - (output.analog[negative] or 0)
end

local function onFrame(dt: number)
	local suspended = not windowFocused or UserInputService:GetFocusedTextBox() ~= nil
	-- Skip all work when nothing could use the pad.
	local listening = runtime._on
		or runtime._capture ~= nil
		or store:GetSetting("listenWhileOff")
		or (app and app:IsShowingTester())
	if not listening or not gamepad:IsConnected() then
		if runtime._on then
			camera:Step(dt, {
				move = Vector2.zero,
				look = Vector2.zero,
				vertical = 0,
				roll = 0,
				fov = 0,
				boost = false,
				precision = false,
			}, activeProfile().tuning)
		end
		hud:Update()
		return
	end

	local frame = gamepad:Sample(suspended)
	if app and app:IsShowingTester() then
		app:UpdateTester(frame)
	end

	if runtime._capture then
		stepCapture(frame)
		hud:Update()
		return
	end

	local output = resolver:Resolve(frame, dt, if runtime._on then nil else ALWAYS_ON)
	for _, actionId in output.fired do
		local handler = pressHandlers[actionId]
		if handler and (runtime._on or ALWAYS_ON[actionId]) then
			hud:Poke()
			handler()
		end
	end

	if runtime._on then
		local tuning = activeProfile().tuning
		local moved = camera:Step(dt, {
			move = CameraController.ShapeStick(output.sticks.move or Vector2.zero, tuning.deadzone, tuning.curve),
			look = CameraController.ShapeStick(output.sticks.look or Vector2.zero, tuning.deadzone, tuning.curve),
			vertical = axis(output, "ascend", "descend"),
			roll = axis(output, "rollRight", "rollLeft"),
			fov = axis(output, "fovWider", "fovNarrower"),
			boost = output.held.boost == true,
			precision = output.held.precision == true,
		}, tuning)
		if moved then
			hud:Poke()
		end
	end
	hud:Update()
end

maid:Give(RunService.PreRender:Connect(onFrame))

-- Store reactions ----------------------------------------------------------------

resolver:SetBindings(activeProfile().bindings)
hud:SetVisible(store:GetSetting("hudEnabled"))

maid:Give(store.Changed:Connect(function(kind)
	if kind == "profile" or kind == "bindings" or kind == "profiles" then
		resolver:SetBindings(activeProfile().bindings)
		refreshHudStatus()
		if hud:IsGuideOpen() then
			refreshGuide()
		end
	elseif kind == "settings" then
		hud:SetVisible(store:GetSetting("hudEnabled"))
	end
end))

maid:Give(gamepad.Changed:Connect(function()
	if hud:IsGuideOpen() then
		refreshGuide()
	end
end))

maid:Give(camera.Feedback:Connect(function(kind, value)
	if kind == "speed" then
		store:SetRuntime("speedIndex", camera.speedIndex)
		hud:SetStatus({ speed = value })
	elseif kind == "fov" then
		hud:SetStatus({ fov = value })
	elseif kind == "roll" then
		hud:SetStatus({ roll = value })
	end
	hud:Poke()
end))

-- Toolbar, actions, widget ---------------------------------------------------------

local toolbar = plugin:CreateToolbar("Studio Controller Pro")
toolbarButton = toolbar:CreateButton(
	"StudioControllerPro_Toggle",
	"Turn controller mode on or off",
	Theme.GetToolbarIcon(),
	"Controller"
)
local settingsButton = toolbar:CreateButton(
	"StudioControllerPro_Panel",
	"Open the Studio Controller Pro panel",
	Theme.Icon(Theme.Icons.Settings),
	"Settings"
)
toolbarButton.ClickableWhenViewportHidden = true
settingsButton.ClickableWhenViewportHidden = true

maid:Give(toolbarButton.Click:Connect(function()
	runtime:Toggle()
end))

local toggleAction = plugin:CreatePluginAction(
	"StudioControllerPro_ToggleAction",
	"Toggle Controller Mode",
	"Turn Studio Controller Pro's controller mode on or off",
	Theme.GetToolbarIcon(),
	true
)
maid:Give(toggleAction.Triggered:Connect(function()
	runtime:Toggle()
end))
local panelAction = plugin:CreatePluginAction(
	"StudioControllerPro_PanelAction",
	"Open Controller Settings",
	"Show the Studio Controller Pro panel",
	Theme.GetToolbarIcon(),
	true
)

app = App.new(plugin, runtime)
maid:Give(app)

local function syncPanelButton()
	settingsButton:SetActive(app.Widget.Enabled)
end
maid:Give(settingsButton.Click:Connect(function()
	app.Widget.Enabled = not app.Widget.Enabled
end))
maid:Give(panelAction.Triggered:Connect(function()
	app.Widget.Enabled = true
end))
maid:Give(app.Widget:GetPropertyChangedSignal("Enabled"):Connect(syncPanelButton))
syncPanelButton()

pressHandlers.openPanel = function()
	app.Widget.Enabled = true
end

if store:GetSetting("enableOnStart") then
	runtime:SetOn(true)
end

-- Cleanup ------------------------------------------------------------------------

plugin.Unloading:Connect(function()
	if runtime._on then
		camera:End(store:GetSetting("levelOnExit"))
	end
	store:SaveNow()
	maid:Clean()
	Theme.Destroy()
end)
