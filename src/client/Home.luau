local Home = {}

local labels = {}
local connections = {}
local started = false
local generation = 0
local player = nil
local workspaceService = nil
local sessionStartedAt = 0
local sessionHoney = 0
local honeyValue = nil
local lastHoneyValue = nil
local honeyConnection = nil
local serverTimeSource = nil
local lastServerTimeScan = -math.huge

local function disconnectConnections()
	if honeyConnection then
		honeyConnection:Disconnect()
		honeyConnection = nil
	end
	for _, connection in ipairs(connections) do
		if connection and connection.Disconnect then
			connection:Disconnect()
		end
	end
	table.clear(connections)
end

local function formatDuration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local remainingSeconds = seconds % 60
	local parts = {}

	if days > 0 then
		table.insert(parts, ("%dd"):format(days))
	end
	if hours > 0 or days > 0 then
		table.insert(parts, ("%dh"):format(hours))
	end
	if minutes > 0 or hours > 0 or days > 0 then
		table.insert(parts, ("%dm"):format(minutes))
	end
	table.insert(parts, ("%ds"):format(remainingSeconds))

	return table.concat(parts, " ")
end

local function formatInteger(value)
	value = math.floor(tonumber(value) or 0)
	local sign = ""
	if value < 0 then
		sign = "-"
	end
	local digits = string.format("%.0f", math.abs(value))
	local formatted = string.reverse(digits):gsub("(%d%d%d)", "%1,")
	formatted = string.reverse(formatted):gsub("^,", "")
	return sign .. formatted
end

local function setLabel(key, text)
	local label = labels[key]
	if not label or not label.Parent then
		labels[key] = nil
		return
	end
	label.Text = text
end

local function getServerUptime()
	if not workspaceService then
		return 0
	end
	local replicatedUptime = player and tonumber(player:GetAttribute("ArcadaServerUptime"))
	if replicatedUptime and replicatedUptime >= 0 then
		return replicatedUptime
	end
	local function readSource(source)
		if not source then return nil end
		local success, value = pcall(function()
			if source:IsA("ValueBase") then
				return source.Value
			end
			return nil
		end)
		if not success then return nil end
		value = tonumber(value)
		if not value then return nil end
		local normalized = string.lower(source.Name):gsub("[^%w]", "")
		if string.find(normalized, "start", 1, true) and value > 1000000000 then
			return math.max(0, workspaceService:GetServerTimeNow() - value)
		end
		if normalized == "servertime" and value > 1000000000 then return nil end
		return value
	end
	local cached = readSource(serverTimeSource)
	if cached then return cached end
	if os.clock() - lastServerTimeScan < 10 then
		return workspaceService.DistributedGameTime
	end
	lastServerTimeScan = os.clock()
	for _, container in ipairs({ workspaceService, game:GetService("ReplicatedStorage") }) do
		for _, descendant in ipairs(container:GetDescendants()) do
			local normalized = string.lower(descendant.Name):gsub("[^%w]", "")
			if descendant:IsA("ValueBase") and table.find({
				"serveruptime", "serverage", "servertime", "serverstarttime", "serverstartedat",
			}, normalized) then
				serverTimeSource = descendant
				local value = readSource(descendant)
				if value then return value end
			end
		end
		for _, attributeName in ipairs({ "ServerUptime", "ServerAge", "ServerStartTime", "ServerStartedAt" }) do
			local value = tonumber(container:GetAttribute(attributeName))
			if value then
				if string.find(string.lower(attributeName), "start", 1, true) and value > 1000000000 then
					return math.max(0, workspaceService:GetServerTimeNow() - value)
				end
				return value
			end
		end
	end
	-- This fallback is only used on games that do not replicate a server-age
	-- marker. ArcadaServerUptime is preferred whenever the farming controller
	-- can obtain it from server stats.
	return workspaceService.DistributedGameTime
end

local function updateLabels()
	if not started then
		return
	end

	setLabel("UpTime", "UpTime: " .. formatDuration(os.clock() - sessionStartedAt))
	setLabel("ServerUpTime", "Server UpTime: " .. formatDuration(getServerUptime()))
	setLabel("SessionHoney", "Session Honey: +" .. formatInteger(sessionHoney))
	setLabel("TokensCollected", "Tokens Collected: " .. formatInteger(player and player:GetAttribute("ArcadaSessionTokens") or 0))
	setLabel("MaxPollen", "Max Pollen: " .. formatInteger(player and player:GetAttribute("ArcadaSessionMaxPollen") or 0))
	setLabel("MaxBalloonPollen", "Max Balloon: " .. formatInteger(player and player:GetAttribute("ArcadaSessionMaxBalloon") or 0))
	setLabel("MaxBalloonBlessing", "Max Balloon Blessing: " .. formatInteger(player and player:GetAttribute("ArcadaSessionMaxBalloonBlessing") or 0))
	setLabel("SproutsBroken", "Sprouts Broken: " .. formatInteger(player and player:GetAttribute("ArcadaSessionSprouts") or 0))
	setLabel("MonstersKilled", "Monsters Killed: " .. formatInteger(player and player:GetAttribute("ArcadaSessionMonsters") or 0))
	setLabel("ServerVersion", "Server Version: " .. tostring(game.PlaceVersion))
end

