--[[
	Studio Controller Pro
	Fly the edit-mode camera with a gamepad: custom bindings, combos, profiles,
	FOV, roll and screenshots.

	This script wires the pieces together and runs the per-frame loop:
	  Gamepad (sample) → Resolver (bindings → actions) → CameraController / actions
]]

local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local UserInputService = game:GetService("UserInputService")

-- Plugins also load inside Play-test data models; the game owns the
-- controller there, so only run in the edit data model.
if not plugin or not RunService:IsEdit() then
	return
end

local Aim = require(script.Core.Aim)
local Actions = require(script.Core.Actions)
local CameraController = require(script.Core.CameraController)
local Captures = require(script.Core.Captures)
local Gamepad = require(script.Core.Gamepad)
local Haptics = require(script.Core.Haptics)
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
-- Local builds (the dev .rbxm in the Plugins folder) are labelled "Test" so they
-- can be told apart from the Creator Store copy. Store plugins are named
-- "cloud_<id>"; local ones keep their file name.
runtime.title = if string.find(plugin.Name, "%.rbxmx?$") then "Studio Controller Pro Test" else "Studio Controller Pro"
runtime.store = Store.new(plugin)
runtime.gamepad = Gamepad.new()
runtime.captures = Captures.new(runtime.store)
runtime.camera = CameraController.new()
runtime.resolver = Resolver.new()
runtime.hud = Hud.new(runtime.gamepad)
runtime.haptics = Haptics.new(runtime.gamepad, runtime.store)
runtime.aim = Aim.new()
runtime.StateChanged = Signal.new()
-- Fired with a user-facing message for the panel (upload results, warnings).
runtime.Notice = Signal.new()
runtime._on = false
runtime._capture = nil

maid:Give(runtime.gamepad)
maid:Give(runtime.captures)
maid:Give(runtime.camera)
maid:Give(runtime.hud)
maid:Give(runtime.haptics)
maid:Give(runtime.aim)
maid:Give(runtime.StateChanged)
maid:Give(runtime.Notice)

local store = runtime.store
local gamepad = runtime.gamepad
local camera = runtime.camera
local resolver = runtime.resolver
local hud = runtime.hud
local haptics = runtime.haptics
local aim = runtime.aim

-- Studio's hover outline follows the mouse pointer, which sits still over the
-- viewport while flying, so whatever is under it stays highlighted. It's turned
-- off in controller mode and restored afterwards; the flag is saved so a crash
-- mid-flight gets restored on the next load.
local studioSettings = settings().Studio

local function setHoverHidden(hidden: boolean)
	if hidden then
		if store:GetRuntime("hoverToRestore") then
			return
		end
		local ok, shown = pcall(function()
			return studioSettings["Show Hover Over"]
		end)
		if ok and shown and pcall(function()
			studioSettings["Show Hover Over"] = false
		end) then
			store:SetRuntime("hoverToRestore", true)
		end
	elseif store:GetRuntime("hoverToRestore") then
		pcall(function()
			studioSettings["Show Hover Over"] = true
		end)
		store:SetRuntime("hoverToRestore", false)
	end
end
setHoverHidden(false)

-- Defined with the target gesture below.
local resetGesture: () -> ()

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
		level = activeProfile().tuning.levelMovement == true,
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
		setHoverHidden(store:GetSetting("hideHover"))
		refreshHudStatus()
		hud:SetConnected(gamepad:IsConnected())
		hud:SetControllerOn(true)
		if gamepad:IsConnected() then
			hud:Toast("Controller mode on")
			haptics:Play("on")
		else
			-- The HUD shows a standing notice; the panel explains what to do.
			self.Notice:Fire(
				"Controller mode is on, but no controller is connected. Plug in or pair one to start flying."
			)
		end
	else
		camera:End(store:GetSetting("levelOnExit"))
		hud:SetControllerOn(false)
		setHoverHidden(false)
		resetGesture()
		haptics:Play("off")
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
		if binding then
			haptics:Play("confirm")
		end
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
			haptics:Play("shutter")
			if store:GetSetting("autoStar") then
				hud:Toast("Screenshot taken · uploading…")
				runtime:UploadCapture(capture.id)
			else
				hud:Toast("Screenshot added to Captures")
			end
		else
			hud:Toast("Screenshot failed")
			haptics:Play("limit")
			warn("[Studio Controller Pro] Screenshot failed:", err)
		end
	end)
