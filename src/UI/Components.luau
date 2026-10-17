--[[
	Small set of Studio-styled UI building blocks. Everything is plain
	Instances with theme bindings (see Theme.Bind), so the panel follows the
	Studio theme without a UI framework.
]]

local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)

local C = Theme.Color
local M = Theme.Modifier

local Components = {}

-- Instance helper ------------------------------------------------------------

-- props may contain:
--   Theme = { Property = token }       bound theme colors
--   Icon = { Property = iconPath }     bound theme icons
--   Events = { EventName = handler }
--   Children = { Instance }
function Components.new(className: string, props: { [string]: any }?): any
	local instance = Instance.new(className)
	local themeProps, iconProps, events, children, parent
	if props then
		for key, value in props do
			if key == "Theme" then
				themeProps = value
			elseif key == "Icon" then
				iconProps = value
			elseif key == "Events" then
				events = value
			elseif key == "Children" then
				children = value
			elseif key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if instance:IsA("GuiObject") and not (props and props.BorderSizePixel) then
		(instance :: any).BorderSizePixel = 0
	end
	if themeProps then
		for property, token in themeProps do
			Theme.Bind(instance, property, token)
		end
	end
	if iconProps then
		for property, path in iconProps do
			Theme.BindIcon(instance, property, path)
		end
	end
	if events then
		for name, handler in events do
			(instance :: any)[name]:Connect(handler)
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local new = Components.new

function Components.Corner(radius: number?): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 4) })
end

function Components.Padding(top: number, right: number?, bottom: number?, left: number?): UIPadding
	return new("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right or top),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, left or right or top),
	})
end

function Components.List(direction: Enum.FillDirection?, padding: number?, props: { [string]: any }?): UIListLayout
	local layoutProps = {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}
	if props then
		for key, value in props do
			layoutProps[key] = value
		end
	end
	return new("UIListLayout", layoutProps)
end

function Components.Stroke(token: any, thickness: number?): UIStroke
	return new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness = thickness or 1,
		Theme = { Color = token },
	})
end

function Components.Text(props: { [string]: any }): TextLabel
	local textProps = {
		BackgroundTransparency = 1,
		FontFace = props.FontFace or Theme.Font.Regular,
		TextSize = props.TextSize or Theme.TextSize.Body,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left,
		TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center,
		TextTruncate = props.TextTruncate or Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = props.Color or C.MainText },
	}
	for key, value in props do
		if key ~= "Color" then
			textProps[key] = value
		end
	end
	return new("TextLabel", textProps)
end

function Components.Icon(path: string, size: number, props: { [string]: any }?): ImageLabel
	local iconProps = {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		ScaleType = Enum.ScaleType.Fit,
		Icon = { Image = path },
	}
	if props then
		for key, value in props do
			iconProps[key] = value
		end
	end
	return new("ImageLabel", iconProps)
end

function Components.TextWidth(text: string, size: number, font: Font): number
	local params = Instance.new("GetTextBoundsParams")
	params.Text = text
	params.Size = size
	params.Font = font
	params.Width = math.huge
	local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
	return if ok then math.ceil(bounds.X) else #text * size * 0.55
end

-- Hover / press tracking shared by interactive elements.
function Components.Interact(button: GuiButton, onState: (state: "Default" | "Hover" | "Pressed") -> ())
	local hovered, pressed = false, false
	local function update()
		onState(if pressed then "Pressed" elseif hovered then "Hover" else "Default")
	end
	button.MouseEnter:Connect(function()
		hovered = true
		update()
	end)
	button.MouseLeave:Connect(function()
		hovered, pressed = false, false
		update()
	end)
	button.MouseButton1Down:Connect(function()
		pressed = true
		update()
	end)
	button.MouseButton1Up:Connect(function()
		pressed = false
		update()
	end)
	update()
end

-- Button -----------------------------------------------------------------------

export type ButtonStyle = "primary" | "secondary" | "ghost" | "danger"

