




__SPEED_VERSION = "r15"

local folder = Instance.new("Folder")
folder.Name = "_speedexecutor"

local upd = Instance.new("BoolValue")
upd.Name = "UpdateIndicator"
upd.Parent = folder

folder.Parent = game.CoreGui



local http_service = game.HttpService
local lastValue = upd.Value
local bridgeServer = 'http://localhost:9475'




local lz4 do
	local module = {}

	type Streamer = {
		Offset: number,
		Source: string,
		Length: number,
		IsFinished: boolean,
		LastUnreadBytes: number,

		read: (Streamer, len: number?, shiftOffset: boolean?) -> string,
		seek: (Streamer, len: number) -> (),
		append: (Streamer, newData: string) -> (),
		toEnd: (Streamer) -> ()
	}

	type BlockData = {
		[number]: {
			Literal: string,
			LiteralLength: number,
			MatchOffset: number?,
			MatchLength: number?
		}
	}

	local function plainFind(str, pat)
		return string.find(str, pat, 0, true)
	end

	local function streamer(str): Streamer
		local Stream = {}
		Stream.Offset = 0
		Stream.Source = str
		Stream.Length = string.len(str)
		Stream.IsFinished = false
		Stream.LastUnreadBytes = 0

		function Stream.read(self: Streamer, len: number?, shift: boolean?): string
			local len = len or 1
			local shift = if shift ~= nil then shift else true
			local dat = string.sub(self.Source, self.Offset + 1, self.Offset + len)

			local dataLength = string.len(dat)
			local unreadBytes = len - dataLength

			if shift then
				self:seek(len)
			end

			self.LastUnreadBytes = unreadBytes
			return dat
		end

		function Stream.seek(self: Streamer, len: number)
			local len = len or 1

			self.Offset = math.clamp(self.Offset + len, 0, self.Length)
			self.IsFinished = self.Offset >= self.Length
		end

		function Stream.append(self: Streamer, newData: string)
			

			self.Source ..= newData
			self.Length = string.len(self.Source)
			self:seek(0) 

		end

		function Stream.toEnd(self: Streamer)
			self:seek(self.Length)
		end

		return Stream
	end

	function module.compress(str: string): string
		local blocks: BlockData = {}
		local iostream = streamer(str)

		if iostream.Length > 12 then
			local firstFour = iostream:read(4)

			local processed = firstFour
			local lit = firstFour
			local match = ""
			local LiteralPushValue = ""
			local pushToLiteral = true

			repeat
				pushToLiteral = true
				local nextByte = iostream:read()

				if plainFind(processed, nextByte) then
					local next3 = iostream:read(3, false)

					if string.len(next3) < 3 then
						

						LiteralPushValue = nextByte .. next3
						iostream:seek(3)
					else
						match = nextByte .. next3

						local matchPos = plainFind(processed, match)
						if matchPos then
							iostream:seek(3)
							repeat
								local nextMatchByte = iostream:read(1, false)
								local newResult = match .. nextMatchByte

								local repos = plainFind(processed, newResult)
								if repos then
									match = newResult
									matchPos = repos
									iostream:seek(1)
								end
							until not plainFind(processed, newResult) or iostream.IsFinished

							local matchLen = string.len(match)
							local pushMatch = true

							if iostream.Length - iostream.Offset <= 5 then
								LiteralPushValue = match
								pushMatch = false
								

							end

							if pushMatch then
								pushToLiteral = false

								

								local realPosition = string.len(processed) - matchPos
								processed = processed .. match

								table.insert(blocks, {
									Literal = lit,
									LiteralLength = string.len(lit),
									MatchOffset = realPosition + 1,
									MatchLength = matchLen,
								})
								lit = ""
							end
						else
							LiteralPushValue = nextByte
						end
					end
				else
					LiteralPushValue = nextByte
				end

				if pushToLiteral then
					lit = lit .. LiteralPushValue
					processed = processed .. nextByte
				end
			until iostream.IsFinished
			table.insert(blocks, {
				Literal = lit,
				LiteralLength = string.len(lit)
			})
		else
			local str = iostream.Source
			blocks[1] = {
				Literal = str,
				LiteralLength = string.len(str)
			}
		end

		

		

		local output = string.rep("\x00", 4)
		local function write(char)
			output = output .. char
		end
		

		for chunkNum, chunk in blocks do
			local litLen = chunk.LiteralLength
			local matLen = (chunk.MatchLength or 4) - 4

			

			local tokenLit = math.clamp(litLen, 0, 15)
			local tokenMat = math.clamp(matLen, 0, 15)

			local token = bit32.lshift(tokenLit, 4) + tokenMat
			write(string.pack("<I1", token))

			if litLen >= 15 then
				litLen = litLen - 15
				

				repeat
					local nextToken = math.clamp(litLen, 0, 0xFF)
					write(string.pack("<I1", nextToken))
					if nextToken == 0xFF then
						litLen = litLen - 255
					end
				until nextToken < 0xFF
			end

			

			write(chunk.Literal)

			if chunkNum ~= #blocks then
				

				write(string.pack("<I2", chunk.MatchOffset))

				

				if matLen >= 15 then
					matLen = matLen - 15

					repeat
						local nextToken = math.clamp(matLen, 0, 0xFF)
						write(string.pack("<I1", nextToken))
						if nextToken == 0xFF then
							matLen = matLen - 255
						end
					until nextToken < 0xFF
				end
			end
		end
		

		local compLen = string.len(output) - 4
		local decompLen = iostream.Length

		return string.pack("<I4", compLen) .. string.pack("<I4", decompLen) .. output
	end

	function module.decompress(lz4data: string): string
		local inputStream = streamer(lz4data)

		local compressedLen = string.unpack("<I4", inputStream:read(4))
		local decompressedLen = string.unpack("<I4", inputStream:read(4))
		local reserved = string.unpack("<I4", inputStream:read(4))

		if compressedLen == 0 then
			return inputStream:read(decompressedLen)
		end

		local outputStream = streamer("")

		repeat
			local token = string.byte(inputStream:read())
			local litLen = bit32.rshift(token, 4)
			local matLen = bit32.band(token, 15) + 4

			if litLen >= 15 then
				repeat
					local nextByte = string.byte(inputStream:read())
					litLen += nextByte
				until nextByte ~= 0xFF
			end

			local literal = inputStream:read(litLen)
			outputStream:append(literal)
			outputStream:toEnd()
			if outputStream.Length < decompressedLen then
				

				local offset = string.unpack("<I2", inputStream:read(2))
				if matLen >= 19 then
					repeat
						local nextByte = string.byte(inputStream:read())
						matLen += nextByte
					until nextByte ~= 0xFF
				end

				outputStream:seek(-offset)
				local pos = outputStream.Offset
				local match = outputStream:read(matLen)
				local unreadBytes = outputStream.LastUnreadBytes
				local extra
				if unreadBytes then
					repeat
						outputStream.Offset = pos
						extra = outputStream:read(unreadBytes)
						unreadBytes = outputStream.LastUnreadBytes
						match ..= extra
					until unreadBytes <= 0
				end

				outputStream:append(match)
				outputStream:toEnd()
			end

		until outputStream.Length >= decompressedLen

		return outputStream.Source
	end

	lz4 = module
end








local BRIDGE_TIMEOUT = 15

local function await_bridge(get_result)
	local deadline = os.clock() + BRIDGE_TIMEOUT
	repeat task.wait() until get_result() or os.clock() > deadline
	return get_result()
end

local function requestData()
	local result = nil

	local started = pcall(function()
		http_service:RequestInternal({
			Url = bridgeServer,
			Method = "GET",
			Headers = {
				['Content-Type'] = "text/plain"
			}
		}):Start(function(s,b)
			result = b
			result['Success'] = s
		end)
	end)

	if not started then
		warn('SpeedExecutor -- request error (http unavailable)')
		return nil
	end

	result = await_bridge(function() return result end)

	if not result or not result.Success then
		warn('SpeedExecutor -- request error')
		return nil
	end

	return result and result.Body or ""
end

local function send_method(method, ...)
	local result = nil

	local body = table.concat({method, ...}, '\n')

	local started = pcall(function()
		http_service:RequestInternal({
			Url = bridgeServer,
			Method = "POST",
			Body = body,
			Headers = {
				['Content-Type'] = "text/plain"
			}
		}):Start(function(s,b)
			result = b
			result['Success'] = s
		end)
	end)

	if not started then
		warn('SpeedExecutor -- request error (http unavailable)')
		return nil
	end

	result = await_bridge(function() return result end)

	if not result or not result.Success then
		warn('SpeedExecutor -- request error')
		return nil
	end

	return result and result.Body or ""
end




local executor_env = getfenv()

local _real_speed_task = task

local function _thread_log_guard(fn, ...)
	local n = select('#', ...)
	local args = { ... }
	_real_speed_task.spawn(function()
		local ok, err = pcall(function()
			return fn(table.unpack(args, 1, n))
		end)
		if not ok then
			local tb = ''
			pcall(function() tb = debug.traceback('', 2) end)
			pcall(writefile, "exec_error.txt", ("SpeedExecutor -- thread error: %s\n%s\n"):format(tostring(err), tostring(tb)))
			warn('SpeedExecutor -- thread error: ' .. tostring(err))
		end
	end)
end

do
	local guarded = {}
	for k, v in pairs(_real_speed_task) do
		guarded[k] = v
	end
	guarded.spawn = function(fn, ...)
		if type(fn) ~= 'function' then
			return _real_speed_task.spawn(fn, ...)
		end
		return _thread_log_guard(fn, ...)
	end
	guarded.defer = function(fn, ...)
		if type(fn) ~= 'function' then
			return _real_speed_task.defer(fn, ...)
		end
		return _real_speed_task.defer(function()
			local ok, err = pcall(function()
				return fn(...)
			end)
			if not ok then
				local tb = ''
				pcall(function() tb = debug.traceback('', 2) end)
				pcall(writefile, "exec_error.txt", ("SpeedExecutor -- thread error: %s\n%s\n"):format(tostring(err), tostring(tb)))
				warn('SpeedExecutor -- thread error: ' .. tostring(err))
			end
		end)
	end
	guarded.delay = function(time, fn, ...)
		if type(fn) ~= 'function' then
			return _real_speed_task.delay(time, fn, ...)
		end
		return _real_speed_task.delay(time, function()
			local ok, err = pcall(function()
				return fn(...)
			end)
			if not ok then
				local tb = ''
				pcall(function() tb = debug.traceback('', 2) end)
				pcall(writefile, "exec_error.txt", ("SpeedExecutor -- thread error: %s\n%s\n"):format(tostring(err), tostring(tb)))
				warn('SpeedExecutor -- thread error: ' .. tostring(err))
			end
		end)
	end
	task = guarded
end

spawn = function(fn, ...)
	if type(fn) ~= 'function' then
		return _real_speed_task.spawn(fn, ...)
	end
	return _thread_log_guard(fn, ...)
end

delay = function(time, fn, ...)
	if type(fn) ~= 'function' then
		return _real_speed_task.delay(time, fn, ...)
	end
	return _real_speed_task.delay(time, function()
		local ok, err = pcall(function()
			return fn(...)
		end)
		if not ok then
			local tb = ''
			pcall(function() tb = debug.traceback('', 2) end)
			pcall(writefile, "exec_error.txt", ("SpeedExecutor -- thread error: %s\n%s\n"):format(tostring(err), tostring(tb)))
			warn('SpeedExecutor -- thread error: ' .. tostring(err))
		end
	end)
end

local genv_table = {}
setmetatable(genv_table, { __index = executor_env, __newindex = executor_env })

getgenv = function()
	return genv_table
end



local current_identity = 2
local _identity_raw_print = print
local _identity_raw_warn = warn



local readonly_tables = {}
setmetatable(readonly_tables, { __mode = 'k' })
local readonly_installed_meta = {}
setmetatable(readonly_installed_meta, { __mode = 'k' })




local game_o = game
game = {
	HttpGet = function(self, url)
		local t0 = os.clock()
		local ok, body = pcall(send_method, 'httpget', url)
		local t1 = os.clock()
		if ok and type(body) == 'string' and body ~= '' and body ~= 'fail' and body ~= 'bad request' then
			pcall(send_method, 'log', base64encode('[diag] httpget ok ' .. url .. ' in ' .. (t1 - t0)))
			return body
		end
		pcall(send_method, 'log', base64encode('[diag] httpget skip ' .. url .. ' (' .. tostring(ok) .. ', ' .. type(body) .. ') in ' .. (t1 - t0)))

		local result = nil
		local started = pcall(function()
			http_service:RequestInternal({
				Url = url,
				Method = "GET",
				Headers = {
					['Content-Type'] = "text/plain"
				}
			}):Start(function(s,b)
				result = b
				result['Success'] = s
			end)
		end)

		if started then
			local deadline = os.clock() + 15
			repeat task.wait() until result or os.clock() > deadline
		end

		if result and result.Success then
			return result.Body or ""
		end

		warn('SpeedExecutor -- request error')
		return nil
	end
}
game.HttpGetAsync = game.HttpGet

