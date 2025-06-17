--[[
		- RO SOCKET -
	A blazing fast implementation of WebSockets in roblox, similar to the "ws" library in Node.
	Supports client and server implementation.
	Backend uses the "ws" library aswell, providing proper socket support, and is coded in Node.
	
	• Creator: @binarychunk
	
		- CHANGELOG -
	
	v1.0.0:
		Initial release
	v1.0.1:
		Improved code readability
		Improved code speed by removing some useless portions
		Made it send all variable arguments from inside the Send function to the Reader
		Added more intelli sense stuff
		Added custom error messages when trying to:
		- send messages to a disconnected socket
		- disconnect a already-disconnected socket
]]--

local RoSocket = {}
local Reader = require(script.Parent.Reader)
local Errors = require(script.Parent.Errors)
local Signal = require(script.Parent.Signal)
local Maid = require(script.Parent.Maid)

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local SOCKET_SERVER_UPDATES = 0.10

if RunService:IsServer() == false then
	error(Reader:FormatText(Errors.INVALID_REQUIREMENT_CONTEXT))
end
if not HttpService.HttpEnabled then
	error(Reader:FormatText(Errors.HTTP_SERVICE_DISABLED))
end

local MaidSocket = Maid.new()
local Sockets = {}
RoSocket.Version = "1.0.1"
RoSocket.Connect = function(socket: string): (any?) -> (table)
	local validsocket = true

	if validsocket ~= false then
		local data = Reader:Connect(socket)
		if data.success ~= false then
			local dis = false
			local uuid = data.UUID
			local localmsgs = {}
			local localerrors = {}
			local tbl = {}
			tbl.readyState = dis
			coroutine.resume(coroutine.create(function() 
				while tbl do 
					tbl.readyState = dis and "CLOSED" or "OPEN"
					task.wait(0.05)
				end
			end))
			tbl.binaryType = "buffer"
			local OnDisconnect : RBXScriptSignal = Signal.new()
			tbl.OnDisconnect = OnDisconnect
			local OnMessageReceived : RBXScriptSignal = Signal.new()
			tbl.OnMessageReceived = OnMessageReceived
			local OnErrorReceived : RBXScriptSignal = Signal.new()
			tbl.OnErrorReceived = OnErrorReceived

			local elapsedTimer = Sockets[uuid] and Sockets[uuid].elapsedtimer or 0

			local MAX_REQUESTS_PER_MIN = 480
			local MIN_INTERVAL = 60 / MAX_REQUESTS_PER_MIN -- ~0.12s
			local lastRequestTime = 0
			local requestsThisMinute = 0
			local minuteStart = os.clock()
			local socketCooldownUntil = 0
			local COOLDOWN_SECONDS = 10

			MaidSocket[uuid] = RunService.Heartbeat:Connect(function(deltaTime)
				local now = os.clock()
				if now < socketCooldownUntil then
					return -- In cooldown, skip
				end
				if now - minuteStart >= 60 then
					minuteStart = now
					requestsThisMinute = 0
				end
				if requestsThisMinute >= MAX_REQUESTS_PER_MIN then
					socketCooldownUntil = now + COOLDOWN_SECONDS
					warn("[RoSocket] Rate limit exceeded (500/min). Cooling down for " .. COOLDOWN_SECONDS .. "s.")
					return
				end
				if now - lastRequestTime < MIN_INTERVAL then
					return -- Throttle
				end
				lastRequestTime = now
				requestsThisMinute = requestsThisMinute + 1
				if elapsedTimer >= SOCKET_SERVER_UPDATES then
					elapsedTimer = 0
				end
				elapsedTimer = elapsedTimer + deltaTime
				if elapsedTimer >= SOCKET_SERVER_UPDATES then
					if dis == false then
						-- messages
						local Msgs = Reader.Get (Reader, uuid)
						if typeof(Msgs) == "table" then
							for _, msgobj in ipairs(Msgs) do
								local existsAlready = false
								for i,msg in ipairs(Sockets[uuid].msgs) do
									if msg.id == msgobj.id then
										existsAlready = true
										break
									end
								end

								if existsAlready == false then
									tbl.OnMessageReceived:Fire(msgobj.message)
									table.insert(Sockets[uuid].msgs, {
										id = msgobj.id,
										message = msgobj.message,
									})
									table.insert(localmsgs, {
										id = msgobj.id,
										message = msgobj.message,
									})
								end
							end
						end
						-- errors
						local suc, Msgs = pcall(Reader.GetErrors, Reader, uuid)
						if typeof(Msgs) == "table" then
							for _, msgobj in ipairs(Msgs) do
								local existsAlready = false
								for i,msg in ipairs(Sockets[uuid].errors) do
									if msg.id == msgobj.id then
										existsAlready = true
										break
									end
								end

								if existsAlready == false then
									tbl.OnErrorReceived:Fire(msgobj.message)
									table.insert(Sockets[uuid].errors, {
										id = msgobj.id,
										message = msgobj.message,
									})
									table.insert(localerrors, {
										id = msgobj.id,
										message = msgobj.message,
									})
								end
							end
						end
					else

					end
				end
			end)

			tbl.UUID = uuid
			tbl.Socket = data.Socket
			tbl.Disconnect = function(table, reason, ...)
				if dis == true then
					warn(Reader:FormatText("You cannot disconnect a disconnected socket!"))
					return false
				else
					local success = Reader:Disconnect(uuid)
					Sockets[uuid] = nil
					MaidSocket[uuid] = nil
					tbl.OnDisconnect:Fire(reason)
					dis = true
					return true
				end
				
			end
			tbl.Send = function(...) 
				if dis == false then
					local success = Reader:Send(uuid, ...)
					return success
				else
					warn(Reader:FormatText("You cannot send messages to a disconnected socket!"))
					return false
				end
			end
			tbl.Messages = localmsgs or {}
			tbl.Errors = localerrors or {}

			setmetatable(tbl, {
				__call = function(self, index, ...) 
					return tbl[index](...)
				end,
				__metatable = "This is a protected metatable!"
			})
			Sockets[uuid] = {
				sockettbl = tbl,
				msgs = {},
				errors = {},
				elapsedtimer = 0
			}

			return tbl
		end
	else
		return {}
	end
end
setmetatable(RoSocket, {
	__call = function(self, ...)
		return RoSocket.Connect(...)
	end
})
table.freeze(RoSocket)
-----------------------------------------------
return RoSocket