local BUTTON_COLORS = {
	primary = { bg = C.DialogMainButton, text = C.DialogMainButtonText, border = C.DialogMainButton },
	secondary = { bg = C.Button, text = C.ButtonText, border = C.ButtonBorder },
	ghost = { bg = C.MainBackground, text = C.MainText, border = nil },
	danger = { bg = C.Button, text = C.ErrorText, border = C.ButtonBorder },
}

function Components.Button(props: {
	text: string?,
	icon: string?,
	iconRotation: number?,
	style: ButtonStyle?,
	onClick: (() -> ())?,
	size: UDim2?,
	layoutOrder: number?,
	parent: Instance?,
	autoWidth: boolean?,
})
	local style = props.style or "secondary"
	local palette = BUTTON_COLORS[style]
	local enabled = true

	local button = new("TextButton", {
		Name = props.text or "Button",
		AutoButtonColor = false,
		Text = "",
		Size = props.size or UDim2.new(0, 0, 0, Theme.RowHeight),
		AutomaticSize = if props.autoWidth ~= false and not props.size
			then Enum.AutomaticSize.X
			else Enum.AutomaticSize.None,
		LayoutOrder = props.layoutOrder or 0,
		Children = {
			Components.Corner(4),
			Components.Padding(0, if props.text then 12 else 6, 0, if props.text then 12 else 6),
			Components.List(Enum.FillDirection.Horizontal, 6, {
				VerticalAlignment = Enum.VerticalAlignment.Center,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			}),
		},
	})
	local stroke = if palette.border then Components.Stroke(palette.border) else nil
	if stroke then
		stroke.Parent = button
	end

	local icon
	if props.icon then
		icon = Components.Icon(props.icon, 16, { LayoutOrder = 1, Rotation = props.iconRotation or 0, Parent = button })
	end
	local label
	if props.text then
		label = Components.Text({
			Text = props.text,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			FontFace = Theme.Font.Medium,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
			Color = palette.text,
			LayoutOrder = 2,
			Parent = button,
		})
	end

	local currentState = "Default"
	local function paint()
		local modifier = if not enabled
			then M.Disabled
			elseif currentState == "Pressed" then M.Pressed
			elseif currentState == "Hover" then M.Hover
			else M.Default
		if style == "ghost" then
			Theme.Bind(
				button,
				"BackgroundColor3",
				if modifier == M.Default or modifier == M.Disabled then C.MainBackground else { C.Button, modifier }
			)
			button.BackgroundTransparency = if modifier == M.Default or modifier == M.Disabled then 1 else 0
		else
			Theme.Bind(button, "BackgroundColor3", { palette.bg, modifier })
		end
		if label then
			Theme.Bind(label, "TextColor3", { palette.text, if enabled then M.Default else M.Disabled })
		end
		if icon then
			icon.ImageTransparency = if enabled then 0 else 0.5
		end
	end
	Components.Interact(button, function(state)
		currentState = state
		paint()
	end)
	button.Activated:Connect(function()
		if enabled and props.onClick then
			props.onClick()
		end
	end)

	local api = {}
	api.Instance = button
	function api.SetText(text: string)
		if label then
			label.Text = text
		end
	end
	function api.SetEnabled(value: boolean)
		enabled = value
		button.Active = value
		paint()
	end
	paint()
	if props.parent then
		button.Parent = props.parent
	end
	return api
end

function Components.IconButton(props: {
	icon: string,
	onClick: (() -> ())?,
	size: number?,
	layoutOrder: number?,
	parent: Instance?,
	tooltip: string?,
})
	local size = props.size or 24
	local button = new("ImageButton", {
		Name = props.tooltip or "IconButton",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 0,
		Theme = { BackgroundColor3 = C.Button },
		Children = { Components.Corner(4) },
	})
	local icon = Components.Icon(props.icon, math.min(16, size - 6), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = button,
	})
	local enabled = true
	Components.Interact(button, function(state)
		button.BackgroundTransparency = if state == "Default" or not enabled then 1 else 0
		Theme.Bind(button, "BackgroundColor3", { C.Button, if state == "Pressed" then M.Pressed else M.Hover })
	end)
	button.Activated:Connect(function()
		Components.HideTooltip()
		if enabled and props.onClick then
			props.onClick()
		end
	end)
	if props.tooltip then
		Components.AttachTooltip(button, props.tooltip)
	end
	if props.parent then
		button.Parent = props.parent
	end
	return {
		Instance = button,
		SetEnabled = function(value: boolean)
			enabled = value
			icon.ImageTransparency = if value then 0 else 0.6
		end,
	}
