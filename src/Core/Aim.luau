--[[
	What the reticle is on: a ray from the centre of the viewport, resolved to
	what a mouse click there would select (the outermost model below Workspace,
	or the part itself). Locked parts and terrain give a point but nothing to
	select, like a click.

	Also draws an outline on the target while the select gesture is held, so
	the scene isn't highlighted the rest of the time.
]]

local CoreGui = game:GetService("CoreGui")

local MAX_DISTANCE = 10000
local OUTLINE_COLOR = Color3.fromRGB(51, 95, 255)

export type Target = {
	instance: Instance?,
	position: Vector3,
	distance: number,
}

local Aim = {}
Aim.__index = Aim

function Aim.new()
	local self = setmetatable({}, Aim)
	self.target = nil :: Target?

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	self._params = params

	local outline = Instance.new("SelectionBox")
	outline.Name = "StudioControllerPro_Target"
	outline.Archivable = false
	outline.Color3 = OUTLINE_COLOR
	outline.LineThickness = 0.06
	outline.SurfaceTransparency = 1
	outline.Visible = false
	outline.Parent = CoreGui
	self._outline = outline
	return self
end

-- What a click on `part` would select, or nil if it can't be selected.
function Aim.Selectable(part: BasePart): Instance?
	if part:IsA("Terrain") or part.Locked then
		return nil
	end
	local result: Instance = part
	local current = part.Parent
	while current and current ~= workspace do
		if current:IsA("Model") then
			result = current
		end
		current = current.Parent
	end
	return if current == workspace then result else nil
end

-- Rough radius of an instance, used to stop a comfortable distance away.
function Aim.Radius(instance: Instance?): number?
	if instance and instance:IsA("BasePart") then
		return instance.Size.Magnitude / 2
	elseif instance and instance:IsA("Model") then
		local ok, _, size = pcall(instance.GetBoundingBox, instance)
		if ok then
			return size.Magnitude / 2
		end
	end
	return nil
end

-- Re-casts from the centre of the viewport. Call once per frame while needed.
function Aim:Update(): Target?
	local camera = workspace.CurrentCamera
	if not camera then
		self.target = nil
		return nil
	end
	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
	local result = workspace:Raycast(ray.Origin, ray.Direction * MAX_DISTANCE, self._params)
	if result then
		self.target = {
			instance = Aim.Selectable(result.Instance :: BasePart),
			position = result.Position,
			distance = result.Distance,
		}
	else
		self.target = nil
	end
	return self.target
end

-- Shows or hides the outline on the current target.
function Aim:SetOutlined(outlined: boolean)
	local instance = if outlined and self.target then self.target.instance else nil
	if self._outline.Adornee ~= instance then
		self._outline.Adornee = instance :: any
	end
	self._outline.Visible = instance ~= nil
end

function Aim:Destroy()
	self._outline:Destroy()
end

return Aim
