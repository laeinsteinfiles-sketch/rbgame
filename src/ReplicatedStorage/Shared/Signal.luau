--!strict
-- Explorer: ReplicatedStorage/Shared/Signal (ModuleScript)
-- Minimal typed signal. Handlers run in their own thread so one slow listener
-- never blocks the emitter.

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (self: Connection) -> () }
export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Destroy: (self: Signal<T...>) -> (),
}

type Impl = {
	_handlers: { [number]: (...any) -> () },
	_nextId: number,
}

function Signal.new<T...>(): Signal<T...>
	local self: Impl = { _handlers = {}, _nextId = 1 }
	return (setmetatable(self, Signal) :: any) :: Signal<T...>
end

function Signal.Connect(self: any, fn: (...any) -> ()): Connection
	local id = self._nextId
	self._nextId += 1
	self._handlers[id] = fn
	return {
		Disconnect = function()
			self._handlers[id] = nil
		end,
	}
end

function Signal.Once(self: any, fn: (...any) -> ()): Connection
	local conn: Connection
	conn = Signal.Connect(self, function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal.Fire(self: any, ...: any)
	for _, fn in self._handlers do
		task.spawn(fn, ...)
	end
end

function Signal.Destroy(self: any)
	table.clear(self._handlers)
end

return Signal