end

-- Tooltip -----------------------------------------------------------------------

local TOOLTIP_DELAY = 0.4
local tooltipHost: GuiObject? = nil
local tooltip: Frame? = nil
local tooltipToken = 0

-- The host is a full-size, top-most frame in the widget.
function Components.SetTooltipHost(host: GuiObject)
	tooltipHost = host
end

function Components.HideTooltip()
	tooltipToken += 1
	if tooltip then
		tooltip:Destroy()
		tooltip = nil
	end
end

local function showTooltip(target: GuiObject, text: string)
	Components.HideTooltip()
	local host = tooltipHost
	if not host or not target:IsDescendantOf(host.Parent :: Instance) then
		return
	end
	local frame = new("Frame", {
		Name = "Tooltip",
		AutomaticSize = Enum.AutomaticSize.XY,
		ZIndex = 50,
		Theme = { BackgroundColor3 = C.Tooltip },
		Children = { Components.Corner(4), Components.Padding(4, 8, 4, 8) },
		Parent = host,
	})
	Components.Stroke(C.Border).Parent = frame
	Components.Text({
		Text = text,
		TextSize = Theme.TextSize.Small,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = 51,
		Parent = frame,
	})
	tooltip = frame
	-- Position below the target, kept inside the host.
	task.defer(function()
		if tooltip ~= frame then
			return
		end
		local hostPosition, hostSize = host.AbsolutePosition, host.AbsoluteSize
		local size = frame.AbsoluteSize
		local x = target.AbsolutePosition.X - hostPosition.X + target.AbsoluteSize.X / 2 - size.X / 2
		local y = target.AbsolutePosition.Y - hostPosition.Y + target.AbsoluteSize.Y + 4
		if y + size.Y > hostSize.Y - 4 then
			y = target.AbsolutePosition.Y - hostPosition.Y - size.Y - 4
		end
		frame.Position = UDim2.fromOffset(math.clamp(x, 4, math.max(4, hostSize.X - size.X - 4)), y)
	end)
end

function Components.AttachTooltip(target: GuiObject, text: string)
	target.MouseEnter:Connect(function()
		tooltipToken += 1
		local token = tooltipToken
		task.delay(TOOLTIP_DELAY, function()
			if token == tooltipToken and target.Parent then
				showTooltip(target, text)
			end
		end)
	end)
	target.MouseLeave:Connect(Components.HideTooltip)
	target.AncestryChanged:Connect(function()
		if not target:IsDescendantOf(game) then
			Components.HideTooltip()
		end
	end)
end

-- Checkbox ---------------------------------------------------------------------

