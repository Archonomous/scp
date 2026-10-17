--[[
	Viewport screenshots via CaptureService.

	Every capture records the exact camera view it came from, so the camera can
	glide back to it later. Plugins can't write image files, so a fresh capture
	lives for the Studio session. Starring one makes it permanent:

	  1. the image is uploaded to the user's account as an Image asset
	  2. a plane showing it is added to ServerStorage › Studio Controller Pro
	     Captures, named after the place and time, with the view stored in
	     attributes (so it can be exported or moved into the world)
	  3. it's remembered in plugin settings, so it shows in the gallery in
	     later sessions

	The HUD is hidden for the frames around the capture so it never appears in
	the shot.
]]

local AssetService = game:GetService("AssetService")
local CaptureService = game:GetService("CaptureService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Signal = require(script.Parent.Parent.Util.Signal)

local MAX_SESSION_CAPTURES = 40
local CAPTURE_TIMEOUT = 5
local UPLOAD_FALLBACK_SIZE = 1024
local FOLDER_NAME = "Studio Controller Pro Captures"
local PLANE_WIDTH = 16

export type Capture = {
	id: number,
	name: string,
	content: string,
	time: number,
	fov: number,
	cframe: CFrame,
	aspect: number,
	placeKey: string,
	placeName: string,
	starred: boolean,
	assetId: number?,
	saving: boolean,
}

local Captures = {}
Captures.__index = Captures
Captures.FolderName = FOLDER_NAME

local function placeKey(): string
	return if game.PlaceId ~= 0 then tostring(game.PlaceId) else game.Name
end

local function placeName(): string
	local name = string.gsub(game.Name, "%.rbxlx?$", "")
	return name
end

-- File-system-safe, sortable names like "My Place 2026-10-17 14-32-05".
local function captureName(time: number, taken: { [string]: boolean }): string
	local place = string.gsub(placeName(), "[^%w%s%-_%.]", "")
	place = string.match(place, "^%s*(.-)%s*$") or ""
	if place == "" then
		place = "Capture"
	end
	local base = place .. " " .. os.date("%Y-%m-%d %H-%M-%S", time)
	local name = base
	local n = 2
	while taken[name] do
		name = string.format("%s (%d)", base, n)
		n += 1
	end
	return name
end

local function fromStarred(entry: any, id: number): Capture
	return {
		id = id,
		name = entry.name,
		content = "rbxassetid://" .. entry.assetId,
		time = entry.time,
		fov = entry.fov,
		cframe = CFrame.new(table.unpack(entry.cframe)),
		aspect = entry.aspect,
		placeKey = entry.placeKey,
		placeName = entry.placeName,
		starred = true,
		assetId = entry.assetId,
		saving = false,
	}
end

function Captures.new(store: any)
	local self = setmetatable({}, Captures)
	self._store = store
	self.list = {} :: { Capture }
	self.busy = false
	self._nextId = 1
	self.Changed = Signal.new()
	for _, entry in store:GetStarred() do
		table.insert(self.list, fromStarred(entry, self._nextId))
		self._nextId += 1
	end
	return self
end

function Captures:Get(id: number): Capture?
	for _, capture in self.list do
		if capture.id == id then
			return capture
		end
	end
	return nil
end

function Captures:IsFromThisPlace(capture: Capture): boolean
	return capture.placeKey == placeKey()
end

function Captures:_takenNames(): { [string]: boolean }
	local taken = {}
	for _, capture in self.list do
		taken[capture.name] = true
	end
	return taken
end

-- `setOverlaysVisible(false)` is called before the capture and with `true`
-- after it. Calls back with (capture?, err?) when done.
function Captures:Take(setOverlaysVisible: (boolean) -> (), callback: (Capture?, string?) -> ())
	if self.busy then
		callback(nil, "A capture is already in progress.")
		return
	end
	self.busy = true
	local camera = workspace.CurrentCamera
	local fov = if camera then camera.FieldOfView else 70
	local cframe = if camera then camera.CFrame else CFrame.identity
	local viewport = if camera then camera.ViewportSize else Vector2.new(16, 9)
	local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9

	task.spawn(function()
		setOverlaysVisible(false)
		-- Two rendered frames guarantee the hidden HUD is out of the back buffer.
		RunService.PreRender:Wait()
		RunService.PreRender:Wait()

		local content: string? = nil
		local finished = false
		local ok, err = pcall(CaptureService.CaptureScreenshot, CaptureService, function(contentId)
			content = contentId
			finished = true
		end)
		local started = os.clock()
		while ok and not finished and os.clock() - started < CAPTURE_TIMEOUT do
			task.wait()
		end
		setOverlaysVisible(true)
		self.busy = false

		if not ok or not content then
			callback(nil, if ok then "The capture timed out." else tostring(err))
			return
		end
		local time = os.time()
		local capture: Capture = {
			id = self._nextId,
			name = captureName(time, self:_takenNames()),
			content = content :: string,
			time = time,
			fov = fov,
			cframe = cframe,
			aspect = aspect,
			placeKey = placeKey(),
			placeName = placeName(),
			starred = false,
			assetId = nil,
			saving = false,
		}
		self._nextId += 1
		table.insert(self.list, 1, capture)
		self:_trimSession()
		self.Changed:Fire()
		callback(capture, nil)
	end)
end

function Captures:_trimSession()
	local unstarred = 0
	for index = 1, #self.list do
		local capture = self.list[index]
		if capture and not capture.starred then
			unstarred += 1
		end
	end
	local index = #self.list
	while unstarred > MAX_SESSION_CAPTURES and index > 0 do
		local capture = self.list[index]
		if not capture.starred and not capture.saving then
			table.remove(self.list, index)
			unstarred -= 1
		end
		index -= 1
	end
end

-- Upload ---------------------------------------------------------------------------

local function scaledCopy(source: EditableImage, maxSize: number): EditableImage
	local scale = math.min(1, maxSize / math.max(source.Size.X, source.Size.Y))
	local size =
		Vector2.new(math.max(1, math.floor(source.Size.X * scale)), math.max(1, math.floor(source.Size.Y * scale)))
	local copy = AssetService:CreateEditableImage({ Size = size })
	copy:DrawImageTransformed(size / 2, Vector2.new(scale, scale), 0, source, {
		CombineType = Enum.ImageCombineType.Overwrite,
		PivotPoint = source.Size / 2,
	})
	return copy
end

local function upload(capture: Capture): (number?, string?)
	local okImage, image = pcall(AssetService.CreateEditableImageAsync, AssetService, Content.fromUri(capture.content))
	if not okImage then
		return nil, "This capture is no longer available. Captures from an earlier session can't be saved."
	end
	local position = capture.cframe.Position
	local description = string.format(
		"Captured with Studio Controller Pro in %s.\nFOV %d° at (%d, %d, %d).",
		capture.placeName,
		math.round(capture.fov),
		math.round(position.X),
		math.round(position.Y),
		math.round(position.Z)
	)
	local function try(source: EditableImage): (number?, string?)
		local ok, result, value = pcall(AssetService.CreateAssetAsync, AssetService, source, Enum.AssetType.Image, {
			Name = capture.name,
			Description = description,
		})
		if ok and result == Enum.CreateAssetResult.Success then
			return value, nil
		end
		return nil, if ok then tostring(value or result) else tostring(result)
	end

	local assetId, err = try(image)
	if not assetId and math.max(image.Size.X, image.Size.Y) > UPLOAD_FALLBACK_SIZE then
		-- Large viewports can exceed the upload limit; retry at a safe size.
		local smaller = scaledCopy(image, UPLOAD_FALLBACK_SIZE)
		assetId, err = try(smaller)
		smaller:Destroy()
	end
	image:Destroy()
	return assetId, err
end

local function capturesFolder(): Folder
	local folder = ServerStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ServerStorage
	end
	return folder :: Folder
end

local function createPlane(capture: Capture, assetId: number)
	local recording = ChangeHistoryService:TryBeginRecording("Save capture " .. capture.name)
	local plane = Instance.new("Part")
	plane.Name = capture.name
	plane.Anchored = true
	plane.CanCollide = false
	plane.CanQuery = true
	plane.CastShadow = false
	plane.Material = Enum.Material.SmoothPlastic
	plane.Color = Color3.new(1, 1, 1)
	plane.Size = Vector3.new(PLANE_WIDTH, PLANE_WIDTH / capture.aspect, 0.05)
	plane.CFrame = capture.cframe * CFrame.new(0, 0, -PLANE_WIDTH)
	local decal = Instance.new("Decal")
	decal.Name = "Capture"
	decal.Face = Enum.NormalId.Back
	decal.Texture = "rbxassetid://" .. assetId
	decal.Parent = plane
	plane:SetAttribute("CameraCFrame", capture.cframe)
	plane:SetAttribute("FieldOfView", capture.fov)
	plane:SetAttribute("CapturedAt", DateTime.fromUnixTimestamp(capture.time):ToIsoDate())
	plane:SetAttribute("AssetId", assetId)
	plane.Parent = capturesFolder()
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
end

-- Stars a capture: upload, add the plane, remember it. Calls back with an
-- error message on failure.
function Captures:Star(id: number, callback: ((string?) -> ())?)
	local capture = self:Get(id)
	if not capture or capture.starred or capture.saving then
		return
	end
	if not self._store:CanStar() then
		if callback then
			callback(string.format("You can keep up to %d starred captures.", self._store.MaxStarred))
		end
		return
	end
	capture.saving = true
	self.Changed:Fire()
	task.spawn(function()
		local assetId, err = upload(capture)
		capture.saving = false
		if not assetId then
			self.Changed:Fire()
			if callback then
				callback("Couldn't upload the capture: " .. tostring(err))
			end
			return
		end
		capture.assetId = assetId
		capture.starred = true
		local c = { capture.cframe:GetComponents() }
		self._store:AddStarred({
			assetId = assetId,
			name = capture.name,
			time = capture.time,
			fov = capture.fov,
			aspect = capture.aspect,
			cframe = c,
			placeKey = capture.placeKey,
			placeName = capture.placeName,
		})
		local ok, planeErr = pcall(createPlane, capture, assetId)
		self.Changed:Fire()
		if callback then
			callback(if ok then nil else "Saved, but couldn't add the plane: " .. tostring(planeErr))
		end
	end)
end

-- Unstarring forgets the capture between sessions but leaves the uploaded
-- image and its plane alone, so nothing the user exported breaks.
function Captures:Unstar(id: number)
	local capture = self:Get(id)
	if not capture or not capture.starred or not capture.assetId then
		return
	end
	self._store:RemoveStarred(capture.assetId)
	capture.starred = false
	self.Changed:Fire()
end

function Captures:Remove(id: number)
	for index, capture in self.list do
		if capture.id == id then
			if capture.starred and capture.assetId then
				self._store:RemoveStarred(capture.assetId)
			end
			table.remove(self.list, index)
			self.Changed:Fire()
			return
		end
	end
end

function Captures:CountUnstarred(): number
	local count = 0
	for _, capture in self.list do
		if not capture.starred and not capture.saving then
			count += 1
		end
	end
	return count
end

-- Clears session captures only; starred ones stay.
function Captures:ClearUnstarred()
	for index = #self.list, 1, -1 do
		local capture = self.list[index]
		if not capture.starred and not capture.saving then
			table.remove(self.list, index)
		end
	end
	self.Changed:Fire()
end

function Captures:Destroy()
	self.Changed:Destroy()
end

return Captures
