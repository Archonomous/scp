--[[
	Studio-native theming. Colors come from the live Studio theme so the panel
	matches Light and Dark (and updates instantly when the theme changes).
	Icons come from Studio's own icon set in the matching variant.
]]

local Theme = {}

local studio = settings().Studio
local C = Enum.StudioStyleGuideColor
local M = Enum.StudioStyleGuideModifier

Theme.Color = C
Theme.Modifier = M

Theme.Font = {
	Regular = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Regular),
	Medium = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium),
	Bold = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
	Mono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular),
}

Theme.TextSize = { Small = 13, Body = 14, Title = 16, Heading = 18 }
Theme.Radius = UDim.new(0, 4)
Theme.Padding = 12
Theme.RowHeight = 28

-- Studio's accent blue, used where the theme has no exact token.
Theme.Accent = Color3.fromRGB(51, 95, 255)

function Theme.IsDark(): boolean
	local ok, name = pcall(function()
		return studio.Theme.Name
	end)
	return not ok or name ~= "Light"
end

function Theme.Get(color: Enum.StudioStyleGuideColor, modifier: Enum.StudioStyleGuideModifier?): Color3
	return studio.Theme:GetColor(color, modifier or M.Default)
end

-- Resolves a token to a color. Tokens are either a StudioStyleGuideColor, a
-- { color, modifier } pair, or a function returning a Color3.
function Theme.Resolve(token: any): Color3
	if typeof(token) == "EnumItem" then
		return Theme.Get(token)
	elseif type(token) == "table" then
		return Theme.Get(token[1], token[2])
	elseif type(token) == "function" then
		return token()
	end
	return token
end

-- Icons: `path` is relative to studio_svg_textures with a {theme} placeholder,
-- e.g. "Shared/Navigation/{theme}/Standard/Settings".
function Theme.Icon(path: string): string
	local variant = if Theme.IsDark() then "Dark" else "Light"
	return "rbxasset://studio_svg_textures/" .. string.gsub(path, "{theme}", variant) .. "@2x.png"
end

Theme.Icons = {
	Settings = "Shared/Navigation/{theme}/Standard/Settings",
	More = "Shared/Navigation/{theme}/Standard/More",
	Close = "Shared/Navigation/{theme}/Standard/CloseWidget",
	Dropdown = "Shared/Navigation/{theme}/Standard/DropdownArrow",
	ArrowUp = "Shared/Navigation/{theme}/Standard/ArrowUp",
	ArrowDown = "Shared/Navigation/{theme}/Standard/ArrowDown",
	ArrowLeft = "Shared/Navigation/{theme}/Standard/ArrowLeft",
	Add = "Shared/Navigation/{theme}/Standard/AddNoBorder",
	Duplicate = "Shared/Clipboard/{theme}/Standard/Duplicate",
	Copy = "Shared/Clipboard/{theme}/Standard/Copy",
	Delete = "Shared/Ribbon/{theme}/Standard/RibbonDeleteSmall",
	Edit = "Shared/GenerativeAI/{theme}/Standard/EditMessage",
	Import = "Lua/AssetManager/{theme}/Standard/Import",
	-- Drawn as Import rotated 180° (no matching export glyph exists).
	Export = "Lua/AssetManager/{theme}/Standard/Import",
	Reset = "Lua/TerrainEditor/{theme}/Standard/Reset",
	Info = "Shared/Alerts/{theme}/Standard/Information",
	Warning = "Shared/Alerts/{theme}/Standard/Warning",
	Check = "Shared/Ribbon/{theme}/Standard/Checkmark",
	Upload = "Lua/AvatarCompatibilityPreviewer/{theme}/Large/publish",
	Search = "Lua/DeveloperFramework/{theme}/Standard/Search",
}

-- Built-in gamepad glyph used for the panel logo and as the toolbar fallback.
Theme.GamepadIcon = "rbxasset://textures/DeviceEmulator/sim_console@32.png"

-- Toolbar / panel icon: assets/toolbar-256.png uploaded as an Image asset. Falls back
-- to the built-in gamepad glyph if set to nil.
Theme.ToolbarIcon = "rbxassetid://135063789186048" :: string?

-- Yields until the asset has loaded or failed.
function Theme.IsAssetAvailable(contentId: string): boolean
	local status = nil
	local ok = pcall(function()
		game:GetService("ContentProvider"):PreloadAsync({ contentId }, function(_, fetchStatus)
			status = fetchStatus
		end)
	end)
	return ok and status == Enum.AssetFetchStatus.Success
end

-- Yields, then returns the toolbar icon to use, or nil if none can load. The
-- uploaded image only loads in places its owner can use it in (not group or
-- other creators' places), so the asset's thumbnail is tried next: thumbnails
-- of approved images load anywhere.
local toolbarIconState: "pending" | "resolving" | "done" = "pending"
local resolvedToolbarIcon: string? = nil
function Theme.ResolveToolbarIcon(): string?
	if toolbarIconState == "pending" then
		toolbarIconState = "resolving"
		local icon = Theme.ToolbarIcon
		local assetId = icon and string.match(icon, "^rbxassetid://(%d+)$")
		local candidates = { icon }
		if assetId then
			table.insert(candidates, `rbxthumb://type=Asset&id={assetId}&w=420&h=420`)
		end
		for _, candidate in candidates do
			if Theme.IsAssetAvailable(candidate) then
				resolvedToolbarIcon = candidate
				break
			end
		end
		toolbarIconState = "done"
	end
	while toolbarIconState ~= "done" do
		task.wait()
	end
	return resolvedToolbarIcon
end

local bindings = setmetatable({}, { __mode = "k" }) :: { [Instance]: { [string]: any } }
local iconBindings = setmetatable({}, { __mode = "k" }) :: { [Instance]: { [string]: string } }
local listeners = {} :: { () -> () }

-- Binds `instance[property]` to a theme token and keeps it updated.
function Theme.Bind(instance: Instance, property: string, token: any)
	local entry = bindings[instance]
	if not entry then
		entry = {}
		bindings[instance] = entry
	end
	entry[property] = token;
	(instance :: any)[property] = Theme.Resolve(token)
end

function Theme.BindIcon(instance: Instance, property: string, path: string)
	local entry = iconBindings[instance]
	if not entry then
		entry = {}
		iconBindings[instance] = entry
	end
	entry[property] = path;
	(instance :: any)[property] = Theme.Icon(path)
end

function Theme.OnChanged(listener: () -> ()): () -> ()
	table.insert(listeners, listener)
	return function()
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

local function refresh()
	for instance, entry in bindings do
		if instance.Parent ~= nil or instance:IsA("DockWidgetPluginGui") then
			for property, token in entry do
				pcall(function()
					(instance :: any)[property] = Theme.Resolve(token)
				end)
			end
		end
	end
	for instance, entry in iconBindings do
		for property, path in entry do
			pcall(function()
				(instance :: any)[property] = Theme.Icon(path)
			end)
		end
	end
	for _, listener in table.clone(listeners) do
		task.spawn(listener)
	end
end

local themeConnection = studio.ThemeChanged:Connect(refresh)

function Theme.Destroy()
	themeConnection:Disconnect()
	table.clear(listeners)
end

return Theme