function Components.Checkbox(props: {
	label: string,
	description: string?,
	value: boolean,
	onChange: (boolean) -> (),
	layoutOrder: number?,
	parent: Instance?,
})
	local value = props.value
	local row = new("TextButton", {
		Name = props.label,
		AutoButtonColor = false,
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = props.layoutOrder or 0,
	})
	local box = new("Frame", {
		Name = "Box",
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.fromOffset(0, 6),
		Children = { Components.Corner(3) },
		Parent = row,
	})
	local boxStroke = Components.Stroke(C.CheckedFieldBorder)
	boxStroke.Parent = box
	local check = Components.Icon(Theme.Icons.Check, 14, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = box,
	})
	local text = new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(26, 0),
		Size = UDim2.new(1, -26, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Children = {
			Components.List(Enum.FillDirection.Vertical, 0),
			Components.Padding(4, 0, 4, 0),
			Components.Text({
				Text = props.label,
				Size = UDim2.new(1, 0, 0, 20),
				LayoutOrder = 1,
			}),
		},
		Parent = row,
	})
	if props.description then
		Components.Text({
			Text = props.description,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextSize = Theme.TextSize.Small,
			Color = C.DimmedText,
			LayoutOrder = 2,
			Parent = text,
		})
	end

	local hovered = false
	local function paint()
		check.Visible = value
		if value then
			Theme.Bind(box, "BackgroundColor3", function()
				return Theme.Accent
			end)
			Theme.Bind(boxStroke, "Color", function()
				return Theme.Accent
			end)
			-- The checkmark sits on the accent fill, so always use the light glyph.
			Theme.BindIcon(check, "Image", "Shared/Ribbon/Dark/Standard/Checkmark")
		else
			Theme.Bind(box, "BackgroundColor3", { C.CheckedFieldBackground, if hovered then M.Hover else M.Default })
			Theme.Bind(boxStroke, "Color", { C.CheckedFieldBorder, if hovered then M.Hover else M.Default })
		end
	end
	row.MouseEnter:Connect(function()
		hovered = true
		paint()
	end)
	row.MouseLeave:Connect(function()
		hovered = false
		paint()
	end)
	row.Activated:Connect(function()
		value = not value
		paint()
		props.onChange(value)
	end)
	paint()
	if props.parent then
		row.Parent = props.parent
	end
	return {
		Instance = row,
		Set = function(newValue: boolean)
			value = newValue
			paint()
		end,
	}
end

-- Slider -----------------------------------------------------------------------

function Components.Slider(props: {
	label: string,
	description: string?,
	min: number,
	max: number,
	step: number,
	value: number,
	format: (number) -> string,
	onChange: (number) -> (),
	layoutOrder: number?,
	parent: Instance?,
})
	local value = props.value
	local row = new("Frame", {
		Name = props.label,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = props.layoutOrder or 0,
		Children = { Components.List(Enum.FillDirection.Vertical, 2) },
	})
	local header = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 1,
		Parent = row,
	})
	Components.Text({ Text = props.label, Size = UDim2.new(1, -76, 1, 0), Parent = header })
	local valueBox = new("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(70, 22),
		ClearTextOnFocus = false,
		FontFace = Theme.Font.Regular,
		TextSize = Theme.TextSize.Small,
		TextXAlignment = Enum.TextXAlignment.Right,
		Theme = {
			BackgroundColor3 = C.InputFieldBackground,
			TextColor3 = C.MainText,
		},
		Children = { Components.Corner(4), Components.Padding(0, 6, 0, 6) },
		Parent = header,
	})
	local valueStroke = Components.Stroke(C.InputFieldBorder)
	valueStroke.Parent = valueBox

	local track = new("TextButton", {
		Name = "Track",
		AutoButtonColor = false,
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 2,
		Parent = row,
	})
	local rail = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, 4),
		Theme = { BackgroundColor3 = C.InputFieldBorder },
		Children = { Components.Corner(2) },
		Parent = track,
	})
	local fill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Accent,
		Children = { Components.Corner(2) },
		Parent = rail,
	})
	local thumb = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 2,
		Children = { Components.Corner(6) },
		Parent = track,
	})
	local thumbStroke = Components.Stroke(function()
		return Theme.Accent
	end, 2)
	thumbStroke.Parent = thumb

	if props.description then
		Components.Text({
			Text = props.description,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextSize = Theme.TextSize.Small,
			Color = C.DimmedText,
			LayoutOrder = 3,
			Parent = row,
		})
	end

	local function quantize(raw: number): number
		local stepped = math.round((raw - props.min) / props.step) * props.step + props.min
		-- Trim float noise from the step math.
		stepped = math.round(stepped * 1e4) / 1e4
		return math.clamp(stepped, props.min, props.max)
	end

	local function render()
		local alpha = (value - props.min) / (props.max - props.min)
		fill.Size = UDim2.fromScale(alpha, 1)
		thumb.Position = UDim2.fromScale(alpha, 0.5)
		if not valueBox:IsFocused() then
			valueBox.Text = props.format(value)
		end
	end

	local function set(newValue: number, notify: boolean)
		newValue = quantize(newValue)
		if newValue == value then
			render()
			return
		end
		value = newValue
		render()
		if notify then
			props.onChange(value)
		end
	end

	local dragging = false
	local function fromX(x: number)
		local alpha = math.clamp((x - rail.AbsolutePosition.X) / math.max(rail.AbsoluteSize.X, 1), 0, 1)
		set(props.min + alpha * (props.max - props.min), true)
	end
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			thumb.Size = UDim2.fromOffset(14, 14)
			fromX(input.Position.X)
		end
	end)
	track.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			fromX(input.Position.X)
		end
	end)
	track.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			thumb.Size = UDim2.fromOffset(12, 12)
		end
	end)
	track.MouseLeave:Connect(function()
		-- Plugin widgets don't capture the mouse, so a drag that leaves the
		-- track ends there rather than getting stuck.
		if dragging then
			dragging = false
			thumb.Size = UDim2.fromOffset(12, 12)
		end
	end)

	valueBox.Focused:Connect(function()
		Theme.Bind(valueStroke, "Color", function()
			return Theme.Accent
		end)
		valueBox.Text = tostring(value)
		valueBox.SelectionStart = 1
		valueBox.CursorPosition = #valueBox.Text + 1
	end)
	valueBox.FocusLost:Connect(function()
		Theme.Bind(valueStroke, "Color", C.InputFieldBorder)
		local parsed = tonumber((string.gsub(valueBox.Text, "[^%d%.%-]", "")))
		if parsed then
			set(parsed, true)
		end
		valueBox.Text = props.format(value)
	end)

	render()
	if props.parent then
		row.Parent = props.parent
	end
	return {
		Instance = row,
		Set = function(newValue: number)
			value = newValue
			render()
		end,
	}