end

-- Uploads a capture (the panel confirms first). Never re-uploads.
function runtime:UploadCapture(id: number)
	runtime.captures:Upload(id, function(err)
		local capture = runtime.captures:Get(id)
		local message = if err
			then err
			else "Uploaded “"
				.. (if capture then capture.name else "capture")
				.. "” and added its plane to ServerStorage."
		if err then
			warn("[Studio Controller Pro]", err)
		end
		hud:Toast(if err then "Couldn't upload capture" else "Capture uploaded")
		if not err then
			haptics:Play("confirm")
		end
		runtime.Notice:Fire(message)
	end)
end

-- Glides back to a capture's exact view. Returns an error message if the
-- capture came from a different place.
function runtime:GoToCapture(id: number): string?
	local capture = runtime.captures:Get(id)
	if not capture then
		return "That capture no longer exists."
	end
	if not runtime.captures:IsFromThisPlace(capture) then
		return "That view is from “" .. capture.placeName .. "”, not this place."
	end
	camera:GoToView(capture.cframe, capture.fov)
	return nil
end

-- Actions ----------------------------------------------------------------------

local function glyphFor(actionId: string): string?
	local binding = activeProfile().bindings[actionId]
	return if binding then binding.key else nil
end

local function switchProfile(direction: number)
	local profile = store:CycleProfile(direction)
	hud:Toast("Profile: " .. profile.name)
	haptics:Play("switch")
end

-- Holding speed up at the top speed repeats; only buzz the limit now and then.
local lastLimitPulse = 0
local function stepSpeed(direction: number)
	if camera:StepSpeed(direction) then
		haptics:Play("tick")
	elseif os.clock() - lastLimitPulse > 0.5 then
		lastLimitPulse = os.clock()
		haptics:Play("limit")
	end
end

local pressHandlers: { [string]: () -> () } = {
	toggleController = function()
		runtime:Toggle()
	end,
	speedUp = function()
		stepSpeed(1)
	end,
	speedDown = function()
		stepSpeed(-1)
	end,
	resetSpeed = function()
		camera:SetSpeedIndex(CameraController.DefaultSpeedIndex)
		haptics:Play("tick")
	end,
	resetRoll = function()
		camera:ResetRoll()
		haptics:Play("glide")
	end,
	levelView = function()
		camera:LevelView()
		hud:Toast("Level view")
		haptics:Play("glide")
	end,
	resetFov = function()
		camera:ResetFov(activeProfile().tuning.defaultFov)
		haptics:Play("glide")
	end,
	resetCamera = function()
		local defaultFov = activeProfile().tuning.defaultFov
		camera:ResetAll(defaultFov)
		hud:SetStatus({ fov = defaultFov, roll = 0 })
		hud:Toast("Camera reset", glyphFor("resetCamera"))
		haptics:Play("glide")
	end,
	focusSelection = function()
		if camera:FrameSelection() then
			haptics:Play("glide")
		else
			hud:Toast("Nothing selected to frame")
			haptics:Play("limit")
		end
	end,
	returnToStart = function()
		if camera:ReturnToStart() then
			hud:Toast("Returning to start")
			haptics:Play("glide")
		end
	end,
	screenshot = function()
		runtime:TakeScreenshot()
	end,
	toggleLevelMovement = function()
		local profile = activeProfile()
		local level = not profile.tuning.levelMovement
		store:SetTuning(profile.id, "levelMovement", level)
		hud:Toast(if level then "Level movement on" else "Level movement off")
		haptics:Play(if level then "switch" else "tick")
	end,
	toggleHud = function()
		local visible = not store:GetSetting("hudEnabled")
		store:SetSetting("hudEnabled", visible)
		if visible then
			hud:Toast("HUD shown")
		end
		haptics:Play("tick")
	end,
	toggleGuide = function()
		local open = not hud:IsGuideOpen()
		if open then
			refreshGuide()
		end
		hud:SetGuideOpen(open)
		haptics:Play("tick")
	end,
	nextProfile = function()
		switchProfile(1)
	end,
	prevProfile = function()
		switchProfile(-1)
	end,
}