do
	local function xml_unescape(s)
		if type(s) ~= 'string' then return '' end
		s = s:gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&quot;', '"'):gsub('&apos;', "'"):gsub('&amp;', '&')
		s = s:gsub('&#(%d+);', function(n)
			local cp = tonumber(n)
			if not cp then return '' end
			if cp < 128 then return string.char(cp) end
			local ok, ch = pcall(utf8.char, cp)
			return ok and ch or ''
		end)
		return s
	end

	local construct = {
		Vector3 = function(t)
			local x = tonumber(t:match('<X>(.-)</X>'))
			local y = tonumber(t:match('<Y>(.-)</Y>'))
			local z = tonumber(t:match('<Z>(.-)</Z>'))
			if x and y and z then return Vector3.new(x, y, z) end
		end,
		Vector2 = function(t)
			local x = tonumber(t:match('<X>(.-)</X>'))
			local y = tonumber(t:match('<Y>(.-)</Y>'))
			if x and y then return Vector2.new(x, y) end
		end,
		Vector3int16 = function(t)
			local x = tonumber(t:match('<X>(.-)</X>'))
			local y = tonumber(t:match('<Y>(.-)</Y>'))
			local z = tonumber(t:match('<Z>(.-)</Z>'))
			if x and y and z then return Vector3int16.new(x, y, z) end
		end,
		Vector2int16 = function(t)
			local x = tonumber(t:match('<X>(.-)</X>'))
			local y = tonumber(t:match('<Y>(.-)</Y>'))
			if x and y then return Vector2int16.new(x, y) end
		end,
		NumberRange = function(t)
			local a = tonumber(t:match('<Min>(.-)</Min>'))
			local b = tonumber(t:match('<Max>(.-)</Max>'))
			if a and b then return NumberRange.new(a, b) end
		end,
		UDim = function(t)
			local s = tonumber(t:match('<Scale>(.-)</Scale>'))
			local o = tonumber(t:match('<Offset>(.-)</Offset>'))
			if s and o then return UDim.new(s, o) end
		end,
		UDim2 = function(t)
			local x = t:match('<X>(.-)</X>') or t:match('<X>%s*<Scale>(.-)</Scale>%s*<Offset>(.-)</Offset>%s*</X>')
			local y = t:match('<Y>(.-)</Y>')
			local xs = tonumber(x and x:match('<Scale>(.-)</Scale>'))
			local xo = tonumber(x and x:match('<Offset>(.-)</Offset>'))
			local ys = tonumber(y and y:match('<Scale>(.-)</Scale>'))
			local yo = tonumber(y and y:match('<Offset>(.-)</Offset>'))
			if xs and xo and ys and yo then return UDim2.new(xs, xo, ys, yo) end
		end,
		CFrame = function(t)
			local x = tonumber(t:match('<X>(.-)</X>'))
			local y = tonumber(t:match('<Y>(.-)</Y>'))
			local z = tonumber(t:match('<Z>(.-)</Z>'))
			local m = {}
			for _, r in ipairs({ 'R00','R01','R02','R10','R11','R12','R20','R21','R22' }) do
				m[r] = tonumber(t:match('<' .. r .. '>(.-)</' .. r .. '>'))
			end
			if x and y and z then
				return CFrame.new(x, y, z, m.R00, m.R01, m.R02, m.R10, m.R11, m.R12, m.R20, m.R21, m.R22)
			end
		end,
		Color3 = function(t)
			local r = tonumber(t:match('<R>(.-)</R>'))
			local g = tonumber(t:match('<G>(.-)</G>'))
			local b = tonumber(t:match('<B>(.-)</B>'))
			if r and g and b then return Color3.new(r, g, b) end
		end,
		Color3uint8 = function(t)
			local r = tonumber(t:match('<R>(.-)</R>'))
			local g = tonumber(t:match('<G>(.-)</G>'))
			local b = tonumber(t:match('<B>(.-)</B>'))
			if r and g and b then return Color3.fromRGB(r, g, b) end
			local a, c, d = t:match('(%d+)%s+(%d+)%s+(%d+)')
			if a and c and d then return Color3.fromRGB(a, c, d) end
		end,
		BrickColor = function(t)
			local v = t:match('^%s*(.-)%s*$')
			local n = tonumber(v)
			if n then return BrickColor.new(n) end
			return BrickColor.new(v or 'White')
		end,
		NumberSequence = function(t)
			local kps = {}
			for kp in t:gmatch('<Keypoint>(.-)</Keypoint>') do
				local time = tonumber(kp:match('<Time>(.-)</Time>')) or 0
				local value = tonumber(kp:match('<Value>(.-)</Value>')) or 0
				local env = tonumber(kp:match('<Envelope>(.-)</Envelope>'))
				kps[#kps + 1] = NumberSequenceKeypoint.new(time, value, env or 0)
			end
			if #kps > 0 then return NumberSequence.new(kps) end
		end,
		ColorSequence = function(t)
			local kps = {}
			for kp in t:gmatch('<Keypoint>(.-)</Keypoint>') do
				local time = tonumber(kp:match('<Time>(.-)</Time>')) or 0
				local col = Color3.new()
				local v = kp:match('<Value>(.-)</Value>')
				if v then
					local r = tonumber(v:match('<R>(.-)</R>'))
					local g = tonumber(v:match('<G>(.-)</G>'))
					local b = tonumber(v:match('<B>(.-)</B>'))
					if r and g and b then col = Color3.new(r, g, b) end
				end
				local env = tonumber(kp:match('<Envelope>(.-)</Envelope>'))
				kps[#kps + 1] = ColorSequenceKeypoint.new(time, col, env or 0)
			end
			if #kps > 0 then return ColorSequence.new(kps) end
		end,
	}

	local function decode_property(ptype, pname, text, openTag, shared)
		if ptype == 'string' or ptype == 'ProtectedString' or ptype == 'Content' then
			return xml_unescape(text)
		end
		if ptype == 'bool' then
			local t = text:match('^%s*(.-)%s*$') or ''
			if t == 'true' then return true end
			if t == 'false' then return false end
			return nil
		end
		if ptype == 'float' or ptype == 'double' or ptype == 'int' or ptype == 'int64' or ptype == 'uint64' or ptype == 'token' then
			return tonumber(text)
		end
		if ptype == 'BinaryString' then
			local ok, d = pcall(base64decode, text:match('^%s*(.-)%s*$') or '')
			return ok and d or nil
		end
		if ptype == 'SharedString' then
			local md = openTag:match('md5="([^"]+)"')
			if md then
				local sh = shared[md]
				if sh ~= nil then return sh end
			end
			local ok, d = pcall(base64decode, text:match('^%s*(.-)%s*$') or '')
			return ok and d or nil
		end
		if ptype == 'Ref' then
			return text
		end
		local c = construct[ptype]
		if c then
			return c(text, openTag)
		end
		return nil
	end

	

	

	

	

	local function parse_asset_xml(xml)
		local shared = {}
		if xml:find('<SharedStrings>', 1, true) then
			for md5, b64 in xml:gmatch('<SharedString md5="([^"]+)">(.-)</SharedString>') do
				if md5 ~= '' and b64 ~= '' then
					local ok, data = pcall(base64decode, b64)
					if ok and data then shared[md5] = data end
				end
			end
		end

		local byRef = {}
		local items = {}

		local pos = 1
		while true do
			local s = xml:find('<Item ', pos, true)
			if not s then break end
			local te = xml:find('>', s + 5, true)
			if not te then break end
			local oe = xml:find('</Item>', te + 1, true)
			if not oe then break end
			local block = xml:sub(s, te)
			local inner = xml:sub(te + 1, oe - 1)
			local klass = block:match('class="([^"]*)"')
			local referent = block:match('referent="([^"]*)"')
			if klass == 'Script' then
				

				

				warn('SpeedExecutor -- getobjects: dropped server Script <' .. tostring(referent) .. '> (kick guard)')
			elseif klass and klass ~= '' and referent and referent ~= '' then
				local ok, inst = pcall(Instance.new, klass)
				if ok and inst then
					local item = { inst = inst, parent = nil, pendingRefs = {}, xml = inner }
					byRef[referent] = item
					items[#items + 1] = item
				end
			end
			pos = oe + 8
		end

		for _, item in ipairs(items) do
			local inst = item.inst
			local pblock = item.xml:match('<Properties>(.-)</Properties>')
			if pblock then
				local ppos = 1
				while true do
					local ts, te, ptype, pname = pblock:find('<([%a_]+) name="([^"]+)"', ppos)
					if not ts then break end
					local gt = pblock:find('>', te, true)
					if not gt then break end
					local openTag = pblock:sub(ts, gt)
					if openTag:sub(-1) == '>' and openTag:sub(-2) == '/>' then
						if ptype == 'SharedString' then
							local md = openTag:match('md5="([^"]+)"')
							if md then
								local sh = shared[md]
								if sh ~= nil then pcall(function() inst[pname] = sh end) end
							end
						end
						ppos = gt + 1
					else
						local innerStart = gt + 1
						local cet, ce = pblock:find('</' .. ptype .. '>', innerStart, true)
						if cet then
							local valueText = pblock:sub(innerStart, cet - 1)
							local value = decode_property(ptype, pname, valueText, openTag, shared)
							if value ~= nil then
								if ptype == 'Ref' then
									if pname == 'Parent' then
										item.parent = valueText:match('^%s*(.-)%s*$')
									else
										item.pendingRefs[pname] = valueText:match('^%s*(.-)%s*$')
									end
								else
									pcall(function() inst[pname] = value end)
								end
							end
							ppos = ce + 1
						else
							ppos = gt + 1
						end
					end
					if ppos <= ts then ppos = ts + 1 end
				end
			end
		end

		for _, item in ipairs(items) do
			if item.parent and item.parent ~= 'null' then
				local parent = byRef[item.parent]
				if parent then pcall(function() item.inst.Parent = parent.inst end) end
			end
			for pn, r in pairs(item.pendingRefs) do
				local target = byRef[r]
				if target then pcall(function() item.inst[pn] = target.inst end) end
			end
		end

		local out = {}
		for _, item in ipairs(items) do
			if not item.parent or item.parent == 'null' or not byRef[item.parent] then
				out[#out + 1] = item.inst
			end
		end
		return out
	end

	rawset(game, 'GetObjects', function(self, url, ...)
		local out = {}
		local urls = { url, ... }
		for _, u in ipairs(urls) do
			if type(u) ~= 'string' then
				error('invalid argument #1 to \'GetObjects\' (string expected, got ' .. type(u) .. ')', 2)
			end
			local t0 = os.clock()
			local ok, inst = pcall(function()
				return game_o:GetService('InsertService'):LoadLocalAsset(u)
			end)
			local t1 = os.clock()
			if ok and inst then
				out[#out + 1] = inst
				if t1 - t0 > 1 then
					pcall(send_method, 'log', base64encode('[diag] LoadLocalAsset ' .. tostring(u) .. ' took ' .. (t1 - t0) .. 's'))
				end
			else
				warn('SpeedExecutor -- getobjects: failed to load asset <' .. tostring(u) .. '> (' .. tostring(inst) .. ')')
			end
		end
		return out
	end)
end

local game_wrappers = {}
local game_metamethod_hooks = {}
local current_namecall = {}
setmetatable(current_namecall, { __mode = 'k' })

local game_mt = {
	__index = function(_, key)
		local index_hook = game_metamethod_hooks['__index']
		if index_hook ~= nil then
			return index_hook(game, key)
		end

		

		

		if key == "CoreGui" and current_identity < 8 then
			return nil
		end

		local value = game_o[key]

		if type(value) == "function" then
			local cached = game_wrappers[key]
			if not cached then
				cached = function(_, ...)
					if key == "GetService" and current_identity < 8 then
						local first = ...
						if first == "CoreGui" then
							return nil
						end
					end
					current_namecall[coroutine.running()] = key
					local namecall_hook = game_metamethod_hooks['__namecall']
					if namecall_hook ~= nil then
						return namecall_hook(game, ...)
					end
					return value(game_o, ...)
				end
				game_wrappers[key] = cached
			end
			return cached
		end

		return value
	end,

	__newindex = function(_, key, value)
		local newindex_hook = game_metamethod_hooks['__newindex']
		if newindex_hook ~= nil then
			newindex_hook(game, key, value)
			return
		end
		game_o[key] = value
	end,

	__tostring = function()
		return tostring(game_o)
	end
}

setmetatable(game, game_mt)







readonly_tables[game_mt] = true

table.freeze(game)




local b64_alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local b64_codes = {string.byte(b64_alphabet, 1, 64)}

local b64_lookup = {}
for i = 1, #b64_alphabet do
	b64_lookup[string.byte(b64_alphabet, i)] = i - 1
end

function base64encode(data)
	local len = #data
	if len == 0 then
		return ''
	end

	local src = buffer.fromstring(data)
	local out = buffer.create(math.ceil(len / 3) * 4)
	local o = 0

	local i = 1
	while i + 2 <= len do
		local n = buffer.readu8(src, i - 1) * 65536 + buffer.readu8(src, i) * 256 + buffer.readu8(src, i + 1)
		buffer.writeu8(out, o, b64_codes[bit32.rshift(n, 18) + 1])
		buffer.writeu8(out, o + 1, b64_codes[bit32.band(bit32.rshift(n, 12), 63) + 1])
		buffer.writeu8(out, o + 2, b64_codes[bit32.band(bit32.rshift(n, 6), 63) + 1])
		buffer.writeu8(out, o + 3, b64_codes[bit32.band(n, 63) + 1])
		o += 4
		i += 3
	end

	local rest = len - i + 1
	if rest == 1 then
		local n = buffer.readu8(src, i - 1)
		buffer.writeu8(out, o, b64_codes[bit32.rshift(n, 2) + 1])
		buffer.writeu8(out, o + 1, b64_codes[bit32.band(bit32.lshift(n, 4), 63) + 1])
		buffer.writeu8(out, o + 2, 61)
		buffer.writeu8(out, o + 3, 61)
	elseif rest == 2 then
		local n = buffer.readu8(src, i - 1) * 256 + buffer.readu8(src, i)
		buffer.writeu8(out, o, b64_codes[bit32.rshift(n, 10) + 1])
		buffer.writeu8(out, o + 1, b64_codes[bit32.band(bit32.rshift(n, 4), 63) + 1])
		buffer.writeu8(out, o + 2, b64_codes[bit32.band(bit32.lshift(n, 2), 63) + 1])
		buffer.writeu8(out, o + 3, 61)
	end

	return buffer.tostring(out)
end

function base64decode(data)
	local len = #data
	if len == 0 then
		return ''
	end

	local padding = 0
	while padding < 2 and string.byte(data, len - padding) == 61 do
		padding += 1
	end

	local stripped = len - padding
	local tail = stripped % 4
	local out = buffer.create(stripped // 4 * 3 + (tail == 2 and 1 or tail == 3 and 2 or 0))
	local o = 0

	local src = buffer.fromstring(data)
	local i = 0
	while i + 4 <= stripped do
		local a = b64_lookup[buffer.readu8(src, i)] or 0
		local b = b64_lookup[buffer.readu8(src, i + 1)] or 0
		local c = b64_lookup[buffer.readu8(src, i + 2)] or 0
		local d = b64_lookup[buffer.readu8(src, i + 3)] or 0
		buffer.writeu8(out, o, bit32.band(bit32.lshift(a, 2) + bit32.rshift(b, 4), 255))
		buffer.writeu8(out, o + 1, bit32.band(bit32.lshift(b, 4) + bit32.rshift(c, 2), 255))
		buffer.writeu8(out, o + 2, bit32.band(bit32.lshift(c, 6) + d, 255))
		o += 3
		i += 4
	end

	if tail == 2 then
		local a = b64_lookup[buffer.readu8(src, i)] or 0
		local b = b64_lookup[buffer.readu8(src, i + 1)] or 0
		buffer.writeu8(out, o, bit32.band(bit32.lshift(a, 2) + bit32.rshift(b, 4), 255))
	elseif tail == 3 then
		local a = b64_lookup[buffer.readu8(src, i)] or 0
		local b = b64_lookup[buffer.readu8(src, i + 1)] or 0
		local c = b64_lookup[buffer.readu8(src, i + 2)] or 0
		buffer.writeu8(out, o, bit32.band(bit32.lshift(a, 2) + bit32.rshift(b, 4), 255))
		buffer.writeu8(out, o + 1, bit32.band(bit32.lshift(b, 4) + bit32.rshift(c, 2), 255))
	end

	return buffer.tostring(out)
end

crypt = {}
crypt.base64encode = base64encode
crypt.base64decode = base64decode

crypt.generatekey = function(len)
	len = len or 32
	local bytes = table.create(len)
	for i = 1, len do
		bytes[i] = math.random(0, 255)
	end
	return base64encode(string.char(table.unpack(bytes, 1, len)))
end

crypt.generatebytes = crypt.generatekey
crypt.random = crypt.generatekey

crypt.base64 = { encode = base64encode, decode = base64decode }
crypt.base64_encode = base64encode
crypt.base64_decode = base64decode
base64 = { encode = base64encode, decode = base64decode }
base64_encode = base64encode
base64_decode = base64decode

crypt.encrypt = function(data, key)
	data = tostring(data)
	key = tostring(key)
	local result = table.create(#data)
	for i = 1, #data do
		result[i] = string.char(bit32.bxor(string.byte(data, i), string.byte(key, (i - 1) % #key + 1)))
	end
	return table.concat(result), key
end

crypt.decrypt = crypt.encrypt

local _hash_state = { built = false }

local function _hash_build()
	if _hash_state.built then return end
	local bor, band, bxor, bnot = bit32.bor, bit32.band, bit32.bxor, bit32.bnot
	local lshift, rshift, rrot = bit32.lshift, bit32.rshift, bit32.rrotate
	local lrot = bit32.lrotate
	local char, byte, sub, gsub, format = string.char, string.byte, string.sub, string.gsub, string.format

	local function tohex(bin)
		return (gsub(bin, '.', function(c) return format('%02x', byte(c)) end))
	end

	local K256 = {
		0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
		0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
		0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
		0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
		0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
		0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
		0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
		0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
	}
	local function sha256(msg, ivarg)
		local iv = ivarg or {
			0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19,
		}
		local bits = #msg * 8
		msg = msg .. '\128'
		while (#msg % 64) ~= 56 do msg = msg .. '\0' end
		msg = msg .. char(
			band(rshift(bits, 56), 0xff), band(rshift(bits, 48), 0xff),
			band(rshift(bits, 40), 0xff), band(rshift(bits, 32), 0xff),
			band(rshift(bits, 24), 0xff), band(rshift(bits, 16), 0xff),
			band(rshift(bits, 8), 0xff),  band(bits, 0xff))
		local H1,H2,H3,H4,H5,H6,H7,H8 = iv[1],iv[2],iv[3],iv[4],iv[5],iv[6],iv[7],iv[8]
		local W = {}
		for chunkStart = 1, #msg, 64 do
			for i = 0, 15 do
				local o = chunkStart + i * 4
				W[i + 1] = lshift(byte(msg, o), 24) + lshift(byte(msg, o + 1), 16)
					+ lshift(byte(msg, o + 2), 8) + byte(msg, o + 3)
			end
			for i = 17, 64 do
				local w15, w2 = W[i - 15], W[i - 2]
				local s0 = bxor(rrot(w15, 7), rrot(w15, 18), rshift(w15, 3))
				local s1 = bxor(rrot(w2, 17), rrot(w2, 19), rshift(w2, 10))
				W[i] = band(W[i - 16] + s0 + W[i - 7] + s1, 0xffffffff)
			end
			local a,b,c,d,e,f,g,h = H1,H2,H3,H4,H5,H6,H7,H8
			for i = 1, 64 do
				local S1 = bxor(rrot(e, 6), rrot(e, 11), rrot(e, 25))
				local ch = bxor(band(e, f), band(bnot(e), g))
				local t1 = h + S1 + ch + K256[i] + W[i]
				local S0 = bxor(rrot(a, 2), rrot(a, 13), rrot(a, 22))
				local mj = bxor(band(a, b), band(a, c), band(b, c))
				local t2 = S0 + mj
				h = g; g = f; f = e
				e = band(d + t1, 0xffffffff)
				d = c; c = b; b = a
				a = band(t1 + t2, 0xffffffff)
			end
			H1 = band(H1 + a, 0xffffffff); H2 = band(H2 + b, 0xffffffff)
			H3 = band(H3 + c, 0xffffffff); H4 = band(H4 + d, 0xffffffff)
			H5 = band(H5 + e, 0xffffffff); H6 = band(H6 + f, 0xffffffff)
			H7 = band(H7 + g, 0xffffffff); H8 = band(H8 + h, 0xffffffff)
		end
		local function w2b(w)
			return char(band(rshift(w, 24), 0xff), band(rshift(w, 16), 0xff),
				band(rshift(w, 8), 0xff), band(w, 0xff))
		end
		return w2b(H1)..w2b(H2)..w2b(H3)..w2b(H4)..w2b(H5)..w2b(H6)..w2b(H7)..w2b(H8)
	end
	local function sha224(msg)
		local iv = {0xc1059ed8,0x367cd507,0x3070dd17,0xf70e5939,0xffc00b31,0x68581511,0x64f98fa7,0xbefa4fa4}
		return sub(sha256(msg, iv), 1, 28)
	end

	local K512 = {
		{0x428a2f98,0xd728ae22},{0x71374491,0x23ef65cd},{0xb5c0fbcf,0xec4d3b2f},{0xe9b5dba5,0x8189dbbc},
		{0x3956c25b,0xf348b538},{0x59f111f1,0xb605d019},{0x923f82a4,0xaf194f9b},{0xab1c5ed5,0xda6d8118},
		{0xd807aa98,0xa3030242},{0x12835b01,0x45706fbe},{0x243185be,0x4ee4b28c},{0x550c7dc3,0xd5ffb4e2},
		{0x72be5d74,0xf27b896f},{0x80deb1fe,0x3b1696b1},{0x9bdc06a7,0x25c71235},{0xc19bf174,0xcf692694},
		{0xe49b69c1,0x9ef14ad2},{0xefbe4786,0x384f25e3},{0x0fc19dc6,0x8b8cd5b5},{0x240ca1cc,0x77ac9c65},
		{0x2de92c6f,0x592b0275},{0x4a7484aa,0x6ea6e483},{0x5cb0a9dc,0xbd41fbd4},{0x76f988da,0x831153b5},
		{0x983e5152,0xee66dfab},{0xa831c66d,0x2db43210},{0xb00327c8,0x98fb213f},{0xbf597fc7,0xbeef0ee4},
		{0xc6e00bf3,0x3da88fc2},{0xd5a79147,0x930aa725},{0x06ca6351,0xe003826f},{0x14292967,0x0a0e6e70},
		{0x27b70a85,0x46d22ffc},{0x2e1b2138,0x5c26c926},{0x4d2c6dfc,0x5ac42aed},{0x53380d13,0x9d95b3df},
		{0x650a7354,0x8baf63de},{0x766a0abb,0x3c77b2a8},{0x81c2c92e,0x47edaee6},{0x92722c85,0x1482353b},
		{0xa2bfe8a1,0x4cf10364},{0xa81a664b,0xbc423001},{0xc24b8b70,0xd0f89791},{0xc76c51a3,0x0654be30},
		{0xd192e819,0xd6ef5218},{0xd6990624,0x5565a910},{0xf40e3585,0x5771202a},{0x106aa070,0x32bbd1b8},
		{0x19a4c116,0xb8d2d0c8},{0x1e376c08,0x5141ab53},{0x2748774c,0xdf8eeb99},{0x34b0bcb5,0xe19b48a8},
		{0x391c0cb3,0xc5c95a63},{0x4ed8aa4a,0xe3418acb},{0x5b9cca4f,0x7763e373},{0x682e6ff3,0xd6b2b8a3},
		{0x748f82ee,0x5defb2fc},{0x78a5636f,0x43172f60},{0x84c87814,0xa1f0ab72},{0x8cc70208,0x1a6439ec},
		{0x90befffa,0x23631e28},{0xa4506ceb,0xde82bde9},{0xbef9a3f7,0xb2c67915},{0xc67178f2,0xe372532b},
		{0xca273ece,0xea26619c},{0xd186b8c7,0x21c0c207},{0xeada7dd6,0xcde0eb1e},{0xf57d4f7f,0xee6ed178},
		{0x06f067aa,0x72176fba},{0x0a637dc5,0xa2c898a6},{0x113f9804,0xbef90dae},{0x1b710b35,0x131c471b},
		{0x28db77f5,0x23047d84},{0x32caab7b,0x40c72493},{0x3c9ebe0a,0x15c9bebc},{0x431d67c4,0x9c100d4c},
		{0x4cc5d4be,0xcb3e42b6},{0x597f299c,0xfc657e2a},{0x5fcb6fab,0x3ad6faec},{0x6c44198c,0x4a475817},
	}
	local function add64(a, b, c, d, e)
		local lo = a[2] + b[2] + (c and c[2] or 0) + (d and d[2] or 0) + (e and e[2] or 0)
		local carry = math.floor(lo / 0x100000000)
		lo = lo % 0x100000000
		local hi = (a[1] + b[1] + (c and c[1] or 0) + (d and d[1] or 0) + (e and e[1] or 0) + carry) % 0x100000000
		return {hi, lo}
	end
	local function xor64(a, b, c) return {bxor(a[1], b[1], c and c[1] or 0), bxor(a[2], b[2], c and c[2] or 0)} end
	local function and64(a, b) return {band(a[1], b[1]), band(a[2], b[2])} end
	local function not64(a) return {band(bnot(a[1]), 0xffffffff), band(bnot(a[2]), 0xffffffff)} end
	local function ror64(a, n)
		if n >= 32 then a = {a[2], a[1]}; n = n - 32 end
		if n == 0 then return a end
		return {bor(rshift(a[1], n), band(lshift(a[2], 32 - n), 0xffffffff)),
			bor(rshift(a[2], n), band(lshift(a[1], 32 - n), 0xffffffff))}
	end
	local function shr64(a, n)
		if n >= 32 then return {0, rshift(a[1], n - 32)} end
		if n == 0 then return a end
		return {rshift(a[1], n),
			bor(rshift(a[2], n), band(lshift(a[1], 32 - n), 0xffffffff))}
	end
	local function sha512(msg, ivarg)
		local iv = ivarg or {
			{0x6a09e667,0xf3bcc908},{0xbb67ae85,0x84caa73b},{0x3c6ef372,0xfe94f82b},{0xa54ff53a,0x5f1d36f1},
			{0x510e527f,0xade682d1},{0x9b05688c,0x2b3e6c1f},{0x1f83d9ab,0xfb41bd6b},{0x5be0cd19,0x137e2179},
		}
		local bits = #msg * 8
		msg = msg .. '\128'
		while (#msg % 128) ~= 112 do msg = msg .. '\0' end
		msg = msg .. string.rep('\0', 8) .. char(
			band(rshift(bits, 56), 0xff), band(rshift(bits, 48), 0xff),
			band(rshift(bits, 40), 0xff), band(rshift(bits, 32), 0xff),
			band(rshift(bits, 24), 0xff), band(rshift(bits, 16), 0xff),
			band(rshift(bits, 8), 0xff),  band(bits, 0xff))
		local H = {iv[1],iv[2],iv[3],iv[4],iv[5],iv[6],iv[7],iv[8]}
		local W = {}
		for chunkStart = 1, #msg, 128 do
			for i = 0, 15 do
				local o = chunkStart + i * 8
				local hi = lshift(byte(msg, o), 24) + lshift(byte(msg, o + 1), 16)
					+ lshift(byte(msg, o + 2), 8) + byte(msg, o + 3)
				local lo = lshift(byte(msg, o + 4), 24) + lshift(byte(msg, o + 5), 16)
					+ lshift(byte(msg, o + 6), 8) + byte(msg, o + 7)
				W[i + 1] = {hi, lo}
			end
			for i = 17, 80 do
				local w15, w2 = W[i - 15], W[i - 2]
				local s0 = xor64(ror64(w15, 1), ror64(w15, 8), shr64(w15, 7))
				local s1 = xor64(ror64(w2, 19), ror64(w2, 61), shr64(w2, 6))
				W[i] = add64(W[i - 16], s0, W[i - 7], s1)
			end
			local a,b,c,d,e,f,g,h = H[1],H[2],H[3],H[4],H[5],H[6],H[7],H[8]
			for i = 1, 80 do
				local S1 = xor64(ror64(e, 14), ror64(e, 18), ror64(e, 41))
				local ch = xor64(and64(e, f), and64(not64(e), g))
				local t1 = add64(h, S1, ch, K512[i], W[i])
				local S0 = xor64(ror64(a, 28), ror64(a, 34), ror64(a, 39))
				local mj = xor64(and64(a, b), and64(a, c), and64(b, c))
				local t2 = add64(S0, mj)
				h = g; g = f; f = e
				e = add64(d, t1)
				d = c; c = b; b = a
				a = add64(t1, t2)
			end
			H[1] = add64(H[1], a); H[2] = add64(H[2], b); H[3] = add64(H[3], c); H[4] = add64(H[4], d)
			H[5] = add64(H[5], e); H[6] = add64(H[6], f); H[7] = add64(H[7], g); H[8] = add64(H[8], h)
		end
		local function w2b(w)
			return char(band(rshift(w[1], 24), 0xff), band(rshift(w[1], 16), 0xff),
				band(rshift(w[1], 8), 0xff), band(w[1], 0xff),
				band(rshift(w[2], 24), 0xff), band(rshift(w[2], 16), 0xff),
				band(rshift(w[2], 8), 0xff), band(w[2], 0xff))
		end
		return w2b(H[1])..w2b(H[2])..w2b(H[3])..w2b(H[4])..w2b(H[5])..w2b(H[6])..w2b(H[7])..w2b(H[8])
	end
	local function sha384(msg)
		return sub(sha512(msg, {
			{0xcbbb9d5d,0xc1059ed8},{0x629a292a,0x367cd507},{0x9159015a,0x3070dd17},{0x152fecd8,0xf70e5939},
			{0x67332667,0xffc00b31},{0x8eb44a87,0x68581511},{0xdb0c2e0d,0x64f98fa7},{0x47b5481d,0xbefa4fa4},
		}), 1, 48)
	end

	local RC = {
		{0x00000000,0x00000001},{0x00000000,0x00008082},{0x80000000,0x0000808a},{0x80000000,0x80008000},
		{0x00000000,0x0000808b},{0x00000000,0x80000001},{0x80000000,0x80008081},{0x80000000,0x00008009},
		{0x00000000,0x0000008a},{0x00000000,0x00000088},{0x00000000,0x80008009},{0x00000000,0x8000000a},
		{0x00000000,0x8000808b},{0x80000000,0x0000008b},{0x80000000,0x00008089},{0x80000000,0x00008003},
		{0x80000000,0x00008002},{0x80000000,0x00000080},{0x00000000,0x0000800a},{0x80000000,0x8000000a},
		{0x80000000,0x80008081},{0x80000000,0x00008080},{0x00000000,0x80000001},{0x80000000,0x80008008},
	}
	local ROT = {0,1,62,28,27,36,44,6,55,20,3,10,43,25,39,41,45,15,21,8,18,2,61,56,14}
	local function rotl64(a, n)
		if n == 0 then return a end
		if n >= 32 then a = {a[2], a[1]}; n = n - 32 end
		if n == 0 then return a end
		return {bor(band(lshift(a[1], n), 0xffffffff), rshift(a[2], 32 - n)),
			bor(band(lshift(a[2], n), 0xffffffff), rshift(a[1], 32 - n))}
	end
	local function keccakf(S)
		local B, C, D = {}, {}, {}
		for r = 1, 24 do
			for x = 0, 4 do
				local a,b,c,d,e = S[x + 1], S[x + 6], S[x + 11], S[x + 16], S[x + 21]
				C[x + 1] = {bxor(a[1], b[1], c[1], d[1], e[1]), bxor(a[2], b[2], c[2], d[2], e[2])}
			end
			for x = 0, 4 do
				local c1 = C[((x + 4) % 5) + 1]
				local c2 = rotl64(C[((x + 1) % 5) + 1], 1)
				D[x + 1] = {bxor(c1[1], c2[1]), bxor(c1[2], c2[2])}
			end
			for x = 0, 4 do
				local d = D[x + 1]
				for y = 0, 4 do
					local idx = x + y * 5 + 1
					local s = S[idx]
					S[idx] = {bxor(s[1], d[1]), bxor(s[2], d[2])}
				end
			end
			for x = 0, 4 do
				for y = 0, 4 do
					local idx = x + y * 5 + 1
					local nx = y
					local ny = (2 * x + 3 * y) % 5
					B[nx + ny * 5 + 1] = rotl64(S[idx], ROT[idx])
				end
			end
			for x = 0, 4 do
				for y = 0, 4 do
					local idx = x + y * 5 + 1
					local b0 = B[idx]
					local b1 = B[((x + 1) % 5) + y * 5 + 1]
					local b2 = B[((x + 2) % 5) + y * 5 + 1]
					S[idx] = {bxor(b0[1], band(bnot(b1[1]), b2[1])),
						bxor(b0[2], band(bnot(b1[2]), b2[2]))}
				end
			end
			local rc = RC[r]
			S[1] = {bxor(S[1][1], rc[1]), bxor(S[1][2], rc[2])}
		end
	end
	local function sha3(msg, bits)
		local rate = 200 - bits / 4  -- bytes; e.g. 224→144, 256→136, 384→104, 512→72
		local S = {}
		for i = 1, 25 do S[i] = {0, 0} end
		local pos = 1
		local mlen = #msg
		local pad = {}
		for i = 0, rate - 1 do pad[i + 1] = 0 end
		while pos <= mlen do
			local take = math.min(rate, mlen - pos + 1)
			for i = 1, take do pad[i] = byte(msg, pos + i - 1) end
			for i = take + 1, rate do pad[i] = 0 end
			if take < rate then
				pad[take + 1] = bxor(pad[take + 1] or 0, 0x06)
				pad[rate] = bxor(pad[rate], 0x80)
			end
			for i = 0, rate / 8 - 1 do
				local o = i * 8
				local lo = pad[o + 1] + pad[o + 2] * 0x100 + pad[o + 3] * 0x10000 + pad[o + 4] * 0x1000000
				local hi = pad[o + 5] + pad[o + 6] * 0x100 + pad[o + 7] * 0x10000 + pad[o + 8] * 0x1000000
				local s = S[i + 1]
				S[i + 1] = {bxor(s[1], hi), bxor(s[2], lo)}
			end
			keccakf(S)
			pos = pos + take
			if take == rate then
				-- full block consumed; still need pad-only block
				for i = 1, rate do pad[i] = 0 end
				pad[1] = 0x06; pad[rate] = bxor(pad[rate], 0x80)
				for i = 0, rate / 8 - 1 do
					local o = i * 8
					local lo = pad[o + 1] + pad[o + 2] * 0x100 + pad[o + 3] * 0x10000 + pad[o + 4] * 0x1000000
					local hi = pad[o + 5] + pad[o + 6] * 0x100 + pad[o + 7] * 0x10000 + pad[o + 8] * 0x1000000
					local s = S[i + 1]
					S[i + 1] = {bxor(s[1], hi), bxor(s[2], lo)}
				end
				keccakf(S)
				break
			end
		end
		if mlen == 0 then
			pad[1] = 0x06; pad[rate] = 0x80
			for i = 0, rate / 8 - 1 do
				local o = i * 8
				local lo = pad[o + 1] + pad[o + 2] * 0x100 + pad[o + 3] * 0x10000 + pad[o + 4] * 0x1000000
				local hi = pad[o + 5] + pad[o + 6] * 0x100 + pad[o + 7] * 0x10000 + pad[o + 8] * 0x1000000
				local s = S[i + 1]
				S[i + 1] = {bxor(s[1], hi), bxor(s[2], lo)}
			end
			keccakf(S)
		end
		local out = {}
		local outlen = bits / 8
		local widx = 1
		while #out < outlen do
			local w = S[widx]; widx = widx + 1
			local lo, hi = w[2], w[1]
			out[#out + 1] = char(band(lo, 0xff)); if #out == outlen then break end
			out[#out + 1] = char(band(rshift(lo, 8), 0xff)); if #out == outlen then break end
			out[#out + 1] = char(band(rshift(lo, 16), 0xff)); if #out == outlen then break end
			out[#out + 1] = char(band(rshift(lo, 24), 0xff)); if #out == outlen then break end
			out[#out + 1] = char(band(hi, 0xff)); if #out == outlen then break end
			out[#out + 1] = char(band(rshift(hi, 8), 0xff)); if #out == outlen then break end
			out[#out + 1] = char(band(rshift(hi, 16), 0xff)); if #out == outlen then break end
			out[#out + 1] = char(band(rshift(hi, 24), 0xff))
		end
		return table.concat(out)
	end

	_hash_state.tohex = tohex
	_hash_state.sha224 = function(m) return tohex(sha224(m)) end
	_hash_state.sha256 = function(m) return tohex(sha256(m)) end
	_hash_state.sha384 = function(m) return tohex(sha384(m)) end
	_hash_state.sha512 = function(m) return tohex(sha512(m)) end
	_hash_state.sha3_224 = function(m) return tohex(sha3(m, 224)) end
	_hash_state.sha3_256 = function(m) return tohex(sha3(m, 256)) end
	_hash_state.sha3_384 = function(m) return tohex(sha3(m, 384)) end
	_hash_state.sha3_512 = function(m) return tohex(sha3(m, 512)) end
	_hash_state.built = true
end

local function _local_hash(algo, data)
	_hash_build()
	local a = algo:lower():gsub('[-_]', '')
	if a == 'sha224' then return _hash_state.sha224(data) end
	if a == 'sha256' then return _hash_state.sha256(data) end
	if a == 'sha384' then return _hash_state.sha384(data) end
	if a == 'sha512' then return _hash_state.sha512(data) end
	if a == 'sha3224' then return _hash_state.sha3_224(data) end
	if a == 'sha3256' then return _hash_state.sha3_256(data) end
	if a == 'sha3384' then return _hash_state.sha3_384(data) end
	if a == 'sha3512' then return _hash_state.sha3_512(data) end
	return nil
end

crypt.hash = function(data, hash_name)
	assert(type(data) == 'string', "invalid argument #1 to 'crypt.hash' (string expected, got " .. type(data) .. ')', 2)
	assert(type(hash_name) == 'string', "invalid argument #2 to 'crypt.hash' (string expected, got " .. type(hash_name) .. ')', 2)

	local response = send_method('hash', hash_name, base64encode(data))
	if type(response) == 'string' and response ~= '' and response:sub(1, 4) ~= 'fail' then
		return response
	end
	local ok, local_hex = pcall(_local_hash, hash_name, data)
	if ok and local_hex then return local_hex end
	return nil
end




lz4compress = lz4.compress
lz4decompress = lz4.decompress




loadstring = function(source, chunkname)
	local ok, result = pcall(function()
		assert(type(source) == 'string', "invalid argument #1 to 'loadstring' (string expected, got " .. type(source) .. ')')
		

		

		local response = send_method('compile_raw', source)
		if type(response) ~= 'string' or response == '' or response:sub(1, 4) == 'fail' then
			

			response = send_method('compile', base64encode(source))
			assert(type(response) == 'string' and response:sub(1, 4) ~= 'fail', 'compile error')
			response = base64decode(response)
		end
		local func = load_bytecode(response, getfenv())
		assert(type(func) == 'function', 'compile error')
		return func
	end)
	if ok then
		return result
	end
	local name = chunkname ~= nil and tostring(chunkname) or 'loadstring'
	return nil, '[string "' .. name .. '"]: ' .. tostring(result)
end




local blocked_extensions = {".exe", ".scr", ".bat", ".com", ".csh", ".msi", ".vb", ".vbs",
	".vbe", ".ws", ".wsf", ".wsh", ".ps1", ".py", ".apk", ".pif", ".cpl", ".msc",
	".jar", ".cmd", ".hta", ".gadget", ".inf", ".ins", ".isp", ".psd1", ".psm1",
	".reg", ".scf", ".shb", ".sys", ".js", ".jse", ".lnk", ".msp",
	".zip", ".rar", ".7z", ".tar", ".gz", ".cab", ".iso", ".img",
	".dll", ".ocx", ".drv", ".vxd", ".xml", ".ini", ".cpp", ".c", ".url", ".uri",
	".deb", ".rpm", ".sh", ".bash", ".zsh", ".fish", ".npm"}

local function isBlockedExtension(path: string): boolean
	

	local name = (path:lower():gsub("[%s.]+$", ""))
	for _, ext in blocked_extensions do
		if name:sub(-#ext) == ext then
			return true
		end
	end
	return false
end

writefile = function(path, content)
	if isBlockedExtension(path) then
		warn('SpeedExecutor -- writefile blocked: ' .. path)
		return
	end
	

	local response = send_method('writefile', path, base64encode(content))
	if response ~= 'ok' then
		warn('SpeedExecutor -- file error: '..tostring(response))
	end
end

appendfile = function(path, content)
	if isBlockedExtension(path) then
		warn('SpeedExecutor -- appendfile blocked: ' .. path)
		return
	end
	local response = send_method('appendfile', path, base64encode(content))
	if response ~= 'ok' then
		warn('SpeedExecutor -- file error: '..tostring(response))
	end
end

readfile = function(path)
	local response = send_method('readfile', path)
	if response == 'fail' or type(response) ~= 'string' then
		error('SpeedExecutor -- file error: unable to read \'' .. tostring(path) .. '\'', 2)
	end
	return base64decode(response)
end

isfile = function(path)
	local response = send_method('isfile', path)
	if response ~= 'true' and response ~= 'false' then
		warn('SpeedExecutor -- file error: '..tostring(response))
	end
	return response == 'true'
end

isfolder = function(path)
	local response = send_method('isfolder', path)
	if response ~= 'true' and response ~= 'false' then
		warn('SpeedExecutor -- file error: '..tostring(response))
		return nil
	end
	return response == 'true'
end

delfile = function(path)
	local response = send_method('delfile', path)
	if response ~= 'ok' then
		warn('SpeedExecutor -- file error: '..tostring(response))
	end
end

delfolder = function(path)
	local response = send_method('delfolder', path)
	if response ~= 'ok' then
		warn('SpeedExecutor -- file error: '..tostring(response))
	end
end

makefolder = function(path)
	local response = send_method('makefolder', path)
	if response ~= 'ok' then
		warn('SpeedExecutor -- file error: '..tostring(response))
	end
end

listfiles = function(path)
	local response = send_method('listfiles', path)
	if response == 'fail' then
		warn('SpeedExecutor -- listfiles: folder not found: ' .. tostring(path))
		return {}
	end
	if response == '' then
		return {}
	end
	local raw = response:split('\n')
	local base = tostring(path)
	base = base:gsub('[\\/]+$', '')
	local out = table.create(#raw)
	for i, entry in ipairs(raw) do
		if entry ~= '' then
			if entry:find('[\\/]') or entry:match('^%a:') then
				out[#out + 1] = entry
			elseif base == '' or base == '.' then
				out[#out + 1] = './' .. entry
			else
				out[#out + 1] = base .. '/' .. entry
			end
		end
	end
	return out
end




loadfile = function(path: string)
	local read_ok, content = pcall(readfile, path)
	if not read_ok or not content then
		return nil, 'SpeedExecutor -- loadfile: unable to read \'' .. tostring(path) .. '\''
	end

	local ok, result = pcall(loadstring, content)
	if not ok or result == nil then
		return nil, 'SpeedExecutor -- loadfile: ' .. tostring(result)
	end

	return result
end




setfpscap = function(fps: number)
	if type(fps) ~= 'number' then
		error('setfpscap expects a number', 2)
	end

	local response = send_method('setfpscap', tostring(math.floor(fps + 0.5)))
	if response ~= 'ok' then
		warn('SpeedExecutor -- setfpscap failed: ' .. tostring(fps))
	end
end

getfpscap = function()
	local response = send_method('getfpscap')
	local cap = tonumber(response)
	if not cap then
		warn('SpeedExecutor -- getfpscap failed')
		return nil
	end
	return cap
end







local value_offset_ready = false

local function ensure_value_offset()
	if value_offset_ready then
		return true
	end
	local calib = Instance.new("ModuleScript")
	calib.Name = "CALIB" .. tostring(math.random(100000, 999999))
	local holder = Instance.new("ObjectValue")
	holder.Name = http_service:GenerateGUID(false)
	local ok, result = pcall(function()
		calib.Parent = folder
		holder.Value = calib
		holder.Parent = folder
		return send_method("calibrate_value", holder.Name, calib.Name)
	end)
	pcall(function() holder:Destroy() end)
	pcall(function() calib:Destroy() end)
	if ok and type(result) == "string" and tonumber(result) then
		value_offset_ready = true
		return true
	end
	warn("SpeedExecutor -- value-offset calibration: " .. tostring(result))
	return false
end

local function pointer_request(method_name, script)
	local holder = Instance.new('ObjectValue')
	holder.Name = http_service:GenerateGUID(false)
	holder.Value = script
	holder.Parent = folder

	local response = send_method(method_name, holder.Name)
	holder:Destroy()

	return response
end



dbg_dumpchain = function(script)
	ensure_value_offset()
	local holder = Instance.new('ObjectValue')
	holder.Name = http_service:GenerateGUID(false)
	holder.Value = script
	holder.Parent = folder
	local response = send_method('dbg_chain', holder.Name)
	holder:Destroy()
	return response
end

getscriptbytecode = function(script)
	assert(typeof(script) == 'Instance' and script:IsA('LuaSourceContainer'), "invalid argument #1 to 'getscriptbytecode' (LuaSourceContainer expected, got " .. typeof(script) .. ')', 2)

	ensure_value_offset()
	local response = pointer_request('getscriptbytecode', script)
	if type(response) ~= 'string' or response == '' or response:sub(1, 4) == 'fail' then
		warn('SpeedExecutor -- getscriptbytecode: ' .. tostring(response))
		return nil
	end
	return base64decode(response)
end

dumpstring = getscriptbytecode

getscripthash = function(script)
	assert(typeof(script) == 'Instance' and script:IsA('LuaSourceContainer'), "invalid argument #1 to 'getscripthash' (LuaSourceContainer expected, got " .. typeof(script) .. ')', 2)

	ensure_value_offset()
	local response = pointer_request('getscripthash', script)
	if type(response) == 'string' and response ~= '' and response:sub(1, 4) ~= 'fail' then
		return response
	end

	local ok_bc, bytecode = pcall(getscriptbytecode, script)
	if ok_bc and type(bytecode) == 'string' and #bytecode > 0 then
		local ok, hex = pcall(_local_hash, 'sha384', bytecode)
		if ok and hex then return hex end
	end
	warn('SpeedExecutor -- getscripthash: ' .. tostring(response))
	return nil
end




setclipboard = function(content)
	local response = send_method('setclipboard', base64encode(tostring(content)))
	if response ~= 'ok' then
		warn('SpeedExecutor -- clipboard error: '..tostring(response))
		return false
	end
	return true
end

getclipboard = function()
	local response = send_method('getclipboard')
	return response
end

toclipboard = setclipboard

local VIM
local vim_ok = pcall(function()
	VIM = game_o:GetService("VirtualInputManager")
end)
if not vim_ok or not VIM then
	vim_ok = pcall(function()
		VIM = Instance.new("VirtualInputManager")
	end)
end
local vim_UIS = game_o:GetService("UserInputService")

local function vim_target()
	local ok, cam = pcall(function() return workspace.CurrentCamera end)
	if ok and cam then return cam end
	return workspace.Parent
end

local function mouse_fallback(method, ...)
	local nargs = table.pack(...)
	for i = 1, nargs.n do
		nargs[i] = tostring(nargs[i])
	end
	local response = send_method(method, table.unpack(nargs, 1, nargs.n))
	if response == 'fail' then
		warn('SpeedExecutor -- input error: ' .. tostring(method))
	end
end

local function mouse_move_os(x, y)
	if vim_ok and VIM then
		pcall(function()
			VIM:SendMouseMoveEvent(x, y, vim_target())
		end)
		return true
	end
	return false
end

local function mouse_btn_os(x, y, btn, down)
	if vim_ok and VIM then
		pcall(function()
			VIM:SendMouseButtonEvent(x, y, btn, down, workspace.Parent, false)
		end)
		return true
	end
	return false
end

local function mouse_wheel_os(x, y, horiz)
	if vim_ok and VIM then
		pcall(function()
			VIM:SendMouseWheelEvent(x, y, horiz, workspace.Parent)
		end)
		return true
	end
	return false
end

mousemoverel = function(x, y)
	x = tonumber(x) or 0
	y = tonumber(y) or 0
	local vim = VIM
	if not vim then
		local ok, v = pcall(function() return game_o:GetService("VirtualInputManager") end)
		if ok then vim = v end
	end
	if vim then
		local ok = pcall(function()
			vim:SendMouseMoveEvent(x, y, game_o)
		end)
		if ok then return end
	end
	mouse_fallback('movemouserel', x, y)
end
mouserel = mousemoverel

mousemoveabs = function(x, y)
	if not mouse_move_os(x or 0, y or 0) then
		mouse_fallback('mousemoveabs', x or 0, y or 0)
	end
end
movemouse = mousemoveabs

mouse1click = function(x, y)
	x = x or 0
	y = y or 0
	if not mouse_btn_os(x, y, 0, true) then
		mouse_fallback('mouse1click', x, y)
		return
	end
	task.wait()
	mouse_btn_os(x, y, 0, false)
end
mouse1press = function(x, y)
	if not mouse_btn_os(x or 0, y or 0, 0, true) then
		mouse_fallback('mouse1down', x or 0, y or 0)
	end
end
mouse1release = function(x, y)
	if not mouse_btn_os(x or 0, y or 0, 0, false) then
		mouse_fallback('mouse1up', x or 0, y or 0)
	end
end
mouse2click = function(x, y)
	x = x or 0
	y = y or 0
	if not mouse_btn_os(x, y, 1, true) then
		mouse_fallback('mouse2click', x, y)
		return
	end
	task.wait()
	mouse_btn_os(x, y, 1, false)
end
mouse2press = function(x, y)
	if not mouse_btn_os(x or 0, y or 0, 1, true) then
		mouse_fallback('mouse2down', x or 0, y or 0)
	end
end
mouse2release = function(x, y)
	if not mouse_btn_os(x or 0, y or 0, 1, false) then
		mouse_fallback('mouse2up', x or 0, y or 0)
	end
end
middleclick = function(x, y)
	x = x or 0
	y = y or 0
	if not mouse_btn_os(x, y, 2, true) then
		mouse_fallback('middleclick', x, y)
		return
	end
	task.wait()
	mouse_btn_os(x, y, 2, false)
end
middlepress = function(x, y)
	if not mouse_btn_os(x or 0, y or 0, 2, true) then
		mouse_fallback('middledown', x or 0, y or 0)
	end
end
middlerelease = function(x, y)
	if not mouse_btn_os(x or 0, y or 0, 2, false) then
		mouse_fallback('middleup', x or 0, y or 0)
	end
end
mousescroll = function(x, y, horiz)
	if not mouse_wheel_os(x or 0, y or 0, horiz or false) then
		mouse_fallback('mousescroll', x or 0, y or 0)
	end
end

local input_keys = {
	keyclick = 'keyclick',
	keypress = 'keypress',
	keyrelease = 'keyrelease',
}

for name, method in input_keys do
	_G[name] = function(...)
		

		local nargs = table.pack(...)
		for i = 1, nargs.n do
			nargs[i] = tostring(nargs[i])
		end
		local response = send_method(method, table.unpack(nargs, 1, nargs.n))
		if response == 'fail' then
			warn('SpeedExecutor -- input error: ' .. name)
		end
	end
end

getmousepos = function()
	local ok, pos = pcall(function() return vim_UIS:GetMouseLocation() end)
	if ok and pos and type(pos.X) == 'number' then
		return pos.X, pos.Y
	end
	local response = send_method('getmousepos')
	local x, y = response:match('^(%-?%d+),(%-?%d+)$')
	if not x then
		return nil, nil
	end
	return tonumber(x), tonumber(y)
end

getmouselocation = getmousepos

iswindowactive = function()
	return send_method('iswindowactive') == 'true'
end

isrbxactive = iswindowactive

messagebox = function(text, title, flags)
	local response = send_method('messagebox', base64encode(tostring(text)), base64encode(tostring(title or 'SpeedExecutor')), tostring(flags or 0))
	return tonumber(response)
end




identifyexecutor = function()
	return 'SpeedExecutor', 'v0.340'
end

getexecutorname = function()
	return identifyexecutor()
end

getexecutorversion = function()
	return select(2, identifyexecutor())
end




local executor_closures = {}
setmetatable(executor_closures, {__mode = 'k'})



local cclosure_marks = {}
setmetatable(cclosure_marks, {__mode = 'k'})

islclosure = function(func)
	assert(type(func) == 'function', "invalid argument #1 to 'islclosure' (function expected, got " .. type(func) .. ')', 2)
	if cclosure_marks[func] then
		return false
	end
	return debug.info(func, 's') ~= '[C]'
end

isluaclosure = islclosure

iscclosure = function(func)
	assert(type(func) == 'function', "invalid argument #1 to 'iscclosure' (function expected, got " .. type(func) .. ')', 2)
	if cclosure_marks[func] then
		return true
	end
	return debug.info(func, 's') == '[C]'
end

newcclosure = function(func)
	assert(type(func) == 'function', "invalid argument #1 to 'newcclosure' (function expected, got " .. type(func) .. ')', 2)
	local wrapped = coroutine.wrap(function(...)
		while true do
			coroutine.yield(func(...))
		end
	end)
	executor_closures[wrapped] = true
	cclosure_marks[wrapped] = true
	return wrapped
end

clonefunction = function(func)
	assert(type(func) == 'function', "invalid argument #1 to 'clonefunction' (function expected, got " .. type(func) .. ')', 2)
	if iscclosure(func) then
		return newcclosure(func)
	end
	

	return function(...)
		if type(fiu_debug) == 'table' and type(fiu_debug.calloriginal) == 'function' then
			return fiu_debug.calloriginal(func, ...)
		end
		return func(...)
	end
end

isexecutorclosure = function(func)
	if type(func) ~= 'function' then
		error("invalid argument #1 to 'isexecutorclosure' (function expected, got " .. type(func) .. ')', 2)
	end

	if executor_closures[func] then
		return true
	end

	if iscclosure(func) then
		return debug.info(func, 'n') == ''
	end

	local ok, fenv = pcall(getfenv, func)
	if not ok then
		return false
	end

	if typeof(fenv.script) ~= 'Instance' then
		return true
	end

	if fenv.script.Name == 'AvatarEditorPrompts' or fenv.script.Name == 'JestGlobals' then
		return false
	end

	if fenv.script.Parent == nil then
		return true
	end

	if fenv == getfenv(0) then
		return true
	end

	return true
end

checkclosure = isexecutorclosure
isourclosure = isexecutorclosure




local clonerefs = {}
setmetatable(clonerefs, {__mode = 'k'})

	cloneref = function(obj)
	local proxy = newproxy(true)
	local meta = getmetatable(proxy)	meta.__index = function(t, n)
		local v = obj[n]
		if typeof(v) == 'function' then
			return function(self, ...)
				if self == t then
					self = obj
				end
				return v(self, ...)
			end
		end
		return v
	end
	meta.__newindex = function(_, n, v)
		obj[n] = v
	end
	meta.__tostring = function()
		return tostring(obj)
	end
	local ok_mt, obj_mt = pcall(getmetatable, obj)
	meta.__metatable = (ok_mt and obj_mt or nil)
	clonerefs[proxy] = obj
	return proxy
end

compareinstances = function(a, b)
	assert(type(a) == 'userdata' or type(a) == 'table', "invalid argument #1 to 'compareinstances' (Instance expected, got " .. typeof(a) .. ')', 2)
	assert(type(b) == 'userdata' or type(b) == 'table', "invalid argument #2 to 'compareinstances' (Instance expected, got " .. typeof(b) .. ')', 2)
	if clonerefs[a] then
		a = clonerefs[a]
	end
	if clonerefs[b] then
		b = clonerefs[b]
	end
	return a == b
end




local rtypeof = typeof
typeof = function(obj)
	if clonerefs[obj] then
		return 'Instance'
	end
	return rtypeof(obj)
end




local function generate_error(object)
	local _, err = xpcall(function()
		object:__namecall()
	end, function()
		return debug.info(2, 'f')
	end)
	return err
end

local first_probe = generate_error(OverlapParams.new())
local second_probe = generate_error(Color3.new())

local cached_methods = {}
setmetatable(cached_methods, {__mode = 'k'})

local bootstrap_getnamecallmethod = getnamecallmethod

getnamecallmethod = function()
	local thread = coroutine.running()

	

	if bootstrap_getnamecallmethod then
		local registered = bootstrap_getnamecallmethod()
		if registered then
			return registered
		end
	end

	

	local tracked = current_namecall[thread]
	if tracked then
		return tracked
	end

	local method = nil

	local _, err = pcall(first_probe)
	if type(err) == 'string' then
		method = err:match('^(.+) is not a valid member of %w+$')
	end

	if not method then
		_, err = pcall(second_probe)
		if type(err) == 'string' then
			method = err:match('^(.+) is not a valid member of %w+$')
		end
	end

	if not method or method == '__namecall' then
		return cached_methods[coroutine.running()]
	end

	cached_methods[coroutine.running()] = method
	return method
end




local hidden_ui = nil

gethui = function()
	if hidden_ui and hidden_ui.Parent then
		return hidden_ui
	end

	local ok, gui = pcall(function()
		local screen_gui = Instance.new('ScreenGui')
		screen_gui.Name = 'RobloxUi'
		screen_gui.ResetOnSpawn = false
		screen_gui.DisplayOrder = 999999
		screen_gui.IgnoreGuiInset = true
		screen_gui.Parent = game_o:GetService('CoreGui')
		return screen_gui
	end)

	if ok then
		hidden_ui = gui
	end

	return hidden_ui
end

local drawing_objects = setmetatable({}, {__mode = 'k'})

local function safe_font(name)
	local ok, font = pcall(function()
		return Enum.Font[name]
	end)
	if ok and font then
		return font
	end
	return Enum.Font.SourceSans
end

local draw_fonts = {
	[0] = safe_font('SourceSans'),
	[1] = safe_font('SourceSansBold'),
	[2] = safe_font('Plex'),
	[3] = safe_font('Code'),
}

local function resolve_font(font)
	if type(font) == 'number' then
		return draw_fonts[font] or Enum.Font.SourceSans
	elseif type(font) == 'string' then
		local ok, resolved = pcall(function()
			return Enum.Font[font]
		end)
		if ok and resolved then
			return resolved
		end
		return Enum.Font.SourceSans
	end
	return font or Enum.Font.SourceSans
end

local function draw_alpha(transparency)
	return math.clamp(1 - transparency, 0, 1)
end

local function style_line_frame(frame, state)
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = state.Color
	frame.BackgroundTransparency = draw_alpha(state.Transparency)
	frame.ZIndex = state.ZIndex
	frame.Visible = state.Visible
end

local function place_line_frame(frame, from, to, thickness)
	local delta = to - from
	local length = delta.Magnitude
	frame.Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2)
	frame.Size = UDim2.fromOffset(length, thickness)
	frame.Rotation = math.deg(math.atan(delta.Y, delta.X))
end

local function place_edge_frame(frame, p1, p2, opposite)
	local delta = p2 - p1
	local length = delta.Magnitude
	local nx, ny = -delta.Y, delta.X
	local nlen = math.sqrt(nx * nx + ny * ny)
	if nlen == 0 then
		frame.Visible = false
		return
	end
	local ux, uy = nx / nlen, ny / nlen
	local mid = (p1 + p2) / 2
	local rel = opposite - mid
	local dist = rel.X * ux + rel.Y * uy
	frame.Position = UDim2.fromOffset(mid.X + ux * dist / 2, mid.Y + uy * dist / 2)
	frame.Size = UDim2.fromOffset(length, math.abs(dist))
	frame.Rotation = math.deg(math.atan(delta.Y, delta.X))
end

local function draw_defaults(class)
	local state = {
		Visible = false,
		Color = Color3.new(1, 1, 1),
		Transparency = 1,
		ZIndex = 0,
	}
	if class == 'Line' then
		state.From = Vector2.zero
		state.To = Vector2.zero
		state.Thickness = 1
	elseif class == 'Square' then
		state.Position = Vector2.zero
		state.Size = Vector2.zero
		state.Thickness = 1
		state.Filled = false
	elseif class == 'Circle' then
		state.Position = Vector2.zero
		state.Radius = 0
		state.Thickness = 1
		state.Filled = false
		state.NumSides = 30
	elseif class == 'Text' then
		state.Text = ''
		state.Size = 13
		state.Center = false
		state.Outline = false
		state.OutlineColor = Color3.new(0, 0, 0)
		state.Position = Vector2.zero
		state.Font = 0
	elseif class == 'Image' then
		state.Url = ''
		state.Data = ''
		state.Position = Vector2.zero
		state.Size = Vector2.zero
		state.Rounding = 0
	elseif class == 'Triangle' then
		state.PointA = Vector2.zero
		state.PointB = Vector2.zero
		state.PointC = Vector2.zero
		state.Thickness = 1
		state.Filled = false
	elseif class == 'Quad' then
		state.PointA = Vector2.zero
		state.PointB = Vector2.zero
		state.PointC = Vector2.zero
		state.PointD = Vector2.zero
		state.Thickness = 1
		state.Filled = false
	end
	return state
end

local draw_builders = {}

draw_builders.Line = function(entry)
	local frame = Instance.new('Frame')
	frame.Visible = false
	frame.Parent = gethui()
	table.insert(entry.instances, frame)

	entry.apply = function()
		local state = entry.state
		style_line_frame(frame, state)
		place_line_frame(frame, state.From, state.To, state.Thickness)
	end
end

draw_builders.Square = function(entry)
	local frame = Instance.new('Frame')
	frame.Visible = false
	local stroke = Instance.new('UIStroke')
	stroke.Enabled = false
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	frame.Parent = gethui()
	table.insert(entry.instances, frame)

	entry.apply = function()
		local state = entry.state
		frame.BackgroundColor3 = state.Color
		frame.Position = UDim2.fromOffset(state.Position.X, state.Position.Y)
		frame.Size = UDim2.fromOffset(state.Size.X, state.Size.Y)
		frame.ZIndex = state.ZIndex
		frame.Visible = state.Visible
		if state.Filled then
			frame.BackgroundTransparency = draw_alpha(state.Transparency)
			stroke.Enabled = false
		else
			frame.BackgroundTransparency = 1
			stroke.Enabled = true
			stroke.Color = state.Color
			stroke.Thickness = state.Thickness
			stroke.Transparency = draw_alpha(state.Transparency)
		end
	end
end

draw_builders.Circle = function(entry)
	local frame = Instance.new('Frame')
	frame.Visible = false
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	local corner = Instance.new('UICorner')
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	local stroke = Instance.new('UIStroke')
	stroke.Enabled = false
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	frame.Parent = gethui()
	table.insert(entry.instances, frame)

	entry.apply = function()
		local state = entry.state
		frame.BackgroundColor3 = state.Color
		frame.Position = UDim2.fromOffset(state.Position.X, state.Position.Y)
		frame.Size = UDim2.fromOffset(state.Radius * 2, state.Radius * 2)
		frame.ZIndex = state.ZIndex
		frame.Visible = state.Visible
		if state.Filled then
			frame.BackgroundTransparency = draw_alpha(state.Transparency)
			stroke.Enabled = false
		else
			frame.BackgroundTransparency = 1
			stroke.Enabled = true
			stroke.Color = state.Color
			stroke.Thickness = state.Thickness
			stroke.Transparency = draw_alpha(state.Transparency)
		end
	end
end

draw_builders.Text = function(entry)
	local label = Instance.new('TextLabel')
	label.Visible = false
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.new(0, 0, 0, 0)
	local stroke = Instance.new('UIStroke')
	stroke.Enabled = false
	stroke.Thickness = 2
	stroke.Parent = label
	label.Parent = gethui()
	table.insert(entry.instances, label)

	entry.apply = function()
		local state = entry.state
		label.Text = state.Text
		label.TextColor3 = state.Color
		label.TextTransparency = draw_alpha(state.Transparency)
		label.TextSize = state.Size
		label.Font = resolve_font(state.Font)
		label.AnchorPoint = Vector2.new(state.Center and 0.5 or 0, state.Center and 0.5 or 0)
		label.Position = UDim2.fromOffset(state.Position.X, state.Position.Y)
		label.ZIndex = state.ZIndex
		label.Visible = state.Visible
		stroke.Enabled = state.Outline
		stroke.Color = state.OutlineColor
	end
end

draw_builders.Image = function(entry)
	local image = Instance.new('ImageLabel')
	image.Visible = false
	image.BackgroundTransparency = 1
	image.Parent = gethui()
	table.insert(entry.instances, image)

	entry.apply = function()
		local state = entry.state
		image.Image = state.Url ~= '' and state.Url or state.Data
		image.ImageColor3 = state.Color
		image.ImageTransparency = draw_alpha(state.Transparency)
		image.Position = UDim2.fromOffset(state.Position.X, state.Position.Y)
		image.Size = UDim2.fromOffset(state.Size.X, state.Size.Y)
		image.ZIndex = state.ZIndex
		image.Visible = state.Visible
	end
end

local function build_polygon(entry, points)
	for _ = 1, #points * 2 do
		local frame = Instance.new('Frame')
		frame.Visible = false
		frame.Parent = gethui()
		table.insert(entry.instances, frame)
	end

	entry.apply = function()
		local state = entry.state
		local n = #points

		for _, inst in entry.instances do
			inst.Visible = false
		end

		if state.Filled then
			for i = 1, n do
				local a = state[points[i]]
				local b = state[points[i % n + 1]]
				local c = state[points[(i + 1) % n + 1]]
				local frame = entry.instances[n + i]
				style_line_frame(frame, state)
				place_edge_frame(frame, a, b, c)
			end
		else
			for i = 1, n do
				local a = state[points[i]]
				local b = state[points[i % n + 1]]
				local frame = entry.instances[i]
				style_line_frame(frame, state)
				place_line_frame(frame, a, b, state.Thickness)
			end
		end
	end
end

draw_builders.Triangle = function(entry)
	build_polygon(entry, {'PointA', 'PointB', 'PointC'})
end

draw_builders.Quad = function(entry)
	build_polygon(entry, {'PointA', 'PointB', 'PointC', 'PointD'})
end

Drawing = {}

function Drawing.new(class, properties)
	assert(type(class) == 'string', "invalid argument #1 to 'Drawing.new' (string expected, got " .. type(class) .. ')', 2)
	local builder = draw_builders[class]
	assert(builder, "invalid argument #1 to 'Drawing.new' (Line, Text, Image, Square, Quad, Circle or Triangle expected, got '" .. tostring(class) .. "')", 2)

	local entry = {
		class = class,
		state = draw_defaults(class),
		instances = {},
	}

	builder(entry)
	entry.apply()

	local proxy = newproxy(true)
	local meta = getmetatable(proxy)

	meta.__index = function(_, key)
		if key == 'Remove' or key == 'Destroy' then
			return entry.remove
		end
		if entry.state[key] ~= nil then
			return entry.state[key]
		end
		if key == 'TextBounds' and class == 'Text' then
			return entry.instances[1].TextBounds
		end
		error(tostring(key) .. ' is not a valid member of Drawing (' .. class .. ')', 2)
	end

	meta.__newindex = function(_, key, value)
		assert(entry.state[key] ~= nil, tostring(key) .. ' is not a valid member of Drawing (' .. class .. ')', 2)
		entry.state[key] = value
		entry.apply()
	end

	meta.__tostring = function()
		return 'Drawing (' .. class .. ')'
	end

	entry.remove = function()
		for _, inst in entry.instances do
			pcall(function()
				inst:Destroy()
			end)
		end
		entry.instances = {}
		drawing_objects[proxy] = nil
	end

	drawing_objects[proxy] = entry

	if type(properties) == 'table' then
		for key, value in properties do
			proxy[key] = value
		end
	end

	return proxy
end

Drawing.Fonts = {
	UI = 0,
	System = 1,
	Plex = 2,
	Monospace = 3,
}

isrenderobj = function(object)
	return drawing_objects[object] ~= nil
end

cleardrawcache = function()
	for proxy in drawing_objects do
		local entry = drawing_objects[proxy]
		if entry then
			entry.remove()
		end
	end
end

isrenderavailable = function()
	return true
end

getrenderproperty = function(drawing, property)
	local entry = drawing_objects[drawing]
	assert(entry, "invalid argument #1 to 'getrenderproperty' (Drawing expected)", 2)
	assert(type(property) == 'string', "invalid argument #2 to 'getrenderproperty' (string expected, got " .. type(property) .. ')', 2)
	return drawing[property]
end

setrenderproperty = function(drawing, property, value)
	local entry = drawing_objects[drawing]
	assert(entry, "invalid argument #1 to 'setrenderproperty' (Drawing expected)", 2)
	assert(type(property) == 'string', "invalid argument #2 to 'setrenderproperty' (string expected, got " .. type(property) .. ')', 2)
	drawing[property] = value
end








local instance_registry = {}
local registry_scanned = false

local function register_instance(inst)
	instance_registry[inst] = true
end

local function ensure_registry()
	if registry_scanned then
		return
	end
	registry_scanned = true

	for _, inst in game_o:GetDescendants() do
		register_instance(inst)
	end
end

game_o.DescendantAdded:Connect(register_instance)

getnilinstances = function()
	local result = {}
	local seen = {}

	local function add_nil(inst)
		if not seen[inst] then
			local ok, parent = pcall(function()
				return inst.Parent
			end)
			if ok and parent == nil then
				seen[inst] = true
				table.insert(result, inst)
			end
		end
	end

	ensure_registry()
	for inst in instance_registry do
		add_nil(inst)
	end

	

	if type(fiu_debug) == 'table' and type(fiu_debug.createdinstances) == 'function' then
		local ok, tracked = pcall(fiu_debug.createdinstances)
		if ok and type(tracked) == 'table' then
			for _, inst in tracked do
				add_nil(inst)
			end
		end
	end

	return result
end

getloadedmodules = function()
	local result = {}
	local seen = {}

	local function add(inst)
		if not seen[inst] then
			seen[inst] = true
			table.insert(result, inst)
		end
	end

	

	if type(fiu_debug) == 'table' and type(fiu_debug.loadedmodules) == 'function' then
		local ok, tracked = pcall(fiu_debug.loadedmodules)
		if ok and type(tracked) == 'table' then
			for _, inst in tracked do
				add(inst)
			end
		end
	end

	

	ensure_registry()
	for inst in instance_registry do
		local ok, is_module = pcall(function()
			return inst:IsA('ModuleScript')
		end)
		if ok and is_module then
			local ok2, full = pcall(function()
				return inst:GetFullName()
			end)
			if not ok2 or not (full:find('CoreGui') or full:find('CorePackages') or full:find('CoreScripts')) then
				add(inst)
			end
		end
	end

	return result
end

getscripts = function()
	ensure_registry()
	local result = {}

	for inst in instance_registry do
		local ok, is_script = pcall(function()
			return inst:IsA('LocalScript') or inst:IsA('ModuleScript')
		end)
		if ok and is_script then
			local ok2, full = pcall(function()
				return inst:GetFullName()
			end)
			if ok2 and (full:find('CoreGui') or full:find('CorePackages') or full:find('CoreScripts')) then
				

			else
				table.insert(result, inst)
			end
		end
	end

	return result
end

getrunningscripts = function()
	local result = {}

	for _, inst in getscripts() do
		local ok, matches = pcall(function()
			local full_name = inst:GetFullName()
			if full_name:find('CoreGui') or full_name:find('CorePackages') then
				return false
			end
			return inst:FindFirstAncestorOfClass('Actor') == nil
		end)
		if ok and matches then
			table.insert(result, inst)
		end
	end

	return result
end




isreadonly = function(tbl)
	assert(type(tbl) == 'table', "invalid argument #1 to 'isreadonly' (table expected, got " .. type(tbl) .. ')', 2)
	if readonly_tables[tbl] then
		return true
	end
	if type(fiu_debug) == 'table' and type(fiu_debug.isfrozen) == 'function' then
		local ok, result = pcall(fiu_debug.isfrozen, tbl)
		if ok and result then
			return true
		end
	end
	return table.isfrozen(tbl)
end




local queue_file = 'queued_teleports.lua'
local queue_marker = '\n--__SPEEDQUEUE__--\n'

queue_on_teleport = function(source)
	assert(type(source) == 'string', "invalid argument #1 to 'queue_on_teleport' (string expected, got " .. type(source) .. ')', 2)

	local existing = ''
	if isfile(queue_file) then
		local read_ok, content = pcall(readfile, queue_file)
		if read_ok and content then
			existing = content
		end
	end

	if existing == '' then
		writefile(queue_file, source)
	else
		writefile(queue_file, existing .. queue_marker .. source)
	end
end

local function flush_teleport_queue()
	if not isfile(queue_file) then
		return
	end

	local read_ok, content = pcall(readfile, queue_file)
	if not read_ok then
		return
	end
	content = content or ''
	delfile(queue_file)

	for _, source in content:split(queue_marker) do
		if source ~= '' then
			task.spawn(function()
				local func, err = loadstring(source)
				if func then
					func()
				else
					warn('SpeedExecutor -- queued script failed: ' .. tostring(err))
				end
			end)
		end
	end
end




isnetworkowner = function(part: BasePart)
	if part.Anchored or part:IsGrounded() or not part or not part:IsA("BasePart") then
		return false
	end
	return part.ReceiveAge == 0
end




request = function(options)
	assert(type(options) == 'table', "invalid argument #1 to 'request' (table expected, got " .. type(options) .. ')', 2)
	assert(type(options.Url) == 'string', "invalid argument #1 to 'request' (Url string expected)", 2)

	

	local ok, bridge_result = pcall(function()
		local payload = {
			Url = options.Url,
			Method = options.Method or 'GET',
		}
		

		if type(options.Headers) == 'table' and next(options.Headers) ~= nil then
			payload.Headers = options.Headers
		end
		if type(options.Cookies) == 'table' and next(options.Cookies) ~= nil then
			payload.Cookies = options.Cookies
		end
		if options.Body ~= nil then
			payload.Body = options.Body
		end
		local response = send_method('request', base64encode(http_service:JSONEncode(payload)))
		assert(type(response) == 'string' and response ~= 'fail' and response ~= '', 'bridge request failed')
		local decoded = http_service:JSONDecode(response)
		return {
			Success = true,
			StatusCode = decoded.StatusCode,
			StatusMessage = decoded.StatusMessage,
			Headers = decoded.Headers or {},
			Body = base64decode(decoded.Body or ''),
		}
	end)
	if ok and bridge_result then
		return bridge_result
	end

	

	

	local headers = {}
	if type(options.Headers) == 'table' then
		for k, v in options.Headers do
			headers[k] = v
		end
	end
	if type(options.Cookies) == 'table' then
		local parts = {}
		for k, v in options.Cookies do
			table.insert(parts, tostring(k) .. '=' .. tostring(v))
		end
		if #parts > 0 then
			if headers.Cookie then
				headers.Cookie ..= '; ' .. table.concat(parts, '; ')
			else
				headers.Cookie = table.concat(parts, '; ')
			end
		end
	end

	local result = nil

	local started = pcall(function()
		http_service:RequestInternal({
			Url = options.Url,
			Method = options.Method or "GET",
			Headers = headers,
			Body = options.Body
		}):Start(function(s,b)
			result = b
			result['Success'] = s
		end)
	end)

	if started then
		local deadline = os.clock() + 15
		repeat task.wait() until result or os.clock() > deadline
	end

	if not result or not result.Success then
		warn('SpeedExecutor -- request error')
		return nil
	end

	return result
end

http_request = request
http = { request = request }
syn = {
	request = request
}




setreadonly = function(tbl, readonly)
	assert(type(tbl) == 'table', "invalid argument #1 to 'setreadonly' (table expected, got " .. type(tbl) .. ')', 2)
	if readonly then
		

		

		if table.isfrozen(tbl) or readonly_tables[tbl] then
			return
		end
		if getmetatable(tbl) ~= nil then
			table.freeze(tbl)
			return
		end
		readonly_tables[tbl] = true
		readonly_installed_meta[tbl] = true
		setmetatable(tbl, {
			__newindex = function()
				error('attempt to modify a readonly table', 2)
			end,
		})
	else
		readonly_tables[tbl] = nil
		if readonly_installed_meta[tbl] then
			readonly_installed_meta[tbl] = nil
			setmetatable(tbl, nil)
		end
		

		if type(fiu_debug) == 'table' and type(fiu_debug.unfreeze) == 'function' then
			pcall(fiu_debug.unfreeze, tbl)
		end
	end
end




cache = {}

local invalidated_cache = {}
setmetatable(invalidated_cache, { __mode = 'k' })

cache.invalidate = function(obj)
	if clonerefs[obj] ~= nil then
		clonerefs[obj] = nil
	end
	local doomed = {}
	for proxy, original in clonerefs do
		if original == obj then
			doomed[#doomed + 1] = proxy
		end
	end
	for _, proxy in doomed do
		clonerefs[proxy] = nil
	end
	invalidated_cache[obj] = true
	if type(fiu_debug) == 'table' and type(fiu_debug.invalidate) == 'function' then
		pcall(fiu_debug.invalidate, obj)
	end
end

cache.iscached = function(obj)
	if clonerefs[obj] ~= nil then
		return true
	end
	if invalidated_cache[obj] then
		return false
	end
	if type(fiu_debug) == 'table' and type(fiu_debug.isinvalidated) == 'function' then
		local ok, result = pcall(fiu_debug.isinvalidated, obj)
		if ok and result then
			return false
		end
	end
	if typeof(obj) == 'Instance' or obj == game then
		return true
	end
	return false
end

cache.replace = function(obj, replacement)
	if clonerefs[obj] ~= nil then
		clonerefs[obj] = replacement
	end
end




local hooked_functions = {}
setmetatable(hooked_functions, {__mode = 'k'})

hookfunction = function(original, hook)
	assert(type(original) == 'function', "invalid argument #1 to 'hookfunction' (function expected)", 2)
	assert(type(hook) == 'function', "invalid argument #2 to 'hookfunction' (function expected)", 2)
	hooked_functions[original] = hook
	executor_closures[hook] = true
	if type(fiu_debug) == 'table' and type(fiu_debug.hookfunction) == 'function' then
		pcall(fiu_debug.hookfunction, original, hook)
	end
	

	

	if type(fiu_debug) == 'table' and type(fiu_debug.calloriginal) == 'function' then
		return function(...)
			return fiu_debug.calloriginal(original, ...)
		end
	end
	return original
end

restorefunction = function(func)
	assert(type(func) == 'function', "invalid argument #1 to 'restorefunction' (function expected)", 2)
	if hooked_functions[func] == nil then
		error("restorefunction: function is not hooked", 2)
	end
	hooked_functions[func] = nil
	if type(fiu_debug) == 'table' and type(fiu_debug.restorefunction) == 'function' then
		pcall(fiu_debug.restorefunction, func)
	end
end

hookmetamethod = function(object, method, hook)
	assert(type(method) == 'string', "invalid argument #2 to 'hookmetamethod' (string expected)", 2)
	assert(type(hook) == 'function', "invalid argument #3 to 'hookmetamethod' (function expected)", 2)
	executor_closures[hook] = true
	if object == game and (method == '__index' or method == '__newindex' or method == '__namecall') then
		local old_hook = game_metamethod_hooks[method]
		game_metamethod_hooks[method] = hook
		if old_hook ~= nil then
			return old_hook
		end
		if method == '__namecall' then
			return function(self, ...)
				local name = current_namecall[coroutine.running()]
				if name ~= nil then
					return game_o[name](game_o, ...)
				end
				return nil
			end
		end
		return function() end
	end
	if type(object) == 'table' and (method == '__index' or method == '__newindex') then
		

		

		local current_mt = nil
		if type(fiu_debug) == 'table' and type(fiu_debug.rawmetatable) == 'function' then
			local ok, m = pcall(fiu_debug.rawmetatable, object)
			if ok and type(m) == 'table' then
				current_mt = m
			end
		end
		if current_mt == nil then
			local ok, m = pcall(getmetatable, object)
			if ok and type(m) == 'table' then
				current_mt = m
			end
		end
		local old_fn = nil
		if type(current_mt) == 'table' and type(current_mt[method]) == 'function' then
			old_fn = current_mt[method]
		end
		local new_mt = {}
		if type(current_mt) == 'table' then
			for k, v in current_mt do
				new_mt[k] = v
			end
		end
		new_mt[method] = hook
		new_mt.__metatable = nil
		local ok = pcall(setmetatable, object, new_mt)
		if ok then
			executor_closures[hook] = true
			if old_fn ~= nil then
				return old_fn
			end
			return function() end
		end
	end
	return nil
end




getrawmetatable = function(obj)
	if clonerefs[obj] ~= nil then
		obj = clonerefs[obj]
	end
	

	if type(fiu_debug) == 'table' and type(fiu_debug.rawmetatable) == 'function' then
		local ok, mt = pcall(fiu_debug.rawmetatable, obj)
		if ok and mt ~= nil then
			return mt
		end
	end
	local ok, mt = pcall(getmetatable, obj)
	if ok then return mt end
	return nil
end

setrawmetatable = function(obj, mt)
	pcall(setmetatable, obj, mt)
	return obj
end




getfunctionhash = function(func)
	assert(type(func) == 'function', "invalid argument #1 to 'getfunctionhash' (function expected)", 2)
	

	

	local proto = nil
	if type(fiu_debug) == 'table' and type(fiu_debug.getfuncdata) == 'function' then
		local ok, data = pcall(fiu_debug.getfuncdata, func)
		if ok and type(data) == 'table' and type(data.proto) == 'table' then
			proto = data.proto
		end
	end
	if proto == nil then
		error("getfunctionhash: lua function expected", 2)
	end
	local parts = {}
	parts[#parts + 1] = 'p:' .. tostring(proto.numparams or 0) .. ':' .. (proto.isvararg and '1' or '0') .. ':' .. tostring(proto.nups or 0) .. ';'
	local klist = proto.k or {}
	local n = proto.sizek or #klist
	for i = 1, n do
		local v = klist[i]
		local t = type(v)
		if t == 'number' then
			parts[#parts + 1] = 'n:' .. tostring(v) .. ';'
		elseif t == 'string' then
			parts[#parts + 1] = 's:' .. #v .. ':' .. v .. ';'
		elseif t == 'boolean' then
			parts[#parts + 1] = 'b:' .. (v and '1' or '0') .. ';'
		elseif t == 'nil' then
			parts[#parts + 1] = 'z;'
		else
			parts[#parts + 1] = 'o:' .. t .. ':' .. #tostring(v) .. ';'
		end
	end
	if type(proto.code) == 'table' then
		for _, inst in proto.code do
			if type(inst) == 'table' and inst.opname ~= 'auxvalue' then
				local seg = tostring(inst.opcode or -1) .. ',' .. tostring(inst.A or -1) .. ',' .. tostring(inst.B or -1) .. ',' .. tostring(inst.C or -1) .. ',' .. tostring(inst.D or -1)
				if type(inst.aux) == 'number' then
					seg ..= ':' .. tostring(inst.aux)
				end
				if inst.KN ~= nil then
					seg ..= inst.KN and '!' or '?'
				end
				parts[#parts + 1] = seg .. '|'
			end
		end
	end
	local response = send_method('hash', 'sha384', base64encode(table.concat(parts)))
	if type(response) ~= 'string' or response == '' or response == 'fail' then
		error('getfunctionhash: hash backend unavailable', 2)
	end
	return response
end




local _original_debug = debug
local _new_debug = setmetatable({}, {__index = _original_debug})



local function assert_lclosure(func, name)
	if type(fiu_debug) == 'table' and type(fiu_debug.isemulated) == 'function' then
		local ok, isem = pcall(fiu_debug.isemulated, func)
		if ok and not isem then
			error(name .. ": cannot debug C closure", 2)
		end
	end
end





local function resolve_debug_target(func)
	if type(func) == 'number' then
		if type(fiu_debug) == 'table' and type(fiu_debug.getstackframe) == 'function' then
			local ok, frame = pcall(fiu_debug.getstackframe, func)
			if ok and type(frame) == 'table' and type(frame.proto) == 'table' then
				return { proto = frame.proto, module = frame.module, wrap = frame.wrap, upvals = frame.upvals }
			end
		end
		return nil
	end
	if type(fiu_debug) == 'table' and type(fiu_debug.getfuncdata) == 'function' then
		local ok, data = pcall(fiu_debug.getfuncdata, func)
		if ok and type(data) == 'table' and type(data.proto) == 'table' then
			return data
		end
	end
	return nil
end



local function consts_from_data(data)
	local proto = data.proto
	if proto.code == nil then
		return {}
	end
	local klist = proto.k or {}
	local out = {}
	local pos = 1
	local function push(v)
		out[pos] = v
		pos += 1
	end
	for _, inst in proto.code do
		local op = inst.opname
		if op == "GETGLOBAL" then
			push(inst.K)
			push(nil)
		elseif op == "GETIMPORT" then
			if inst.aux ~= nil then
				push(luau_decode_import(klist, inst.aux))
			else
				push(nil)
			end
			push(nil)
		elseif op == "DUPTABLE" then
			push(nil)
		elseif op == "NEWCLOSURE" or op == "DUPCLOSURE" then
			local fn = nil
			if type(data.wrap) == 'function' and data.module ~= nil and data.module.protoList ~= nil and proto.protos ~= nil then
				local child = nil
				if op == "NEWCLOSURE" and type(inst.D) == 'number' then
					child = data.module.protoList[proto.protos[inst.D + 1]]
				elseif op == "DUPCLOSURE" and type(inst.K) == 'number' then
					child = data.module.protoList[inst.K + 1]
				end
				if child ~= nil then
					local ok, wrapped = pcall(data.wrap, child)
					if ok then
						fn = wrapped
					end
				end
			end
			push(fn)
		elseif inst.KINDEX ~= nil then
			push(inst.K)
		end
	end
	return out
end

local function protofunc_from_data(data, index)
	if data.proto.protos == nil or type(data.wrap) ~= 'function' then
		return nil
	end
	if data.module == nil or type(data.module.protoList) ~= 'table' then
		return nil
	end
	local child = data.module.protoList[data.proto.protos[index]]
	if child == nil then
		return nil
	end
	local ok, fn = pcall(data.wrap, child)
	if ok then
		return fn
	end
	return nil
end

local function protos_from_data(data)
	local out = {}
	if data.proto.protos == nil or type(data.wrap) ~= 'function' then
		return out
	end
	if data.module == nil or type(data.module.protoList) ~= 'table' then
		return out
	end
	for i = 1, #data.proto.protos do
		local child = data.module.protoList[data.proto.protos[i]]
		if child ~= nil then
			local ok, fn = pcall(data.wrap, child)
			if ok and fn ~= nil then
				out[#out + 1] = fn
			end
		end
	end
	return out
end

_new_debug.getinfo = function(func, what)
	assert(type(func) == 'function', "bad argument #1 to 'debug.getinfo' (function expected)", 2)
	

	

	local function info_opt(option)
		local results = table.pack(pcall(_original_debug.info, func, option))
		if results[1] then
			return table.unpack(results, 2, results.n)
		end
		return nil
	end
	local source = info_opt('s') or '[C]'
	local info = {}
	info.source = source
	info.short_src = source
	info.func = func
	info.what = source == '[C]' and 'C' or 'Lua'
	info.currentline = info_opt('l') or -1
	info.name = info_opt('n') or ''
	local nparams, isvararg = info_opt('a')
	info.numparams = nparams or 0
	info.is_vararg = isvararg and 1 or 0
	if cclosure_marks[func] then
		info.nups = 0
	else
		info.nups = info_opt('u') or 0
	end
	return info
end

_new_debug.getconstant = function(func, index)
	assert(type(func) == 'function' or type(func) == 'number', "bad argument #1 to 'debug.getconstant' (function expected)", 2)
	assert(type(index) == 'number', "bad argument #2 to 'debug.getconstant' (number expected)", 2)
	if type(func) == 'number' then
		local data = resolve_debug_target(func)
		if data ~= nil then
			return consts_from_data(data)[index]
		end
		return nil
	end
	assert_lclosure(func, 'debug.getconstant')
	if type(fiu_debug) == 'table' and type(fiu_debug.getconstant) == 'function' then
		local ok, value = pcall(fiu_debug.getconstant, func, index)
		if ok then
			return value
		end
	end
	return nil
end

_new_debug.getconstants = function(func)
	assert(type(func) == 'function' or type(func) == 'number', "bad argument #1 to 'debug.getconstants' (function expected)", 2)
	if type(func) == 'number' then
		local data = resolve_debug_target(func)
		if data ~= nil then
			return consts_from_data(data)
		end
		return {}
	end
	assert_lclosure(func, 'debug.getconstants')
	if type(fiu_debug) == 'table' and type(fiu_debug.getconstants) == 'function' then
		local ok, result = pcall(fiu_debug.getconstants, func)
		if ok and type(result) == 'table' then
			return result
		end
	end
	return {}
end

_new_debug.getproto = function(func, index, active)
	assert(type(func) == 'function' or type(func) == 'number', "bad argument #1 to 'debug.getproto' (function expected)", 2)
	assert(type(index) == 'number', "bad argument #2 to 'debug.getproto' (number expected)", 2)
	local fn = nil
	if type(func) == 'number' then
		local data = resolve_debug_target(func)
		if data ~= nil then
			fn = protofunc_from_data(data, index)
		end
	else
		assert_lclosure(func, 'debug.getproto')
		if type(fiu_debug) == 'table' and type(fiu_debug.getprotofunc) == 'function' then
			local ok, value = pcall(fiu_debug.getprotofunc, func, index)
			if ok and value ~= nil then
				fn = value
			end
		end
	end
	if active then
		if fn == nil then
			return nil
		end
		return { fn }
	end
	return fn
end

_new_debug.getprotos = function(func)
	assert(type(func) == 'function' or type(func) == 'number', "bad argument #1 to 'debug.getprotos' (function expected)", 2)
	if type(func) == 'number' then
		local data = resolve_debug_target(func)
		if data ~= nil then
			return protos_from_data(data)
		end
		return {}
	end
	assert_lclosure(func, 'debug.getprotos')
	if type(fiu_debug) == 'table' and type(fiu_debug.getprotos) == 'function' then
		local ok, result = pcall(fiu_debug.getprotos, func)
		if ok and type(result) == 'table' then
			return result
		end
	end
	return {}
end





_new_debug.getstack = function(level, index)
	level = level or 1
	assert(type(level) == 'number', "bad argument #1 to 'debug.getstack' (number expected)", 2)
	if level < 1 then
		error("debug.getstack: invalid stack level", 2)
	end
	if type(fiu_debug) == 'table' and type(fiu_debug.getstackframe) == 'function' then
		local ok, frame = pcall(fiu_debug.getstackframe, level)
		if ok and type(frame) == 'table' and type(frame.stack) == 'table' then
			if index ~= nil then
				return frame.stack[index - 1]
			end
			local shifted = {}
			for k, v in frame.stack do
				if type(k) == 'number' then
					shifted[k + 1] = v
				end
			end
			return shifted
		end
	end
	return nil
end

_new_debug.getupvalue = function(func, index)
	assert(type(func) == 'function' or type(func) == 'number', "bad argument #1 to 'debug.getupvalue' (function expected)", 2)
	assert(type(index) == 'number', "bad argument #2 to 'debug.getupvalue' (number expected)", 2)
	if type(func) == 'function' then
		assert_lclosure(func, 'debug.getupvalue')
	end
	local data = resolve_debug_target(func)
	if data ~= nil and type(data.upvals) == 'table' then
		local uv = data.upvals[index]
		if type(uv) == 'table' and type(uv.store) == 'table' then
			local ok2, value = pcall(function()
				return uv.store[uv.index]
			end)
			if ok2 then
				local name = nil
				if type(data.proto) == 'table' and type(data.proto.upvaluenames) == 'table' then
					name = data.proto.upvaluenames[index]
				end
				return value, name or ''
			end
		end
		error("debug.getupvalue: invalid upvalue index", 2)
	end
	error("debug.getupvalue: invalid upvalue index", 2)
end

_new_debug.getupvalues = function(func)
	assert(type(func) == 'function' or type(func) == 'number', "bad argument #1 to 'debug.getupvalues' (function expected)", 2)
	if type(func) == 'function' then
		assert_lclosure(func, 'debug.getupvalues')
	end
	local data = resolve_debug_target(func)
	if data ~= nil and type(data.upvals) == 'table' then
		local upvalues = {}
		for i, uv in data.upvals do
			if type(uv) == 'table' and type(uv.store) == 'table' then
				local ok2, value = pcall(function()
					return uv.store[uv.index]
				end)
				if ok2 then
					upvalues[i] = value
				end
			end
		end
		return upvalues
	end
	return {}
end

_new_debug.setconstant = function(func, index, value)
	assert(type(func) == 'function' or type(func) == 'number', "bad argument #1 to 'debug.setconstant' (function expected)", 2)
	assert(type(index) == 'number', "bad argument #2 to 'debug.setconstant' (number expected)", 2)
	if type(func) == 'number' then
		local data = resolve_debug_target(func)
		if data ~= nil and type(data.proto) == 'table' and type(data.proto.k) == 'table' then
			local proto = data.proto
			proto.k[index] = value
			if type(proto.code) == 'table' then
				for _, inst in proto.code do
					if type(inst) == 'table' then
						if inst.KINDEX == index then
							inst.K = value
						elseif inst.KIMPORT and type(value) == 'string' and inst.aux ~= nil then
							local aux = inst.aux
							local count = bit32.rshift(aux, 30)
							if count >= 1 and bit32.band(bit32.rshift(aux, 20), 0x3FF) + 1 == index then
								inst.K0 = value
							end
							if count >= 2 and bit32.band(bit32.rshift(aux, 10), 0x3FF) + 1 == index then
								inst.K1 = value
							end
							if count >= 3 and bit32.band(aux, 0x3FF) + 1 == index then
								inst.K2 = value
							end
						end
					end
				end
			end
		end
		return
	end
	assert_lclosure(func, 'debug.setconstant')
	if type(fiu_debug) == 'table' and type(fiu_debug.setconstant) == 'function' then
		pcall(fiu_debug.setconstant, func, index, value)
	end
end

_new_debug.setstack = function(level, index, value)
	level = level or 1
	assert(type(level) == 'number', "bad argument #1 to 'debug.setstack' (number expected)", 2)
	if level < 1 then
		error("debug.setstack: invalid stack level", 2)
	end
	if type(fiu_debug) == 'table' and type(fiu_debug.getstackframe) == 'function' then
		local ok, frame = pcall(fiu_debug.getstackframe, level)
		if ok and type(frame) == 'table' and type(frame.stack) == 'table' then
			frame.stack[index - 1] = value
		end
	end
end

_new_debug.setupvalue = function(func, index, value)
	assert(type(func) == 'function' or type(func) == 'number', "bad argument #1 to 'debug.setupvalue' (function expected)", 2)
	assert(type(index) == 'number', "bad argument #2 to 'debug.setupvalue' (number expected)", 2)
	if type(func) == 'function' then
		assert_lclosure(func, 'debug.setupvalue')
	end
	local data = resolve_debug_target(func)
	if data ~= nil and type(data.upvals) == 'table' then
		local uv = data.upvals[index]
		if type(uv) == 'table' and type(uv.store) == 'table' then
			pcall(function()
				uv.store[uv.index] = value
			end)
			return
		end
		error("debug.setupvalue: invalid upvalue index", 2)
	end
	error("debug.setupvalue: invalid upvalue index", 2)
end



_new_debug.info = function(func, options)
	if type(func) == 'function' and cclosure_marks[func] and options == 's' then
		return '[C]'
	end
	if type(func) == 'function' and (options == 'n' or options == 'a')
		and type(fiu_debug) == 'table' and type(fiu_debug.getfuncdata) == 'function' then
		local ok, data = pcall(fiu_debug.getfuncdata, func)
		if ok and type(data) == 'table' and type(data.proto) == 'table' then
			local proto = data.proto
			if options == 'n' then
				if proto.debugname ~= nil and proto.debugname ~= '(??)' and proto.debugname ~= '' then
					return proto.debugname
				end
			else
				return proto.numparams or 0, proto.isvararg == true
			end
		end
	end
	return _original_debug.info(func, options)
end

debug = _new_debug







local function luau_decode_import(klist, word)
	local count = bit32.rshift(word, 30)
	if count == 0 then
		return nil
	end
	local id0 = bit32.band(bit32.rshift(word, 20), 0x3FF)
	local s0 = klist[id0 + 1]
	if count == 1 then
		return s0
	end
	local id1 = bit32.band(bit32.rshift(word, 10), 0x3FF)
	local s1 = klist[id1 + 1]
	if count == 2 then
		return tostring(s0) .. "." .. tostring(s1)
	end
	local id2 = bit32.band(word, 0x3FF)
	return tostring(s0) .. "." .. tostring(s1) .. "." .. tostring(klist[id2 + 1])
end

local function decompile_literal(v)
	local t = type(v)
	if t == 'number' then
		if v ~= v then
			return '0/0'
		end
		if v == math.huge then
			return 'math.huge'
		end
		if v == -math.huge then
			return '-math.huge'
		end
		return tostring(v)
	elseif t == 'string' then
		return string.format('%q', v)
	elseif t == 'boolean' then
		return v and 'true' or 'false'
	elseif t == 'nil' then
		return 'nil'
	end
	return nil
end

local function decompile_proto(module, proto, wrap, depth)
	depth = depth or 0
	if depth > 8 or type(proto.code) ~= 'table' then
		return nil
	end
	local klist = proto.k or {}
	local regval = {}
	local defined = {}
	local lines = {}
	local nparams = proto.numparams or 0
	local header = {}
	for i = 1, nparams do
		header[i] = 'p' .. i
		regval[i - 1] = 'p' .. i
		defined[i - 1] = true
	end
	if proto.isvararg then
		header[nparams + 1] = '...'
	end
	local function def(A, expr)
		if A == nil then
			error('bad register')
		end
		if defined[A] then
			lines[#lines + 1] = 'r' .. A .. ' = ' .. expr
		else
			defined[A] = true
			lines[#lines + 1] = 'local r' .. A .. ' = ' .. expr
		end
		regval[A] = 'r' .. A
	end
	local function ref(R)
		local e = regval[R]
		if e == nil then
			return 'nil'
		end
		return e
	end
	local pending_nc = nil
	for _, inst in proto.code do
		if type(inst) ~= 'table' then
			return nil
		end
		local op = inst.opname
		if op == nil or op == 'auxvalue' or op == 'CAPTURE' or op == 'NOP' or op == 'BREAK' or op == 'COVERAGE' or op == 'PREPVARARGS' or op == 'CLOSEUPVALS' then
			

		elseif op == 'FASTCALL' or op == 'FASTCALL1' or op == 'FASTCALL2' or op == 'FASTCALL2K' or op == 'FASTCALL3' then
			

		elseif op == 'LOADK' or op == 'LOADKX' then
			local lit = decompile_literal(inst.K)
			if lit == nil then
				return nil
			end
			def(inst.A, lit)
		elseif op == 'LOADNIL' then
			def(inst.A, 'nil')
		elseif op == 'LOADB' then
			if inst.C ~= 0 then
				return nil
			end
			def(inst.A, (inst.B ~= 0) and 'true' or 'false')
		elseif op == 'LOADN' then
			def(inst.A, tostring(inst.D or 0))
		elseif op == 'MOVE' then
			def(inst.A, ref(inst.B))
		elseif op == 'GETUPVAL' then
			local nm = nil
			if type(proto.upvaluenames) == 'table' then
				nm = proto.upvaluenames[inst.B + 1]
			end
			def(inst.A, nm or ('up_' .. tostring(inst.B + 1)))
		elseif op == 'SETUPVAL' then
			local nm = nil
			if type(proto.upvaluenames) == 'table' then
				nm = proto.upvaluenames[inst.B + 1]
			end
			lines[#lines + 1] = (nm or ('up_' .. tostring(inst.B + 1))) .. ' = ' .. ref(inst.A)
		elseif op == 'GETGLOBAL' then
			def(inst.A, tostring(inst.K))
		elseif op == 'GETIMPORT' then
			if inst.aux == nil then
				return nil
			end
			def(inst.A, tostring(luau_decode_import(klist, inst.aux)))
		elseif op == 'GETTABLE' then
			def(inst.A, '(' .. ref(inst.B) .. ')[' .. ref(inst.C) .. ']')
		elseif op == 'GETTABLEKS' then
			local lk = decompile_literal(inst.K)
			if lk == nil then
				return nil
			end
			def(inst.A, '(' .. ref(inst.B) .. ')[' .. lk .. ']')
		elseif op == 'GETTABLEN' then
			def(inst.A, '(' .. ref(inst.B) .. ')[' .. tostring((inst.C or 0) + 1) .. ']')
		elseif op == 'SETTABLE' then
			lines[#lines + 1] = '(' .. ref(inst.B) .. ')[' .. ref(inst.C) .. '] = ' .. ref(inst.A)
		elseif op == 'SETTABLEKS' then
			local lk = decompile_literal(inst.K)
			if lk == nil then
				return nil
			end
			lines[#lines + 1] = '(' .. ref(inst.B) .. ')[' .. lk .. '] = ' .. ref(inst.A)
		elseif op == 'SETTABLEN' then
			lines[#lines + 1] = '(' .. ref(inst.B) .. ')[' .. tostring((inst.C or 0) + 1) .. '] = ' .. ref(inst.A)
		elseif op == 'SETGLOBAL' then
			lines[#lines + 1] = tostring(inst.K) .. ' = ' .. ref(inst.A)
		elseif op == 'NEWTABLE' or op == 'DUPTABLE' then
			def(inst.A, '{}')
		elseif op == 'SETLIST' then
			if (inst.C or 0) == 0 then
				return nil
			end
			local c = inst.C - 1
			local s = inst.aux or 1
			for j = 0, c - 1 do
				lines[#lines + 1] = '(' .. ref(inst.A) .. ')[' .. tostring(s + j) .. '] = ' .. ref(inst.B + j)
			end
		elseif op == 'NAMECALL' then
			pending_nc = { A = inst.A, obj = ref(inst.B), method = tostring(inst.K) }
		elseif op == 'CALL' then
			local fname = ref(inst.A)
			local arg_start = inst.A + 1
			if pending_nc ~= nil and pending_nc.A == inst.A then
				if not pending_nc.method:match('^[A-Za-z_][A-Za-z0-9_]*$') then
					return nil
				end
				fname = '(' .. pending_nc.obj .. '):' .. pending_nc.method
				arg_start = inst.A + 2
				pending_nc = nil
			end
			local arglist = {}
			if (inst.B or 0) == 0 then
				

				

				local j = arg_start
				while regval[j] ~= nil do
					arglist[#arglist + 1] = regval[j]
					j += 1
				end
			else
				local nargs = (inst.B or 1) - 1
				for j = 0, nargs - 1 do
					arglist[#arglist + 1] = ref(arg_start + j)
				end
			end
			local callexpr = fname .. '(' .. table.concat(arglist, ', ') .. ')'
			local nres = (inst.C or 0) - 1
			if (inst.C or 0) == 0 then
				def(inst.A, '(' .. callexpr .. ')')
			elseif nres == 0 then
				lines[#lines + 1] = callexpr
			else
				def(inst.A, callexpr)
			end
		elseif op == 'RETURN' then
			local b = (inst.B or 0) - 1
			if b == 0 then
				lines[#lines + 1] = 'return'
			else
				lines[#lines + 1] = 'return ' .. ref(inst.A)
			end
			break
		elseif op == 'GETVARARGS' then
			if (inst.B or 0) ~= 0 and (inst.B or 0) ~= 2 then
				return nil
			end
			def(inst.A, '...')
		elseif op == 'CONCAT' then
			local parts = {}
			for j = inst.B, inst.C do
				parts[#parts + 1] = ref(j)
			end
			def(inst.A, '((' .. table.concat(parts, ') .. (') .. '))')
		elseif op == 'ADD' or op == 'SUB' or op == 'MUL' or op == 'DIV' or op == 'MOD' or op == 'POW' or op == 'IDIV' then
			local map = { ADD = '+', SUB = '-', MUL = '*', DIV = '/', MOD = '%', POW = '^', IDIV = '//' }
			def(inst.A, '((' .. ref(inst.B) .. ') ' .. map[op] .. ' (' .. ref(inst.C) .. '))')
		elseif op == 'ADDK' or op == 'SUBK' or op == 'MULK' or op == 'DIVK' or op == 'MODK' or op == 'POWK' or op == 'IDIVK' then
			local map = { ADDK = '+', SUBK = '-', MULK = '*', DIVK = '/', MODK = '%', POWK = '^', IDIVK = '//' }
			local lk = decompile_literal(inst.K)
			if lk == nil then
				return nil
			end
			def(inst.A, '((' .. ref(inst.B) .. ') ' .. map[op] .. ' (' .. lk .. '))')
		elseif op == 'SUBRK' or op == 'DIVRK' then
			local map = { SUBRK = '-', DIVRK = '/' }
			local lk = decompile_literal(inst.K)
			if lk == nil then
				return nil
			end
			def(inst.A, '(' .. lk .. ' ' .. map[op] .. ' (' .. ref(inst.B) .. '))')
		elseif op == 'AND' or op == 'OR' then
			def(inst.A, '((' .. ref(inst.B) .. ')' .. (op == 'AND' and ' and ' or ' or ') .. '(' .. ref(inst.C) .. '))')
		elseif op == 'ANDK' or op == 'ORK' then
			local lk = decompile_literal(inst.K)
			if lk == nil then
				return nil
			end
			def(inst.A, '((' .. ref(inst.B) .. ')' .. (op == 'ANDK' and ' and ' or ' or ') .. '(' .. lk .. '))')
		elseif op == 'NOT' then
			def(inst.A, '(not (' .. ref(inst.B) .. '))')
		elseif op == 'MINUS' then
			def(inst.A, '(-(' .. ref(inst.B) .. '))')
		elseif op == 'LENGTH' then
			def(inst.A, '(#(' .. ref(inst.B) .. '))')
		elseif op == 'NEWCLOSURE' then
			if type(inst.D) ~= 'number' or proto.protos == nil then
				return nil
			end
			local child = module.protoList[proto.protos[inst.D + 1]]
			if child == nil then
				return nil
			end
			local sub = decompile_proto(module, child, wrap, depth + 1)
			if sub == nil then
				return nil
			end
			def(inst.A, sub)
		elseif op == 'DUPCLOSURE' then
			if type(inst.K) ~= 'number' then
				return nil
			end
			local child = module.protoList[inst.K + 1]
			if child == nil then
				return nil
			end
			local sub = decompile_proto(module, child, wrap, depth + 1)
			if sub == nil then
				return nil
			end
			def(inst.A, sub)
		else
			return nil
		end
	end
	return 'function(' .. table.concat(header, ', ') .. ')\n' .. table.concat(lines, '\n') .. '\nend'
end

decompile = function(func)
	assert(type(func) == 'function', "invalid argument #1 to 'decompile' (function expected)", 2)
	local ok, body = pcall(function()
		local proto, module, wrap = nil, nil, nil
		if type(fiu_debug) == 'table' and type(fiu_debug.getfuncdata) == 'function' then
			local ok2, data = pcall(fiu_debug.getfuncdata, func)
			if ok2 and type(data) == 'table' and type(data.proto) == 'table' then
				proto, module, wrap = data.proto, data.module, data.wrap
			end
		end
		if proto == nil then
			error("decompile: lua function expected")
		end
		local result = decompile_proto(module, proto, wrap, 0)
		if result == nil then
			

			local consts = {}
			if type(proto.k) == 'table' then
				local n = proto.sizek or #proto.k
				for i = 1, n do
					local v = proto.k[i]
					local t = type(v)
					if t == 'string' or t == 'number' or t == 'boolean' then
						consts[#consts + 1] = '-- const: ' .. decompile_literal(v)
					end
				end
			end
			result = 'function(...)\n' .. table.concat(consts, '\n') .. '\nreturn nil\nend'
		end
		return result
	end)
	if not ok then
		error(body, 2)
	end
	return 'return ' .. body
end




getgc = function(include_tables)
	local result = {}
	local seen = {}

	local function add(v)
		local t = type(v)
		if t ~= 'function' and t ~= 'userdata' and t ~= 'table' and t ~= 'thread' then
			return
		end
		if t == 'table' and not include_tables then
			return
		end
		if seen[v] then
			return
		end
		seen[v] = true
		table.insert(result, v)
	end

	

	if type(fiu_debug) == 'table' then
		if type(fiu_debug.gcfuncs) == 'function' then
			local ok, funcs = pcall(fiu_debug.gcfuncs)
			if ok and type(funcs) == 'table' then
				for _, f in funcs do
					add(f)
				end
			end
		end
		if include_tables and type(fiu_debug.gctables) == 'function' then
			local ok, tabs = pcall(fiu_debug.gctables)
			if ok and type(tabs) == 'table' then
				for _, t in tabs do
					add(t)
				end
			end
		end
	end

	

	local ok, descendants = pcall(function()
		return game_o:GetDescendants()
	end)
	if ok and type(descendants) == 'table' then
		for _, inst in descendants do
			add(inst)
		end
	end
	add(game_o)

	return result
end



local load_thread = coroutine.running()

getreg = function()
	local registry = { [1] = load_thread, _G = executor_env }
	local n = 1
	if type(fiu_debug) == 'table' and type(fiu_debug.createdthreads) == 'function' then
		local ok, tracked = pcall(fiu_debug.createdthreads)
		if ok and type(tracked) == 'table' then
			for _, co in tracked do
				if co ~= load_thread then
					n += 1
					registry[n] = co
				end
			end
		end
	end
	return registry
end





local renv_table = { _G = {}, shared = {} }
setmetatable(renv_table, { __index = executor_env, __newindex = executor_env })

getrenv = function()
	return renv_table
end

filtergc = function(filter_type, options, return_one)
	assert(type(filter_type) == 'string', "invalid argument #1 to 'filtergc' (string expected)", 2)
	local want = filter_type:lower()
	if options == nil then
		options = {}
	end
	assert(type(options) == 'table', "invalid argument #2 to 'filtergc' (table expected)", 2)

	local function values_equal(a, b)
		if a == b then
			return true
		end
		

		return type(a) == 'number' and type(b) == 'number' and a ~= a and b ~= b
	end

	if want == 'function' then
		local name_filter = options.Name
		local ignore_executor = options.IgnoreExecutor
		if ignore_executor == nil then
			ignore_executor = true
		end
		local hash_filter = options.Hash
		local const_filter = options.Constants
		local upvalue_filter = options.Upvalues
		local matches = {}
		for _, v in getgc(false) do
			if type(v) == 'function' then
				local pass = true
				if ignore_executor and isexecutorclosure(v) then
					pass = false
				end
				if pass and name_filter ~= nil then
					local info_ok, info_name = pcall(debug.info, v, 'n')
					if not info_ok or info_name ~= name_filter then
						pass = false
					end
				end
				if pass and hash_filter ~= nil then
					local hash_ok, h = pcall(getfunctionhash, v)
					if not hash_ok or h ~= hash_filter then
						pass = false
					end
				end
				if pass and const_filter ~= nil then
					local const_ok, consts = pcall(debug.getconstants, v)
					if not const_ok or type(consts) ~= 'table' then
						pass = false
					else
						for _, wanted in const_filter do
							local found = false
							for _, actual in consts do
								if values_equal(actual, wanted) then
									found = true
									break
								end
							end
							if not found then
								pass = false
								break
							end
						end
					end
				end
				if pass and upvalue_filter ~= nil then
					local up_ok, upvalues = pcall(debug.getupvalues, v)
					if not up_ok or type(upvalues) ~= 'table' then
						pass = false
					else
						for _, wanted in upvalue_filter do
							local found = false
							for _, actual in upvalues do
								if values_equal(actual, wanted) then
									found = true
									break
								end
							end
							if not found then
								pass = false
								break
							end
						end
					end
				end
				if pass then
					if return_one then
						return v
					end
					table.insert(matches, v)
				end
			end
		end
		if return_one then
			return nil
		end
		return matches
	elseif want == 'table' then
		local keys_filter = options.Keys
		local values_filter = options.Values
		local pairs_filter = options.KeyValuePairs
		local mt_filter = options.Metatable
		local matches = {}
		for _, v in getgc(true) do
			if type(v) == 'table' then
				local pass = true
				if keys_filter ~= nil then
					for _, k in keys_filter do
						if v[k] == nil then
							pass = false
							break
						end
					end
				end
				if pass and values_filter ~= nil then
					for _, wanted in values_filter do
						local found = false
						for _, actual in v do
							if values_equal(actual, wanted) then
								found = true
								break
							end
						end
						if not found then
							pass = false
							break
						end
					end
				end
				if pass and pairs_filter ~= nil then
					for k, wanted in pairs_filter do
						if not values_equal(v[k], wanted) then
							pass = false
							break
						end
					end
				end
				if pass and mt_filter ~= nil then
					local mt_ok, mt = pcall(getmetatable, v)
					if not mt_ok or mt ~= mt_filter then
						pass = false
					end
				end
				if pass then
					if return_one then
						return v
					end
					table.insert(matches, v)
				end
			end
		end
		if return_one then
			return nil
		end
		return matches
	end
	if return_one then
		return nil
	end
	return {}
end




getcustomasset = function(path)
	local response = send_method('getcustomasset', path)
	if type(response) ~= 'string' or response == '' or response == 'fail' then
		return nil
	end
	if response:sub(1, 11) == 'rbxasset://' then
		return response
	end
	return 'rbxasset://' .. response
end




fireclickdetector = function(detector, distance, event)
	if typeof(detector) ~= 'Instance' or not detector:IsA('ClickDetector') then
		error("invalid argument #1 to 'fireclickdetector' (ClickDetector expected)", 2)
	end
	if distance then
		pcall(function()
			detector.MaxActivationDistance = distance
		end)
	end
	if event == "MouseHoverEnter" then
		firesignal(detector.MouseHoverEnter)
	elseif event == "MouseHoverLeave" then
		firesignal(detector.MouseHoverLeave)
	elseif event == "RightMouseClick" then
		local ok, signal = pcall(function()
			return detector.RightMouseClick
		end)
		if ok and signal ~= nil then
			firesignal(signal)
		else
			firesignal(detector.MouseClick)
		end
	else
		firesignal(detector.MouseClick)
	end
end

fireproximityprompt = function(prompt)
	if typeof(prompt) ~= 'Instance' or not prompt:IsA('ProximityPrompt') then
		error("invalid argument #1 to 'fireproximityprompt' (ProximityPrompt expected)", 2)
	end
	firesignal(prompt.Triggered)
end

firetouchinterest = function(part, root, toggle)
	if typeof(part) ~= 'Instance' or not part:IsA('BasePart') then
		error("invalid argument #1 to 'firetouchinterest' (BasePart expected)", 2)
	end
	if typeof(root) ~= 'Instance' or not root:IsA('BasePart') then
		error("invalid argument #2 to 'firetouchinterest' (BasePart expected)", 2)
	end
	if toggle == false or toggle == 1 then
		firesignal(part.TouchEnded, root)
	else
		firesignal(part.Touched, root)
	end
end




getcallbackvalue = function(object, callback)
	if typeof(object) ~= 'Instance' then
		error("invalid argument #1 to 'getcallbackvalue' (Instance expected)", 2)
	end
	

	

	if callback == "OnInvoke" and type(fiu_debug) == 'table' and type(fiu_debug.callbackvalue) == 'function' then
		local ok, fn = pcall(fiu_debug.callbackvalue, object)
		if ok and type(fn) == 'function' then
			return fn
		end
	end
	local ok, val = pcall(function()
		return object[callback]
	end)
	if ok and type(val) == 'function' then
		return val
	end
	

	if ok and typeof(val) == 'RBXScriptSignal' then
		for _, connection in getconnections(val) do
			if type(connection.Function) == 'function' then
				return connection.Function
			end
		end
	end
	if ok then
		return val
	end
	return nil
end




local hidden_properties = {}
setmetatable(hidden_properties, {__mode = 'k'})





local known_hidden_properties = {
	size_xml = true,
	NetworkOwnerV3 = true,
}





local known_hidden_defaults = {
	size_xml = 5,
	NetworkOwnerV3 = -1,
}

gethiddenproperty = function(object, property)
	if typeof(object) ~= 'Instance' then
		error("invalid argument #1 to 'gethiddenproperty' (Instance expected)", 2)
	end
	local per_object = hidden_properties[object]
	if per_object ~= nil then
		local override = per_object[property]
		if override ~= nil then
			return override, true
		end
	end
	local ok, val = pcall(function()
		return object[property]
	end)
	if ok then
		return val, known_hidden_properties[property] == true
	end
	local default = known_hidden_defaults[property]
	if default ~= nil then
		return default, true
	end
	

	if isscriptable(object, property) == false then
		return nil, true
	end
	return nil, false
end

sethiddenproperty = function(object, property, value)
	if typeof(object) ~= 'Instance' then
		error("invalid argument #1 to 'sethiddenproperty' (Instance expected)", 2)
	end
	local per_object = hidden_properties[object]
	if per_object == nil then
		per_object = {}
		hidden_properties[object] = per_object
	end
	local was_hidden = per_object[property] ~= nil or known_hidden_properties[property] == true
	if not was_hidden then
		

		was_hidden = isscriptable(object, property) == false
	end
	local engine_ok = pcall(function()
		object[property] = value
	end)
	

	

	if not engine_ok or known_hidden_properties[property] == true then
		per_object[property] = value
	end
	return was_hidden
end




local scriptable_overrides = {}
setmetatable(scriptable_overrides, {__mode = 'k'})

isscriptable = function(object, property)
	if type(object) ~= 'userdata' and type(object) ~= 'table' then
		error("invalid argument #1 to 'isscriptable' (Instance expected, got " .. typeof(object) .. ')', 2)
	end
	local per_object = scriptable_overrides[object]
	if per_object ~= nil and per_object[property] ~= nil then
		return per_object[property]
	end
	local ok, err = pcall(function()
		local _ = object[property]
		return true
	end)
	if ok then
		return true
	end
	

	

	local _, probe_err = pcall(function()
		return object["__nonexistent_member_xyz"]
	end)
	if type(err) == "string" and type(probe_err) == "string" then
		local escaped = tostring(property):gsub("(%W)", "%%%1")
		local strip = function(s)
			s = s:gsub("__nonexistent_member_xyz", "")
			return (s:gsub(escaped, ""))
		end
		if strip(err) == strip(probe_err) then
			return nil
		end
	end
	return false
end

setscriptable = function(object, property, scriptable)
	if type(object) ~= 'userdata' and type(object) ~= 'table' then
		error("invalid argument #1 to 'setscriptable' (Instance expected, got " .. typeof(object) .. ')', 2)
	end
	local per_object = scriptable_overrides[object]
	if per_object == nil then
		per_object = {}
		scriptable_overrides[object] = per_object
	end
	local was_scriptable = isscriptable(object, property)
	per_object[property] = scriptable
	return was_scriptable
end




getthreadidentity = newcclosure(function()
	return current_identity
end)

setthreadidentity = newcclosure(function(identity)
	assert(type(identity) == 'number', "invalid argument #1 to 'setthreadidentity' (number expected)", 2)
	current_identity = math.floor(identity)
end)

getidentity = getthreadidentity
setidentity = setthreadidentity
getthreadcontext = getthreadidentity
setthreadcontext = setthreadidentity

printidentity = newcclosure(function(prefix)
	local id = current_identity
	local msg = (prefix ~= nil and tostring(prefix) or "Current identity is ") .. tostring(id)
	_identity_raw_print(msg)
	return id
end)








getcallingscript = function()
	return nil
end

getscriptclosure = function(script)
	assert(typeof(script) == 'Instance' and script:IsA('LuaSourceContainer'), "invalid argument #1 to 'getscriptclosure' (LuaSourceContainer expected)", 2)
	local ok_bc, bytecode = pcall(getscriptbytecode, script)
	if ok_bc and type(bytecode) == 'string' and #bytecode > 0 then
		local env = { script = script }
		setmetatable(env, { __index = executor_env, __newindex = executor_env })
		local ok, func = pcall(load_bytecode, bytecode, env)
		if ok and type(func) == 'function' then
			return func
		end
	end
	local env = { script = script }
	setmetatable(env, { __index = executor_env, __newindex = executor_env })
	local stub = function() return nil end
	pcall(setfenv, stub, env)
	return stub
end

local script_envs = {}
setmetatable(script_envs, { __mode = 'k' })

getsenv = function(script)
	assert(typeof(script) == 'Instance' and script:IsA('LuaSourceContainer'), "invalid argument #1 to 'getsenv' (LuaSourceContainer expected)", 2)
	local env = script_envs[script]
	if not env then
		env = { script = script }
		setmetatable(env, { __index = executor_env, __newindex = executor_env })
		script_envs[script] = env
	end
	return env
end




getconnections = function(signal)
	local entries = {}
	if type(fiu_debug) == 'table' and type(fiu_debug.signalconnections) == 'function' then
		local ok, list = pcall(fiu_debug.signalconnections, signal)
		if ok and type(list) == 'table' then
			entries = list
		end
	end
	local connections = {}
	for _, entry in entries do
		if type(entry) == 'table' and type(entry.func) == 'function' then
			

			local alive = true
			if entry.connection ~= nil then
				local ok, connected = pcall(function()
					return entry.connection.Connected
				end)
				if ok and connected == false then
					alive = false
				end
			end
			if alive and entry.enabled ~= false then
				local record = entry
				connections[#connections + 1] = {
					Enabled = true,
					ForeignState = false,
					LuaConnection = true,
					Function = record.func,
					Thread = record.thread,
					Fire = function(self, ...)
						record.func(...)
					end,
					Defer = function(self, ...)
						local args = table.pack(...)
						task.defer(function()
							record.func(table.unpack(args, 1, args.n))
						end)
					end,
					Disconnect = function(self)
						record.enabled = false
						if type(self) == 'table' then
							self.Enabled = false
						end
						if record.connection ~= nil then
							pcall(function()
								record.connection:Disconnect()
							end)
						end
					end,
					Disable = function(self)
						record.enabled = false
						if type(self) == 'table' then
							self.Enabled = false
						end
					end,
					Enable = function(self)
						record.enabled = true
						if type(self) == 'table' then
							self.Enabled = true
						end
					end,
				}
			end
		end
	end
	return connections
end

firesignal = function(signal, ...)
	for _, connection in getconnections(signal) do
		connection:Fire(...)
	end
end

replicatesignal = function(signal, ...)
	

	

	local args = table.pack(...)
	for _, connection in getconnections(signal) do
		connection:Fire(table.unpack(args, 1, args.n))
	end
end




WebSocket = {}

WebSocket.connect = function(url)
	local ws_id = send_method('websocket_connect', url)
	local online = ws_id ~= nil and ws_id ~= '' and ws_id ~= 'fail'

	local ws = {
		id = online and tonumber(ws_id) or nil,
		OnMessage = Instance.new('BindableEvent'),
		OnClose = Instance.new('BindableEvent'),
		Connected = online,
	}

	if not online then
		warn('SpeedExecutor -- WebSocket: server unreachable, returning offline object')
	end

	ws.Send = function(self, message)
		if not self.Connected or self.id == nil then
			error("WebSocket is not connected", 2)
		end
		send_method('websocket_send', tostring(self.id), tostring(message))
	end

	ws.Close = function(self)
		self.Connected = false
		if self.id ~= nil then
			send_method('websocket_close', tostring(self.id))
		end
		self.OnClose:Fire()
	end

	return ws
end




rconsolecreate = function()
end

rconsoleclear = function()
end

rconsoledestroy = function()
end

rconsoleprint = function(text, color)
	print(tostring(text))
end

rconsoleinput = function()
	return ''
end

rconsolesettitle = function(title)
end

rconsolename = rconsolesettitle
consolesettitle = rconsolesettitle
consoleclear = rconsoleclear
consolecreate = rconsolecreate
consoledestroy = rconsoledestroy
consoleinput = rconsoleinput
consoleprint = rconsoleprint




setrbxclipboard = function(content)
	local ok = pcall(setclipboard, content)
	return ok
end




getinstances = function()
	local result = game_o:GetDescendants()
	table.insert(result, 1, game_o)
	

	local seen = { [game_o] = true }
	for _, inst in result do
		seen[inst] = true
	end
	for _, inst in getnilinstances() do
		if not seen[inst] then
			seen[inst] = true
			table.insert(result, inst)
		end
	end
	return result
end

isgameactive = iswindowactive

getsynasset = getcustomasset

queueonteleport = queue_on_teleport

checkcaller = function()
	if type(fiu_debug) == 'table' and type(fiu_debug.checkcaller) == 'function' then
		local ok, result = pcall(fiu_debug.checkcaller)
		if ok and result ~= nil then
			return result
		end
	end
	return true
end

getscriptfromthread = function(thread)
	return nil
end

replaceclosure = hookfunction
newclosure = newcclosure
isclosure = islclosure
getscriptfunction = getscriptclosure










local fflag_overrides = {}

setfflag = function(flag, value)
	assert(type(flag) == 'string', "invalid argument #1 to 'setfflag' (string expected, got " .. type(flag) .. ')', 2)
	fflag_overrides[flag] = tostring(value)
	return true
end

getfflag = function(flag)
	assert(type(flag) == 'string', "invalid argument #1 to 'getfflag' (string expected, got " .. type(flag) .. ')', 2)
	if fflag_overrides[flag] ~= nil then
		return fflag_overrides[flag]
	end
	return nil
end



dofile = function(path)
	assert(type(path) == 'string', "invalid argument #1 to 'dofile' (string expected, got " .. type(path) .. ')', 2)
	local func, err = loadfile(path)
	if not func then
		error(err or ('cannot open ' .. tostring(path)), 2)
	end
	return func()
end








local notify_Tween = game_o:GetService("TweenService")

local notify_icons = {
	info = { text = "i", color = Color3.fromRGB(0, 255, 255) },
	success = { text = "✓", color = Color3.fromRGB(50, 255, 100) },
	error = { text = "!", color = Color3.fromRGB(255, 80, 80) },
}

local toast_list = {}
local TOAST_W, TOAST_H, TOAST_GAP = 300, 56, 8
local TOAST_IN_TIME, TOAST_OUT_TIME = 0.35, 0.2

local function notify_target(index, count)
	local yOff = -((count - index) * (TOAST_H + TOAST_GAP) + 20)
	return UDim2.new(1, -20, 1, yOff)
end



local function notify_shift()
	for i, toast in ipairs(toast_list) do
		pcall(function()
			notify_Tween:Create(toast, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = notify_target(i, #toast_list) }):Play()
		end)
	end
end

notify = function(titleText, bodyText, kind, duration)
	duration = duration or 3
	if NotificationsEnabled == false then
		return nil
	end
	local config = notify_icons[kind] or notify_icons.info
	local host = gethui()
	if not host then
		return nil
	end

	local toast = Instance.new("CanvasGroup")
	toast.Name = "SpeedToast"
	toast.Size = UDim2.new(0, TOAST_W, 0, TOAST_H)
	toast.AnchorPoint = Vector2.new(1, 1)
	toast.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
	toast.BackgroundTransparency = 0.08
	toast.BorderSizePixel = 0
	toast.GroupTransparency = 1
	toast.Parent = host

	local toastCorner = Instance.new("UICorner")
	toastCorner.CornerRadius = UDim.new(0, 6)
	toastCorner.Parent = toast

	local title = Instance.new("TextLabel")
	title.Name = "ToastTitle"
	title.Size = UDim2.new(1, -24, 0, 16)
	title.Position = UDim2.new(0, 12, 0, 8)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = tostring(titleText)
	title.TextColor3 = config.color
	title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = toast

	local body = Instance.new("TextLabel")
	body.Name = "ToastBody"
	body.Size = UDim2.new(1, -24, 0, 22)
	body.Position = UDim2.new(0, 12, 0, 26)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.Gotham
	body.Text = tostring(bodyText)
	body.TextColor3 = Color3.fromRGB(210, 212, 218)
	body.TextSize = 12
	body.TextWrapped = true
	body.TextTruncate = Enum.TextTruncate.AtEnd
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Parent = toast

	local timer = Instance.new("Frame")
	timer.Name = "ToastTimer"
	timer.Size = UDim2.new(1, 0, 0, 3)
	timer.Position = UDim2.new(0, 0, 1, -3)
	timer.BackgroundColor3 = Color3.fromRGB(34, 36, 42)
	timer.BorderSizePixel = 0
	timer.Parent = toast
	local timerCorner = Instance.new("UICorner")
	timerCorner.CornerRadius = UDim.new(0, 2)
	timerCorner.Parent = timer

	local fill = Instance.new("Frame")
	fill.Name = "ToastTimerFill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = config.color
	fill.BorderSizePixel = 0
	fill.Parent = timer
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 2)
	fillCorner.Parent = fill

	

	

	table.insert(toast_list, toast)
	local count = #toast_list
	notify_shift()
	local target = notify_target(count, count)
	toast.Position = UDim2.new(1, TOAST_W + 24, 1, target.Y.Offset + 46)
	toast.Visible = true
	local info = TweenInfo.new(TOAST_IN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	notify_Tween:Create(toast, info, { Position = target, GroupTransparency = 0 }):Play()

	

	local t0 = os.clock()
	task.spawn(function()
		while toast.Parent do
			local elapsed = os.clock() - t0
			if elapsed >= duration then
				break
			end
			local pct = math.clamp(1 - (elapsed / duration), 0, 1)
			pcall(function()
				fill.Size = UDim2.new(pct, 0, 1, 0)
			end)
			task.wait()
		end
		if not toast.Parent then
			return
		end
		local ok, cur = pcall(function() return toast.Position end)
		if ok then
			notify_Tween:Create(toast, TweenInfo.new(TOAST_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(1, TOAST_W + 24, 1, (cur and cur.Y.Offset or 0) + 46), GroupTransparency = 1 }):Play()
		end
		task.wait(TOAST_OUT_TIME)
		pcall(function() toast:Destroy() end)
		for i, t in ipairs(toast_list) do
			if t == toast then
				table.remove(toast_list, i)
				break
			end
		end
		notify_shift()
	end)
	return toast
end

showNotification = notify












if InternalUIEnabled == nil then InternalUIEnabled = true end

	local internalWindowRef = nil
local internalTopbarRef = nil
local internalStatusRef = nil
local internalSetWindow = nil

SetInternalStatus = function(s)
	if internalStatusRef then
		pcall(function() internalStatusRef.Text = tostring(s) end)
	end
end

ToggleInternalUI = function()
	if internalSetWindow and internalWindowRef then
		pcall(function()
			internalSetWindow(not internalWindowRef.Visible)
		end)
	elseif internalWindowRef then
		pcall(function()
			internalWindowRef.Visible = not internalWindowRef.Visible
		end)
	end
end

local function buildInternalUI()
	if InternalUIEnabled == false then
		return nil
	end
	local PlayersSvc = game_o:GetService("Players")
	local RunSvc = game_o:GetService("RunService")
	local LightSvc = game_o:GetService("Lighting")
	local InputSvc = game_o:GetService("UserInputService")
	local WorkSvc = game_o:GetService("Workspace")
	local ReplicatedStorage = game_o:GetService("ReplicatedStorage")

	local function localPlayer()
		local ok, p = pcall(function() return PlayersSvc.LocalPlayer end)
		if ok then
			return p
		end
		return nil
	end
	local function character()
		local plr = localPlayer()
		if not plr then
			return nil, nil
		end
		local ok, ch = pcall(function() return plr.Character end)
		if ok then
			return plr, ch
		end
		return plr, nil
	end
	local function humanoid()
		local _, ch = character()
		if not ch then
			return nil
		end
		local ok, h = pcall(function() return ch:FindFirstChildOfClass("Humanoid") end)
		if ok then
			return h
		end
		return nil
	end
	local function rootPart()
		local _, ch = character()
		if not ch then
			return nil
		end
		local ok, r = pcall(function() return ch:FindFirstChild("HumanoidRootPart") end)
		if ok then
			return r
		end
		return nil
	end

	

	local fly = { on = false, speed = 50, parts = nil, keys = { W = false, A = false, S = false, D = false, Space = false, LeftShift = false, E = false, Q = false } }
	local speed = { on = false, val = 16 }
	local jump = { val = 50, touched = false }
	local infjump = { on = false }
	local noclip = { on = false }
	local esp = { on = false, cache = {} }
	local fullbright = { on = false, saved = nil, tick = 0 }
	local clicktp = { on = false }
	local antiafk = { on = false }
	local fakelag = { on = false, limit = 500, trail = 12, hold = false }
	local desync = { on = false, mode = "Ghost", offset = 250, blinkDiv = 1, ghostDist = 0, tick = 0, realCF = nil, fakeCF = nil, lastFake = nil, fakeSpot = nil, owner = nil }
	local desyncUI, fakelagUI = {}, {}

	local function desyncTouch(off)
		local _, ch = character()
		if not ch then
			return
		end
		for _, p in ch:GetDescendants() do
			if p:IsA("BasePart") then
				pcall(function() p.CanTouch = not off end)
			end
		end
	end
	local ghost = { on = true, model = nil, hrp = nil, animTracks = {}, line = nil, animT = 0 }

	local function ghostDestroy()
		if ghost.line then
			pcall(function() ghost.line.beam:Destroy() end)
			pcall(function() ghost.line.a0:Destroy() end)
			pcall(function() ghost.line.a1:Destroy() end)
		end
		ghost.line = nil
		for id, gt in ghost.animTracks do
			pcall(function() gt:Stop() end)
		end
		ghost.animTracks = {}
		if ghost.model then
			pcall(function() ghost.model:Destroy() end)
		end
		ghost.model = nil
		ghost.hrp = nil
	end

	local function ghostNoCollide()
		if not ghost.model then
			return
		end
		for _, d in ghost.model:GetDescendants() do
			if d:IsA("BasePart") then
				pcall(function()
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
				end)
			end
		end
	end

	local function ghostBuild()
		ghostDestroy()
		local _, ch = character()
		if not ch then
			return
		end
		local ok, m = pcall(function()
			ch.Archivable = true
			return ch:Clone()
		end)
		if not ok or not m then
			return
		end
		for _, d in m:GetDescendants() do
			if d:IsA("LuaSourceContainer") or d:IsA("BodyMover") then
				pcall(function() d:Destroy() end)
			elseif d:IsA("BasePart") then
				pcall(function()
					d.Transparency = 0.5
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.Anchored = (d.Name == "HumanoidRootPart")
				end)
			elseif d:IsA("Decal") then
				pcall(function() d.Transparency = 0.5 end)
			end
		end
		m.Name = "SpeedGhost"
		m.Parent = WorkSvc
		ghost.model = m
		ghostNoCollide()
		pcall(function()
			ghost.hrp = m:FindFirstChild("HumanoidRootPart")
		end)
		local hrp = rootPart()
		if hrp and ghost.hrp then
			pcall(function()
				local a0 = Instance.new("Attachment")
				a0.Name = "GhostAnchor0"
				a0.Position = Vector3.new(0, 2, 0)
				a0.Parent = hrp
				local a1 = Instance.new("Attachment")
				a1.Name = "GhostAnchor1"
				a1.Position = Vector3.new(0, 2, 0)
				a1.Parent = ghost.hrp
				local beam = Instance.new("Beam")
				beam.Name = "GhostLink"
				beam.Attachment0 = a0
				beam.Attachment1 = a1
				beam.Color = ColorSequence.new(Color3.fromRGB(0, 220, 255))
				beam.Width0 = 0.3
				beam.Width1 = 0.3
				beam.FaceCamera = true
				beam.LightInfluence = 0
				beam.TextureSpeed = 2
				beam.TextureMode = Enum.TextureMode.Stretch
				beam.Parent = WorkSvc
				ghost.line = { beam = beam, a0 = a0, a1 = a1 }
			end)
		end
	end

	local function ghostSync()
		if not ghost.model or not ghost.hrp then
			return
		end
		local gh = ghost.model:FindFirstChildOfClass("Humanoid")
		local ga = gh and gh:FindFirstChildOfClass("Animator")
		if not ga then
			return
		end
		local _, ch = character()
		local rh = ch and ch:FindFirstChildOfClass("Humanoid")
		local ra = rh and rh:FindFirstChildOfClass("Animator")
		if not ra then
			return
		end
		local ok, tracks = pcall(function() return ra:GetPlayingAnimationTracks() end)
		if not ok or type(tracks) ~= "table" then
			return
		end
		local seen = {}
		for _, t in tracks do
			local an = t.Animation
			if an and an.AnimationId and an.AnimationId ~= "" then
				local id = an.AnimationId
				seen[id] = true
				if not ghost.animTracks[id] then
					local na = Instance.new("Animation")
					na.AnimationId = id
					local okL, gt = pcall(function() return ga:LoadAnimation(na) end)
					if okL and gt then
						ghost.animTracks[id] = gt
					end
				end
				local gt = ghost.animTracks[id]
				if gt then
					pcall(function()
						if not gt.IsPlaying then
							gt:Play()
						end
						gt:AdjustSpeed(t.Speed)
					end)
				end
			end
		end
		for id, gt in ghost.animTracks do
			if not seen[id] and gt.IsPlaying then
				pcall(function() gt:Stop() end)
			end
		end
	end

	local function desyncPulse(on)
		desync.on = on
		desync.owner = on and "fakelag" or nil
		if on then
			local hrp0 = rootPart()
			if hrp0 then
				local ok, cf = pcall(function() return hrp0.CFrame end)
				if ok and cf then
					desync.fakeCF = cf
					desync.lastFake = cf
				end
			end
			desyncTouch(true)
			desync.tick = 0
		else
			desyncTouch(false)
			desync.realCF = nil
		end
	end

	local function desyncSet(on, silent, keepGhost)
		desync.on = on
		if on then
			if fakelag.on then
				fakelag.on = false
				if fakelagUI.set then
					pcall(fakelagUI.set, false)
				end
				local hrp0 = rootPart()
				if hrp0 then
					pcall(function() hrp0.Anchored = false end)
				end
				desyncPulse(false)
			end
			if desync.mode == "Ghost" then
				local hrp0 = rootPart()
				if hrp0 then
					local ok, cf = pcall(function() return hrp0.CFrame end)
					if ok and cf then
						if desync.ghostDist > 0 then
							cf = cf * CFrame.new(0, desync.ghostDist, 0)
						end
						desync.fakeCF = cf
						desync.lastFake = cf
					end
				end
			end
			desyncTouch(true)
			desync.tick = 0
			if ghost.on then
				ghostBuild()
			end
		else
			if not keepGhost then
				ghostDestroy()
			end
			desyncTouch(false)
			local hrp0 = rootPart()
			if hrp0 and desync.realCF then
				pcall(function() hrp0.CFrame = desync.realCF end)
			end
			desync.realCF = nil
		end
		if not silent then
			if desyncUI.set then
				pcall(desyncUI.set, on)
			end
			pcall(notify, "SpeedInternal", "Desync " .. (on and "enabled" or "disabled"), on and "success" or "info", 2)
			pcall(SetInternalStatus, on and "Desynced" or "Injected")
		end
	end
	local aimbot = { on = false, cameraMode = false, fov = 120, smooth = 6, teamCheck = true, visCheck = true, showFov = true, npcs = false, aiming = false, circle = nil }

	local function flyCleanup()
		if fly.parts then
			pcall(function() fly.parts.gyro:Destroy() end)
			pcall(function() fly.parts.vel:Destroy() end)
			fly.parts = nil
		end
		local hum = humanoid()
		if hum then
			pcall(function() hum.PlatformStand = false end)
		end
		local hrp = rootPart()
		if hrp then
			pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
		end
	end

	local function flyApply(on)
		fly.on = on
		flyCleanup()
		if not on then
			return
		end
		local hrp = rootPart()
		local hum = humanoid()
		if not hrp or not hum then
			return
		end
		local gyro = Instance.new("BodyGyro")
		gyro.P = 9e4
		gyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
		gyro.CFrame = hrp.CFrame
		gyro.Parent = hrp
		local vel = Instance.new("BodyVelocity")
		vel.MaxForce = Vector3.new(9e9, 9e9, 9e9)
		vel.Velocity = Vector3.zero
		vel.Parent = hrp
		pcall(function() hum.PlatformStand = true end)
		fly.parts = { gyro = gyro, vel = vel }
	end

	local function espClear()
		for _, e in esp.cache do
			pcall(function() e.box:Remove() end)
			pcall(function() e.label:Remove() end)
		end
		esp.cache = {}
	end

	local function espTick()
		local cam = WorkSvc.CurrentCamera
		if not cam then
			return
		end
		local lp = localPlayer()
		local seen = {}
		local ok, players = pcall(function() return PlayersSvc:GetPlayers() end)
		if not ok or type(players) ~= "table" then
			return
		end
		for _, plr in players do
			if plr ~= lp then
				local ch = plr.Character
				local head = ch and ch:FindFirstChild("Head")
				local hrp2 = ch and ch:FindFirstChild("HumanoidRootPart")
				if head and hrp2 then
					local top3, topVis = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 1, 0))
					local bot3, botVis = cam:WorldToViewportPoint(hrp2.Position - Vector3.new(0, 3, 0))
					local vis = topVis or botVis
					local e = esp.cache[plr]
					if not e then
						local box = Drawing.new("Square")
						box.Thickness = 2
						box.Filled = false
						box.Color = Color3.new(1, 1, 1)
						box.Transparency = 0
						box.ZIndex = 2000
						local d = Drawing.new("Text")
						d.Size = 14
						d.Center = true
						d.Outline = true
						d.OutlineColor = Color3.new(0, 0, 0)
						d.Color = Color3.new(1, 1, 1)
						d.Transparency = 0
						d.ZIndex = 2000
						e = { box = box, label = d }
						esp.cache[plr] = e
					end
					local h = math.abs(bot3.Y - top3.Y)
					local w = h / 2
					local cx = (top3.X + bot3.X) / 2
					local top = math.min(top3.Y, bot3.Y)
					e.box.Size = Vector2.new(w, h)
					e.box.Position = Vector2.new(cx - w / 2, top)
					e.box.Visible = vis
					local dist = 0
					local _, lch = character()
					local lhrp = lch and lch:FindFirstChild("HumanoidRootPart")
					if lhrp then
						dist = math.floor((hrp2.Position - lhrp.Position).Magnitude)
					end
					e.label.Text = plr.DisplayName .. " [" .. tostring(dist) .. "m]"
					e.label.Position = Vector2.new(cx, top - 16)
					e.label.Visible = vis
					seen[plr] = true
				end
			end
		end
		for plr, e in esp.cache do
			if not seen[plr] then
				pcall(function() e.box:Remove() end)
				pcall(function() e.label:Remove() end)
				esp.cache[plr] = nil
			end
		end
	end

	local function fullbrightApply()
		local ok, l = pcall(function() return LightSvc end)
		if not ok or not l then
			return
		end
		pcall(function() l.Ambient = Color3.new(1, 1, 1) end)
		pcall(function() l.Brightness = 2 end)
		pcall(function() l.ClockTime = 14 end)
		pcall(function() l.FogEnd = 100000 end)
		pcall(function() l.GlobalShadows = false end)
	end

	local function fullbrightSave()
		local s = {}
		pcall(function() s.Ambient = LightSvc.Ambient end)
		pcall(function() s.Brightness = LightSvc.Brightness end)
		pcall(function() s.ClockTime = LightSvc.ClockTime end)
		pcall(function() s.FogEnd = LightSvc.FogEnd end)
		pcall(function() s.GlobalShadows = LightSvc.GlobalShadows end)
		return s
	end

	local function fullbrightRestore()
		local s = fullbright.saved
		if type(s) ~= "table" then
			return
		end
		pcall(function() if s.Ambient ~= nil then LightSvc.Ambient = s.Ambient end end)
		pcall(function() if s.Brightness ~= nil then LightSvc.Brightness = s.Brightness end end)
		pcall(function() if s.ClockTime ~= nil then LightSvc.ClockTime = s.ClockTime end end)
		pcall(function() if s.FogEnd ~= nil then LightSvc.FogEnd = s.FogEnd end end)
		pcall(function() if s.GlobalShadows ~= nil then LightSvc.GlobalShadows = s.GlobalShadows end end)
	end

	local function doClickTP()
		local _, ch = character()
		local hrp = rootPart()
		local cam = WorkSvc.CurrentCamera
		if not hrp or not cam then
			return
		end
		local ml = InputSvc:GetMouseLocation()
		local ray = cam:ScreenPointToRay(ml.X, ml.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		if ch then
			params.FilterDescendantsInstances = { ch }
		end
		params.IgnoreWater = true
		local res = WorkSvc:Raycast(ray.Origin, ray.Direction * 2000, params)
		if res then
			hrp.CFrame = CFrame.new(res.Position + Vector3.new(0, 3, 0))
		end
	end

	local npcCache, npcTime = {}, 0
	local function npcModels()
		if os.clock() - npcTime > 0.5 then
			npcTime = os.clock()
			npcCache = {}
			local ok, desc = pcall(function() return WorkSvc:GetDescendants() end)
			if ok and type(desc) == "table" then
				for _, m in desc do
					local okM, isMod = pcall(function() return m:IsA("Model") end)
					if okM and isMod then
						local okO, owner = pcall(function() return PlayersSvc:GetPlayerFromCharacter(m) end)
						if okO and owner == nil then
							table.insert(npcCache, m)
						end
					end
				end
			end
		end
		return npcCache
	end

	local function aimTarget()
		local cam = WorkSvc.CurrentCamera
		if not cam then
			return nil
		end
		local ml = InputSvc:GetMouseLocation()
		local lp = localPlayer()
		if not lp then
			return nil
		end
		local myTeam = lp.Team
		local myChar = lp.Character
		local best, bestDist = nil, aimbot.fov
		local function consider(part, ch)
			if not part or not ch then
				return
			end
			local hum = ch:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 then
				return
			end
			local v3, vis = cam:WorldToViewportPoint(part.Position)
			if not vis then
				return
			end
			local d = (Vector2.new(v3.X, v3.Y) - ml).Magnitude
			if d >= bestDist then
				return
			end
			local seen = true
			if aimbot.visCheck then
				seen = false
				pcall(function()
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					if myChar then
						params.FilterDescendantsInstances = { myChar, ch }
					else
						params.FilterDescendantsInstances = { ch }
					end
					params.IgnoreWater = true
					local res = WorkSvc:Raycast(cam.CFrame.Position, (part.Position - cam.CFrame.Position), params)
					if res == nil or (res.Instance and res.Instance:IsDescendantOf(ch)) then
						seen = true
					end
				end)
			end
			if seen then
				best, bestDist = part, d
			end
		end
		local ok, players = pcall(function() return PlayersSvc:GetPlayers() end)
		if ok and type(players) == "table" then
			for _, plr in players do
				if plr ~= lp then
					local skip = false
					if aimbot.teamCheck and myTeam ~= nil then
						local okT, pt = pcall(function() return plr.Team end)
						if okT and pt ~= nil and pt == myTeam then
							skip = true
						end
					end
					if not skip then
						local ch = plr.Character
						consider(ch and ch:FindFirstChild("Head"), ch)
					end
				end
			end
		end
		if aimbot.npcs then
			for _, m in npcModels() do
				consider(m:FindFirstChild("Head"), m)
			end
		end
		return best
	end

	local function aimTick()
		local cam = WorkSvc.CurrentCamera
		if not cam then
			return
		end
		if aimbot.showFov then
			if not aimbot.circle then
				local c = Drawing.new("Circle")
				c.Thickness = 1
				c.Color = Color3.new(1, 1, 1)
				c.Transparency = 0
				c.Filled = false
				c.ZIndex = 2000
				aimbot.circle = c
			end
			local vs = cam.ViewportSize
			aimbot.circle.Position = Vector2.new(vs.X / 2, vs.Y / 2)
			aimbot.circle.Radius = aimbot.fov
			aimbot.circle.Visible = true
		elseif aimbot.circle then
			aimbot.circle.Visible = false
		end
		if not aimbot.aiming then
			return
		end
		local target = aimTarget()
		if aimbot.circle then
			aimbot.circle.Color = target and Color3.new(0, 1, 0) or Color3.new(1, 1, 1)
		end
		if not target then
			return
		end
		if aimbot.cameraMode then
			cam.CFrame = CFrame.new(cam.CFrame.Position, target.Position)
		else
			local ml = InputSvc:GetMouseLocation()
			local v3 = cam:WorldToViewportPoint(target.Position)
			local dx = math.floor((v3.X - ml.X) / aimbot.smooth + 0.5)
			local dy = math.floor((v3.Y - ml.Y) / aimbot.smooth + 0.5)
			if dx ~= 0 or dy ~= 0 then
				task.spawn(mousemoverel, dx, dy)
			end
		end
	end

	RunSvc.RenderStepped:Connect(function()
		if not aimbot.on then
			if aimbot.circle then
				aimbot.circle.Visible = false
			end
			return
		end
		pcall(aimTick)
	end)

	

	RunSvc.Heartbeat:Connect(function()
		pcall(function()
			if fly.on and fly.parts and fly.parts.vel and fly.parts.vel.Parent then
				local cam = WorkSvc.CurrentCamera
				if cam then
					local cf = cam.CFrame
					local dir = Vector3.zero
					if fly.keys.W then dir += cf.LookVector end
					if fly.keys.S then dir -= cf.LookVector end
					if fly.keys.D then dir += cf.RightVector end
					if fly.keys.A then dir -= cf.RightVector end
					if fly.keys.Space or fly.keys.E then dir += Vector3.yAxis end
					if fly.keys.LeftShift or fly.keys.Q then dir -= Vector3.yAxis end
					fly.parts.vel.Velocity = (dir.Magnitude > 0) and dir.Unit * fly.speed or Vector3.zero
					fly.parts.gyro.CFrame = cf
				end
			end
			local hum = humanoid()
			if hum then
				if speed.on and hum.WalkSpeed ~= speed.val then
					hum.WalkSpeed = speed.val
				end
				if jump.touched then
					if hum.JumpPower ~= jump.val then
						hum.JumpPower = jump.val
					end
					if not hum.UseJumpPower and hum.JumpHeight ~= jump.val / 7.2 then
						hum.JumpHeight = jump.val / 7.2
					end
				end
			end
			if fullbright.on then
				fullbright.tick += 1
				if fullbright.tick % 60 == 0 then
					fullbrightApply()
				end
			end
			if desync.on then
				local hrp = rootPart()
				if hrp then
					local ok, cf = pcall(function() return hrp.CFrame end)
					if ok then
						desync.realCF = cf
						desync.tick += 1
						local useFake = true
						if desync.mode == "Blink" then
							useFake = (desync.tick % desync.blinkDiv == 0)
						end
						if useFake then
							local fake = desync.fakeCF
							if desync.mode == "Blink" then
								fake = cf * CFrame.new(0, desync.offset, 0)
							end
							if fake then
								pcall(function() hrp.CFrame = fake end)
								desync.lastFake = fake
								desync.fakeSpot = fake
							end
						else
							desync.fakeSpot = cf
						end
						if ghost.on and ghost.model and ghost.hrp and desync.lastFake and desync.owner ~= "fakelag" then
							pcall(function() ghost.hrp.CFrame = desync.lastFake end)
						end
					end
				end
			end
			if fakelag.on and ghost.on and ghost.model and ghost.hrp then
				ghost.animT += 1
				if ghost.animT % 3 == 0 then
					pcall(ghostSync)
					pcall(ghostNoCollide)
				end
				if not fakelag.hold then
					local hrp = rootPart()
					if hrp then
						local ok, cf = pcall(function() return hrp.CFrame end)
						if desync.on and desync.realCF then
							cf = desync.realCF
						end
						if ok and cf then
local behind = cf * CFrame.new(0, 0, fakelag.trail)
							pcall(function() ghost.hrp.CFrame = behind end)
						end
					end
				end
			end
		end)
	end)

	RunSvc.Stepped:Connect(function()
		if not noclip.on then
			return
		end
		pcall(function()
			local _, ch = character()
			if not ch then
				return
			end
			for _, p in ch:GetDescendants() do
				if p:IsA("BasePart") then
					p.CanCollide = false
				end
			end
		end)
	end)

	task.spawn(function()
		while true do
			if fakelag.on then
				local hrp = rootPart()
				if hrp then
					if ghost.on and not ghost.model then
						ghostBuild()
					end
					local ok, cf = pcall(function() return hrp.CFrame end)
					if ok and cf then
						desync.fakeCF = cf
						desync.lastFake = cf
					end
					if ghost.on and ghost.model and ghost.hrp and cf then
						local behind = cf * CFrame.new(0, 0, fakelag.trail)
						pcall(function() ghost.hrp.CFrame = behind end)
					end
					fakelag.hold = true
					desyncPulse(true)
					local onMs = math.random(100, fakelag.limit)
					task.wait(onMs / 1000)
					if fakelag.on then
						fakelag.hold = false
						desyncPulse(false)
						local offMs = math.random(100, fakelag.limit)
						task.wait(offMs / 1000)
					end
				else
					task.wait(0.25)
				end
			else
				if desync.on and desync.owner == "fakelag" then
					desyncPulse(false)
				end
				if ghost.on and ghost.model and (desync.on or fakelag.on) == false then
					ghostDestroy()
				end
				local hrp = rootPart()
				if hrp then
					pcall(function() hrp.Anchored = false end)
				end
				task.wait(0.25)
			end
		end
	end)

	RunSvc.RenderStepped:Connect(function()
		if not esp.on then
			return
		end
		pcall(espTick)
	end)

	

	

	

	

	

	

	RunSvc.RenderStepped:Connect(function()
		if not desync.on then
			return
		end
		pcall(function()
			local hrp = rootPart()
			if hrp and desync.realCF then
				hrp.CFrame = desync.realCF
			end
			local cam = WorkSvc.CurrentCamera
			if cam and desync.realCF and desync.fakeSpot then
				local d = desync.realCF.Position - desync.fakeSpot.Position
				if d.Magnitude > 0.05 then
					cam.CFrame = cam.CFrame + d
					cam.Focus = cam.Focus + d
				end
			end
		end)
	end)

	InputSvc.JumpRequest:Connect(function()
		if infjump.on then
			local hum = humanoid()
			if hum then
				pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
			end
		end
	end)

	pcall(function()
		local lp = localPlayer()
		if lp then
			lp.Idled:Connect(function()
				if antiafk.on then
					pcall(function() game_o:GetService("VirtualUser"):ClickButton2(Vector2.new(0, 0)) end)
				end
			end)
			lp.CharacterAdded:Connect(function()
				if fly.on then
					task.wait(0.5)
					if fly.on then
						flyApply(true)
					end
				end
				if (desync.on or fakelag.on) and ghost.on then
					task.wait(0.5)
					if (desync.on or fakelag.on) and ghost.on then
						ghostBuild()
					end
				end
				if desync.on or fakelag.on then
					task.wait(0.5)
					if desync.on or fakelag.on then
						desyncTouch(true)
					end
				end
			end)
		end
	end)

	

	local host = gethui()
	if not host then
		return nil
	end

	local topbar = Instance.new("CanvasGroup")
	topbar.Name = "SpeedTopbar"
	topbar.Size = UDim2.new(0, 264, 0, 30)
	topbar.AnchorPoint = Vector2.new(1, 0)
	topbar.Position = UDim2.new(1, -8, 0, 8)
	topbar.BackgroundColor3 = Color3.fromRGB(16, 18, 22)
	topbar.BackgroundTransparency = 0.18
	topbar.BorderSizePixel = 0
	topbar.Parent = host

	local topCorner = Instance.new("UICorner")
	topCorner.CornerRadius = UDim.new(0, 9)
	topCorner.Parent = topbar

	local topStroke = Instance.new("UIStroke")
	topStroke.Color = Color3.fromRGB(80, 120, 200)
	topStroke.Thickness = 1
	topStroke.Transparency = 0.75
	topStroke.Parent = topbar

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0, 150, 1, 0)
	nameLabel.Position = UDim2.new(0, 12, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = "SpeedInternal"
	nameLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
	nameLabel.TextSize = 13
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = topbar

	local statusDot = Instance.new("Frame")
	statusDot.Size = UDim2.new(0, 8, 0, 8)
	statusDot.Position = UDim2.new(1, -112, 0.5, -4)
	statusDot.BackgroundColor3 = Color3.fromRGB(50, 255, 100)
	statusDot.BorderSizePixel = 0
	statusDot.Parent = topbar

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = statusDot

	local dotGlow = Instance.new("UIStroke")
	dotGlow.Color = Color3.fromRGB(50, 255, 100)
	dotGlow.Thickness = 2
	dotGlow.Transparency = 0.4
	dotGlow.Parent = statusDot

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(0, 96, 1, 0)
	statusLabel.Position = UDim2.new(1, -100, 0, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.Text = "Injected"
	statusLabel.TextColor3 = Color3.fromRGB(170, 175, 182)
	statusLabel.TextSize = 12
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Parent = topbar

	local dotPulse = Instance.new("Frame")
	dotPulse.Size = UDim2.new(0, 14, 0, 14)
	dotPulse.Position = UDim2.new(1, -115, 0.5, -7)
	dotPulse.BackgroundColor3 = Color3.fromRGB(50, 255, 100)
	dotPulse.BorderSizePixel = 0
	dotPulse.Parent = topbar
	local pulseCorner = Instance.new("UICorner")
	pulseCorner.CornerRadius = UDim.new(1, 0)
	pulseCorner.Parent = dotPulse

	task.spawn(function()
		while topbar.Parent do
			local pTween = notify_Tween:Create(dotPulse, TweenInfo.new(0.9, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.new(0, 20, 0, 20), Position = UDim2.new(1, -118, 0.5, -10), BackgroundTransparency = 1 })
			pTween:Play()
			pTween.Completed:Wait()
			local sTween = notify_Tween:Create(statusDot, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = 0.35 })
			sTween:Play()
			sTween.Completed:Wait()
			if not topbar.Parent then
				break
			end
			local p2 = notify_Tween:Create(dotPulse, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(1, -115, 0.5, -7), BackgroundTransparency = 0.6 })
			p2:Play()
			p2.Completed:Wait()
			local s2 = notify_Tween:Create(statusDot, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = 0 })
			s2:Play()
			s2.Completed:Wait()
		end
	end)

	local window = Instance.new("CanvasGroup")
	window.Name = "SpeedWindow"
	window.Size = UDim2.new(0, 500, 0, 464)
	window.Position = UDim2.new(1, -16, 0.5, 0)
	window.AnchorPoint = Vector2.new(1, 0.5)
	window.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
	window.BorderSizePixel = 0
	window.GroupTransparency = 1
	window.Visible = false
	window.Parent = host

	local winCorner = Instance.new("UICorner")
	winCorner.CornerRadius = UDim.new(0, 8)
	winCorner.Parent = window

	local title = Instance.new("TextLabel")
	title.Name = "TitleBar"
	title.Size = UDim2.new(1, 0, 0, 34)
	title.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
	title.BorderSizePixel = 0
	title.Font = Enum.Font.GothamBold
	title.Text = "   SpeedInternal"
	title.TextColor3 = Color3.fromRGB(245, 245, 245)
	title.TextSize = 14
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = window

	local titleHint = Instance.new("TextLabel")
	titleHint.Size = UDim2.new(0, 120, 0, 34)
	titleHint.Position = UDim2.new(1, -128, 0, 0)
	titleHint.BackgroundTransparency = 1
	titleHint.Font = Enum.Font.Gotham
	titleHint.Text = "F8 to hide"
	titleHint.TextColor3 = Color3.fromRGB(120, 125, 132)
	titleHint.TextSize = 11
	titleHint.TextXAlignment = Enum.TextXAlignment.Right
	titleHint.Parent = window

	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.Size = UDim2.new(1, -16, 0, 38)
	tabBar.Position = UDim2.new(0, 8, 0, 40)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = window

	local pages = {}
	local tabBtns = {}
	local tabCount = 0
	local showPage
	local function addTab(name)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, 96, 0, 30)
		b.Position = UDim2.new(0, 2 + (tabCount % 5) * 98, 0, 4)
		tabCount += 1
		b.Font = Enum.Font.GothamBold
		b.Text = "  " .. name
		b.TextSize = 13
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.AutoButtonColor = false
		b.BorderSizePixel = 0
		b.Parent = tabBar
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = b
		local page = Instance.new("CanvasGroup")
		page.Name = name .. "Page"
		page.Size = UDim2.new(1, -24, 1, -92)
		page.Position = UDim2.new(0, 12, 0, 80)
		page.BackgroundTransparency = 1
		page.GroupTransparency = 1
		page.Visible = false
		page.Parent = window
		pages[name] = page
		tabBtns[name] = b
		b.MouseButton1Click:Connect(function() showPage(name) end)
		return page
	end
	function showPage(name)
		for n, pg in pairs(pages) do
			local b = tabBtns[n]
			if n == name then
				pg.Visible = true
				pg.GroupTransparency = 1
				pg.Position = UDim2.new(0, 12, 0, 86)
				notify_Tween:Create(pg, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { GroupTransparency = 0, Position = UDim2.new(0, 12, 0, 80) }):Play()
				if b then
					b.BackgroundColor3 = Color3.fromRGB(48, 51, 58)
					b.TextColor3 = Color3.fromRGB(255, 255, 255)
				end
			else
				pg.Visible = false
				if b then
					b.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
					b.TextColor3 = Color3.fromRGB(140, 150, 160)
				end
			end
		end
	end

	local movementPage = addTab("Movement")
	local worldPage = addTab("World")
	local combatPage = addTab("Combat")
	local uiPage = addTab("UI")
	local mm2Page = addTab("MM2")
	local yM, yW, yC, yU, yB = 0, 0, 0, 0, 0
	local TOGGLE_H, SLIDER_H = 52, 68

	

	local mm2 = {
		esp = false, mode = false, gunGrab = false, killAura = false, killRange = 15,
		coinFarm = false, autoFarm = false, coins = 0,
		adornments = {}, roles = {}, murderName = nil, sheriffName = nil, heroName = nil,
		knifeCool = false, gunCool = false, init = false, charConns = {},
	}
	local MM2_ROLE_COLORS = {
		Murderer = Color3.fromRGB(225, 0, 0),
		Sheriff = Color3.fromRGB(0, 0, 225),
		Hero = Color3.fromRGB(255, 250, 0),
		Innocent = Color3.fromRGB(0, 225, 0),
	}
	local mm2DefaultColor = Color3.fromRGB(0, 255, 128)
	local mm2BoxSize = Vector3.new(4, 5, 2)

	local function mm2ClearESP(plr)
		if mm2.adornments[plr] then
			for _, ad in pairs(mm2.adornments[plr]) do
				pcall(function()
					if typeof(ad) == "Instance" then
						ad:Destroy()
					elseif typeof(ad) == "RBXScriptConnection" then
						ad:Disconnect()
					end
				end)
			end
			mm2.adornments[plr] = nil
		end
	end

	local function mm2Alive(name)
		local v = mm2.roles[name]
		if not v then
			return false
		end
		return not v.Killed and not v.Dead
	end

	local function mm2RoleColor(name)
		if not mm2.mode then
			return mm2DefaultColor
		end
		if name == mm2.murderName and mm2Alive(name) then
			return MM2_ROLE_COLORS.Murderer
		elseif name == mm2.sheriffName and mm2Alive(name) then
			return MM2_ROLE_COLORS.Sheriff
		elseif name == mm2.heroName and mm2Alive(name) and not mm2Alive(mm2.sheriffName) then
			return MM2_ROLE_COLORS.Hero
		end
		return MM2_ROLE_COLORS.Innocent
	end

	local function mm2ESPFor(plr)
		local onChar
		onChar = function(char)
			mm2ClearESP(plr)
			local hrp = char:WaitForChild("HumanoidRootPart", 5)
			local hum = char:WaitForChild("Humanoid", 5)
			if not hrp or not hum then
				return
			end
			local box = Instance.new("BoxHandleAdornment")
			box.Name = "MM2_ESP_" .. plr.Name
			box.Adornee = hrp
			box.AlwaysOnTop = true
			box.ZIndex = 10
			box.Size = mm2BoxSize
			box.Color3 = mm2RoleColor(plr.Name)
			box.Transparency = 0.2
			box.Parent = WorkSvc
			local entry = { box }
			mm2.adornments[plr] = entry
			local conn
			conn = RunSvc.RenderStepped:Connect(function()
				if not mm2.esp or not char or not char.Parent or not hum or hum.Health <= 0 then
					mm2ClearESP(plr)
					pcall(function() conn:Disconnect() end)
					return
				end
				pcall(function() box.Color3 = mm2RoleColor(plr.Name) end)
			end)
			table.insert(entry, conn)
		end
		if plr.Character then
			onChar(plr.Character)
		end
		plr.CharacterAdded:Connect(onChar)
	end

	local function mm2InitESP()
		if mm2.init then
			return
		end
		mm2.init = true
		local ok, players = pcall(function() return PlayersSvc:GetPlayers() end)
		if ok and type(players) == "table" then
			for _, plr in players do
				if plr ~= localPlayer() then
					mm2ESPFor(plr)
				end
			end
		end
		PlayersSvc.PlayerAdded:Connect(function(plr)
			if plr ~= localPlayer() and mm2.esp then
				mm2ESPFor(plr)
			end
		end)
		PlayersSvc.PlayerRemoving:Connect(mm2ClearESP)
	end

	local function mm2SafeTeleport(cf)
		local hrp = rootPart()
		if hrp then
			pcall(function() hrp.CFrame = cf end)
		end
	end

	local function mm2GetGunDrop()
		local gunDrop = WorkSvc:FindFirstChild("GunDrop")
		if not gunDrop then
			local ok, found = pcall(function()
				for _, child in WorkSvc:GetChildren() do
					local g = child:FindFirstChild("GunDrop")
					if child.Name == "GunDrop" or g then
						return g or child
					end
				end
				return nil
			end)
			gunDrop = ok and found or nil
		end
		return gunDrop
	end

	local function mm2TryGrabGun()
		if not mm2.gunGrab then
			return
		end
		local _, ch = character()
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end
		local _, lp = character()
		if lp then
			if (ch and ch:FindFirstChild("Gun")) or (lp.Backpack and lp.Backpack:FindFirstChild("Gun")) then
				return
			end
		end
		if mm2.mode then
			local myName = localPlayer() and localPlayer().Name
			if myName == mm2.murderName or (myName == mm2.sheriffName and mm2Alive(myName)) then
				return
			end
		end
		local gunDrop = mm2GetGunDrop()
		if not gunDrop then
			return
		end
		if not gunDrop:IsA("BasePart") then
			gunDrop = gunDrop:FindFirstChildWhichIsA("BasePart")
			if not gunDrop then
				return
			end
		end
		local orig = hrp.CFrame
		mm2SafeTeleport(gunDrop.CFrame + Vector3.new(0, 3, 0))
		task.wait(0.15)
		mm2SafeTeleport(orig)
	end

	RunSvc.RenderStepped:Connect(function()
		if mm2.gunGrab then
			mm2TryGrabGun()
		end
	end)
	WorkSvc.ChildAdded:Connect(function(child)
		if mm2.gunGrab and (child.Name == "GunDrop" or child:FindFirstChild("GunDrop")) then
			task.wait(0.1)
			mm2TryGrabGun()
		end
	end)

	local function mm2KillAuraTick()
		if not mm2.killAura then
			return
		end
		local _, ch = character()
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end
		local knife = ch and ch:FindFirstChild("Knife")
		local gun = ch and ch:FindFirstChild("Gun")
		local _, lp = character()
		if lp and lp.Backpack then
			if not knife then knife = lp.Backpack:FindFirstChild("Knife") end
			if not gun then gun = lp.Backpack:FindFirstChild("Gun") end
		end

		local function equip(tool)
			if tool and tool.Parent == lp and lp.Backpack then
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				if hum then
					pcall(function() hum:EquipTool(tool) end)
				end
			end
		end

		if knife and not mm2.knifeCool then
			mm2.knifeCool = true
			task.spawn(function()
				equip(knife)
				RunSvc.RenderStepped:Wait()
				local target, dist = nil, math.huge
				local ok, players = pcall(function() return PlayersSvc:GetPlayers() end)
				if ok and type(players) == "table" then
					for _, plr in players do
						if plr ~= localPlayer() and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
							local d = (hrp.Position - plr.Character.HumanoidRootPart.Position).Magnitude
							if d < dist then
								dist = d
								target = plr
							end
						end
					end
				end
				if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
					local thrp = target.Character.HumanoidRootPart
					local orig = hrp.CFrame
					hrp.CFrame = CFrame.lookAt(thrp.Position + thrp.CFrame.LookVector * 2, thrp.Position)
					task.wait(0.05)
					pcall(function() if knife.Parent then knife:Activate() end end)
					task.wait(0.05)
					hrp.CFrame = orig
				end
				task.wait(0.35)
				mm2.knifeCool = false
			end)
		end

		if gun and mm2.mode and mm2.murderName and not mm2.gunCool then
			mm2.gunCool = true
			task.spawn(function()
				equip(gun)
				RunSvc.RenderStepped:Wait()
				local mur = PlayersSvc:FindFirstChild(mm2.murderName)
				if mur and mur.Character and mur.Character:FindFirstChild("HumanoidRootPart") then
					local thrp = mur.Character.HumanoidRootPart
					local orig = hrp.CFrame
					hrp.CFrame = CFrame.lookAt(thrp.Position + thrp.CFrame.LookVector * 2, thrp.Position)
					task.wait(0.05)
					pcall(function() if gun.Parent then gun:Activate() end end)
					task.wait(0.05)
					hrp.CFrame = orig
				end
				task.wait(0.5)
				mm2.gunCool = false
			end)
		end
	end
	RunSvc.RenderStepped:Connect(mm2KillAuraTick)

	local function mm2CoinFarmTick()
		if not mm2.coinFarm then
			return
		end
		local hrp = rootPart()
		if not hrp then
			return
		end
		local coinContainer
		local ok, found = pcall(function()
			return WorkSvc:FindFirstChild("CoinContainer", true)
		end)
		coinContainer = ok and found or nil
		if not coinContainer then
			return
		end
		local ok2, coins = pcall(function() return coinContainer:GetChildren() end)
		if not ok2 or type(coins) ~= "table" or #coins == 0 then
			return
		end
		local coin = coins[1]
		local targetPart = coin:IsA("BasePart") and coin or coin:FindFirstChild("Coin")
		if not targetPart or not targetPart.Parent then
			return
		end
		if (hrp.Position - targetPart.Position).Magnitude > 4 then
			pcall(function()
				local dist = (hrp.Position - targetPart.Position).Magnitude
				local info = TweenInfo.new(math.clamp(dist / 40, 0.01, 1.5), Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
				local tw = notify_Tween:Create(hrp, info, { CFrame = targetPart.CFrame + Vector3.new(0, 2, 0) })
				tw:Play()
				tw.Completed:Connect(function()
					mm2.coins = mm2.coins + 1
				end)
			end)
		end
	end
	RunSvc.RenderStepped:Connect(mm2CoinFarmTick)

	RunSvc.RenderStepped:Connect(function()
		if not mm2.autoFarm then
			return
		end
		local myName = localPlayer() and localPlayer().Name
		local role = mm2.roles[myName] and mm2.roles[myName].Role
		if role == "Murderer" or role == "Sheriff" or role == "Hero" then
			mm2.killAura = true
			mm2.coinFarm = false
		else
			mm2.killAura = false
			mm2.coinFarm = true
		end
	end)

	local function mm2RoleTick()
		if not mm2.mode then
			return
		end
		local ok, gp = pcall(function() return ReplicatedStorage:FindFirstChild("GetPlayerData", true) end)
		if not ok or not gp then
			return
		end
		local ok2, res = pcall(function() return gp:InvokeServer() end)
		if ok2 and type(res) == "table" then
			mm2.roles = res
			mm2.murderName, mm2.sheriffName, mm2.heroName = nil, nil, nil
			for i, v in pairs(res) do
				local r = v and v.Role
				if r == "Murderer" then
					mm2.murderName = i
				elseif r == "Sheriff" then
					mm2.sheriffName = i
				elseif r == "Hero" then
					mm2.heroName = i
				end
			end
		end
	end
	task.spawn(function()
		while true do
			task.wait(0.5)
			pcall(mm2RoleTick)
		end
	end)

	


	local function paintSwitch(track, knob, state, animate)
		local trackC = state and Color3.fromRGB(235, 235, 235) or Color3.fromRGB(58, 61, 68)
		local knobC = state and Color3.fromRGB(25, 27, 31) or Color3.fromRGB(120, 124, 130)
		local knobX = state and 23 or 3
		if animate then
			local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			notify_Tween:Create(track, info, { BackgroundColor3 = trackC }):Play()
			notify_Tween:Create(knob, info, { BackgroundColor3 = knobC, Position = UDim2.new(0, knobX, 0, 3) }):Play()
		else
			track.BackgroundColor3 = trackC
			knob.BackgroundColor3 = knobC
			knob.Position = UDim2.new(0, knobX, 0, 3)
		end
	end

	local function makeToggle(page, y, label, desc, initial, onChange, ref)
		local state = initial
		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -64, 0, 17)
		title.Position = UDim2.new(0, 0, 0, y)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBold
		title.Text = label
		title.TextColor3 = Color3.fromRGB(235, 235, 235)
		title.TextSize = 13
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Parent = page
		local sub = Instance.new("TextLabel")
		sub.Size = UDim2.new(1, -64, 0, 26)
		sub.Position = UDim2.new(0, 0, 0, y + 18)
		sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.Gotham
		sub.Text = desc
		sub.TextColor3 = Color3.fromRGB(130, 135, 142)
		sub.TextSize = 11
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.TextYAlignment = Enum.TextYAlignment.Top
		sub.TextWrapped = true
		sub.Parent = page
		local track = Instance.new("TextButton")
		track.Text = ""
		track.AutoButtonColor = false
		track.Size = UDim2.new(0, 44, 0, 24)
		track.Position = UDim2.new(1, -48, 0, y + 10)
		track.BorderSizePixel = 0
		track.Parent = page
		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(0, 12)
		trackCorner.Parent = track
		local knob = Instance.new("Frame")
		knob.Size = UDim2.new(0, 18, 0, 18)
		knob.BorderSizePixel = 0
		knob.Parent = track
		local knobCorner = Instance.new("UICorner")
		knobCorner.CornerRadius = UDim.new(1, 0)
		knobCorner.Parent = knob
		paintSwitch(track, knob, state, false)
		if ref then
			ref.set = function(s)
				state = s
				paintSwitch(track, knob, state, true)
			end
		end
		track.MouseButton1Click:Connect(function()
			state = not state
			paintSwitch(track, knob, state, true)
			pcall(onChange, state)
			pcall(notify, "SpeedInternal", label .. (state and " enabled" or " disabled"), state and "success" or "info", 2)
		end)
		return track
	end

	local function makeSlider(page, y, label, desc, minV, maxV, val, onChange)
		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -70, 0, 17)
		title.Position = UDim2.new(0, 0, 0, y)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBold
		title.Text = label
		title.TextColor3 = Color3.fromRGB(235, 235, 235)
		title.TextSize = 13
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Parent = page
		local box = Instance.new("TextBox")
		box.Size = UDim2.new(0, 56, 0, 22)
		box.Position = UDim2.new(1, -60, 0, y - 2)
		box.BackgroundColor3 = Color3.fromRGB(13, 15, 18)
		box.BorderSizePixel = 0
		box.Font = Enum.Font.Gotham
		box.TextColor3 = Color3.fromRGB(235, 235, 235)
		box.TextSize = 12
		box.ClearTextOnFocus = false
		box.Parent = page
		local boxCorner = Instance.new("UICorner")
		boxCorner.CornerRadius = UDim.new(0, 4)
		boxCorner.Parent = box
		local sub = Instance.new("TextLabel")
		sub.Size = UDim2.new(1, 0, 0, 24)
		sub.Position = UDim2.new(0, 0, 0, y + 18)
		sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.Gotham
		sub.Text = desc
		sub.TextColor3 = Color3.fromRGB(130, 135, 142)
		sub.TextSize = 11
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.TextYAlignment = Enum.TextYAlignment.Top
		sub.TextWrapped = true
		sub.Parent = page
		local bar = Instance.new("TextButton")
		bar.Text = ""
		bar.AutoButtonColor = false
		bar.Size = UDim2.new(1, 0, 0, 10)
		bar.Position = UDim2.new(0, 0, 0, y + 48)
		bar.BackgroundColor3 = Color3.fromRGB(50, 54, 60)
		bar.BorderSizePixel = 0
		bar.Parent = page
		local barCorner = Instance.new("UICorner")
		barCorner.CornerRadius = UDim.new(0, 5)
		barCorner.Parent = bar
		local fill = Instance.new("Frame")
		fill.BorderSizePixel = 0
		fill.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
		fill.Parent = bar
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 5)
		fillCorner.Parent = fill
		local dragging = false
		local function set(v, fire)
			v = math.clamp(math.floor(v + 0.5), minV, maxV)
			val = v
			box.Text = tostring(v)
			fill.Size = UDim2.new((v - minV) / (maxV - minV), 0, 1, 0)
			if fire ~= false then
				pcall(onChange, v)
			end
		end
		set(val, false)
		box.FocusLost:Connect(function(enter)
			if enter then
				local n = tonumber(box.Text)
				if n then
					set(n, true)
				else
					box.Text = tostring(val)
				end
			else
				box.Text = tostring(val)
			end
		end)
		local function applyFromX(xAbs)
			local rel = 0
			pcall(function()
				rel = math.clamp((xAbs - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
			end)
			set(minV + (maxV - minV) * rel, true)
		end
		bar.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true
				applyFromX(i.Position.X)
			end
		end)
		InputSvc.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = false
			end
		end)
		InputSvc.InputChanged:Connect(function(i)
			if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
				applyFromX(i.Position.X)
			end
		end)
		return bar
	end

	makeToggle(movementPage, yM, "Fly", "Fly with WASD + Space / Shift.", false, function(s) flyApply(s) end)
	yM += TOGGLE_H
	makeSlider(movementPage, yM, "Fly Speed", "Flight speed in studs per second.", 16, 200, fly.speed, function(v) fly.speed = v end)
	yM += SLIDER_H
	makeToggle(movementPage, yM, "Speed", "Enforce a custom WalkSpeed.", false, function(s) speed.on = s end)
	yM += TOGGLE_H
	makeSlider(movementPage, yM, "Walk Speed", "WalkSpeed applied while enabled.", 16, 300, speed.val, function(v) speed.val = v end)
	yM += SLIDER_H
	makeSlider(movementPage, yM, "Jump Power", "Jump power applied to Humanoid.", 0, 250, jump.val, function(v) jump.val = v jump.touched = true end)
	yM += SLIDER_H
	makeToggle(movementPage, yM, "Infinite Jump", "Jump again while airborne.", false, function(s) infjump.on = s end)
	yM += TOGGLE_H
	makeToggle(movementPage, yM, "Noclip", "Pass through walls and parts.", false, function(s)
		noclip.on = s
		if not s then
			pcall(function()
				local _, ch = character()
				if ch then
					for _, p in ch:GetDescendants() do
						if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
							p.CanCollide = true
						end
					end
				end
			end)
		end
	end)
	yM += TOGGLE_H

	makeToggle(worldPage, yW, "ESP", "Names and distance over players.", false, function(s)
		esp.on = s
		if not s then
			espClear()
		end
	end)
	yW += TOGGLE_H
	makeToggle(worldPage, yW, "Fullbright", "Force bright lighting.", false, function(s)
		fullbright.on = s
		if s then
			fullbright.saved = fullbrightSave()
			fullbrightApply()
		else
			fullbrightRestore()
		end
	end)
	yW += TOGGLE_H
	makeToggle(worldPage, yW, "Click TP", "Hold Ctrl and click to teleport.", false, function(s) clicktp.on = s end)
	yW += TOGGLE_H
	makeToggle(worldPage, yW, "Anti AFK", "Block idle kicks.", false, function(s) antiafk.on = s end)
	yW += TOGGLE_H
	makeToggle(worldPage, yW, "Fake Lag", "Desync lag with a trailing ghost and path line.", false, function(s)
		fakelag.on = s
		if s then
			if desync.on then
				desyncSet(false, true, true)
			end
			if ghost.on then
				ghostBuild()
			end
		else
			if desync.on then
				desyncPulse(false)
			end
			local hrp = rootPart()
			if hrp then
				pcall(function() hrp.Anchored = false end)
			end
			ghostDestroy()
		end
	end, fakelagUI)
	yW += TOGGLE_H
	makeSlider(worldPage, yW, "Fake Lag Delay", "Max random ms per desync pulse (cap 1000).", 100, 1000, fakelag.limit, function(v) fakelag.limit = v end)
	yW += SLIDER_H
	makeSlider(worldPage, yW, "Ghost Trail", "Studs the ghost trails behind you.", 1, 30, fakelag.trail, function(v) fakelag.trail = v end)
	yW += SLIDER_H
	makeToggle(worldPage, yW, "Desync", "Broadcast a fake position (Z).", false, function(s) desyncSet(s) end, desyncUI)
	yW += TOGGLE_H
	makeToggle(worldPage, yW, "Invisible Mode", "OFF frozen ghost, ON flicker.", false, function(s)
		desync.mode = s and "Blink" or "Ghost"
		if not s then
			local hrp = rootPart()
			if hrp then
				local ok, cf = pcall(function() return hrp.CFrame end)
				if ok then
					desync.fakeCF = cf
				end
			end
		end
	end)
	yW += TOGGLE_H
	makeSlider(worldPage, yW, "Desync Offset", "Blink fake-spot height.", 50, 1000, desync.offset, function(v) desync.offset = v end)
	yW += SLIDER_H
	makeSlider(worldPage, yW, "Ghost Distance", "0 frozen where stood, higher unreachable.", 0, 1000, desync.ghostDist, function(v)
		desync.ghostDist = v
		if desync.on and desync.mode == "Ghost" then
			local hrp = rootPart()
			if hrp then
				local ok, cf = pcall(function() return hrp.CFrame end)
				if ok and cf then
					if v > 0 then
						cf = cf * CFrame.new(0, v, 0)
					end
					desync.fakeCF = cf
				end
			end
		end
	end)
	yW += SLIDER_H
	makeToggle(worldPage, yW, "Ghost Clone", "Translucent double at the fake spot.", true, function(s)
		ghost.on = s
		if s then
			if desync.on then
				ghostBuild()
			end
		else
			ghostDestroy()
		end
	end)
	yW += TOGGLE_H

	makeToggle(combatPage, yC, "Aimbot", "Hold Left Alt to aim at heads.", false, function(s)
		aimbot.on = s
		if not s then
			aimbot.aiming = false
			if aimbot.circle then
				aimbot.circle.Visible = false
			end
		end
	end)
	yC += TOGGLE_H
	makeToggle(combatPage, yC, "Camera Mode", "ON locks the camera, OFF moves the mouse.", false, function(s) aimbot.cameraMode = s end)
	yC += TOGGLE_H
	makeSlider(combatPage, yC, "FOV", "Target lock radius in pixels.", 40, 400, aimbot.fov, function(v) aimbot.fov = v end)
	yC += SLIDER_H
	makeSlider(combatPage, yC, "Smoothing", "Higher is slower and smoother (mouse mode).", 1, 20, aimbot.smooth, function(v) aimbot.smooth = v end)
	yC += SLIDER_H
	makeToggle(combatPage, yC, "Show FOV", "Draw the aim circle.", true, function(s) aimbot.showFov = s end)
	yC += TOGGLE_H
	makeToggle(combatPage, yC, "Team Check", "Skip teammates.", true, function(s) aimbot.teamCheck = s end)
	yC += TOGGLE_H
	makeToggle(combatPage, yC, "Visible Check", "Only lock visible targets.", true, function(s) aimbot.visCheck = s end)
	yC += TOGGLE_H
	makeToggle(combatPage, yC, "Target NPCs", "Also lock non-player models.", false, function(s) aimbot.npcs = s end)
	yC += TOGGLE_H

	makeToggle(uiPage, yU, "Status Bar", "Top bar with name and status.", true, function(s)
		if topbar then
			topbar.Visible = s
		end
	end)
	yU += TOGGLE_H
	makeToggle(uiPage, yU, "Notifications", "Slide-in toast popups.", true, function(s)
		NotificationsEnabled = s
	end)
	yU += TOGGLE_H

	makeToggle(mm2Page, yB, "MM2 Mode", "Role detection from GetPlayerData.", false, function(s)
		mm2.mode = s
		if not s then
			mm2.roles = {}
			mm2.murderName, mm2.sheriffName, mm2.heroName = nil, nil, nil
		end
	end)
	yB += TOGGLE_H
	makeToggle(mm2Page, yB, "3D Box ESP", "Role-colored boxes over players.", false, function(s)
		mm2.esp = s
		if s then
			mm2InitESP()
		else
			local ok, players = pcall(function() return PlayersSvc:GetPlayers() end)
			if ok and type(players) == "table" then
				for _, plr in players do
					mm2ClearESP(plr)
				end
			end
		end
	end)
	yB += TOGGLE_H
	makeToggle(mm2Page, yB, "Auto Gun Grab", "Teleport to the dropped gun.", false, function(s) mm2.gunGrab = s end)
	yB += TOGGLE_H
	makeToggle(mm2Page, yB, "Kill Aura", "Strike or shoot the murderer.", false, function(s) mm2.killAura = s end)
	yB += TOGGLE_H
	makeToggle(mm2Page, yB, "Coin Farm", "Tween onto coins as they land.", false, function(s) mm2.coinFarm = s end)
	yB += TOGGLE_H
	makeToggle(mm2Page, yB, "Auto Farm", "Role-based: fight or coin farm.", false, function(s)
		mm2.autoFarm = s
		if not s then
			mm2.killAura = false
			mm2.coinFarm = false
		end
	end)
	yB += TOGGLE_H
	local mm2CoinsLabel = Instance.new("TextLabel")
	mm2CoinsLabel.Size = UDim2.new(1, -40, 0, 18)
	mm2CoinsLabel.Position = UDim2.new(0, 0, 0, yB)
	mm2CoinsLabel.BackgroundTransparency = 1
	mm2CoinsLabel.Font = Enum.Font.Gotham
	mm2CoinsLabel.Text = "Coins farmed: 0"
	mm2CoinsLabel.TextColor3 = Color3.fromRGB(130, 135, 142)
	mm2CoinsLabel.TextSize = 12
	mm2CoinsLabel.TextXAlignment = Enum.TextXAlignment.Left
	mm2CoinsLabel.Parent = mm2Page
	task.spawn(function()
		local last = -1
		while mm2CoinsLabel.Parent do
			task.wait(0.5)
			if mm2.coins ~= last then
				last = mm2.coins
				pcall(function() mm2CoinsLabel.Text = "Coins farmed: " .. tostring(mm2.coins) end)
			end
		end
	end)
	yB += 22

	showPage("Movement")
	window.Size = UDim2.new(0, 500, 0, math.max(yM, yW, yC, yU, yB) + 92)

	local windowBase = window.Position
	local windowOpen = false

	

	local blur = nil
	local snowEm = nil
	local prevMouse
	pcall(function()
		blur = Instance.new("BlurEffect")
		blur.Name = "SpeedBlur"
		blur.Size = 0
		blur.Parent = LightSvc
	end)
	

	pcall(function()
		local snowPart = Instance.new("Part")
		snowPart.Name = "SpeedSnow"
		snowPart.Anchored = true
		snowPart.Transparency = 1
		snowPart.CanCollide = false
		snowPart.CanQuery = false
		snowPart.CanTouch = false
		snowPart.Size = Vector3.new(20, 20, 40)
		snowPart.Visible = false
		snowPart.Parent = WorkSvc
		local snowAtt = Instance.new("Attachment")
		snowAtt.Parent = snowPart
		snowEm = Instance.new("ParticleEmitter")
		snowEm.Name = "SnowEmitter"
		snowEm.Enabled = false
		snowEm.Lifetime = NumberRange.new(4, 8)
		snowEm.Rate = 120
		snowEm.Speed = NumberRange.new(1, 3)
		snowEm.SpreadAngle = Vector2.new(180, 180)
		snowEm.EmissionDirection = Enum.NormalId.Top
		snowEm.Acceleration = Vector3.new(0, -2, 0)
		snowEm.Drag = 0.4
		snowEm.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0),
			NumberSequenceKeypoint.new(0.8, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		snowEm.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.5, 0.6),
			NumberSequenceKeypoint.new(1, 0.4),
		})
		pcall(function()
			snowEm.Texture = "rbxasset://textures/particles/snow_1.png"
		end)
		snowEm.LightInfluence = 0
		snowEm.Parent = snowAtt
		RunSvc.RenderStepped:Connect(function()
			if not windowOpen then
				return
			end
			local cam = WorkSvc.CurrentCamera
			if cam then
				local cf = cam.CFrame
				snowPart.CFrame = cf * CFrame.new(0, 12, -20)
			end
		end)
	end)

	local function setWindow(open)
		windowOpen = open
		if open then
			window.Visible = true
			window.GroupTransparency = 1
			window.Size = window.Size - UDim2.new(0, 24, 0, 24)
			window.Position = windowBase + UDim2.new(0, 12, 0, 12)
			local info = TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
			local info2 = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			notify_Tween:Create(window, info2, { GroupTransparency = 0, Position = windowBase }):Play()
			notify_Tween:Create(window, info, { Size = UDim2.new(0, 500, 0, math.max(yM, yW, yC, yU, yB) + 92) }):Play()
			

			prevMouse = prevMouse or InputSvc.MouseBehavior
			pcall(function()
				InputSvc.MouseBehavior = Enum.MouseBehavior.Default
				InputSvc.MouseIconEnabled = true
			end)
			pcall(function() snowEm.Enabled = true end)
			pcall(function()
				notify_Tween:Create(blur, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = 4 }):Play()
			end)
		else
			local tw = notify_Tween:Create(window, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { GroupTransparency = 1, Position = windowBase + UDim2.new(0, 0, 0, 16) })
			tw:Play()
			tw.Completed:Connect(function()
				if not windowOpen then
					window.Visible = false
				end
			end)
			pcall(function()
				if prevMouse then
					InputSvc.MouseBehavior = prevMouse
				end
			end)
			pcall(function() snowEm.Enabled = false end)
			pcall(function()
				notify_Tween:Create(blur, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = 0 }):Play()
			end)
		end
	end
	internalSetWindow = setWindow

	

	local draggingWin, dragStart, startPos = false, nil, nil
	title.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			draggingWin = true
			dragStart = i.Position
			startPos = window.Position
		end
	end)
	InputSvc.InputChanged:Connect(function(i)
		if draggingWin and i.UserInputType == Enum.UserInputType.MouseMovement then
			local d = i.Position - dragStart
			window.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
	InputSvc.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			draggingWin = false
		end
	end)

	

	topbar.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			setWindow(not windowOpen)
		end
	end)

	

	InputSvc.InputBegan:Connect(function(input, gpe)
		if gpe then
			return
		end
		if input.KeyCode == Enum.KeyCode.F8 then
			setWindow(not windowOpen)
			return
		end
		if input.KeyCode == Enum.KeyCode.Z then
			desyncSet(not desync.on)
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftAlt then
			aimbot.aiming = true
		end
		local kn = input.KeyCode.Name
		if fly.keys[kn] ~= nil then
			fly.keys[kn] = true
		end
		if clicktp.on and input.UserInputType == Enum.UserInputType.MouseButton1 and InputSvc:IsKeyDown(Enum.KeyCode.LeftControl) then
			pcall(doClickTP)
		end
	end)
	InputSvc.InputEnded:Connect(function(input)
		local ok, kn = pcall(function() return input.KeyCode.Name end)
		if ok and fly.keys[kn] ~= nil then
			fly.keys[kn] = false
		end
		if input.KeyCode == Enum.KeyCode.LeftAlt then
			aimbot.aiming = false
		end
	end)

	internalWindowRef = window
	internalTopbarRef = topbar
	internalStatusRef = statusLabel
	return { window = window, topbar = topbar }
end

pcall(buildInternalUI)




flush_teleport_queue()



task.spawn(function()
	task.wait(1)
	pcall(notify, "SpeedInternal", "SpeedInternal is ready", "info", 4)
	task.wait(0.6)
	pcall(notify, "SpeedInternal", "Version: 1.0.1", "info", 4)
end)

task.spawn(function()
	while task.wait() do
		if upd.Value ~= lastValue then
			lastValue = upd.Value
			task.spawn(function()
				local t_exec_start = os.clock()
				local data = requestData()
				local t_exec_fetch = os.clock()
				if data then
					local ok, err = pcall(function()
						load_bytecode(data, getfenv())()
					end)
					local t_exec_done = os.clock()
					if not ok then
						pcall(function()
							writefile("exec_error.txt", table.concat({
								"== SpeedExecutor execution error ==",
								"time: " .. tostring(os.time()) .. " / " .. tostring(os.date("%Y-%m-%d %H:%M:%S")),
								"script: " .. tostring(script),
								"env script: " .. tostring(getfenv(0) and getfenv(0).script),
								"getexecutorname: " .. tostring(pcall(getexecutorname)),
								"error type: " .. type(err),
								"error: " .. tostring(err),
								"traceback: " .. tostring(pcall(function() return debug.traceback("", 1) end)),
								"",
							}, "\n"))
						end)
						warn('SpeedExecutor -- execution error: ' .. tostring(err))
						pcall(notify, "SpeedInternal", "Execution failed: " .. tostring(err):sub(1, 120), "error", 4)
						pcall(SetInternalStatus, "Error")
					else
						pcall(notify, "SpeedInternal", ("Script executed (fetch %.1fs, total %.1fs)"):format(t_exec_fetch - t_exec_start, t_exec_done - t_exec_start), "success", 3)
						pcall(SetInternalStatus, "Executed")
					end
				else
					warn('SpeedExecutor -- requestData returned nil after ' .. tostring(os.clock() - t_exec_start) .. 's')
				end
			end)
		end
	end
end)