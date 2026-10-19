--[[
	Viewport overlay: status pill, toasts, screenshot flash and the button
	guide. Lives in CoreGui so it draws over the edit viewport without touching
	the place. Uses fixed dark colors (like Studio's own viewport overlays)
	since it sits on top of arbitrary scene content.
]]

local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")

local Actions = require(script.Parent.Parent.Core.Actions)
local Components = require(script.Parent.Components)
local Glyphs = require(script.Parent.Glyphs)
local Theme = require(script.Parent.Theme)

local new = Components.new

local SURFACE = Color3.fromRGB(32, 32, 34)
local SURFACE_TRANSPARENCY = 0.12
local TEXT = Color3.fromRGB(240, 240, 242)
local DIM_TEXT = Color3.fromRGB(165, 165, 172)
local IDLE_DELAY = 2.5
local IDLE_TRANSPARENCY = 0.55
local TOAST_TIME = 1.8
local GUIDE_WIDTH = 470
local GUIDE_GLYPH_WIDTH = 66
local RETICLE_RING = 18
local RETICLE_HOLD_RING = 10

local FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLOW = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local Hud = {}
Hud.__index = Hud

local function hudText(props: { [string]: any }): TextLabel
	local textProps = {
		BackgroundTransparency = 1,
		FontFace = Theme.Font.Medium,
		TextSize = 14,
		TextColor3 = TEXT,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in props do
		textProps[key] = value
	end
	return new("TextLabel", textProps)
end

local function separator(order: number): Frame
	return new("Frame", {
		Size = UDim2.fromOffset(1, 14),
		BackgroundColor3 = TEXT,
		BackgroundTransparency = 0.75,
		LayoutOrder = order,
	})
end

function Hud.new(gamepad: any)
	local self = setmetatable({}, Hud)
	self._gamepad = gamepad
	self._controllerOn = false
	self._visible = true
	self._captureHidden = false
	self._connected = true
	self._guideOpen = false
	self._lastActivity = 0
	self._toastToken = 0

	local gui = new("ScreenGui", {
		Name = "StudioControllerPro_HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Archivable = false,
	})
	self.Gui = gui

	-- Status pill ---------------------------------------------------------------
	local status = new("CanvasGroup", {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = SURFACE,
		BackgroundTransparency = SURFACE_TRANSPARENCY,
		Children = {
			Components.Corner(16),
			Components.Padding(0, 14, 0, 10),
			Components.List(Enum.FillDirection.Horizontal, 10, { VerticalAlignment = Enum.VerticalAlignment.Center }),
		},
		Parent = gui,
	})
	self._status = status
	local badge = new("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = Theme.Accent,
		LayoutOrder = 1,
		Children = { Components.Corner(10) },
		Parent = status,
	})
	new("ImageLabel", {
		Image = Theme.GamepadIcon,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(14, 14),
		Parent = badge,
	})
	self._badge = badge
	self._profileLabel = hudText({ Text = "Default", LayoutOrder = 2, Parent = status })
	local speedSeparator = separator(3)
	speedSeparator.Parent = status
	self._speedLabel = hudText({ Text = "1×", LayoutOrder = 4, Parent = status })
	local fovSeparator = separator(5)
	fovSeparator.Parent = status
	self._fovLabel = hudText({ Text = "FOV 70°", LayoutOrder = 6, Parent = status })
	self._rollSeparator = separator(7)
	self._rollSeparator.Parent = status
	self._rollLabel = hudText({ Text = "Roll 0°", LayoutOrder = 8, Parent = status })
	self._levelSeparator = separator(9)
	self._levelSeparator.Parent = status
	self._levelLabel = hudText({ Text = "Level", LayoutOrder = 10, Parent = status })
	-- Shown instead of the readouts while no controller is connected.
	self._waitingLabel = hudText({
		Text = "No controller connected · plug in or pair one to fly",
		LayoutOrder = 11,
		Parent = status,
	})
	self._readouts = { self._profileLabel, speedSeparator, self._speedLabel, fovSeparator, self._fovLabel }
	self._showRoll = false
	self._showLevel = false
	self:_applyReadouts()

	-- Toast -----------------------------------------------------------------------
	local toast = new("CanvasGroup", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 52),
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = SURFACE,
		BackgroundTransparency = SURFACE_TRANSPARENCY,
		GroupTransparency = 1,
		Visible = false,
		Children = {
			Components.Corner(6),
			Components.Padding(0, 12, 0, 12),
			Components.List(Enum.FillDirection.Horizontal, 8, { VerticalAlignment = Enum.VerticalAlignment.Center }),
		},
		Parent = gui,
	})
	self._toast = toast
	self._toastGlyph = new("ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(20, 20),
		LayoutOrder = 1,
		Visible = false,
		Parent = toast,
	})
	self._toastLabel = hudText({ Text = "", FontFace = Theme.Font.Regular, LayoutOrder = 2, Parent = toast })

	-- Flash ----------------------------------------------------------------------
	self._flash = new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = gui,
	})

	-- Button guide ------------------------------------------------------------------
	local guide = new("CanvasGroup", {
		Name = "Guide",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.fromOffset(GUIDE_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = SURFACE,
		BackgroundTransparency = SURFACE_TRANSPARENCY,
		Visible = false,
		Children = {
			Components.Corner(8),
			Components.Padding(10, 12, 12, 12),
			Components.List(Enum.FillDirection.Vertical, 6),
		},
		Parent = gui,
	})
	self._guide = guide

	-- Reticle -----------------------------------------------------------------------
	-- Its own ScreenGui so it stays up when the status HUD is hidden. A dot marks
	-- the centre; a ring appears when there's something to select, and closes
	-- in while the select gesture is held.
	local reticleGui = new("ScreenGui", {
		Name = "StudioControllerPro_Reticle",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 49,
		Enabled = false,
		Archivable = false,
	})
	self._reticleGui = reticleGui
	self._reticleEnabled = true
	new("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		BackgroundColor3 = TEXT,
		Children = {
			Components.Corner(3),
			new("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 0.5, Thickness = 1 }),
		},
		Parent = reticleGui,
	})
	local ring = new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(RETICLE_RING, RETICLE_RING),
		BackgroundTransparency = 1,
		Visible = false,
		Children = { Components.Corner(RETICLE_RING) },
		Parent = reticleGui,
	})
	self._ringStroke = new("UIStroke", { Color = TEXT, Transparency = 0.25, Thickness = 1.5, Parent = ring })
	self._ring = ring
	reticleGui.Parent = CoreGui

	gui.Parent = CoreGui
	return self