end

-- Section header ----------------------------------------------------------------

function Components.SectionHeader(title: string, layoutOrder: number?, parent: Instance?): Frame
	return new("Frame", {
		Name = "Section_" .. title,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = layoutOrder or 0,
		Children = {
			Components.Text({
				Text = title,
				FontFace = Theme.Font.Bold,
				TextSize = Theme.TextSize.Body,
				Size = UDim2.new(1, 0, 0, 20),
				Position = UDim2.fromOffset(0, 8),
			}),
		},
		Parent = parent,
	})
end

function Components.Divider(layoutOrder: number?, parent: Instance?): Frame
	return new("Frame", {
		Name = "Divider",
		Size = UDim2.new(1, 0, 0, 1),
		LayoutOrder = layoutOrder or 0,
		Theme = { BackgroundColor3 = C.Border },
		Parent = parent,
	})
end

-- Scrolling page ---------------------------------------------------------------

function Components.Page(name: string): (ScrollingFrame, Frame)
	local scroller = new("ScrollingFrame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		Theme = { ScrollBarImageColor3 = C.ScrollBar },
		Visible = false,
	})
	local content = new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Children = {
			Components.List(Enum.FillDirection.Vertical, 8),
			Components.Padding(Theme.Padding, Theme.Padding, Theme.Padding + 8, Theme.Padding),
		},
		Parent = scroller,
	})
	return scroller, content
end

-- Dropdown ----------------------------------------------------------------------

export type DropdownItem = { id: string, label: string, detail: string? }