-- Select / fly to target -------------------------------------------------------
-- One button, three gestures on what the reticle is on: tap selects it,
-- double-tap flies toward it, hold selects and frames it. A tap waits out the
-- double-tap window before selecting.

local TARGET_HOLD_TIME = 0.45
local TARGET_DOUBLE_TAP_GAP = 0.3
-- Hold feedback starts after this, so ordinary taps don't flash the outline.
local TARGET_HOLD_FEEDBACK = 0.12
-- Fly-to arrives this many studs above the line to the point, so landing on
-- the ground doesn't leave the camera at floor level.
local FLY_TO_HEIGHT = 5

local gesture = {
	down = false,
	downAt = 0,
	consumed = false,
	target = nil :: Aim.Target?,
	pendingTap = false,
	tapAt = 0,
}

function resetGesture()
	gesture.down = false
	gesture.consumed = false
	gesture.pendingTap = false
	gesture.target = nil
	aim:SetOutlined(false)
	hud:SetReticle(false, 0)
end

local function selectTarget(target: Aim.Target?, frame: boolean)
	local instance = target and target.instance
	if not instance and frame then
		-- Holding on empty space (or terrain / locked parts) clears the selection.
		if #Selection:Get() > 0 then
			Selection:Set({})
			hud:Toast("Selection cleared", glyphFor("target"))
			haptics:Play("tick")
		else
			hud:Toast("Nothing selected", glyphFor("target"))
			haptics:Play("limit")
		end
		return
	elseif not instance then
		hud:Toast(if target then "Can't select that" else "Nothing under the reticle", glyphFor("target"))
		haptics:Play("limit")
		return
	end
	Selection:Set({ instance })
	if frame then
		camera:FrameSelection()
		hud:Toast("Framing " .. instance.Name .. " · right stick orbits, triggers zoom", glyphFor("target"))
		haptics:Play("glide")
	else
		hud:Toast("Selected " .. instance.Name, glyphFor("target"))
		haptics:Play("tick")
	end
end

local function flyToTarget(target: Aim.Target?)
	if not target then
		hud:Toast("Nothing under the reticle", glyphFor("target"))
		haptics:Play("limit")
		return
	end
	local standoff = math.clamp(Aim.Radius(target.instance) or 8, 4, 30)
	if camera:FlyTo(target.position, standoff, FLY_TO_HEIGHT) then
		haptics:Play("glide")
	else
		haptics:Play("limit")
	end
end

local function stepTarget(held: boolean)
	local now = os.clock()
	if held and not gesture.down then
		gesture.down = true
		gesture.downAt = now
		gesture.consumed = false
		gesture.target = aim.target
		if gesture.pendingTap and now - gesture.tapAt <= TARGET_DOUBLE_TAP_GAP then
			gesture.pendingTap = false
			gesture.consumed = true
			hud:Poke()
			flyToTarget(aim.target)
		end
	elseif held and not gesture.consumed and now - gesture.downAt >= TARGET_HOLD_TIME then
		gesture.consumed = true
		hud:Poke()
		selectTarget(aim.target, true)
	elseif not held and gesture.down then
		gesture.down = false
		if not gesture.consumed then
			gesture.pendingTap = true
			gesture.tapAt = now
		end
	end
	if gesture.pendingTap and not gesture.down and now - gesture.tapAt > TARGET_DOUBLE_TAP_GAP then
		gesture.pendingTap = false
		hud:Poke()
		selectTarget(gesture.target, false)
	end

	local hold = 0
	if gesture.down and not gesture.consumed then
		hold = math.max(now - gesture.downAt - TARGET_HOLD_FEEDBACK, 0) / (TARGET_HOLD_TIME - TARGET_HOLD_FEEDBACK)
	end
	aim:SetOutlined(hold > 0)
	local current = aim.target
	hud:SetReticle(current ~= nil and current.instance ~= nil, hold)
end

-- Frame loop -------------------------------------------------------------------

local app: any = nil
local windowFocused = true

maid:Give(UserInputService.WindowFocused:Connect(function()
	windowFocused = true
end))
maid:Give(UserInputService.WindowFocusReleased:Connect(function()
	windowFocused = false
	haptics:Stop()
end))

local function axis(output: Resolver.Output, positive: string, negative: string): number
	return (output.analog[positive] or 0) - (output.analog[negative] or 0)
end

