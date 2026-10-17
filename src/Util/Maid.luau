--[[
	Tracks connections, instances and cleanup functions so a whole subsystem can
	be torn down with one call (plugin unload, widget rebuild, etc).
]]

local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _tasks = {} }, Maid)
end

function Maid:Give<T>(task: T): T
	table.insert(self._tasks, task)
	return task
end

local function clean(task: any)
	local kind = typeof(task)
	if kind == "function" then
		task()
	elseif kind == "RBXScriptConnection" then
		task:Disconnect()
	elseif kind == "Instance" then
		task:Destroy()
	elseif kind == "table" then
		if type(task.Destroy) == "function" then
			task:Destroy()
		elseif type(task.Disconnect) == "function" then
			task:Disconnect()
		end
	elseif kind == "thread" then
		pcall(task.cancel, task)
	end
end

function Maid:Clean()
	local tasks = self._tasks
	self._tasks = {}
	for index = #tasks, 1, -1 do
		local ok, err = pcall(clean, tasks[index])
		if not ok then
			warn("[Studio Controller Pro] cleanup error:", err)
		end
	end
end

Maid.Destroy = Maid.Clean

return Maid