-- `overlayHost` is a full-size frame (ZIndex above content) that hosts the
-- open menu so it isn't clipped by scrolling containers.
function Components.Dropdown(props: {
	items: { DropdownItem },
	selected: string?,
	onSelect: (string) -> (),
	overlayHost: GuiObject,
	size: UDim2?,
	layoutOrder: number?,
	parent: Instance?,
})
	local items = props.items
	local selected = props.selected
	local button = new("TextButton", {
		Name = "Dropdown",
		AutoButtonColor = false,
		Text = "",
		Size = props.size or UDim2.new(1, 0, 0, Theme.RowHeight),
		LayoutOrder = props.layoutOrder or 0,
		Theme = { BackgroundColor3 = C.InputFieldBackground },
		Children = { Components.Corner(4), Components.Padding(0, 6, 0, 10) },
	})
	local stroke = Components.Stroke(C.InputFieldBorder)
	stroke.Parent = button
	local label = Components.Text({ Text = "", Size = UDim2.new(1, -20, 1, 0), Parent = button })
	Components.Icon(Theme.Icons.Dropdown, 16, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Parent = button,
	})

	local menu: Frame? = nil
	local function close()
		if menu then
			menu:Destroy()
			menu = nil
			props.overlayHost.Visible = false
			Theme.Bind(stroke, "Color", C.InputFieldBorder)
		end
	end

	local function render()
		local text = ""
		for _, item in items do
			if item.id == selected then
				text = item.label
			end
		end
		label.Text = text
	end

	local function open()
		local host = props.overlayHost
		host.Visible = true
		Theme.Bind(stroke, "Color", function()
			return Theme.Accent
		end)
		for _, child in host:GetChildren() do
			child:Destroy()
		end
		-- Clicking anywhere outside the menu closes it.
		new("TextButton", {
			Name = "Dismiss",
			Text = "",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Events = { Activated = close },
			Parent = host,
		})
		local hostPosition = host.AbsolutePosition
		local top = button.AbsolutePosition.Y - hostPosition.Y + button.AbsoluteSize.Y + 4
		local itemHeight = 28
		local maxVisible = math.max(3, math.floor((host.AbsoluteSize.Y - top - 8) / itemHeight))
		local visible = math.min(#items, maxVisible)
		local list = new("ScrollingFrame", {
			Name = "Menu",
			Position = UDim2.fromOffset(button.AbsolutePosition.X - hostPosition.X, top),
			Size = UDim2.fromOffset(button.AbsoluteSize.X, visible * itemHeight + 8),
			CanvasSize = UDim2.fromOffset(0, #items * itemHeight + 8),
			ScrollBarThickness = if #items > visible then 6 else 0,
			ZIndex = 10,
			Theme = { BackgroundColor3 = C.Dropdown, ScrollBarImageColor3 = C.ScrollBar },
			Children = {
				Components.Corner(4),
				Components.Padding(4, 4, 4, 4),
				Components.List(Enum.FillDirection.Vertical, 0),
			},
			Parent = host,
		})
		Components.Stroke(C.Border).Parent = list
		menu = list
		for index, item in items do
			local option = new("TextButton", {
				Name = item.id,
				AutoButtonColor = false,
				Text = "",
				Size = UDim2.new(1, 0, 0, itemHeight),
				LayoutOrder = index,
				ZIndex = 11,
				Children = { Components.Corner(3), Components.Padding(0, 8, 0, 8) },
				Parent = list,
			})
			local optionLabel = Components.Text({
				Text = item.label,
				Size = UDim2.new(1, if item.detail then -60 else -20, 1, 0),
				FontFace = if item.id == selected then Theme.Font.Medium else Theme.Font.Regular,
				ZIndex = 12,
				Parent = option,
			})
			if item.detail then
				Components.Text({
					Text = item.detail,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -20, 0, 0),
					Size = UDim2.new(0, 60, 1, 0),
					TextXAlignment = Enum.TextXAlignment.Right,
					TextSize = Theme.TextSize.Small,
					Color = C.DimmedText,
					ZIndex = 12,
					Parent = option,
				})
			end
			if item.id == selected then
				Components.Icon(Theme.Icons.Check, 14, {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0),
					ZIndex = 12,
					Parent = option,
				})
			end
			Components.Interact(option, function(state)
				option.BackgroundTransparency = if state == "Default" then 1 else 0
				Theme.Bind(option, "BackgroundColor3", { C.Item, M.Hover })
			end)
			option.Activated:Connect(function()
				close()
				if item.id ~= selected then
					selected = item.id
					render()
					props.onSelect(item.id)
				end
			end)
			optionLabel.Name = "Label"
		end
	end

	button.Activated:Connect(function()
		if menu then
			close()
		else
			open()
		end
	end)
	Components.Interact(button, function(state)
		if not menu then
			Theme.Bind(stroke, "Color", { C.InputFieldBorder, if state == "Default" then M.Default else M.Hover })
		end
	end)

	render()
	if props.parent then
		button.Parent = props.parent
	end
	return {
		Instance = button,
		Set = function(newItems: { DropdownItem }?, newSelected: string?)
			if newItems then
				items = newItems
			end
			selected = newSelected
			render()
		end,
		Close = close,
	}
