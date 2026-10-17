--[[
	Minimal synchronous signal. Handlers run in connection order; a handler that
	errors is reported with `task.spawn` semantics so it can't break the others.
]]

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (self: Connection) -> (), Connected: boolean }

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	local handlers = self._handlers
	local connection = { Connected = true }
	function connection.Disconnect()
		if not connection.Connected then
			return
		end
		connection.Connected = false
		local index = table.find(handlers, fn)
		if index then
			table.remove(handlers, index)
		end
	end
	table.insert(handlers, fn)
	return connection
end

function Signal:Fire(...)
	for _, fn in table.clone(self._handlers) do
		task.spawn(fn, ...)
	end
end

function Signal:Destroy()
	table.clear(self._handlers)
end

return Signal
