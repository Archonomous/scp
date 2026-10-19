--[[
	The dock widget: header (on/off switch, controller status, profile picker)
	and five tabs: Bindings, Tuning, Profiles, Captures, Controller.

	`runtime` is the plugin's main controller (see init.server.luau). The App
	only reads state and calls into the runtime / store; it owns no input
	handling of its own beyond the binding-capture UI.
]]

local TweenService = game:GetService("TweenService")

local Actions = require(script.Parent.Parent.Core.Actions)
local Inputs = require(script.Parent.Parent.Core.Inputs)
local Tuning = require(script.Parent.Parent.Core.Tuning)
local Components = require(script.Parent.Components)
local Glyphs = require(script.Parent.Glyphs)
local Theme = require(script.Parent.Theme)
local Maid = require(script.Parent.Parent.Util.Maid)

local new = Components.new
local C = Theme.Color
local M = Theme.Modifier

local VERSION = "1.0.0"
local CHIP_WIDTH = 100

local TABS = {
	{ id = "bindings", label = "Bindings" },
	{ id = "tuning", label = "Tuning" },
	{ id = "profiles", label = "Profiles" },
	{ id = "captures", label = "Captures" },
	{ id = "controller", label = "Controller" },
}

local App = {}
App.__index = App

-- Switch ----------------------------------------------------------------------

local function Switch(props: { value: boolean, onChange: (boolean) -> (), parent: Instance? })
	local value = props.value
	local button = new("TextButton", {
		Name = "Switch",
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(36, 20),
		Children = { Components.Corner(10) },
		Parent = props.parent,
	})
	local stroke = Components.Stroke(C.InputFieldBorder)
	stroke.Parent = button
	local knob = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Children = { Components.Corner(7) },
		Parent = button,
	})
	local function paint(animate: boolean)
		local position = if value then UDim2.new(1, -17, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
		if animate then
			TweenService:Create(knob, TweenInfo.new(0.12), { Position = position }):Play()
		else
			knob.Position = position
		end
		if value then
			Theme.Bind(button, "BackgroundColor3", function()
				return Theme.Accent
			end)
			Theme.Bind(stroke, "Color", function()
				return Theme.Accent
			end)
			knob.BackgroundColor3 = Color3.new(1, 1, 1)
		else
			Theme.Bind(button, "BackgroundColor3", C.InputFieldBackground)
			Theme.Bind(stroke, "Color", C.InputFieldBorder)
			Theme.Bind(knob, "BackgroundColor3", C.SubText)
		end
	end
	button.Activated:Connect(function()
		value = not value
		paint(true)
		props.onChange(value)
	end)
	paint(false)
	return {
		Instance = button,
		Set = function(newValue: boolean)
			if newValue ~= value then
				value = newValue
				paint(true)
			end
		end,
	}
end

-- Binding chip ------------------------------------------------------------------

local function bindingText(gamepad: any, binding: any): string
	if not binding then
		return "Not set"
	end
	local text = gamepad:InputName(binding.key)
	if binding.mod then
		text = gamepad:InputName(binding.mod) .. " + " .. text
	end
	return text
end

local function hint(text: string, order: number, parent: Instance): TextLabel
	return Components.Text({
		Text = text,
		TextWrapped = true,
		TextSize = Theme.TextSize.Small,
		Color = C.DimmedText,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	})
end

local function buttonRow(order: number, parent: Instance): Frame
	return new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.RowHeight),
		LayoutOrder = order,
		Children = { Components.List(Enum.FillDirection.Horizontal, 6) },
		Parent = parent,
	})
end

-- App ---------------------------------------------------------------------------

function App.new(plugin: Plugin, runtime: any)
	local self = setmetatable({}, App)
	self._plugin = plugin
	self._runtime = runtime
	self._store = runtime.store
	self._gamepad = runtime.gamepad
	self._captures = runtime.captures
	self._maid = Maid.new()
	self._pageMaids = {}
	self._currentTab = "bindings"
	self._capturingAction = nil
	self._selectedCapture = nil
	self._exportVisible = false

	local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 340, 600, 300, 360)
	local widget = plugin:CreateDockWidgetPluginGuiAsync("StudioControllerPro", info)
	widget.Title = "Studio Controller Pro"
	widget.Name = "StudioControllerPro"
	widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self.Widget = widget

	local root = new("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		Theme = { BackgroundColor3 = C.MainBackground },
		Parent = widget,
	})
	self._root = root

	self:_buildHeader(root)

	local tabs = Components.Tabs({
		tabs = TABS,
		onSelect = function(id)
			self:SelectTab(id)
		end,
		parent = root,
	})
	tabs.Instance.Position = UDim2.fromOffset(0, self._headerHeight)
	self._tabs = tabs

	local pages = new("Frame", {
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, self._headerHeight + 32),
		Size = UDim2.new(1, 0, 1, -(self._headerHeight + 32)),
		ClipsDescendants = true,
		Parent = root,
	})
	self._pagesHost = pages
	self._pages = {}
	for _, tab in TABS do
		local scroller, content = Components.Page(tab.id)
		scroller.Parent = pages
		self._pages[tab.id] = { scroller = scroller, content = content }
	end

	-- Snackbar for in-panel feedback.
	local snackbar = new("Frame", {
		Name = "Snackbar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -24, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		ZIndex = 30,
		Theme = { BackgroundColor3 = C.Tooltip },
		Children = {
			Components.Corner(6),
			Components.Padding(8, 12, 8, 12),
		},
		Parent = root,
	})
	Components.Stroke(C.Border).Parent = snackbar
	self._snackbarLabel = Components.Text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		ZIndex = 31,
		Parent = snackbar,
	})
	self._snackbar = snackbar
	self._snackToken = 0

	-- Overlay host for dropdown menus.
	self._overlay = new("Frame", {
		Name = "Overlay",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 40,
		Parent = root,
	})
	-- Tooltips sit above everything, including open menus.
	local tooltipLayer = new("Frame", {
		Name = "Tooltips",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Parent = root,
	})
	Components.SetTooltipHost(tooltipLayer)

	-- Store / device subscriptions ----------------------------------------------------
	self._maid:Give(self._store.Changed:Connect(function(kind, key, tuningKey)
		if kind == "profile" or kind == "profiles" then
			self:_renderProfilePicker()
			self:_renderPage("bindings")
			self:_renderPage("tuning")
			self:_renderPage("profiles")
		elseif kind == "bindings" then
			self:_renderPage("bindings")
		elseif kind == "tuning" then
			-- Keep controls in sync with changes made from the pad.
			local profile = self._store:GetActiveProfile()
			local control = self._tuningControls and self._tuningControls[tuningKey]
			if control and key == profile.id then
				control.Set(profile.tuning[tuningKey])
			end
		elseif kind == "settings" then
			self:_syncSettings()
		elseif kind == "runtime" and key == "gamepad" then
			self:_renderPage("controller")
		end
	end))
	self._maid:Give(self._gamepad.Changed:Connect(function()
		self:_renderStatus()
		self:_renderPage("bindings")
		self:_renderPage("controller")
	end))
	self._maid:Give(self._captures.Changed:Connect(function()
		self:_renderPage("captures")
	end))
	if runtime.Notice then
		self._maid:Give(runtime.Notice:Connect(function(message)
			self:Notify(message)
		end))
	end
	self._maid:Give(runtime.StateChanged:Connect(function()
		self._switch.Set(runtime:IsOn())
		self:_renderStatus()
	end))
	self._maid:Give(Theme.OnChanged(function()
		-- Glyph tinting and accent fills don't follow theme tokens, so a full
		-- rebuild keeps everything consistent after a theme switch.
		for _, tab in TABS do
			self:_renderPage(tab.id)
		end
	end))
	self._maid:Give(widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not widget.Enabled then
			self:CancelCapture()
		end
	end))

	for _, tab in TABS do
		self:_renderPage(tab.id)
	end
	self:SelectTab("bindings")
	if not self._store:GetRuntime("welcomed") then
		self:ShowWelcome()
	end
	return self