local IDLE_INPUT: CameraController.StepInput = {
	move = Vector2.zero,
	look = Vector2.zero,
	vertical = 0,
	roll = 0,
	fov = 0,
	boost = false,
	precision = false,
}

local function onFrame(dt: number)
	local suspended = not windowFocused or UserInputService:GetFocusedTextBox() ~= nil
	-- Transitions started from the panel (e.g. "Go to view") play even while
	-- controller mode is off.
	if not runtime._on and camera.transition then
		camera:Step(dt, IDLE_INPUT, activeProfile().tuning)
	end
	-- Skip all work when nothing could use the pad.
	local listening = runtime._on
		or runtime._capture ~= nil
		or store:GetSetting("listenWhileOff")
		or (app and app:IsShowingTester())
	if not listening or not gamepad:IsConnected() then
		if runtime._on then
			camera:Step(dt, IDLE_INPUT, activeProfile().tuning)
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
		aim:Update()
		stepTarget(output.held.target == true)

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
hud:SetReticleEnabled(store:GetSetting("showReticle"))

maid:Give(store.Changed:Connect(function(kind)
	if kind == "profile" or kind == "bindings" or kind == "profiles" then
		resolver:SetBindings(activeProfile().bindings)
		refreshHudStatus()
		if hud:IsGuideOpen() then
			refreshGuide()
		end
	elseif kind == "tuning" then
		refreshHudStatus()
	elseif kind == "settings" then
		hud:SetVisible(store:GetSetting("hudEnabled"))
		hud:SetReticleEnabled(store:GetSetting("showReticle"))
		if runtime._on then
			setHoverHidden(store:GetSetting("hideHover"))
		end
	end
end))

local wasConnected = gamepad:IsConnected()
maid:Give(gamepad.Changed:Connect(function()
	if hud:IsGuideOpen() then
		refreshGuide()
	end
	local connected = gamepad:IsConnected()
	if connected == wasConnected then
		return
	end
	wasConnected = connected
	haptics:Stop()
	hud:SetConnected(connected)
	if runtime._on then
		if connected then
			hud:Toast(gamepad:DisplayName() .. " connected")
			haptics:Play("on")
		else
			resolver:Reset()
			runtime.Notice:Fire("Controller disconnected. Reconnect it to keep flying.")
		end
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

local toolbar = plugin:CreateToolbar(runtime.title)
toolbarButton = toolbar:CreateButton(
	"StudioControllerPro_Toggle",
	"Turn controller mode on or off",
	Theme.GamepadIcon,
	"Controller"
)
local settingsButton = toolbar:CreateButton(
	"StudioControllerPro_Panel",
	"Open the " .. runtime.title .. " panel",
	Theme.Icon(Theme.Icons.Settings),
	"Settings"
)
toolbarButton.ClickableWhenViewportHidden = true

-- The custom icon is an uploaded asset; swap it in once it loads so the
-- button never shows blank (e.g. while a new upload is in moderation).
task.spawn(function()
	local icon = Theme.ResolveIcon(Theme.ToolbarIcon)
	if icon then
		toolbarButton.Icon = icon
	end
end)
settingsButton.ClickableWhenViewportHidden = true

maid:Give(toolbarButton.Click:Connect(function()
	runtime:Toggle()
end))

local toggleAction = plugin:CreatePluginAction(
	"StudioControllerPro_ToggleAction",
	"Toggle Controller Mode",
	"Turn Studio Controller Pro's controller mode on or off",
	Theme.GamepadIcon,
	true
)
maid:Give(toggleAction.Triggered:Connect(function()
	runtime:Toggle()
end))
local panelAction = plugin:CreatePluginAction(
	"StudioControllerPro_PanelAction",
	"Open Controller Settings",
	"Show the Studio Controller Pro panel",
	Theme.GamepadIcon,
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

-- First run: open the panel on its welcome card.
if not store:GetRuntime("welcomed") then
	app.Widget.Enabled = true
end

if store:GetSetting("enableOnStart") then
	runtime:SetOn(true)
end

-- Cleanup ------------------------------------------------------------------------

plugin.Unloading:Connect(function()
	haptics:Stop()
	if runtime._on then
		camera:End(store:GetSetting("levelOnExit"))
	end
	setHoverHidden(false)
	store:SaveNow()
	maid:Clean()
	Theme.Destroy()
end)