end

-- Tabs ---------------------------------------------------------------------------

function Components.Tabs(props: {
	tabs: { { id: string, label: string } },
	onSelect: (string) -> (),
	parent: Instance?,
})
	local bar = new("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, 32),
		Theme = { BackgroundColor3 = C.MainBackground },
	})
	local divider = Components.Divider(0, bar)
	divider.AnchorPoint = Vector2.new(0, 1)
	divider.Position = UDim2.new(0, 0, 1, 0)
	local strip = new("Frame", {
		Name = "Strip",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Children = {
			Components.List(Enum.FillDirection.Horizontal, 0),
			Components.Padding(0, 4, 0, 4),
		},
		Parent = bar,
	})

	local buttons = {}
	local selected = nil
	local function paint()
		for id, entry in buttons do
			local isSelected = id == selected
			entry.indicator.Visible = isSelected
			entry.label.FontFace = if isSelected then Theme.Font.Medium else Theme.Font.Regular
			Theme.Bind(entry.label, "TextColor3", if isSelected or entry.hovered then C.MainText else C.SubText)
		end
	end
	for index, tab in props.tabs do
		local button = new("TextButton", {
			Name = tab.id,
			AutoButtonColor = false,
			Text = "",
			BackgroundTransparency = 1,
			Size = UDim2.new(1 / #props.tabs, 0, 1, 0),
			LayoutOrder = index,
			Parent = strip,
		})
		local label = Components.Text({
			Text = tab.label,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = Theme.TextSize.Body,
			Parent = button,
		})
		local indicator = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.new(1, -8, 0, 2),
			BackgroundColor3 = Theme.Accent,
			ZIndex = 2,
			Children = { Components.Corner(1) },
			Parent = button,
		})
		local entry = { label = label, indicator = indicator, hovered = false }
		buttons[tab.id] = entry
		button.MouseEnter:Connect(function()
			entry.hovered = true
			paint()
		end)
		button.MouseLeave:Connect(function()
			entry.hovered = false
			paint()
		end)
		button.Activated:Connect(function()
			if selected ~= tab.id then
				selected = tab.id
				paint()
				props.onSelect(tab.id)
			end
		end)
	end
	if props.parent then
		bar.Parent = props.parent
	end
	return {
		Instance = bar,
		Select = function(id: string)
			selected = id
			paint()
		end,
	}
end

-- Text area ----------------------------------------------------------------------

function Components.TextArea(props: {
	placeholder: string?,
	text: string?,
	height: number?,
	readOnly: boolean?,
	layoutOrder: number?,
	parent: Instance?,
}): TextBox
	local box = new("TextBox", {
		Name = "TextArea",
		Size = UDim2.new(1, 0, 0, props.height or 96),
		ClearTextOnFocus = false,
		MultiLine = true,
		TextWrapped = true,
		TextEditable = not props.readOnly,
		Text = props.text or "",
		PlaceholderText = props.placeholder or "",
		FontFace = Theme.Font.Mono,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ClipsDescendants = true,
		LayoutOrder = props.layoutOrder or 0,
		Theme = {
			BackgroundColor3 = C.InputFieldBackground,
			TextColor3 = C.MainText,
			PlaceholderColor3 = C.DimmedText,
		},
		Children = { Components.Corner(4), Components.Padding(6, 8, 6, 8) },
	})
	local stroke = Components.Stroke(C.InputFieldBorder)
	stroke.Parent = box
	box.Focused:Connect(function()
		Theme.Bind(stroke, "Color", function()
			return Theme.Accent
		end)
	end)
	box.FocusLost:Connect(function()
		Theme.Bind(stroke, "Color", C.InputFieldBorder)
	end)
	if props.parent then
		box.Parent = props.parent
	end
	return box
end

-- Used by the binding capture to ignore keyboard focus in text boxes.
function Components.IsTyping(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

return Components