end

-- Welcome ----------------------------------------------------------------------------
-- Shown over the tabs on first run, and from the Controller tab on request.

function App:ShowWelcome()
	if not self._welcome then
		local scroller, content = Components.Page("Welcome")
		scroller.Visible = true
		local host = new("Frame", {
			Name = "Welcome",
			Position = UDim2.fromOffset(0, self._headerHeight),
			Size = UDim2.new(1, 0, 1, -self._headerHeight),
			ZIndex = 20,
			Theme = { BackgroundColor3 = C.MainBackground },
			Parent = self._root,
		})
		new("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			Theme = { BackgroundColor3 = C.Border },
			Parent = host,
		})
		scroller.Parent = host
		local maid = Maid.new()
		self._welcome = { host = host, content = content, maid = maid }
		maid:Give(self._gamepad.Changed:Connect(function()
			self:_renderWelcome()
		end))
		maid:Give(self._store.Changed:Connect(function(kind)
			if kind == "profile" or kind == "bindings" or kind == "profiles" then
				self:_renderWelcome()
			end
		end))
		maid:Give(Theme.OnChanged(function()
			self:_renderWelcome()
		end))
		maid:Give(self._runtime.StateChanged:Connect(function()
			self:_renderWelcome()
		end))
	end
	self:CancelCapture()
	self:_renderWelcome()
end

function App:DismissWelcome()
	local welcome = self._welcome
	if welcome then
		self._welcome = nil
		welcome.maid:Clean()
		welcome.host:Destroy()
	end
	self._store:SetRuntime("welcomed", true)
end

function App:IsShowingWelcome(): boolean
	return self._welcome ~= nil
end

local function welcomeStep(number: number, title: string, order: number, parent: Instance): Frame
	local card = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Theme = { BackgroundColor3 = C.InputFieldBackground },
		Children = { Components.Corner(6), Components.Padding(10, 12, 12, 12) },
		Parent = parent,
	})
	Components.Stroke(C.Border).Parent = card
	local badge = new("Frame", {
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = Theme.Accent,
		Children = { Components.Corner(11) },
		Parent = card,
	})
	new("TextLabel", {
		Text = tostring(number),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.Font.Bold,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Color3.new(1, 1, 1),
		Parent = badge,
	})
	local body = new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(34, 0),
		Size = UDim2.new(1, -34, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Children = { Components.List(Enum.FillDirection.Vertical, 6) },
		Parent = card,
	})
	Components.Text({
		Text = title,
		FontFace = Theme.Font.Medium,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 1,
		Parent = body,
	})
	return body
end

-- A row of glyphs for a binding followed by a short label.
function App:_glyphLine(binding: any, label: string, order: number, parent: Instance)
	local row = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = order,
		Children = {
			Components.List(Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center }),
		},
		Parent = parent,
	})
	if binding then
		local glyphs = new("Frame", {
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			LayoutOrder = 1,
			Children = {
				Components.List(
					Enum.FillDirection.Horizontal,
					2,
					{ VerticalAlignment = Enum.VerticalAlignment.Center }
				),
			},
			Parent = row,
		})
		Glyphs.Render(glyphs, self._gamepad, binding, { size = 20 })
	end
	Components.Text({
		Text = if binding then label else "Not bound in this profile",
		Color = C.SubText,
		TextSize = Theme.TextSize.Small,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 2,
		Parent = row,
	})
end

function App:_renderWelcome()
	local welcome = self._welcome
	if not welcome then
		return
	end
	local content = welcome.content
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local gamepad = self._gamepad
	local bindings = self._store:GetActiveProfile().bindings

	local intro = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Children = {
			Components.Padding(8, 0, 4, 0),
			Components.List(Enum.FillDirection.Vertical, 4, { HorizontalAlignment = Enum.HorizontalAlignment.Center }),
		},
		Parent = content,
	})
	local logo = new("ImageLabel", {
		Image = Theme.GamepadIcon,
		BackgroundColor3 = Theme.Accent,
		Size = UDim2.fromOffset(56, 56),
		LayoutOrder = 1,
		Children = { Components.Corner(12) },
		Parent = intro,
	})
	task.spawn(function()
		if Theme.ToolbarIcon and Theme.IsAssetAvailable(Theme.ToolbarIcon) and logo.Parent then
			logo.Image = Theme.ToolbarIcon
			logo.BackgroundTransparency = 1
		end
	end)
	new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(1, 4), LayoutOrder = 2, Parent = intro })
	Components.Text({
		Text = "Welcome to Studio Controller Pro",
		FontFace = Theme.Font.Bold,
		TextSize = Theme.TextSize.Heading,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Parent = intro,
	})
	local tagline = hint("Fly the edit camera with a gamepad. Three steps to get going:", 4, intro)
	tagline.TextXAlignment = Enum.TextXAlignment.Center

	-- 1. Connect.
	local connect = welcomeStep(1, "Connect a controller", 2, content)
	local status = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 2,
		Children = {
			Components.List(Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center }),
		},
		Parent = connect,
	})
	local connected = gamepad:IsConnected()
	local dot = new("Frame", {
		Size = UDim2.fromOffset(8, 8),
		LayoutOrder = 1,
		Children = { Components.Corner(4) },
		Parent = status,
	})
	if connected then
		dot.BackgroundColor3 = Color3.fromRGB(45, 190, 110)
	else
		dot.BackgroundColor3 = Color3.fromRGB(196, 140, 30)
	end
	Components.Text({
		Text = if connected then gamepad:DisplayName() .. " connected" else "Waiting for a controller…",
		TextSize = Theme.TextSize.Small,
		Color = if connected then C.MainText else C.SubText,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 2,
		Parent = status,
	})
	if not connected then
		hint("Plug in or pair an Xbox, PlayStation or other gamepad. It's detected automatically.", 3, connect)
	end

	-- 2. Toggle.
	local start = welcomeStep(2, "Turn on controller mode", 3, content)
	self:_glyphLine(bindings.toggleController, "click both sticks", 2, start)
	hint("Or use the Controller button in the toolbar, or the switch above.", 3, start)

	-- 3. Guide.
	local guide = welcomeStep(3, "See every button", 4, content)
	self:_glyphLine(bindings.toggleGuide, "shows the button guide on screen", 2, guide)
	hint("Rebind anything on the Bindings tab, and save layouts as profiles.", 3, guide)

	local row = buttonRow(5, content)
	Components.Button({
		text = if self._runtime:IsOn() then "Got it" else "Start flying",
		style = "primary",
		onClick = function()
			self:DismissWelcome()
			self._runtime:SetOn(true)
		end,
		parent = row,
	})
	if not self._runtime:IsOn() then
		Components.Button({
			text = "Not now",
			style = "ghost",
			onClick = function()
				self:DismissWelcome()
			end,
			parent = row,
		})
	end
	hint("You can open this again from the Controller tab.", 6, content)