end

function Hud:_refreshVisibility()
	self:_refreshReticle()
	-- The button guide is shown on request even when the status HUD is hidden,
	-- and the missing-controller notice always shows.
	local warning = not self._connected
	self.Gui.Enabled = self._controllerOn and not self._captureHidden and (self._visible or self._guideOpen or warning)
	self._status.Visible = self._visible or warning
	if not self._visible then
		self._toast.Visible = false
	end
end

function Hud:_refreshReticle()
	self._reticleGui.Enabled = self._controllerOn
		and self._connected
		and not self._captureHidden
		and self._reticleEnabled
end

function Hud:SetReticleEnabled(enabled: boolean)
	self._reticleEnabled = enabled
	self:_refreshReticle()
end

-- `hasTarget` shows the ring; `hold` (0..1) closes it in toward the dot while
-- the select gesture is held.
function Hud:SetReticle(hasTarget: boolean, hold: number?)
	local ring = self._ring
	ring.Visible = hasTarget or (hold or 0) > 0
	if not ring.Visible then
		return
	end
	local t = math.clamp(hold or 0, 0, 1)
	local size = RETICLE_RING + (RETICLE_HOLD_RING - RETICLE_RING) * t
	ring.Size = UDim2.fromOffset(size, size)
	self._ringStroke.Color = if t > 0 then TEXT:Lerp(Theme.Accent, t) else TEXT
	self._ringStroke.Thickness = if t > 0 then 2 else 1.5
end

function Hud:_applyReadouts()
	local connected = self._connected
	for _, readout in self._readouts do
		readout.Visible = connected
	end
	self._rollLabel.Visible = connected and self._showRoll
	self._rollSeparator.Visible = connected and self._showRoll
	self._levelLabel.Visible = connected and self._showLevel
	self._levelSeparator.Visible = connected and self._showLevel
	self._waitingLabel.Visible = not connected
	self._badge.BackgroundColor3 = if connected then Theme.Accent else Color3.fromRGB(196, 140, 30)
end

function Hud:SetConnected(connected: boolean)
	if self._connected == connected then
		return
	end
	self._connected = connected
	self:_applyReadouts()
	self:_refreshVisibility()
	self:Poke()
end

function Hud:SetControllerOn(on: boolean)
	self._controllerOn = on
	self:_refreshVisibility()
	if on then
		self:Poke()
	end
end

function Hud:SetVisible(visible: boolean)
	self._visible = visible
	self:_refreshVisibility()
end

function Hud:IsVisible(): boolean
	return self._visible
end

function Hud:SetCaptureHidden(hidden: boolean)
	self._captureHidden = hidden
	self:_refreshVisibility()
end

-- Brightens the status pill; it dims again after a short idle period.
function Hud:Poke()
	self._lastActivity = os.clock()
	if self._status.GroupTransparency ~= 0 then
		TweenService:Create(self._status, FAST, { GroupTransparency = 0 }):Play()
	end
