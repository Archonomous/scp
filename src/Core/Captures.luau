--[[
	Viewport screenshots via CaptureService.

	Plugins can capture the viewport but can't write image files, so captures
	are kept for the Studio session and shown in the Captures tab, newest first.
	The HUD is hidden for the frames around the capture so it never appears in
	the shot.
]]

local CaptureService = game:GetService("CaptureService")
local RunService = game:GetService("RunService")

local Signal = require(script.Parent.Parent.Util.Signal)

local MAX_CAPTURES = 40
local CAPTURE_TIMEOUT = 5

export type Capture = {
	id: number,
	content: string,
	time: number,
	fov: number,
	position: Vector3,
	aspect: number,
}

local Captures = {}
Captures.__index = Captures

function Captures.new()
	local self = setmetatable({}, Captures)
	self.list = {} :: { Capture }
	self.busy = false
	self._nextId = 1
	self.Changed = Signal.new()
	return self
end

-- `setOverlaysVisible(false)` is called before the capture and with `true`
-- after it. Calls back with (capture?) when done.
function Captures:Take(setOverlaysVisible: (boolean) -> (), callback: (Capture?, string?) -> ())
	if self.busy then
		callback(nil, "A capture is already in progress.")
		return
	end
	self.busy = true
	local camera = workspace.CurrentCamera
	local fov = if camera then camera.FieldOfView else 70
	local position = if camera then camera.CFrame.Position else Vector3.zero
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
		local capture = {
			id = self._nextId,
			content = content :: string,
			time = os.time(),
			fov = fov,
			position = position,
			aspect = aspect,
		}
		self._nextId += 1
		table.insert(self.list, 1, capture)
		while #self.list > MAX_CAPTURES do
			table.remove(self.list)
		end
		self.Changed:Fire()
		callback(capture, nil)
	end)
end

function Captures:Remove(id: number)
	for index, capture in self.list do
		if capture.id == id then
			table.remove(self.list, index)
			self.Changed:Fire()
			return
		end
	end
end

function Captures:Clear()
	table.clear(self.list)
	self.Changed:Fire()
end

function Captures:Destroy()
	self.Changed:Destroy()
end

return Captures