end

-- Header ---------------------------------------------------------------------------

function App:_buildHeader(root: Frame)
	local header = new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 100),
		Theme = { BackgroundColor3 = C.MainBackground },
		Children = { Components.Padding(12, 12, 8, 12) },
		Parent = root,
	})
	self._headerHeight = 100

	local logo = new("Frame", {
		Name = "Logo",
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = Theme.Accent,
		Children = { Components.Corner(6) },
		Parent = header,
	})
	local logoImage = new("ImageLabel", {
		Image = Theme.GamepadIcon,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(22, 22),
		Parent = logo,
	})
	-- Swap to the full-color logo once the uploaded asset is available.
	task.spawn(function()
		if Theme.ToolbarIcon and Theme.IsAssetAvailable(Theme.ToolbarIcon) and logo.Parent then
			logo.BackgroundTransparency = 1
			logoImage.Image = Theme.ToolbarIcon
			logoImage.Size = UDim2.fromScale(1, 1)
		end
	end)

	Components.Text({
		Text = "Studio Controller Pro",
		FontFace = Theme.Font.Bold,
		TextSize = Theme.TextSize.Title,
		Position = UDim2.fromOffset(42, -1),
		Size = UDim2.new(1, -92, 0, 18),
		Parent = header,
	})
	local statusRow = new("Frame", {
		Name = "Status",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(42, 18),
		Size = UDim2.new(1, -92, 0, 16),
		Children = {
			Components.List(Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center }),
		},
		Parent = header,
	})
	self._statusDot = new("Frame", {
		Size = UDim2.fromOffset(8, 8),
		LayoutOrder = 1,
		Children = { Components.Corner(4) },
		Parent = statusRow,
	})
	self._statusText = Components.Text({
		Text = "",
		TextSize = Theme.TextSize.Small,
		Color = C.SubText,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 2,
		Parent = statusRow,
	})

	self._switch = Switch({
		value = self._runtime:IsOn(),
		onChange = function(value)
			self._runtime:SetOn(value)
		end,
		parent = header,
	})
	self._switch.Instance.AnchorPoint = Vector2.new(1, 0)
	self._switch.Instance.Position = UDim2.new(1, 0, 0, 6)

	local profileRow = new("Frame", {
		Name = "ProfileRow",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 0, Theme.RowHeight),
		Parent = header,
	})
	Components.Text({
		Text = "Profile",
		Color = C.SubText,
		Size = UDim2.new(0, 56, 1, 0),
		Parent = profileRow,
	})
	self._profileDropdownHost = new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(56, 0),
		Size = UDim2.new(1, -56, 1, 0),
		Parent = profileRow,
	})
	self:_renderStatus()
	-- The dropdown needs the overlay host, which is created after the header.
	task.defer(function()
		self:_renderProfilePicker()
	end)
end

function App:_renderStatus()
	local gamepad = self._gamepad
	local on = self._runtime:IsOn()
	local text
	if not gamepad:IsConnected() then
		text = "No controller connected"
		Theme.Bind(self._statusDot, "BackgroundColor3", C.DimmedText)
	else
		text = string.format("%s · Gamepad %d", gamepad:DisplayName(), gamepad:SlotNumber() or 1)
		if on then
			self._statusDot.BackgroundColor3 = Color3.fromRGB(45, 190, 110)
			Theme.Bind(self._statusDot, "BackgroundColor3", function()
				return Color3.fromRGB(45, 190, 110)
			end)
		else
			Theme.Bind(self._statusDot, "BackgroundColor3", C.SubText)
		end
	end
	self._statusText.Text = text .. (if on then " · On" else " · Off")
end

function App:_renderProfilePicker()
	if not self._overlay then
		return
	end
	local items = {}
	for _, profile in self._store:GetProfiles() do
		table.insert(items, { id = profile.id, label = profile.name })
	end
	local selected = self._store:GetActiveProfile().id
	if self._profileDropdown then
		self._profileDropdown.Set(items, selected)
		return
	end
	self._profileDropdown = Components.Dropdown({
		items = items,
		selected = selected,
		overlayHost = self._overlay,
		onSelect = function(id)
			self._store:SetActiveProfile(id)
		end,
		parent = self._profileDropdownHost,
	})
end

-- Tabs & pages ----------------------------------------------------------------------

function App:SelectTab(id: string)
	self._currentTab = id
	self._tabs.Select(id)
	for tabId, page in self._pages do
		page.scroller.Visible = tabId == id
	end
	if id ~= "bindings" then
		self:CancelCapture()
	end
end

function App:IsShowingTester(): boolean
	return self.Widget.Enabled and self._currentTab == "controller" and not self._welcome
end

function App:_renderPage(id: string)
	local page = self._pages and self._pages[id]
	if not page then
		return
	end
	local maid = self._pageMaids[id]
	if maid then
		maid:Clean()
	end
	maid = Maid.new()
	self._pageMaids[id] = maid
	for _, child in page.content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local render = (self :: any)["_render_" .. id]
	render(self, page.content, maid)
end

function App:Notify(text: string)
	self._snackToken += 1
	local token = self._snackToken
	self._snackbarLabel.Text = text
	self._snackbar.Visible = true
	task.delay(3, function()
		if self._snackToken == token then
			self._snackbar.Visible = false
		end
	end)
end

-- Bindings page ------------------------------------------------------------------------