local function readHoneyValue(valueObject)
	if not valueObject then
		return nil
	end

	local success, value = pcall(function()
		return valueObject.Value
	end)
	if not success then
		return nil
	end
	local numericText = tostring(value):gsub(",", "")
	return tonumber(numericText)
end

local function updateSessionHoney()
	local currentHoney = readHoneyValue(honeyValue)
	if currentHoney == nil then
		return
	end

	if lastHoneyValue ~= nil and currentHoney > lastHoneyValue then
		sessionHoney = sessionHoney + currentHoney - lastHoneyValue
	end
	lastHoneyValue = currentHoney
	updateLabels()
end

local function bindHoneyValue(valueObject)
	if honeyValue == valueObject then
		return
	end
	if honeyConnection then
		honeyConnection:Disconnect()
		honeyConnection = nil
	end

	honeyValue = valueObject
	lastHoneyValue = readHoneyValue(valueObject)
	if valueObject then
		honeyConnection = valueObject:GetPropertyChangedSignal("Value"):Connect(updateSessionHoney)
	end
end

local function isHoneyValue(instance)
	if not instance or string.lower(instance.Name) ~= "honey" then
		return false
	end
	return instance:IsA("IntValue") or instance:IsA("NumberValue") or instance:IsA("StringValue")
end

local function findHoneyValue()
	if not player then
		return nil
	end

	-- CoreStats is the authoritative numeric source. Arcada mirrors Honey into
	-- leaderstats as a compact display string (for example "25B"), which cannot
	-- be used to calculate session gains reliably.
	local coreStats = player:FindFirstChild("CoreStats")
	local coreStatsHoney = coreStats and coreStats:FindFirstChild("Honey")
	if isHoneyValue(coreStatsHoney) then
		return coreStatsHoney
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local leaderstatsHoney = leaderstats and leaderstats:FindFirstChild("Honey")
	if isHoneyValue(leaderstatsHoney) then
		return leaderstatsHoney
	end

	for _, descendant in ipairs(player:GetDescendants()) do
		if isHoneyValue(descendant) then
			return descendant
		end
	end

	return nil
end

local function registerLabel(key, label)
	labels[key] = label
	updateLabels()
end

local function createLabel(key, text, searchText, image, layoutOrder, wide)
	return {
		Type = "Label",
		Text = text,
		Image = image,
		LayoutOrder = layoutOrder,
		Wide = wide == true,
		SearchText = searchText,
		OnCreated = function(_, label)
			registerLabel(key, label)
		end,
	}
end

function Home.CreateSection(icon)
	return {
		Name = "Home",
		NavigationButton = "Home",
		Icon = icon,
		FrameOpened = true,
		CompactPrimary = true,
		Controls = {
			createLabel("UpTime", "UpTime: 0s", "UpTime Session Time", nil, 10),
			createLabel("ServerUpTime", "Server UpTime: 0s", "Server UpTime Time", nil, 20),
			createLabel(
				"ServerVersion",
				"Server Version: " .. tostring(game.PlaceVersion),
				"Server Version GameVersion",
				nil,
				40
			),
		},
		Lists = {},
		SecondarySingle = {
			Title = "Session Stats",
			Opened = true,
			Controls = {
				createLabel("SessionHoney", "Session Honey: +0", "Session Honey", nil, 10),
				createLabel("TokensCollected", "Tokens Collected: 0", "Tokens Collected", nil, 20),
				createLabel("MaxPollen", "Max Pollen: 0", "Max Pollen", nil, 30),
				createLabel("MaxBalloonPollen", "Max Balloon: 0", "Max Balloon", nil, 40),
				createLabel("MaxBalloonBlessing", "Max Balloon Blessing: 0", "Balloon Blessing", nil, 50),
				createLabel("SproutsBroken", "Sprouts Broken: 0", "Sprouts Broken", nil, 60),
				createLabel("MonstersKilled", "Monsters Killed: 0", "Monsters Killed", nil, 70),
			},
		},
	}
end

function Home.Start(options)
	if started then
		return
	end

	options = options or {}
	player = options.Player
	workspaceService = options.Workspace
	-- os.clock() starts with the Roblox client session, so this remains accurate
	-- even when Arcada is loaded some time after the player joined.
	sessionStartedAt = 0
	sessionHoney = 0
	started = true
	generation = generation + 1
	local currentGeneration = generation

	if player then
		bindHoneyValue(findHoneyValue())
		table.insert(
			connections,
			player.DescendantAdded:Connect(function(descendant)
				if isHoneyValue(descendant)
					and (not honeyValue or (descendant.Parent and descendant.Parent.Name == "CoreStats"))
				then
					bindHoneyValue(descendant)
				end
			end)
		)
		table.insert(
			connections,
			player.DescendantRemoving:Connect(function(descendant)
				if descendant == honeyValue then
					bindHoneyValue(nil)
					task.defer(function()
						bindHoneyValue(findHoneyValue())
					end)
				end
			end)
		)
	end

	task.spawn(function()
		while started and generation == currentGeneration do
			local preferredHoneyValue = findHoneyValue()
			if preferredHoneyValue ~= honeyValue then
				bindHoneyValue(preferredHoneyValue)
			end
			updateLabels()
			task.wait(1)
		end
	end)
end

function Home.Stop()
	if not started then
		return
	end

	started = false
	generation = generation + 1
	disconnectConnections()
	table.clear(labels)
	honeyValue = nil
	lastHoneyValue = nil
end

return Home