end

-- Called every frame by the plugin loop.
function Hud:Update()
	if not self.Gui.Enabled then
		return
	end
	if self._connected and os.clock() - self._lastActivity > IDLE_DELAY and self._status.GroupTransparency == 0 then
		TweenService:Create(self._status, SLOW, { GroupTransparency = IDLE_TRANSPARENCY }):Play()
	end
end

function Hud:SetStatus(status: { profile: string?, speed: number?, fov: number?, roll: number?, level: boolean? })
	if status.level ~= nil then
		self._showLevel = status.level
		self:_applyReadouts()
	end
	if status.profile then
		self._profileLabel.Text = status.profile
	end
	if status.speed then
		local speed = status.speed
		local text = if speed >= 1 then string.format("%d×", speed) else string.format("%g×", speed)
		self._speedLabel.Text = "Speed " .. text
	end
	if status.fov then
		self._fovLabel.Text = string.format("FOV %d°", math.round(status.fov))
	end
	if status.roll then
		local roll = math.round(status.roll)
		local showRoll = roll ~= 0
		if showRoll ~= self._showRoll then
			self._showRoll = showRoll
			self:_applyReadouts()
		end
		self._rollLabel.Text = string.format("Roll %d°", roll)
	end
end

function Hud:Toast(text: string, glyphKey: string?)
	if not self._visible then
		return
	end
	self:Poke()
	self._toastToken += 1
	local token = self._toastToken
	local glyph = if glyphKey then self._gamepad:Glyph(glyphKey) else ""
	self._toastGlyph.Image = glyph
	self._toastGlyph.Visible = glyph ~= ""
	self._toastLabel.Text = text
	local toast = self._toast
	toast.Visible = true
	TweenService:Create(toast, FAST, { GroupTransparency = 0 }):Play()
	task.delay(TOAST_TIME, function()
		if self._toastToken == token then
			local tween = TweenService:Create(toast, SLOW, { GroupTransparency = 1 })
			tween.Completed:Connect(function()
				if self._toastToken == token then
					toast.Visible = false
				end
			end)
			tween:Play()
		end
	end)
end

function Hud:Flash()
	self._flash.BackgroundTransparency = 0.35
	TweenService:Create(self._flash, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
end

function Hud:IsGuideOpen(): boolean
	return self._guideOpen
end

function Hud:SetGuideOpen(open: boolean)
	self._guideOpen = open
	self._guide.Visible = open
	self:_refreshVisibility()
end

-- Rebuilds the guide from a profile's bindings.
function Hud:RenderGuide(profileName: string, bindings: { [string]: any })
	local guide = self._guide
	for _, child in guide:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	hudText({
		Text = profileName,
		FontFace = Theme.Font.Bold,
		Size = UDim2.new(1, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.None,
		LayoutOrder = 0,
		Parent = guide,
	})
	-- Two columns keep the guide short enough for small viewports.
	local grid = new("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Children = {
			new("UIGridLayout", {
				CellSize = UDim2.new(0.5, -6, 0, 22),
				CellPadding = UDim2.fromOffset(12, 2),
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				FillDirectionMaxCells = 0,
			}),
		},
		Parent = guide,
	})
	local gamepad = self._gamepad
	local bound = {}
	for _, action in Actions.List do
		if bindings[action.id] then
			table.insert(bound, action)
		end
	end
	local layout = grid:FindFirstChildOfClass("UIGridLayout") :: UIGridLayout
	layout.FillDirectionMaxCells = math.ceil(#bound / 2)
	grid.Size = UDim2.new(1, 0, 0, layout.FillDirectionMaxCells * 24)
	grid.AutomaticSize = Enum.AutomaticSize.None
	for index, action in bound do
		local binding = bindings[action.id]
		local row = new("Frame", {
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = grid,
		})
		local glyphs = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(0, GUIDE_GLYPH_WIDTH, 1, 0),
			Children = {
				Components.List(Enum.FillDirection.Horizontal, 2, {
					VerticalAlignment = Enum.VerticalAlignment.Center,
				}),
			},
			Parent = row,
		})
		Glyphs.Render(glyphs, gamepad, binding, { size = 18, onDark = true, textColor = TEXT, dimColor = DIM_TEXT })
		hudText({
			Text = action.name,
			FontFace = Theme.Font.Regular,
			TextColor3 = DIM_TEXT,
			TextSize = 13,
			Position = UDim2.fromOffset(GUIDE_GLYPH_WIDTH + 4, 0),
			Size = UDim2.new(1, -(GUIDE_GLYPH_WIDTH + 4), 1, 0),
			AutomaticSize = Enum.AutomaticSize.None,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})
	end
end

function Hud:Destroy()
	self.Gui:Destroy()
	self._reticleGui:Destroy()
end

return Hud