function App:_render_bindings(content: Frame, maid: any)
	local store = self._store
	local gamepad = self._gamepad
	local profile = store:GetActiveProfile()
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	if self._capturingAction then
		local action = Actions.ById[self._capturingAction]
		local banner = new("Frame", {
			Name = "CaptureBanner",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = nextOrder(),
			BackgroundColor3 = Theme.Accent,
			BackgroundTransparency = 0.85,
			Children = {
				Components.Corner(6),
				Components.Padding(10, 10, 10, 10),
				Components.List(Enum.FillDirection.Vertical, 8),
			},
			Parent = content,
		})
		local stroke = Components.Stroke(function()
			return Theme.Accent
		end)
		stroke.Parent = banner
		Components.Text({
			Text = "Binding “" .. action.name .. "”",
			FontFace = Theme.Font.Bold,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = 1,
			Parent = banner,
		})
		hint(
			if action.kind == "stick"
				then "Move the stick you want to use."
				else "Press a button. For a combo, hold one button and press another.",
			2,
			banner
		)
		local row = buttonRow(3, banner)
		Components.Button({
			text = "Cancel",
			onClick = function()
				self:CancelCapture()
			end,
			parent = row,
		})
		Components.Button({
			text = "Clear binding",
			style = "ghost",
			onClick = function()
				local actionId = self._capturingAction
				self:CancelCapture()
				store:SetBinding(profile.id, actionId, false)
			end,
			parent = row,
		})
	else
		hint(
			"Click a binding, then press a button on your controller. Hold one button and press another to make a combo.",
			nextOrder(),
			content
		)
	end

	if not gamepad:IsConnected() then
		local warning = new("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = nextOrder(),
			Theme = { BackgroundColor3 = C.Item },
			Children = {
				Components.Corner(6),
				Components.Padding(8, 10, 8, 10),
				Components.List(Enum.FillDirection.Horizontal, 8),
			},
			Parent = content,
		})
		Components.Icon(Theme.Icons.Warning, 16, { LayoutOrder = 1, Parent = warning })
		Components.Text({
			Text = "Connect a controller to bind buttons. Glyphs update to match it.",
			TextWrapped = true,
			TextSize = Theme.TextSize.Small,
			Size = UDim2.new(1, -24, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = warning,
		})
	end

	for _, category in Actions.Categories do
		Components.SectionHeader(category, nextOrder(), content)
		for _, action in Actions.List do
			if action.category ~= category then
				continue
			end
			local binding = profile.bindings[action.id]
			local capturing = self._capturingAction == action.id
			local row = new("Frame", {
				Name = action.id,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = nextOrder(),
				Parent = content,
			})
			local labels = new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -CHIP_WIDTH - 36, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Children = {
					Components.List(Enum.FillDirection.Vertical, 1),
					Components.Padding(3, 0, 3, 0),
				},
				Parent = row,
			})
			Components.Text({
				Text = action.name,
				Size = UDim2.new(1, 0, 0, 18),
				LayoutOrder = 1,
				Parent = labels,
			})
			Components.Text({
				Text = action.description,
				TextSize = Theme.TextSize.Small,
				TextWrapped = true,
				TextTruncate = Enum.TextTruncate.None,
				Color = C.DimmedText,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 2,
				Parent = labels,
			})

			local chip = new("TextButton", {
				Name = "Chip",
				AutoButtonColor = false,
				Text = "",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -26, 0.5, 0),
				Size = UDim2.fromOffset(CHIP_WIDTH, 28),
				Theme = { BackgroundColor3 = C.InputFieldBackground },
				Children = { Components.Corner(4), Components.Padding(0, 6, 0, 6) },
				Parent = row,
			})
			local chipStroke = Components.Stroke(C.InputFieldBorder)
			chipStroke.Parent = chip
			local glyphs = new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Children = {
					Components.List(Enum.FillDirection.Horizontal, 3, {
						VerticalAlignment = Enum.VerticalAlignment.Center,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
					}),
				},
				Parent = chip,
			})
			if capturing then
				Theme.Bind(chipStroke, "Color", function()
					return Theme.Accent
				end)
				chipStroke.Thickness = 2
				local label = Components.Text({
					Text = "Listening…",
					FontFace = Theme.Font.Medium,
					TextSize = Theme.TextSize.Small,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.fromScale(1, 1),
					Parent = glyphs,
				})
				Theme.Bind(label, "TextColor3", function()
					return Theme.Accent
				end)
			elseif binding then
				Glyphs.Render(glyphs, gamepad, binding, { size = 20 })
			else
				Components.Text({
					Text = "Not set",
					TextSize = Theme.TextSize.Small,
					TextXAlignment = Enum.TextXAlignment.Center,
					Color = C.DimmedText,
					Size = UDim2.fromScale(1, 1),
					Parent = glyphs,
				})
			end
			Components.Interact(chip, function(state)
				if not capturing then
					Theme.Bind(
						chipStroke,
						"Color",
						{ C.InputFieldBorder, if state == "Default" then M.Default else M.Hover }
					)
				end
			end)
			chip.Activated:Connect(function()
				if capturing then
					self:CancelCapture()
				else
					self:BeginCapture(action.id)
				end
			end)

			local clear = Components.IconButton({
				icon = Theme.Icons.Close,
				size = 22,
				tooltip = "Clear",
				onClick = function()
					store:SetBinding(profile.id, action.id, false)
				end,
				parent = row,
			})
			clear.Instance.AnchorPoint = Vector2.new(1, 0.5)
			clear.Instance.Position = UDim2.new(1, 0, 0.5, 0)
			clear.Instance.Visible = binding ~= false and binding ~= nil
		end
	end

	Components.Divider(nextOrder(), content)
	local row = buttonRow(nextOrder(), content)
	Components.Button({
		text = "Reset bindings",
		icon = Theme.Icons.Reset,
		onClick = function()
			self:CancelCapture()
			store:ResetBindings(profile.id)
			self:Notify("Bindings reset for “" .. profile.name .. "”.")
		end,
		parent = row,
	})
	local _ = maid
end

-- Binding capture ---------------------------------------------------------------------

function App:BeginCapture(actionId: string)
	self._capturingAction = actionId
	local action = Actions.ById[actionId]
	self._runtime:BeginCapture(action.kind, function(binding)
		if self._capturingAction ~= actionId then
			return
		end
		self._capturingAction = nil
		if binding then
			local profile = self._store:GetActiveProfile()
			local displaced = self._store:SetBinding(profile.id, actionId, binding)
			local text = action.name .. " → " .. bindingText(self._gamepad, binding)
			if #displaced > 0 then
				local names = {}
				for _, id in displaced do
					table.insert(names, Actions.ById[id].name)
				end
				text ..= ". Removed from " .. table.concat(names, ", ") .. "."
			end
			self:Notify(text)
		else
			self:_renderPage("bindings")
		end
	end)
	self:_renderPage("bindings")
end

function App:CancelCapture()
	if not self._capturingAction then
		return
	end
	self._capturingAction = nil
	self._runtime:CancelCapture()
	self:_renderPage("bindings")
end

-- Tuning page -------------------------------------------------------------------------

function App:_render_tuning(content: Frame, maid: any)
	local store = self._store
	local profile = store:GetActiveProfile()
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	hint("Tuning is saved per profile. Changes apply instantly.", nextOrder(), content)

	self._tuningControls = {}
	for _, section in Tuning.Sections do
		Components.SectionHeader(section, nextOrder(), content)
		for _, spec in Tuning.Profile do
			if spec.section ~= section then
				continue
			end
			local control
			if spec.kind == "bool" then
				control = Components.Checkbox({
					label = spec.label,
					description = spec.description,
					value = profile.tuning[spec.key],
					onChange = function(value)
						store:SetTuning(profile.id, spec.key, value)
					end,
					layoutOrder = nextOrder(),
					parent = content,
				})
			else
				control = Components.Slider({
					label = spec.label,
					description = spec.description,
					min = spec.min :: number,
					max = spec.max :: number,
					step = spec.step :: number,
					value = profile.tuning[spec.key],
					format = function(value)
						return Tuning.Format(spec, value)
					end,
					onChange = function(value)
						store:SetTuning(profile.id, spec.key, value)
					end,
					layoutOrder = nextOrder(),
					parent = content,
				})
			end
			self._tuningControls[spec.key] = control
		end
	end

	local row = buttonRow(nextOrder(), content)
	Components.Button({
		text = "Reset tuning",
		icon = Theme.Icons.Reset,
		onClick = function()
			store:ResetTuning(profile.id)
			self:_renderPage("tuning")
			self:Notify("Tuning reset for “" .. profile.name .. "”.")
		end,
		parent = row,
	})

	Components.Divider(nextOrder(), content)
	Components.SectionHeader("General", nextOrder(), content)
	hint("These apply to every profile.", nextOrder(), content)
	self._settingControls = {}
	for _, spec in Tuning.Global do
		local onChange = function(value)
			store:SetSetting(spec.key, value)
			-- A sample pulse, so the new strength can be felt right away.
			if string.sub(spec.key, 1, 9) == "vibration" and store:GetSetting("vibration") then
				self._runtime.haptics:Play("switch")
			end
		end
		if spec.kind == "bool" then
			self._settingControls[spec.key] = Components.Checkbox({
				label = spec.label,
				description = spec.description,
				value = store:GetSetting(spec.key),
				onChange = onChange,
				layoutOrder = nextOrder(),
				parent = content,
			})
		else
			self._settingControls[spec.key] = Components.Slider({
				label = spec.label,
				description = spec.description,
				min = spec.min :: number,
				max = spec.max :: number,
				step = spec.step :: number,
				value = store:GetSetting(spec.key),
				format = function(value)
					return Tuning.Format(spec, value)
				end,
				onChange = onChange,
				layoutOrder = nextOrder(),
				parent = content,
			})
		end
	end
	local _ = maid
