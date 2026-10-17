--[[
	Renders a binding (optional modifier + key) as controller glyphs. Shared by
	the panel and the HUD so both read the same way.

	Roblox's D-pad glyphs only differ by a tiny notch, so D-pad keys get a
	direction arrow next to the glyph to stay readable at small sizes.
]]

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local new = Components.new

local DPAD_ARROWS = {
	DPadUp = "ArrowUp",
	DPadDown = "ArrowDown",
	DPadLeft = "ArrowLeft",
	DPadRight = "ArrowRight",
}

local Glyphs = {}

export type Options = {
	size: number,
	-- Fixed colors for overlays drawn on dark surfaces; theme colors otherwise.
	onDark: boolean?,
	textColor: Color3?,
	dimColor: Color3?,
}

local function arrowIcon(direction: string, onDark: boolean?): string
	local path = "Shared/Navigation/{theme}/Standard/" .. direction
	if onDark then
		return "rbxasset://studio_svg_textures/" .. string.gsub(path, "{theme}", "Dark") .. "@2x.png"
	end
	return path
end

function Glyphs.Render(container: Instance, gamepad: any, binding: any, options: Options)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end
	local function text(value: string, dim: boolean)
		local label = new("TextLabel", {
			Text = value,
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			TextSize = Theme.TextSize.Small,
			FontFace = if dim then Theme.Font.Regular else Theme.Font.Medium,
			LayoutOrder = nextOrder(),
			Parent = container,
		})
		if options.onDark then
			label.TextColor3 = (if dim then options.dimColor else options.textColor) or Color3.new(1, 1, 1)
		else
			Theme.Bind(label, "TextColor3", if dim then Theme.Color.DimmedText else Theme.Color.MainText)
		end
	end
	local function key(name: string)
		local image = gamepad:Glyph(name)
		if image ~= "" then
			local glyph = new("ImageLabel", {
				Image = image,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(options.size, options.size),
				LayoutOrder = nextOrder(),
				Parent = container,
			})
			-- Roblox glyphs are white; tint them so they read on light themes.
			if not options.onDark then
				Theme.Bind(glyph, "ImageColor3", Theme.Color.MainText)
			end
		else
			text(gamepad:InputName(name), false)
		end
		local direction = DPAD_ARROWS[name]
		if direction then
			local arrowSize = math.max(12, math.floor(options.size * 0.8))
			local arrow = new("ImageLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(arrowSize, arrowSize),
				LayoutOrder = nextOrder(),
				Parent = container,
			})
			if options.onDark then
				arrow.Image = arrowIcon(direction, true)
			else
				Theme.BindIcon(arrow, "Image", arrowIcon(direction, false))
			end
		end
	end

	if binding.mod then
		key(binding.mod)
		text("+", true)
	end
	key(binding.key)
end

return Glyphs