end

function App:_syncSettings()
	if not self._settingControls then
		return
	end
	for key, control in self._settingControls do
		control.Set(self._store:GetSetting(key))
	end
end

-- Profiles page ------------------------------------------------------------------------

function App:_render_profiles(content: Frame, maid: any)
	local store = self._store
	local active = store:GetActiveProfile()
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	hint(
		"Click a profile to make it active. Switch from the controller with View + D-Pad Left/Right (by default).",
		nextOrder(),
		content
	)

	local list = new("Frame", {
		Name = "List",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = nextOrder(),
		Theme = { BackgroundColor3 = C.InputFieldBackground },
		Children = {
			Components.Corner(6),
			Components.Padding(4, 4, 4, 4),
			Components.List(Enum.FillDirection.Vertical, 2),
		},
		Parent = content,
	})
	Components.Stroke(C.Border).Parent = list

	for index, profile in store:GetProfiles() do
		local isActive = profile.id == active.id
		local row = new("TextButton", {
			Name = profile.id,
			AutoButtonColor = false,
			Text = "",
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = index,
			Children = { Components.Corner(4), Components.Padding(0, 8, 0, 8) },
			Parent = list,
		})
		local function paint(state)
			if isActive then
				row.BackgroundTransparency = 0
				Theme.Bind(row, "BackgroundColor3", { C.Item, M.Selected })
			else
				row.BackgroundTransparency = if state == "Default" then 1 else 0
				Theme.Bind(row, "BackgroundColor3", { C.Item, M.Hover })
			end
		end
		Components.Interact(row, paint)

		if isActive and self._renaming then
			local box = new("TextBox", {
				Text = profile.name,
				ClearTextOnFocus = false,
				FontFace = Theme.Font.Regular,
				TextSize = Theme.TextSize.Body,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -24, 0, 24),
				Position = UDim2.fromOffset(0, 3),
				Theme = { BackgroundColor3 = C.InputFieldBackground, TextColor3 = C.MainText },
				Children = { Components.Corner(4), Components.Padding(0, 6, 0, 6) },
				Parent = row,
			})
			local stroke = Components.Stroke(function()
				return Theme.Accent
			end)
			stroke.Parent = box
			box.FocusLost:Connect(function(enterPressed)
				self._renaming = false
				local renamed = store:RenameProfile(profile.id, box.Text)
				if not renamed then
					self:_renderPage("profiles")
				end
				local _ = enterPressed
			end)
			task.defer(function()
				box:CaptureFocus()
				box.SelectionStart = 1
				box.CursorPosition = #box.Text + 1
			end)
		else
			Components.Text({
				Text = profile.name,
				FontFace = if isActive then Theme.Font.Medium else Theme.Font.Regular,
				Size = UDim2.new(1, -24, 1, 0),
				Parent = row,
			})
		end
		if isActive then
			Components.Icon(Theme.Icons.Check, 16, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				Parent = row,
			})
		end
		row.Activated:Connect(function()
			if not isActive then
				self._renaming = false
				self._confirmDelete = false
				store:SetActiveProfile(profile.id)
			end
		end)
		local lastClick = 0
		row.MouseButton1Down:Connect(function()
			local now = os.clock()
			if isActive and now - lastClick < 0.35 then
				self._renaming = true
				self:_renderPage("profiles")
			end
			lastClick = now
		end)
	end

	-- Actions on the active profile.
	local actionsRow = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.RowHeight),
		LayoutOrder = nextOrder(),
		Children = { Components.List(Enum.FillDirection.Horizontal, 4) },
		Parent = content,
	})
	local newButton = Components.IconButton({
		icon = Theme.Icons.Add,
		size = 28,
		tooltip = "New profile",
		onClick = function()
			if store:CreateProfile("New profile") then
				self:Notify("Created a new profile from the Default preset.")
			end
		end,
		parent = actionsRow,
		layoutOrder = 1,
	})
	newButton.SetEnabled(store:CanAddProfile())
	local duplicateButton = Components.IconButton({
		icon = Theme.Icons.Duplicate,
		size = 28,
		tooltip = "Duplicate",
		onClick = function()
			local copy = store:DuplicateProfile(active.id)
			if copy then
				self:Notify("Duplicated as “" .. copy.name .. "”.")
			end
		end,
		parent = actionsRow,
		layoutOrder = 2,
	})
	duplicateButton.SetEnabled(store:CanAddProfile())
	Components.IconButton({
		icon = Theme.Icons.Edit,
		size = 28,
		tooltip = "Rename",
		onClick = function()
			self._renaming = true
			self:_renderPage("profiles")
		end,
		parent = actionsRow,
		layoutOrder = 3,
	})
	local profiles = store:GetProfiles()
	local activeIndex = table.find(profiles, active) or 1
	local up = Components.IconButton({
		icon = Theme.Icons.ArrowUp,
		size = 28,
		tooltip = "Move up",
		onClick = function()
			store:MoveProfile(active.id, -1)
		end,
		parent = actionsRow,
		layoutOrder = 4,
	})
	up.SetEnabled(activeIndex > 1)
	local down = Components.IconButton({
		icon = Theme.Icons.ArrowDown,
		size = 28,
		tooltip = "Move down",
		onClick = function()
			store:MoveProfile(active.id, 1)
		end,
		parent = actionsRow,
		layoutOrder = 5,
	})
	down.SetEnabled(activeIndex < #profiles)

	local deleteButton
	deleteButton = Components.Button({
		text = if self._confirmDelete then "Confirm delete" else "Delete",
		icon = Theme.Icons.Delete,
		style = if self._confirmDelete then "danger" else "ghost",
		onClick = function()
			if #store:GetProfiles() <= 1 then
				self:Notify("You need at least one profile.")
				return
			end
			if self._confirmDelete then
				self._confirmDelete = false
				local name = active.name
				store:DeleteProfile(active.id)
				self:Notify("Deleted “" .. name .. "”.")
			else
				self._confirmDelete = true
				self:_renderPage("profiles")
				task.delay(3, function()
					if self._confirmDelete then
						self._confirmDelete = false
						self:_renderPage("profiles")
					end
				end)
			end
		end,
		parent = actionsRow,
		layoutOrder = 6,
	})
	deleteButton.SetEnabled(#profiles > 1)
	local deleteHolder = deleteButton.Instance
	deleteHolder.LayoutOrder = 10

	-- Share.
	Components.Divider(nextOrder(), content)
	Components.SectionHeader("Share", nextOrder(), content)
	hint(
		"Export copies the active profile as text you can share. Import adds a profile from pasted text.",
		nextOrder(),
		content
	)
	local shareRow = buttonRow(nextOrder(), content)
	Components.Button({
		text = "Export",
		icon = Theme.Icons.Export,
		iconRotation = 180,
		onClick = function()
			self._exportVisible = not self._exportVisible
			self._importVisible = false
			self:_renderPage("profiles")
		end,
		parent = shareRow,
	})
	Components.Button({
		text = "Import",
		icon = Theme.Icons.Import,
		onClick = function()
			self._importVisible = not self._importVisible
			self._exportVisible = false
			self:_renderPage("profiles")
		end,
		parent = shareRow,
	})

	if self._exportVisible then
		local box = Components.TextArea({
			text = store:Export(active.id) or "",
			height = 110,
			layoutOrder = nextOrder(),
			parent = content,
		})
		hint("Click the text, press Ctrl+A, then Ctrl+C to copy it.", nextOrder(), content)
		box.Focused:Connect(function()
			box.SelectionStart = 1
			box.CursorPosition = #box.Text + 1
		end)
	elseif self._importVisible then
		local box = Components.TextArea({
			placeholder = "Paste an exported profile here",
			height = 110,
			layoutOrder = nextOrder(),
			parent = content,
		})
		local errorLabel = Components.Text({
			Text = "",
			TextWrapped = true,
			TextSize = Theme.TextSize.Small,
			Color = C.ErrorText,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Visible = false,
			LayoutOrder = nextOrder(),
			Parent = content,
		})
		local importRow = buttonRow(nextOrder(), content)
		Components.Button({
			text = "Add profile",
			style = "primary",
			onClick = function()
				local profile, err = store:Import(box.Text)
				if profile then
					self._importVisible = false
					self:Notify("Imported “" .. profile.name .. "”.")
				else
					errorLabel.Text = err or "Couldn't import that profile."
					errorLabel.Visible = true
				end
			end,
			parent = importRow,
		})
	end
	local _ = maid
end

-- Captures page --------------------------------------------------------------------------

-- Badges sit on dark translucent circles over the image, so they always use
-- the Dark icon variants.
local UPLOAD_BADGE = "rbxasset://studio_svg_textures/Lua/AvatarCompatibilityPreviewer/Dark/Large/publish@2x.png"
local UPLOADED_BADGE = "rbxasset://studio_svg_textures/Shared/Alerts/Dark/Standard/Success@2x.png"
local BADGE_SURFACE = Color3.fromRGB(20, 20, 24)

-- Upload state drawn over thumbnails and the viewer image.
local function uploadBadge(capture: any, onClick: () -> (), parent: Instance): ImageButton
	local badge = new("ImageButton", {
		Name = "Upload",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = BADGE_SURFACE,
		BackgroundTransparency = 0.35,
		ZIndex = 3,
		Children = { Components.Corner(12) },
		Parent = parent,
	})
	local icon = new("ImageLabel", {
		Image = if capture.uploaded then UPLOADED_BADGE else UPLOAD_BADGE,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		ZIndex = 4,
		Parent = badge,
	})
	if capture.saving then
		icon.ImageTransparency = 0.6
		Components.AttachTooltip(badge, "Uploading…")
	elseif capture.uploaded then
		Components.AttachTooltip(badge, "Uploaded and saved to ServerStorage")
	else
		icon.ImageTransparency = 0.15
		Components.AttachTooltip(badge, "Upload to keep it: adds an exportable plane in ServerStorage")
	end
	badge.Activated:Connect(function()
		Components.HideTooltip()
		onClick()
	end)
	return badge
end

-- Opens a capture in the viewer, optionally straight to the upload prompt.
function App:_openCapture(capture: any, confirmUpload: boolean?)
	self._selectedCapture = capture.id
	self._confirmCaptureDelete = false
	self._confirmUpload = if confirmUpload and not capture.uploaded and not capture.saving then capture.id else nil
	self:_renderPage("captures")
end

function App:_renderUploadPrompt(selected: any, order: number, content: Frame)
	local card = new("Frame", {
		Name = "UploadPrompt",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Theme = { BackgroundColor3 = C.InputFieldBackground },
		Children = {
			Components.Corner(6),
			Components.Padding(10, 12, 12, 12),
			Components.List(Enum.FillDirection.Vertical, 8),
		},
		Parent = content,
	})
	Components.Stroke(function()
		return Theme.Accent
	end).Parent = card
	Components.Text({
		Text = "Upload this capture?",
		FontFace = Theme.Font.Medium,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 1,
		Parent = card,
	})
	hint(
		"It's uploaded to your Roblox account as an image, which goes through moderation and shows up in "
			.. "Creator Hub. A plane showing it is added to ServerStorage › "
			.. self._captures.FolderName
			.. ". Each capture is only uploaded once.",
		2,
		card
	)
	local row = buttonRow(3, card)
	Components.Button({
		text = "Upload",
		icon = Theme.Icons.Upload,
		style = "primary",
		onClick = function()
			self._confirmUpload = nil
			self._runtime:UploadCapture(selected.id)
			self:Notify("Uploading “" .. selected.name .. "”…")
		end,
		parent = row,
	})
	Components.Button({
		text = "Cancel",
		style = "ghost",
		onClick = function()
			self._confirmUpload = nil
			self:_renderPage("captures")
		end,
		parent = row,
	})
end

function App:_renderUploadedInfo(selected: any, nextOrder: () -> number, content: Frame)
	local captures = self._captures
	-- Read-only, selectable, so the id can be copied.
	local idBox = new("TextBox", {
		Text = "rbxassetid://" .. tostring(selected.assetId),
		TextEditable = false,
		ClearTextOnFocus = false,
		FontFace = Theme.Font.Regular,
		TextSize = Theme.TextSize.Small,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, Theme.RowHeight),
		LayoutOrder = nextOrder(),
		Theme = { BackgroundColor3 = C.InputFieldBackground, TextColor3 = C.MainText },
		Children = { Components.Corner(4), Components.Padding(0, 8, 0, 8) },
		Parent = content,
	})
	Components.Stroke(C.InputFieldBorder).Parent = idBox

	if captures:HasPlane(selected) then
		hint(
			"Uploaded. Its plane is in ServerStorage › "
				.. captures.FolderName
				.. " with this view in its attributes. Deleting it here only removes it from the gallery.",
			nextOrder(),
			content
		)
	else
		hint(
			"Uploaded, but its plane isn't in this place's ServerStorage. Add it back from the existing upload; nothing is uploaded again.",
			nextOrder(),
			content
		)
		local row = buttonRow(nextOrder(), content)
		Components.Button({
			text = "Add plane",
			icon = Theme.Icons.Add,
			onClick = function()
				local err = captures:AddPlane(selected.id)
				self:Notify(err or ("Added “" .. selected.name .. "” to ServerStorage."))
			end,
			parent = row,
		})
	end
end

function App:_render_captures(content: Frame, maid: any)
	local captures = self._captures
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	local selected = captures:Get(self._selectedCapture or -1)

	if selected then
		local row = buttonRow(nextOrder(), content)
		Components.Button({
			text = "All captures",
			icon = Theme.Icons.ArrowLeft,
			style = "ghost",
			onClick = function()
				self._selectedCapture = nil
				self._confirmUpload = nil
				self:_renderPage("captures")
			end,
			parent = row,
		})
		local preview = new("ImageLabel", {
			Image = selected.content,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.new(1, 0, 0, 200),
			LayoutOrder = nextOrder(),
			Theme = { BackgroundColor3 = C.InputFieldBackground },
			Children = { Components.Corner(6) },
			Parent = content,
		})
		uploadBadge(selected, function()
			self:_openCapture(selected, true)
		end, preview)
		-- Fit the preview to the capture's aspect ratio, capped so tall
		-- viewports don't push everything else off screen.
		local function fitPreview()
			local width = preview.AbsoluteSize.X
			if width > 0 then
				preview.Size = UDim2.new(1, 0, 0, math.min(math.round(width / (selected.aspect or 16 / 9)), 420))
			end
		end
		maid:Give(preview:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPreview))
		task.defer(fitPreview)

		Components.Text({
			Text = selected.name,
			FontFace = Theme.Font.Medium,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = nextOrder(),
			Parent = content,
		})
		local position = selected.cframe.Position
		hint(
			string.format(
				"FOV %d° · (%d, %d, %d)%s",
				math.round(selected.fov),
				math.round(position.X),
				math.round(position.Y),
				math.round(position.Z),
				if captures:IsFromThisPlace(selected) then "" else " · from " .. selected.placeName
			),
			nextOrder(),
			content
		)

		local actionRow = buttonRow(nextOrder(), content)
		local goButton = Components.Button({
			text = "Go to view",
			style = "primary",
			onClick = function()
				local err = self._runtime:GoToCapture(selected.id)
				if err then
					self:Notify(err)
				end
			end,
			parent = actionRow,
		})
		goButton.SetEnabled(captures:IsFromThisPlace(selected))
		local uploadButton = Components.Button({
			text = if selected.saving then "Uploading…" elseif selected.uploaded then "Uploaded" else "Upload…",
			icon = if selected.uploaded then Theme.Icons.Check else Theme.Icons.Upload,
			onClick = function()
				self:_openCapture(selected, true)
			end,
			parent = actionRow,
		})
		uploadButton.SetEnabled(not selected.uploaded and not selected.saving and self._confirmUpload ~= selected.id)
		Components.Button({
			text = if self._confirmCaptureDelete then "Confirm" else "Delete",
			icon = Theme.Icons.Delete,
			style = if self._confirmCaptureDelete then "danger" else "ghost",
			onClick = function()
				if self._confirmCaptureDelete then
					self._confirmCaptureDelete = false
					self._selectedCapture = nil
					self._confirmUpload = nil
					captures:Remove(selected.id)
				else
					self._confirmCaptureDelete = true
					self:_renderPage("captures")
					task.delay(3, function()
						if self._confirmCaptureDelete then
							self._confirmCaptureDelete = false
							self:_renderPage("captures")
						end
					end)
				end
			end,
			parent = actionRow,
		})

		if self._confirmUpload == selected.id and not selected.uploaded and not selected.saving then
			self:_renderUploadPrompt(selected, nextOrder(), content)
		elseif selected.uploaded and selected.assetId then
			self:_renderUploadedInfo(selected, nextOrder, content)
		elseif selected.saving then
			hint("Uploading to your account…", nextOrder(), content)
		else
			hint(
				"This capture lasts for this Studio session. Upload it to keep it and add an exportable plane to ServerStorage.",
				nextOrder(),
				content
			)
		end
		return
	end

	local row = buttonRow(nextOrder(), content)
	Components.Button({
		text = "Take screenshot",
		style = "primary",
		onClick = function()
			self._runtime:TakeScreenshot()
		end,
		parent = row,
	})
	local unsaved = captures:CountUnsaved()
	if unsaved > 0 then
		Components.Button({
			text = if self._confirmClear then string.format("Confirm clear (%d)", unsaved) else "Clear unsaved",
			style = if self._confirmClear then "danger" else "ghost",
			onClick = function()
				if self._confirmClear then
					self._confirmClear = false
					captures:ClearUnsaved()
					self:Notify("Cleared captures that weren't uploaded.")
				else
					self._confirmClear = true
					self:_renderPage("captures")
					task.delay(3, function()
						if self._confirmClear then
							self._confirmClear = false
							self:_renderPage("captures")
						end
					end)
				end
			end,
			parent = row,
		})
	end

	if #captures.list == 0 then
		local empty = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = nextOrder(),
			Children = {
				Components.Padding(24, 8, 24, 8),
				Components.List(Enum.FillDirection.Vertical, 8, {
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
				}),
			},
			Parent = content,
		})
		Components.Text({
			Text = "No captures yet",
			FontFace = Theme.Font.Medium,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = 1,
			Parent = empty,
		})
		local binding = self._store:GetActiveProfile().bindings.screenshot
		local how = if binding
			then "Press " .. bindingText(self._gamepad, binding) .. " while controller mode is on, or use the button above."
			else "Use the button above, or bind Take screenshot on the Bindings tab."
		local label = hint(how, 2, empty)
		label.TextXAlignment = Enum.TextXAlignment.Center
		return
	end

	hint(
		"Upload a capture to keep it between sessions. Click one to view it or jump back to its view.",
		nextOrder(),
		content
	)

	local grid = new("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = nextOrder(),
		Children = {
			new("UIGridLayout", {
				CellSize = UDim2.new(0.5, -4, 0, 90),
				CellPadding = UDim2.fromOffset(8, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = content,
	})
	for index, capture in captures.list do
		local thumb = new("ImageButton", {
			Name = "Capture" .. capture.id,
			Image = capture.content,
			ScaleType = Enum.ScaleType.Crop,
			AutoButtonColor = false,
			LayoutOrder = index,
			Theme = { BackgroundColor3 = C.InputFieldBackground },
			Children = { Components.Corner(6) },
			Parent = grid,
		})
		local stroke = Components.Stroke(C.Border)
		stroke.Parent = thumb
		Components.Interact(thumb, function(state)
			if state == "Default" then
				Theme.Bind(stroke, "Color", C.Border)
				stroke.Thickness = 1
			else
				Theme.Bind(stroke, "Color", function()
					return Theme.Accent
				end)
				stroke.Thickness = 2
			end
		end)
		thumb.Activated:Connect(function()
			self:_openCapture(capture, false)
		end)
		uploadBadge(capture, function()
			self:_openCapture(capture, true)
		end, thumb)
		if not captures:IsFromThisPlace(capture) then
			new("TextLabel", {
				Text = capture.placeName,
				BackgroundColor3 = BADGE_SURFACE,
				BackgroundTransparency = 0.35,
				TextColor3 = Color3.new(1, 1, 1),
				FontFace = Theme.Font.Regular,
				TextSize = 11,
				TextTruncate = Enum.TextTruncate.AtEnd,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 6, 1, -6),
				Size = UDim2.new(1, -12, 0, 16),
				ZIndex = 3,
				Children = { Components.Corner(4), Components.Padding(0, 4, 0, 4) },
				Parent = thumb,
			})
		end
	end
end

-- Controller page ------------------------------------------------------------------------

function App:_render_controller(content: Frame, maid: any)
	local gamepad = self._gamepad
	local store = self._store
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	-- Device card.
	local card = new("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		LayoutOrder = nextOrder(),
		Theme = { BackgroundColor3 = C.InputFieldBackground },
		Children = { Components.Corner(6), Components.Padding(8, 12, 8, 12) },
		Parent = content,
	})
	Components.Stroke(C.Border).Parent = card
	local deviceIcon = new("ImageLabel", {
		Image = Theme.GamepadIcon,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.fromOffset(0, 6),
		Parent = card,
	})
	Theme.Bind(deviceIcon, "ImageColor3", if gamepad:IsConnected() then C.MainText else C.DimmedText)
	Components.Text({
		Text = gamepad:DisplayName(),
		FontFace = Theme.Font.Medium,
		Position = UDim2.fromOffset(40, 2),
		Size = UDim2.new(1, -40, 0, 18),
		Parent = card,
	})
	Components.Text({
		Text = if gamepad:IsConnected()
			then string.format("Gamepad %d · %d connected", gamepad:SlotNumber() or 1, #gamepad.connected)
			else "Plug in or pair a controller to get started.",
		TextSize = Theme.TextSize.Small,
		Color = C.DimmedText,
		Position = UDim2.fromOffset(40, 20),
		Size = UDim2.new(1, -40, 0, 16),
		Parent = card,
	})

	-- Pad selection.
	Components.SectionHeader("Use controller", nextOrder(), content)
	local items = { { id = "Auto", label = "Automatic (last used)" } }
	for index, slot in gamepad.Slots do
		local connected = table.find(gamepad.connected, slot) ~= nil
		if connected or store:GetRuntime("gamepad") == slot.Name then
			table.insert(items, {
				id = slot.Name,
				label = "Gamepad " .. index,
				detail = if connected then nil else "Not connected",
			})
		end
	end
	Components.Dropdown({
		items = items,
		selected = store:GetRuntime("gamepad"),
		overlayHost = self._overlay,
		onSelect = function(id)
			store:SetRuntime("gamepad", id)
			gamepad:SetPreference(id)
		end,
		layoutOrder = nextOrder(),
		parent = content,
	})

	-- Live tester.
	Components.SectionHeader("Input tester", nextOrder(), content)
	hint("Studio only receives controller input while its window is focused.", nextOrder(), content)
	local tester = new("Frame", {
		Name = "Tester",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = nextOrder(),
		Theme = { BackgroundColor3 = C.InputFieldBackground },
		Children = {
			Components.Corner(6),
			Components.Padding(12, 12, 12, 12),
			Components.List(Enum.FillDirection.Vertical, 12),
		},
		Parent = content,
	})
	Components.Stroke(C.Border).Parent = tester

	local sticksRow = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 84),
		LayoutOrder = 1,
		Children = {
			Components.List(Enum.FillDirection.Horizontal, 12, {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			}),
		},
		Parent = tester,
	})
	local stickDots = {}
	local triggerFills = {}
	local function trigger(key: string, order: number)
		local holder = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(18, 84),
			LayoutOrder = order,
			Parent = sticksRow,
		})
		local bar = new("Frame", {
			Size = UDim2.new(0, 8, 0, 64),
			Position = UDim2.fromOffset(5, 0),
			Theme = { BackgroundColor3 = C.MainBackground },
			ClipsDescendants = true,
			Children = { Components.Corner(4), Components.Stroke(C.InputFieldBorder) },
			Parent = holder,
		})
		triggerFills[key] = new("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Theme.Accent,
			Parent = bar,
		})
		Components.Text({
			Text = gamepad:InputName(key),
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			Color = C.DimmedText,
			Position = UDim2.new(0, -6, 0, 68),
			Size = UDim2.new(1, 12, 0, 14),
			Parent = holder,
		})
	end
	local function stick(key: string, label: string, order: number)
		local holder = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(64, 84),
			LayoutOrder = order,
			Parent = sticksRow,
		})
		local ring = new("Frame", {
			Size = UDim2.fromOffset(64, 64),
			Theme = { BackgroundColor3 = C.MainBackground },
			Children = { Components.Corner(32) },
			Parent = holder,
		})
		Components.Stroke(C.InputFieldBorder).Parent = ring
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -2, 0, 1),
			Theme = { BackgroundColor3 = C.Border },
			Parent = ring,
		})
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 1, 1, -2),
			Theme = { BackgroundColor3 = C.Border },
			Parent = ring,
		})
		stickDots[key] = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = Theme.Accent,
			ZIndex = 2,
			Children = { Components.Corner(7) },
			Parent = ring,
		})
		Components.Text({
			Text = label,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			Color = C.DimmedText,
			Position = UDim2.fromOffset(0, 68),
			Size = UDim2.new(1, 0, 0, 14),
			Parent = holder,
		})
	end
	trigger("ButtonL2", 1)
	stick("Thumbstick1", "Left stick", 2)
	stick("Thumbstick2", "Right stick", 3)
	trigger("ButtonR2", 4)

	local buttonGrid = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Children = {
			new("UIGridLayout", {
				CellSize = UDim2.fromOffset(30, 30),
				CellPadding = UDim2.fromOffset(6, 6),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = tester,
	})
	local buttonCells = {}
	for index, input in Inputs.List do
		if input.kind ~= "button" then
			continue
		end
		local cell = new("Frame", {
			Name = input.key,
			LayoutOrder = index,
			BackgroundTransparency = 1,
			Children = { Components.Corner(15) },
			Parent = buttonGrid,
		})
		local image = gamepad:Glyph(input.key)
		local glyph
		if image ~= "" then
			glyph = new("ImageLabel", {
				Image = image,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(24, 24),
				ImageTransparency = 0.55,
				Theme = { ImageColor3 = C.MainText },
				Parent = cell,
			})
		else
			glyph = Components.Text({
				Text = gamepad:InputName(input.key),
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.fromScale(1, 1),
				TextTransparency = 0.55,
				Parent = cell,
			})
		end
		buttonCells[input.key] = { cell = cell, glyph = glyph }
	end

	self._tester = { sticks = stickDots, triggers = triggerFills, buttons = buttonCells }
	maid:Give(function()
		self._tester = nil
	end)

	-- About.
	Components.Divider(nextOrder(), content)
	Components.SectionHeader("About", nextOrder(), content)
	hint(
		"Studio Controller Pro "
			.. VERSION
			.. ". Fly the edit camera with a gamepad, with custom bindings and profiles.",
		nextOrder(),
		content
	)
	hint(
		"Tip: bind a keyboard shortcut to “Toggle Controller Mode” in File › Customize Shortcuts.",
		nextOrder(),
		content
	)
	local row = buttonRow(nextOrder(), content)
	Components.Button({
		text = "Show welcome",
		icon = Theme.Icons.Info,
		style = "ghost",
		onClick = function()
			self:ShowWelcome()
		end,
		parent = row,
	})
end

-- Called every frame by the runtime while the Controller tab is visible.
function App:UpdateTester(frame: any)
	local tester = self._tester
	if not tester then
		return
	end
	for key, dot in tester.sticks do
		local value = frame.sticks[key] or Vector2.zero
		dot.Position = UDim2.new(0.5, value.X * 25, 0.5, -value.Y * 25)
	end
	for key, fill in tester.triggers do
		fill.Size = UDim2.fromScale(1, frame.values[key] or 0)
	end
	for key, entry in tester.buttons do
		local isDown = frame.down[key] == true
		entry.cell.BackgroundTransparency = if isDown then 0.6 else 1
		entry.cell.BackgroundColor3 = Theme.Accent
		if entry.glyph:IsA("ImageLabel") then
			entry.glyph.ImageTransparency = if isDown then 0 else 0.55
		else
			entry.glyph.TextTransparency = if isDown then 0 else 0.55
		end
	end
end

function App:Destroy()
	if self._welcome then
		self._welcome.maid:Clean()
	end
	for _, maid in self._pageMaids do
		maid:Clean()
	end
	self._maid:Clean()
	self.Widget:Destroy()
end

return App
