--// Services and Variables //--
local function getService(serviceName)
	local success, service = pcall(function()
		return game:GetService(serviceName)
	end)

	if success then
		return service
	end

	warn(("Service unavailable: %s"):format(serviceName))
	return nil
end

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local function createStandaloneHome()
	local home = {}
	local labels = {}
	local started = false
	local homePlayer = nil
	local homeWorkspace = nil
	local startedAt = 0
	local sessionHoney = 0
	local honeyValue = nil
	local lastHoneyValue = nil
	local honeyConnection = nil
	local homeConnections = {}
	local serverTimeSource = nil
	local lastServerTimeScan = -math.huge

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
		local digits = string.format("%.0f", math.abs(tonumber(value) or 0))
		local formatted = string.reverse(digits):gsub("(%d%d%d)", "%1,")
		return string.reverse(formatted):gsub("^,", "")
	end

	local function setLabel(key, text)
		local label = labels[key]
		if label and label.Parent then
			label.Text = text
		else
			labels[key] = nil
		end
	end

	local function updateLabels()
		if not started then
			return
		end
		local serverUptime = homePlayer and tonumber(homePlayer:GetAttribute("ArcadaServerUptime")) or nil
		if homeWorkspace then
			local function readServerSource(source)
				if not source or not source:IsA("ValueBase") then
					return nil
				end
				local value = tonumber((source :: any).Value)
				if not value then
					return nil
				end
				local normalized = string.lower(source.Name):gsub("[^%w]", "")
				if string.find(normalized, "start", 1, true) and value > 1000000000 then
					return math.max(0, homeWorkspace:GetServerTimeNow() - value)
				end
				if normalized == "servertime" and value > 1000000000 then
					return nil
				end
				return value
			end
			serverUptime = serverUptime or readServerSource(serverTimeSource)
			if not serverUptime and os.clock() - lastServerTimeScan >= 10 then
				lastServerTimeScan = os.clock()
				for _, descendant in ipairs(homeWorkspace:GetDescendants()) do
					local normalized = string.lower(descendant.Name):gsub("[^%w]", "")
					if
						descendant:IsA("ValueBase")
						and table.find({
							"serveruptime",
							"serverage",
							"servertime",
							"serverstarttime",
							"serverstartedat",
						}, normalized)
					then
						serverTimeSource = descendant
						serverUptime = readServerSource(descendant)
						if serverUptime then
							break
						end
					end
				end
			end
			serverUptime = serverUptime or homeWorkspace.DistributedGameTime
		end
		setLabel("UpTime", "UpTime: " .. formatDuration(os.clock() - startedAt))
		setLabel("ServerUpTime", "Server UpTime: " .. formatDuration(serverUptime or 0))
		setLabel("SessionHoney", "Session Honey: +" .. formatInteger(sessionHoney))
		setLabel("ServerVersion", "Server Version: " .. tostring(game.PlaceVersion))
	end

	local function readHoney(instance)
		if not instance then
			return nil
		end
		local success, value = pcall(function()
			return instance.Value
		end)
		if not success then
			return nil
		end
		return tonumber((tostring(value):gsub(",", "")))
	end

	local function updateHoney()
		local value = readHoney(honeyValue)
		if value == nil then
			return
		end
		if lastHoneyValue ~= nil and value > lastHoneyValue then
			sessionHoney += value - lastHoneyValue
		end
		lastHoneyValue = value
		updateLabels()
	end

	local function isHoneyValue(instance)
		return instance
			and string.lower(instance.Name) == "honey"
			and (instance:IsA("IntValue") or instance:IsA("NumberValue") or instance:IsA("StringValue"))
	end

	local function findHoneyValue()
		if not homePlayer then
			return nil
		end
		local coreStats = homePlayer:FindFirstChild("CoreStats")
		local coreStatsHoney = coreStats and coreStats:FindFirstChild("Honey")
		if isHoneyValue(coreStatsHoney) then
			return coreStatsHoney
		end
		local leaderstats = homePlayer:FindFirstChild("leaderstats")
		local leaderstatsHoney = leaderstats and leaderstats:FindFirstChild("Honey")
		if isHoneyValue(leaderstatsHoney) then
			return leaderstatsHoney
		end
		for _, descendant in ipairs(homePlayer:GetDescendants()) do
			if isHoneyValue(descendant) then
				return descendant
			end
		end
		return nil
	end

	local function bindHoney(instance)
		if honeyValue == instance then
			return
		end
		if honeyConnection then
			honeyConnection:Disconnect()
			honeyConnection = nil
		end
		honeyValue = instance
		lastHoneyValue = readHoney(instance)
		if instance then
			honeyConnection = instance:GetPropertyChangedSignal("Value"):Connect(updateHoney)
		end
	end

	local function createLabel(key, text, searchText, image, layoutOrder)
		return {
			Type = "Label",
			Text = text,
			Image = image,
			LayoutOrder = layoutOrder,
			SearchText = searchText,
			OnCreated = function(_, label)
				labels[key] = label
				updateLabels()
			end,
		}
	end

	function home.CreateSection(icon)
		return {
			Name = "Home",
			NavigationButton = "Home",
			Icon = icon,
			FrameOpened = true,
			Controls = {
				createLabel("UpTime", "UpTime: 0s", "UpTime Session Time", nil, 10),
				createLabel("ServerUpTime", "Server UpTime: 0s", "Server UpTime Time", nil, 20),
				createLabel("SessionHoney", "Session Honey: +0", "Session Honey", "rbxassetid://1472135114", 30),
				createLabel(
					"ServerVersion",
					"Server Version: " .. tostring(game.PlaceVersion),
					"Server Version GameVersion",
					nil,
					40
				),
			},
			Lists = {},
		}
	end

	function home.Start(options)
		if started then
			return
		end
		options = options or {}
		homePlayer = options.Player
		homeWorkspace = options.Workspace
		startedAt = 0
		started = true
		bindHoney(findHoneyValue())
		if homePlayer then
			table.insert(
				homeConnections,
				homePlayer.DescendantAdded:Connect(function(descendant)
					if
						isHoneyValue(descendant)
						and (not honeyValue or (descendant.Parent and descendant.Parent.Name == "CoreStats"))
					then
						bindHoney(descendant)
					end
				end)
			)
		end
		task.spawn(function()
			while started do
				if honeyValue and homePlayer and not honeyValue:IsDescendantOf(homePlayer) then
					bindHoney(nil)
				end
				local preferredHoneyValue = findHoneyValue()
				if preferredHoneyValue ~= honeyValue then
					bindHoney(preferredHoneyValue)
				end
				updateLabels()
				task.wait(1)
			end
		end)
	end

	function home.Stop()
		started = false
		if honeyConnection then
			honeyConnection:Disconnect()
			honeyConnection = nil
		end
		for _, connection in ipairs(homeConnections) do
			connection:Disconnect()
		end
		table.clear(homeConnections)
		table.clear(labels)
	end

	return home
end

local REMOTE_MODULE_CONFIG = {
	Owner = "rudevhd-glitch",
	Repository = "testload",
	Branch = "main",
}

local function getBootstrapEnvironment()
	if getgenv then
		local success, environment = pcall(getgenv)
		if success and type(environment) == "table" then
			return environment
		end
	end
	if type(shared) == "table" then
		return shared
	end
	return _G
end

local BOOTSTRAP_ENVIRONMENT = getBootstrapEnvironment()
if type(BOOTSTRAP_ENVIRONMENT.__ARCADA_BOOTSTRAP_CLEANUP) == "function" then
	pcall(BOOTSTRAP_ENVIRONMENT.__ARCADA_BOOTSTRAP_CLEANUP)
end
local bootstrapRuntimeToken = {}
BOOTSTRAP_ENVIRONMENT.__ARCADA_BOOTSTRAP_RUNTIME_TOKEN = bootstrapRuntimeToken
local bootstrapConnections = {}
local REMOTE_MODULE_CACHE = {}
local REMOTE_MODULE_LOADING = {}

local function validateRemoteModulePath(path)
	path = tostring(path or "")
	return path ~= ""
		and not string.find(path, "..", 1, true)
		and not string.find(path, "\\", 1, true)
		and string.match(path, "^[%w%._%-%/]+$") ~= nil
end

local function getExecutorRequest()
	for _, requestName in ipairs({ "request", "http_request", "httprequest" }) do
		local candidate = BOOTSTRAP_ENVIRONMENT[requestName]
		if type(candidate) == "function" then
			return candidate
		end
	end
	local synTable = BOOTSTRAP_ENVIRONMENT.syn
	if type(synTable) == "table" then
		for _, requestName in ipairs({ "request", "http_request" }) do
			local candidate = synTable[requestName]
			if type(candidate) == "function" then
				return candidate
			end
		end
	end
	return nil
end

local function requestPrivateGitHubSource(path, token)
	local apiUrl = ("https://api.github.com/repos/%s/%s/contents/%s?ref=%s"):format(
		REMOTE_MODULE_CONFIG.Owner,
		REMOTE_MODULE_CONFIG.Repository,
		path,
		REMOTE_MODULE_CONFIG.Branch
	)
	local headers = {
		Accept = "application/vnd.github.raw+json",
		Authorization = "Bearer " .. token,
		["X-GitHub-Api-Version"] = "2022-11-28",
		["User-Agent"] = "Arcada-Remote-Loader",
	}
	local requestFunction = getExecutorRequest()
	if requestFunction then
		local success, response = pcall(requestFunction, {
			Url = apiUrl,
			Method = "GET",
			Headers = headers,
		})
		if success and type(response) == "table" then
			local statusCode = tonumber(response.StatusCode or response.Status or response.status_code)
			local body = response.Body or response.body
			if (statusCode == nil or statusCode == 200) and type(body) == "string" and body ~= "" then
				return body
			end
			return nil, "GitHub API status " .. tostring(statusCode or "unknown")
		end
	end

	local httpService = game:GetService("HttpService")
	local success, response = pcall(function()
		return httpService:RequestAsync({
			Url = apiUrl,
			Method = "GET",
			Headers = headers,
		})
	end)
	if success and response.Success and type(response.Body) == "string" and response.Body ~= "" then
		return response.Body
	end
	return nil, if success then "GitHub API status " .. tostring(response.StatusCode) else tostring(response)
end

local function requestPublicGitHubSource(path)
	local rawUrl = ("https://raw.githubusercontent.com/%s/%s/%s/%s?cache=%d"):format(
		REMOTE_MODULE_CONFIG.Owner,
		REMOTE_MODULE_CONFIG.Repository,
		REMOTE_MODULE_CONFIG.Branch,
		path,
		os.time()
	)
	local success, source = pcall(function()
		return game:HttpGet(rawUrl)
	end)
	if success and type(source) == "string" and source ~= "" and not string.find(source, "404: Not Found", 1, true) then
		return source
	end
	return nil, if success then "public raw file unavailable" else tostring(source)
end

local RemoteModules = {}

function RemoteModules.Load(path)
	path = tostring(path or "")
	if not validateRemoteModulePath(path) then
		return nil, "invalid module path"
	end
	local cached = REMOTE_MODULE_CACHE[path]
	if cached then
		return cached.Value
	end
	if REMOTE_MODULE_LOADING[path] then
		return nil, "circular remote module load: " .. path
	end
	REMOTE_MODULE_LOADING[path] = true

	local token = BOOTSTRAP_ENVIRONMENT.ARCADA_GITHUB_TOKEN
	local source, requestError
	if type(token) == "string" and token ~= "" then
		source, requestError = requestPrivateGitHubSource(path, token)
	else
		source, requestError = requestPublicGitHubSource(path)
	end
	if not source then
		REMOTE_MODULE_LOADING[path] = nil
		return nil, requestError
	end

	local compiler = loadstring or load
	if type(compiler) ~= "function" then
		REMOTE_MODULE_LOADING[path] = nil
		return nil, "loadstring is unavailable"
	end
	local compileSuccess, chunk, compileError = pcall(compiler, source, "@Arcada/" .. path)
	if not compileSuccess or type(chunk) ~= "function" then
		REMOTE_MODULE_LOADING[path] = nil
		return nil, tostring(compileError or chunk)
	end
	local executeSuccess, result = pcall(chunk)
	REMOTE_MODULE_LOADING[path] = nil
	if not executeSuccess then
		return nil, tostring(result)
	end

	local moduleValue = if result == nil then true else result
	REMOTE_MODULE_CACHE[path] = {
		Value = moduleValue,
	}
	return moduleValue
end

BOOTSTRAP_ENVIRONMENT.ArcadaLoadModule = RemoteModules.Load

local REMOTE_MODULE_REGISTRY = {}
BOOTSTRAP_ENVIRONMENT.ArcadaModules = REMOTE_MODULE_REGISTRY

local function loadRemoteManifest()
	local manifest = RemoteModules.Load("Manifest.luau")
	if type(manifest) ~= "table" then
		return
	end

	local function loadEntry(name, path)
		name = tostring(name or "")
		path = tostring(path or "")
		if name == "" or path == "" or string.lower(path) == "init.client.luau" then
			return
		end
		local moduleValue, loadError = RemoteModules.Load(path)
		if moduleValue ~= nil then
			REMOTE_MODULE_REGISTRY[name] = moduleValue
		else
			warn(("Remote module %s failed: %s"):format(path, tostring(loadError)))
		end
	end

	if #manifest > 0 then
		for _, entry in ipairs(manifest) do
			if type(entry) == "string" then
				local name = string.match(entry, "([^/]+)%.luau$") or entry
				loadEntry(name, entry)
			elseif type(entry) == "table" then
				loadEntry(entry.Name or entry.Key, entry.Path or entry.File)
			end
		end
	else
		for name, path in pairs(manifest) do
			loadEntry(name, path)
		end
	end
end

loadRemoteManifest()

-- Rojo mounts this directory as the bootstrap LocalScript, so the farming
-- controller is a child ModuleScript and must be required explicitly. The
-- remote manifest remains the preferred path for the distributed loader.
if REMOTE_MODULE_REGISTRY.FarmingController == nil then
	local farmingModule = script and script:FindFirstChild("FarmingController")
	if farmingModule and farmingModule:IsA("ModuleScript") then
		local success, result = pcall(require, farmingModule)
		if success then
			REMOTE_MODULE_REGISTRY.FarmingController = if result == nil then true else result
		else
			warn("Local FarmingController failed: " .. tostring(result))
		end
	else
		warn("FarmingController was not loaded and no local ModuleScript fallback was found")
	end
end

local Home = REMOTE_MODULE_REGISTRY.Home
local homeLoadError = nil
if type(Home) ~= "table" then
	Home, homeLoadError = RemoteModules.Load("Home.luau")
end
if type(Home) ~= "table" then
	Home = nil
	local homeModule = script and script:FindFirstChild("Home")
	if homeModule and homeModule:IsA("ModuleScript") then
		local success, result = pcall(require, homeModule)
		if success and type(result) == "table" then
			Home = result
		end
	end
	if not Home then
		warn("Remote Home.luau unavailable; using standalone fallback: " .. tostring(homeLoadError))
		Home = createStandaloneHome()
	end
end

local SERVICE = {
	["Version"] = "Arcada v0.1",

	["ReplicatedStorage"] = getService("ReplicatedStorage"),
	["Players"] = Players,
	["Workspace"] = getService("Workspace"),
	["RunService"] = getService("RunService"),
	["UserInputService"] = getService("UserInputService"),
	["TweenService"] = getService("TweenService"),
	["StarterGui"] = getService("StarterGui"),
	["Lighting"] = getService("Lighting"),
	["GuiService"] = getService("GuiService"),
	["HttpService"] = getService("HttpService"),
	["VirtualInputManager"] = getService("VirtualInputManager"),
	["VirtualUser"] = getService("VirtualUser"),
	["TeleportService"] = getService("TeleportService"),

	["Player"] = LocalPlayer,
	["PlayerGui"] = PlayerGui,
}

Home.Start({
	Player = LocalPlayer,
	Workspace = SERVICE.Workspace,
})

local function updatePlayerListStats(targetPlayer)
	local coreStats = targetPlayer:FindFirstChild("CoreStats")
	if not coreStats then
		return
	end
	local leaderstats = targetPlayer:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = targetPlayer
	end
	local function formatCompactNumber(value)
		local text = tostring(value or "0"):gsub("[%s,]", "")
		local number = tonumber(text) or 0
		local suffixes = { "", "K", "M", "B", "T", "qd", "qn", "sx", "sp", "oc", "no", "dc" }
		local suffixIndex = 1
		while math.abs(number) >= 1000 and suffixIndex < #suffixes do
			number /= 1000
			suffixIndex += 1
		end
		if suffixIndex == 1 then
			return string.format("%.0f", number)
		end
		local formatted = string.format("%.3f", number):gsub("0+$", ""):gsub("%.$", ""):gsub("%.", ",")
		return formatted .. suffixes[suffixIndex]
	end
	for _, statName in ipairs({ "Honey", "Pollen" }) do
		local source = coreStats:FindFirstChild(statName)
		if source and source:IsA("ValueBase") then
			local display = leaderstats:FindFirstChild(statName)
			if display and not display:IsA("StringValue") then
				display:Destroy()
				display = nil
			end
			if not display then
				display = Instance.new("StringValue")
				display.Name = statName
				display.Parent = leaderstats
			end
			if display:IsA("StringValue") then
				pcall(function()
					display.Value = formatCompactNumber((source :: any).Value)
				end)
			end
		end
	end
end

task.spawn(function()
	while BOOTSTRAP_ENVIRONMENT.__ARCADA_BOOTSTRAP_RUNTIME_TOKEN == bootstrapRuntimeToken do
		for _, targetPlayer in ipairs(SERVICE.Players:GetPlayers()) do
			updatePlayerListStats(targetPlayer)
		end
		task.wait(0.5)
	end
end)

local SETTING = {
	["Farming"] = {
		["Auto_Farm"] = false,
		["Auto_Sprinkler"] = false,
		["Auto_Dig"] = false,
		["Selected_Field"] = nil,
		["Auto_Sprouts"] = false,
		["ESC_Tokens"] = false,
		["Farm_Bubbles"] = false,
		["Farm_Petals"] = false,
		["Shift_Lock"] = false,
		["Wealth_Clock"] = false,
		["Auto_Puffshrooms"] = false,
		["Puff_Collect_Loot"] = true,
		["Puff_Prefer_Rarity"] = true,
		["Puff_Min_Level"] = 1,
		["Puff_Min_Rarity"] = "Common",
		["Puff_Loot_Seconds"] = 12,
		["Puff_Fields"] = "All",
		["Priority_Tokens"] = {
			["Test"] = 500,
		},

		["Movement_Tween"] = false,
		["Movement_Walk"] = false,
		["Movement_Speed"] = 25,
	},
	["Config"] = {
		["Speed"] = 20,
		["Anti_AFK"] = false,
		["Selected_Mask"] = "Diamond Mask",
		["Auto_Honey_Mask"] = false,
		["Convert_Balloons"] = true,
		["Convert_Percent"] = 100,
		["Convert_Minutes"] = 20,
		["Hive_Slot"] = 4,
		["Auto_Hive"] = true,
		["Auto_Rejoin"] = BOOTSTRAP_ENVIRONMENT.ARCADA_AUTO_REJOIN == true,
		["VIP_Server_Link"] = tostring(BOOTSTRAP_ENVIRONMENT.ARCADA_VIP_SERVER_LINK or ""),
		["Show_Player_List"] = false,
		["Minimum_Render"] = false,
		["Hide_Decorations"] = false,
		["Hide_Field_Decos"] = false,
		["Hide_Fields"] = false,
		["Disable_Shadows"] = false,
		["Low_Fog_Effects"] = false,
	},
	["Bosses"] = {
		["Farm_Mondo_Chick"] = false,
		["Collect_Mondo_Tokens"] = false,
		["Farm_Windy_Bee"] = false,
		["Farm_Vicious_Bee"] = false,
		["Farm_Stump_Snail"] = false,
	},
	["MemoryMatch"] = {
		["Auto"] = false,
		["Show_Images"] = false,
	},
}

local function bindBackpackSearch(content)
	if not content then
		return
	end
	local existingSearch = content:FindFirstChild("ArcadaBackpackSearch")
	if existingSearch and existingSearch:GetAttribute("ArcadaSearchVersion") == 2 then
		return
	elseif existingSearch then
		existingSearch:Destroy()
	end
	local contentLayout = content:FindFirstChildWhichIsA("UIGridStyleLayout")
	if contentLayout then
		contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	end
	local search = Instance.new("TextBox")
	search.Name = "ArcadaBackpackSearch"
	search:SetAttribute("ArcadaSearchVersion", 2)
	search.LayoutOrder = 2147483647
	search.Size = UDim2.new(1, -18, 0, 38)
	search.BackgroundColor3 = Color3.fromRGB(212, 221, 218)
	search.BorderSizePixel = 0
	search.ClearTextOnFocus = false
	search.Font = Enum.Font.BuilderSansBold
	search.PlaceholderText = "Search items..."
	search.PlaceholderColor3 = Color3.fromRGB(78, 91, 98)
	search.Text = ""
	search.TextColor3 = Color3.fromRGB(27, 42, 53)
	search.TextSize = 18
	search.TextXAlignment = Enum.TextXAlignment.Left
	search.Parent = content
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = search
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = search
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(188, 186, 194)
	stroke.Thickness = 1
	stroke.Transparency = 0.15
	stroke.Parent = search

	local searchableRows = {}
	local function indexRow(row)
		if row == search or not row:IsA("GuiObject") then
			return
		end
		local words = {}
		for _, descendant in ipairs(row:GetDescendants()) do
			if (descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox")) and descendant.Text ~= "" then
				table.insert(words, descendant.Text)
			end
		end
		searchableRows[row] = string.lower(table.concat(words, " "))
	end
	for _, row in ipairs(content:GetChildren()) do
		indexRow(row)
	end

	local filterGeneration = 0
	local function applyFilter()
		local query = string.lower(search.Text):match("^%s*(.-)%s*$") or ""
		for row, searchable in pairs(searchableRows) do
			if row.Parent == content then
				row.Visible = query == "" or string.find(searchable, query, 1, true) ~= nil
			else
				searchableRows[row] = nil
			end
		end
	end
	table.insert(bootstrapConnections, search:GetPropertyChangedSignal("Text"):Connect(function()
		filterGeneration += 1
		local generation = filterGeneration
		task.delay(0.12, function()
			if search.Parent and generation == filterGeneration then
				applyFilter()
			end
		end)
	end))
	table.insert(
		bootstrapConnections,
		content.ChildAdded:Connect(function(row)
			task.defer(function()
				indexRow(row)
				applyFilter()
			end)
		end)
	)
	table.insert(bootstrapConnections, content.ChildRemoved:Connect(function(row)
		searchableRows[row] = nil
	end))
end

task.spawn(function()
	while BOOTSTRAP_ENVIRONMENT.__ARCADA_BOOTSTRAP_RUNTIME_TOKEN == bootstrapRuntimeToken do
		local screenGui = PlayerGui:FindFirstChild("ScreenGui")
		local menus = screenGui and screenGui:FindFirstChild("Menus")
		local children = menus and menus:FindFirstChild("Children")
		local eggs = children and children:FindFirstChild("Eggs")
		local content = eggs and eggs:FindFirstChild("Content")
		if content then
			bindBackpackSearch(content)
		end
		task.wait(1)
	end
end)

local function formatBossTimer(totalSeconds)
	totalSeconds = math.max(0, math.floor(tonumber(totalSeconds) or 0))
	return string.format(
		"%02d:%02d:%02d",
		math.floor(totalSeconds / 3600),
		math.floor(totalSeconds / 60) % 60,
		totalSeconds % 60
	)
end

local function getSpawnerTimerText(spawnerName)
	local spawners = SERVICE.Workspace and SERVICE.Workspace:FindFirstChild("MonsterSpawners")
	local spawner = spawners and spawners:FindFirstChild(spawnerName)
	local label = spawner and spawner:FindFirstChild("TimerLabel", true)
	if label and label:IsA("GuiObject") then
		if label.Visible == false then
			return "00:00:00"
		end
		local numbers = tostring((label :: any).Text or ""):gsub("[^%d:]", "")
		return if numbers ~= "" then numbers else "--:--:--"
	end
	return "--:--:--"
end

local function getMondoTimerText()
	local monsters = SERVICE.Workspace and SERVICE.Workspace:FindFirstChild("Monsters")
	if monsters and monsters:FindFirstChild("Mondo Chick") then
		return "00:00:00"
	end
	local now = os.date("!*t")
	local elapsed = now.min * 60 + now.sec
	return formatBossTimer(if elapsed == 0 then 0 else 3600 - elapsed)
end

local function requestMemoryMatch(gameType)
	LocalPlayer:SetAttribute("ArcadaMemoryStartRequest", tostring(gameType) .. ":" .. tostring(os.clock()))
end

local optimizationState = {
	HiddenParents = setmetatable({}, { __mode = "k" }),
	QualityLevel = nil,
	StreamingTargetRadius = nil,
	StreamingMinRadius = nil,
	GlobalShadows = nil,
	FogEnd = nil,
	FogObjectEnd = nil,
	Effects = setmetatable({}, { __mode = "k" }),
	HiddenFieldParts = setmetatable({}, { __mode = "k" }),
	RemovedFieldDecals = {},
}

local function setPlayerListEnabled(enabled)
	if SERVICE.StarterGui then
		pcall(SERVICE.StarterGui.SetCoreGuiEnabled, SERVICE.StarterGui, Enum.CoreGuiType.PlayerList, enabled == true)
	end
end

local function setMinimumRender(enabled)
	local ok, rendering = pcall(settings)
	if ok and rendering and rendering.Rendering then
		if optimizationState.QualityLevel == nil then
			pcall(function()
				optimizationState.QualityLevel = rendering.Rendering.QualityLevel
			end)
		end
		pcall(function()
			rendering.Rendering.QualityLevel = if enabled
				then Enum.QualityLevel.Level01
				else optimizationState.QualityLevel
		end)
	end
	local world = SERVICE.Workspace
	if world then
		if optimizationState.StreamingTargetRadius == nil then
			pcall(function()
				optimizationState.StreamingTargetRadius = world.StreamingTargetRadius
			end)
			pcall(function()
				optimizationState.StreamingMinRadius = world.StreamingMinRadius
			end)
		end
		pcall(function()
			world.StreamingTargetRadius = if enabled then 64 else optimizationState.StreamingTargetRadius
		end)
		pcall(function()
			world.StreamingMinRadius = if enabled then 64 else optimizationState.StreamingMinRadius
		end)
	end
end

local function setFoldersHidden(names, enabled)
	local world = SERVICE.Workspace
	if not world then
		return
	end
	if enabled then
		for _, name in ipairs(names) do
			local folder = world:FindFirstChild(name)
			if folder and optimizationState.HiddenParents[folder] == nil then
				optimizationState.HiddenParents[folder] = folder.Parent
				folder.Parent = nil
			end
		end
	else
		for instance, parent in pairs(optimizationState.HiddenParents) do
			if table.find(names, instance.Name) and instance.Parent == nil and parent then
				instance.Parent = parent
			end
		end
	end
end

local function setFieldDecosHidden(enabled)
	local folder = SERVICE.Workspace and SERVICE.Workspace:FindFirstChild("FieldDecos")
	if not folder then
		return
	end
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if descendant:GetAttribute("ArcadaOriginalTransparency") == nil then
				descendant:SetAttribute("ArcadaOriginalTransparency", descendant.Transparency)
			end
			descendant.Transparency = if enabled then 1 else descendant:GetAttribute("ArcadaOriginalTransparency") or 0
		elseif descendant:IsA("Decal") and descendant.Name == "TopTexture" then
			if descendant:GetAttribute("ArcadaOriginalTransparency") == nil then
				descendant:SetAttribute("ArcadaOriginalTransparency", descendant.Transparency)
			end
			descendant.Transparency = if enabled then 1 else descendant:GetAttribute("ArcadaOriginalTransparency") or 0
		end
	end
end

local function setFieldsHidden(enabled)
	local flowers = SERVICE.Workspace and SERVICE.Workspace:FindFirstChild("Flowers")
	if not flowers then
		return
	end
	if enabled then
		for _, descendant in ipairs(flowers:GetDescendants()) do
			if descendant:IsA("BasePart") then
				if optimizationState.HiddenFieldParts[descendant] == nil then
					optimizationState.HiddenFieldParts[descendant] = descendant.LocalTransparencyModifier
				end
				descendant.LocalTransparencyModifier = 1
			elseif descendant:IsA("Decal") and descendant.Name == "TopTexture" then
				table.insert(
					optimizationState.RemovedFieldDecals,
					{ Parent = descendant.Parent, Clone = descendant:Clone() }
				)
				descendant:Destroy()
			end
		end
	else
		for part, transparency in pairs(optimizationState.HiddenFieldParts) do
			if part.Parent then
				part.LocalTransparencyModifier = transparency
			end
			optimizationState.HiddenFieldParts[part] = nil
		end
		for _, record in ipairs(optimizationState.RemovedFieldDecals) do
			if record.Parent and not record.Parent:FindFirstChild("TopTexture") then
				record.Clone.Parent = record.Parent
			end
		end
		table.clear(optimizationState.RemovedFieldDecals)
	end
end

local function setShadowsDisabled(enabled)
	local lighting = SERVICE.Lighting
	if not lighting then
		return
	end
	if optimizationState.GlobalShadows == nil then
		optimizationState.GlobalShadows = lighting.GlobalShadows
	end
	lighting.GlobalShadows = if enabled then false else optimizationState.GlobalShadows
end

local function setLowFogEffects(enabled)
	local lighting = SERVICE.Lighting
	if not lighting then
		return
	end
	if optimizationState.FogEnd == nil then
		optimizationState.FogEnd = lighting.FogEnd
	end
	lighting.FogEnd = if enabled then 200 else optimizationState.FogEnd
	local fog = lighting:FindFirstChild("Fog")
	if fog and pcall(function()
		return fog.FogEnd
	end) then
		if optimizationState.FogObjectEnd == nil then
			optimizationState.FogObjectEnd = fog.FogEnd
		end
		fog.FogEnd = if enabled then 200 else optimizationState.FogObjectEnd
	end
	for _, effect in ipairs(lighting:GetChildren()) do
		if effect:IsA("PostEffect") then
			if optimizationState.Effects[effect] == nil then
				optimizationState.Effects[effect] = effect.Enabled
			end
			effect.Enabled = if enabled then false else optimizationState.Effects[effect]
		end
	end
end

local function reapplyOptimizations()
	setMinimumRender(SETTING.Config.Minimum_Render)
	setFoldersHidden({ "Decorations", "FieldDecos" }, SETTING.Config.Hide_Decorations)
	setFieldDecosHidden(SETTING.Config.Hide_Field_Decos)
	setFieldsHidden(SETTING.Config.Hide_Fields)
	setShadowsDisabled(SETTING.Config.Disable_Shadows)
	setLowFogEffects(SETTING.Config.Low_Fog_Effects)
end

table.insert(
	bootstrapConnections,
	LocalPlayer.CharacterAdded:Connect(function()
		-- The game can recreate visual folders during respawn. Reapply after both
		-- the character and the streamed map decorations have returned.
		task.delay(1, reapplyOptimizations)
		task.delay(3, reapplyOptimizations)
	end)
)
if SERVICE.Workspace then
	table.insert(
		bootstrapConnections,
		SERVICE.Workspace.ChildAdded:Connect(function(child)
			if child.Name == "Decorations" or child.Name == "FieldDecos" or child.Name == "Flowers" then
				task.defer(reapplyOptimizations)
			end
		end)
	)
end

-- FarmingController runs as a remote chunk or child ModuleScript. Attributes
-- provide a Roblox-safe bridge without relying on executor globals.
local farmingBridgeToken = {}
BOOTSTRAP_ENVIRONMENT.__ARCADA_FARMING_BRIDGE_TOKEN = farmingBridgeToken
local function setPlayerAttributeIfChanged(name, value)
	if LocalPlayer:GetAttribute(name) ~= value then
		LocalPlayer:SetAttribute(name, value)
	end
end
task.spawn(function()
	local lastPriorityJson = ""
	while BOOTSTRAP_ENVIRONMENT.__ARCADA_FARMING_BRIDGE_TOKEN == farmingBridgeToken do
		setPlayerAttributeIfChanged("ArcadaAutoFarm", SETTING.Farming.Auto_Farm == true)
		setPlayerAttributeIfChanged("ArcadaAutoDig", SETTING.Farming.Auto_Dig == true)
		setPlayerAttributeIfChanged("ArcadaAutoSprinkler", SETTING.Farming.Auto_Sprinkler == true)
		setPlayerAttributeIfChanged("ArcadaAutoSprouts", SETTING.Farming.Auto_Sprouts == true)
		setPlayerAttributeIfChanged("ArcadaESCTokens", SETTING.Farming.ESC_Tokens == true)
		setPlayerAttributeIfChanged("ArcadaFarmBubbles", SETTING.Farming.Farm_Bubbles == true)
		setPlayerAttributeIfChanged("ArcadaFarmPetals", SETTING.Farming.Farm_Petals == true)
		setPlayerAttributeIfChanged("ArcadaShiftLock", SETTING.Farming.Shift_Lock == true)
		setPlayerAttributeIfChanged("ArcadaWealthClock", SETTING.Farming.Wealth_Clock == true)
		setPlayerAttributeIfChanged("ArcadaAutoPuffshrooms", SETTING.Farming.Auto_Puffshrooms == true)
		setPlayerAttributeIfChanged("ArcadaPuffCollectLoot", SETTING.Farming.Puff_Collect_Loot == true)
		setPlayerAttributeIfChanged("ArcadaPuffPreferRarity", SETTING.Farming.Puff_Prefer_Rarity == true)
		setPlayerAttributeIfChanged("ArcadaPuffMinLevel", SETTING.Farming.Puff_Min_Level)
		setPlayerAttributeIfChanged("ArcadaPuffMinRarity", SETTING.Farming.Puff_Min_Rarity)
		setPlayerAttributeIfChanged("ArcadaPuffLootSeconds", SETTING.Farming.Puff_Loot_Seconds)
		setPlayerAttributeIfChanged("ArcadaPuffFields", SETTING.Farming.Puff_Fields)
		setPlayerAttributeIfChanged("ArcadaFarmMondo", SETTING.Bosses.Farm_Mondo_Chick == true)
		setPlayerAttributeIfChanged("ArcadaCollectMondoTokens", SETTING.Bosses.Collect_Mondo_Tokens == true)
		setPlayerAttributeIfChanged("ArcadaFarmWindyBee", SETTING.Bosses.Farm_Windy_Bee == true)
		setPlayerAttributeIfChanged("ArcadaFarmViciousBee", SETTING.Bosses.Farm_Vicious_Bee == true)
		setPlayerAttributeIfChanged("ArcadaFarmStumpSnail", SETTING.Bosses.Farm_Stump_Snail == true)
		setPlayerAttributeIfChanged("ArcadaAutoMemoryMatch", SETTING.MemoryMatch.Auto == true)
		setPlayerAttributeIfChanged("ArcadaShowMemoryImages", SETTING.MemoryMatch.Show_Images == true)
		setPlayerAttributeIfChanged("ArcadaAntiAFK", SETTING.Config.Anti_AFK == true)
		setPlayerAttributeIfChanged("ArcadaSelectedField", SETTING.Farming.Selected_Field)
		setPlayerAttributeIfChanged("ArcadaConfiguredSpeed", SETTING.Config.Speed)
		setPlayerAttributeIfChanged("ArcadaSelectedMask", SETTING.Config.Selected_Mask)
		setPlayerAttributeIfChanged("ArcadaAutoHoneyMask", SETTING.Config.Auto_Honey_Mask == true)
		setPlayerAttributeIfChanged("ArcadaConvertBalloons", SETTING.Config.Convert_Balloons == true)
		setPlayerAttributeIfChanged("ArcadaConvertPercent", SETTING.Config.Convert_Percent)
		setPlayerAttributeIfChanged("ArcadaConvertMinutes", SETTING.Config.Convert_Minutes)
		setPlayerAttributeIfChanged("ArcadaHiveSlot", SETTING.Config.Hive_Slot)
		setPlayerAttributeIfChanged("ArcadaAutoHive", SETTING.Config.Auto_Hive == true)
		local success, encoded =
			pcall(SERVICE.HttpService.JSONEncode, SERVICE.HttpService, SETTING.Farming.Priority_Tokens)
		if success and encoded ~= lastPriorityJson then
			lastPriorityJson = encoded
			LocalPlayer:SetAttribute("ArcadaPriorityTokens", encoded)
		end
		task.wait(0.25)
	end
end)

local function getQueueOnTeleport()
	for _, name in ipairs({ "queue_on_teleport", "queueonteleport" }) do
		local candidate = BOOTSTRAP_ENVIRONMENT[name]
		if type(candidate) == "function" then
			return candidate
		end
	end
	local synEnvironment = BOOTSTRAP_ENVIRONMENT.syn
	if type(synEnvironment) == "table" and type(synEnvironment.queue_on_teleport) == "function" then
		return synEnvironment.queue_on_teleport
	end
	return nil
end

local function extractPrivateServerCode(link)
	link = tostring(link or ""):match("^%s*(.-)%s*$") or ""
	if link == "" then
		return nil
	end
	local code = link:match("[?&]privateServerLinkCode=([^&#]+)") or link:match("[?&]code=([^&#]+)")
	if not code and not link:find("[/?:&=]", 1) then
		code = link
	end
	if not code or code == "" then
		return nil
	end
	if SERVICE.HttpService then
		local success, decoded = pcall(SERVICE.HttpService.UrlDecode, SERVICE.HttpService, code)
		if success then
			code = decoded
		end
	end
	return code
end

local function queueArcadaAfterTeleport()
	local queueFunction = getQueueOnTeleport()
	if not queueFunction then
		warn("Auto Rejoin: executor does not provide queue_on_teleport; Arcada cannot restart automatically")
		return false
	end
	local loaderUrl = "https://raw.githubusercontent.com/rudevhd-glitch/testload/main/Loader.luau"
	local queuedSource = (
		"local e=(getgenv and getgenv()) or shared or _G;"
		.. "e.ARCADA_AUTO_REJOIN=true;e.ARCADA_VIP_SERVER_LINK=%q;"
		.. "loadstring(game:HttpGet(%q))()"
	):format(tostring(SETTING.Config.VIP_Server_Link or ""), loaderUrl)
	local success, message = pcall(queueFunction, queuedSource)
	if not success then
		warn("Auto Rejoin: failed to queue Loader.luau: " .. tostring(message))
	end
	return success
end

-- Rejoin only after Roblox reports that this client has lost the server. A
-- cooldown prevents repeated Teleport calls while the disconnect prompt is up.
do
	local rejoinPending = false
	local guiService = SERVICE.GuiService
	if guiService then
		table.insert(
			bootstrapConnections,
			guiService.ErrorMessageChanged:Connect(function(message)
				if not SETTING.Config.Auto_Rejoin or rejoinPending or tostring(message or "") == "" then
					return
				end
				rejoinPending = true
				task.delay(2, function()
					local teleportService = SERVICE.TeleportService
					if SETTING.Config.Auto_Rejoin and teleportService then
						queueArcadaAfterTeleport()
						local privateServerCode = extractPrivateServerCode(SETTING.Config.VIP_Server_Link)
						local teleportStarted = false
						if privateServerCode then
							teleportStarted = pcall(
								teleportService.TeleportToPrivateServer,
								teleportService,
								game.PlaceId,
								privateServerCode,
								{ LocalPlayer }
							)
						end
						if not teleportStarted then
							pcall(teleportService.Teleport, teleportService, game.PlaceId, LocalPlayer)
						end
					end
					task.delay(8, function()
						rejoinPending = false
					end)
				end)
			end)
		)
	end
end

local WARNING_LIST = {
	[1] = "not replacement frame",
	[2] = "frame already exists",
	[3] = "not adding shadow",
	[4] = "open close",
	[5] = "not standart template",
}

local IMAGES_ALL = {
	[1] = "rbxassetid://1472580249", --// Tab
	[2] = "rbxassetid://4359655183", --// Search
	[3] = "rbxassetid://13060262529", --// Home
	[4] = "rbxassetid://15332137726", --// Farming
	[5] = "rbxassetid://4391741881", --// Combat
	[6] = "rbxassetid://212154312", --// Quests
	[7] = "rbxassetid://1454236209", --// Planters
	[8] = "rbxassetid://10004737652", --// Toys
	[9] = "rbxassetid://4857706689", --// Config
	[10] = "rbxassetid://15000526827", --// Active Button

	[11] = "rbxassetid://2908768829", --// Bamboo Field
	[12] = "rbxassetid://2908768899", --// Blue Flower Field
	[13] = "rbxassetid://2908768937", --// Cactus Field
	[14] = "rbxassetid://2908768973", --// Clover Field
	[15] = "rbxassetid://2908769010", --// Coconut Field
	[16] = "rbxassetid://2908769047", --// Dandelion Field
	[17] = "rbxassetid://2908769086", --// Mountain Top Field
	[18] = "rbxassetid://2908769124", --// Mushroom Field
	[19] = "rbxassetid://3835712489", --// Pepper Patch
	[20] = "rbxassetid://2908769190", --// Pine Tree Forest
	[21] = "rbxassetid://2908769153", --// Pineapple Patch
	[22] = "rbxassetid://2908769220", --// Pumpkin Patch
	[23] = "rbxassetid://2908818982", --// Rose Field
	[24] = "rbxassetid://2908769301", --// Spider Field
	[25] = "rbxassetid://2908769330", --// Strawberry Field
	[26] = "rbxassetid://2908769372", --// Stump Field
	[27] = "rbxassetid://2908769405", --// Sunflower Field
}

local SCREEN_GUI_NAME = "ScreenGui"

local function getScreenGui()
	local screenGui = SERVICE.PlayerGui:FindFirstChild(SCREEN_GUI_NAME)

	if screenGui then
		return screenGui
	end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = SCREEN_GUI_NAME
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = SERVICE.PlayerGui

	return screenGui
end

--// Create Main Frame //--
local function CreateMainFrame()
	local CREATE_FRAME_SETTINGS = {
		["AnchorPoint"] = Vector2.new(0.5, 0.5),
		["BackgroundTransparency"] = 1,
		["Position"] = UDim2.new(0.5, 0, 0.5, 0),
		["Size"] = UDim2.new(0.36, 0, 0.47, 0),
		["Zindex"] = 10000,
	}

	local screenGui = getScreenGui()

	local function reject()
		local CREATE_FRAME = Instance.new("Frame")
		CREATE_FRAME.Name = "EggHuntLayer"
		CREATE_FRAME.Parent = screenGui
		--// Parametrs
		CREATE_FRAME.AnchorPoint = CREATE_FRAME_SETTINGS.AnchorPoint
		CREATE_FRAME.BackgroundTransparency = CREATE_FRAME_SETTINGS.BackgroundTransparency
		CREATE_FRAME.Position = CREATE_FRAME_SETTINGS.Position
		CREATE_FRAME.Size = CREATE_FRAME_SETTINGS.Size
		CREATE_FRAME.ZIndex = CREATE_FRAME_SETTINGS.Zindex
	end

	local existingFrame = screenGui:FindFirstChild("EggHuntLayer")

	if existingFrame == nil then
		reject()
		return
	end

	existingFrame:Destroy()
	reject()
end

--// Add UIListLayout and UICorner or UIShadow //--
local function addUI(parent, settings)
	settings = settings or {}
	local created = {
		Layout = nil,
		Corner = nil,
		Shadow = nil,
	}
	local function setProps(instance, props)
		for propertyName, value in pairs(props) do
			if propertyName ~= "Name" and value ~= nil then
				pcall(function()
					instance[propertyName] = value
				end)
			end
		end
	end

	--// UIListLayout
	if settings.Layout then
		local layoutSettings = settings.Layout
		if layoutSettings == true then
			layoutSettings = {}
		end
		local layout = Instance.new("UIListLayout")
		layout.Name = layoutSettings.Name or "UIListLayout"
		layout.Parent = parent
		local defaultLayoutSettings = {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 0),
			Wraps = false,
		}
		setProps(layout, defaultLayoutSettings)
		setProps(layout, layoutSettings)
		created.Layout = layout
	end

	--// UICorner
	if settings.Corner then
		local cornerSettings = settings.Corner
		if cornerSettings == true then
			cornerSettings = {}
		elseif typeof(cornerSettings) == "UDim" then
			cornerSettings = {
				CornerRadius = cornerSettings,
			}
		end
		local corner = Instance.new("UICorner")
		corner.Name = cornerSettings.Name or "UICorner"
		corner.Parent = parent
		if cornerSettings.CornerRadius ~= nil then
			pcall(function()
				corner.CornerRadius = cornerSettings.CornerRadius
			end)
		else
			pcall(function()
				corner.CornerRadius = UDim.new(0, 8)
			end)
		end
		local individualCorners = {
			"TopLeftRadius",
			"TopRightRadius",
			"BottomLeftRadius",
			"BottomRightRadius",
		}
		for _, propertyName in ipairs(individualCorners) do
			if cornerSettings[propertyName] ~= nil then
				pcall(function()
					corner[propertyName] = cornerSettings[propertyName]
				end)
			end
		end
		created.Corner = corner
	end

	--// UIShadow
	if settings.Shadow then
		local shadowSettings = settings.Shadow
		if shadowSettings == true then
			shadowSettings = {}
		end
		local success, shadow = pcall(function()
			return Instance.new("UIShadow")
		end)
		if success and shadow then
			shadow.Name = shadowSettings.Name or "UIShadow"
			shadow.Parent = parent
			local defaultShadowSettings = {
				Color = Color3.fromRGB(0, 0, 0),
				BlurRadius = UDim.new(0, 20),
				Transparency = 0.8,
				ZIndex = -1,
			}
			setProps(shadow, defaultShadowSettings)
			setProps(shadow, shadowSettings)
			created.Shadow = shadow
		else
			warn(WARNING_LIST[3])
		end
	end

	return created
end

local UI_STATE = {
	Sections = {},
	SectionOrder = {},
	NavigationButtons = {},
	Buttons = {},
	Lists = {},
	SearchRecords = {},
	SearchResultFrames = {},
	ButtonStates = {},
	ActiveSection = nil,
	LastContentSection = nil,
	MainPanel = nil,
	SearchBox = nil,
	SearchSection = nil,
	SearchContent = nil,
	ConfigInputs = {},
	Sliders = {},
	PriorityInputs = {},
	PriorityByImage = {},
	PushContainer = nil,
	PushNotifications = {},
	ConfigPasteFrame = nil,
	LastCopiedConfig = "",
	SuppressSearchUpdate = false,
}

local copyConfigToImportBox
local loadConfigFromImportBox
local updateConfigControls
local saveCurrentConfig
local loadSavedConfig
local getTokenPriorityByImage
local clearRuntimeCaches

local Sections = {
	Home.CreateSection(IMAGES_ALL[3]),
	{
		Name = "Farming",
		NavigationButton = "Farming",
		Icon = IMAGES_ALL[4],
		Layout = "Double",
		ControlsSlot = "Right",
		ControlsPosition = "AfterLists",
		LeftTitle = "Farming",
		RightTitle = "Farm Helper",

		LeftControls = {
			Lists = {
				{
					Title = "Field: SELECT ONE",
					LayoutOrder = 10,
					SelectPrefix = "Field",
					Placeholder = "SELECT ONE",
					SearchText = "Field Select Bamboo Field",
					Items = {
						{
							Type = "Button",
							Text = "Bamboo Field",
							Image = IMAGES_ALL[11],
							SearchText = "Bamboo Field",
							Default = false,
							Callback = function(selected)
								SETTING.Farming.Selected_Field = selected
							end,
						},
						{
							Type = "Button",
							Text = "Blue Flower Field",
							Image = IMAGES_ALL[12],
							SearchText = "Blue Flower Field",
							Default = false,
							Callback = function(selected)
								SETTING.Farming.Selected_Field = selected
							end,
						},
						{
							Type = "Button",
							Text = "Cactus Field",
							Image = IMAGES_ALL[13],
							SearchText = "Cactus Field",
							Default = false,
							Callback = function(selected)
								SETTING.Farming.Selected_Field = selected
							end,
						},
						{
							Type = "Button",
							Text = "Clover Field",
							Image = IMAGES_ALL[14],
							SearchText = "Clover Field",
							Default = false,
							Callback = function(selected)
								SETTING.Farming.Selected_Field = selected
							end,
						},
						{
							Type = "Button",
							Text = "Coconut Field",
							Image = IMAGES_ALL[15],
							SearchText = "Coconut Field",
							Default = false,
							Callback = function(selected)
								SETTING.Farming.Selected_Field = selected
							end,
						},
						{
							Type = "Button",
							Text = "Dandelion Field",
							Image = IMAGES_ALL[16],
							SearchText = "Dandelion Field",
							Default = false,
							Callback = function(selected)
								SETTING.Farming.Selected_Field = selected
							end,
						},
						{
							Type = "Button",
							Text = "Mountain Top Field",
							Image = IMAGES_ALL[17],
							SearchText = "Mountain Top Field",
							Default = false,
							Callback = function(selected)
								SETTING.Farming.Selected_Field = selected
							end,
						},
						{
							Type = "Button",
							Text = "Mushroom Field",
							Image = IMAGES_ALL[18],
							SearchText = "Mushroom Field",
							Default = false,
							Callback = function(selected)
								SETTING.Farming.Selected_Field = selected
							end,
						},
						{
							Type = "Button",
							Text = "Pepper Patch",
							Image = IMAGES_ALL[19],
							SearchText = "Pepper Patch",
							Default = false,
							Callback = function(selected)
								SETTING.Farming.Selected_Field = selected
							end,
						},
						{
							Type = "Button",
							Text = "Pine Tree Forest",
							Image = IMAGES_ALL[20],
							SearchText = "Pine Tree Forest",
							Default = false,
							Callback = function(selected)
								SETTING.Farming.Selected_Field = selected
							end,
						},
						{
							Type = "Button",
							Text = "Pineapple Patch",
							Image = IMAGES_ALL[21],
							SearchText = "Pineapple Patch",
							Default = false,
							Callback = function(selected)
								SETTING.Farming.Selected_Field = selected
							end,
						},
						{
							Type = "Button",
							Text = "Pumpkin Patch",
							Image = IMAGES_ALL[22],
							SearchText = "Pumpkin Patch",
							Default = false,
							Callback = function(selected)
								SETTING.Farming.Selected_Field = selected
							end,
						},
						{
							Type = "Button",
							Text = "Rose Field",
							Image = IMAGES_ALL[23],
							SearchText = "Rose Field",
							Default = false,
							Callback = function(selected)
								SETTING.Farming.Selected_Field = selected
							end,
						},
						{
							Type = "Button",
							Text = "Spider Field",
							Image = IMAGES_ALL[24],
							SearchText = "Spider Field",
							Default = false,
							Callback = function(selected)
								SETTING.Farming.Selected_Field = selected
							end,
						},
						{
							Type = "Button",
							Text = "Strawberry Field",
							Image = IMAGES_ALL[25],
							SearchText = "Strawberry Field",
							Default = false,
							Callback = function(selected)
								SETTING.Farming.Selected_Field = selected
							end,
						},
						{
							Type = "Button",
							Text = "Stump Field",
							Image = IMAGES_ALL[26],
							SearchText = "Stump Field",
							Default = false,
							Callback = function(selected)
								SETTING.Farming.Selected_Field = selected
							end,
						},
						{
							Type = "Button",
							Text = "Sunflower Field",
							Image = IMAGES_ALL[27],
							SearchText = "Sunflower Field",
							Default = false,
							Callback = function(selected)
								SETTING.Farming.Selected_Field = selected
							end,
						},
					},
				},

				{
					Title = "Priority Tokens: 0-1000",
					LayoutOrder = 20,
					SearchText = "Priority Tokens",
					Items = {
						{
							Type = "Priority",
							Text = "Bear Morph",
							Key = "Bear Morph",
							Images = {
								{ Key = "Black Bear", Image = "rbxassetid://1472491940" },
								{ Key = "Brown Bear", Image = "rbxassetid://1472425802" },
								{ Key = "Polar Bear", Image = "rbxassetid://1472532912" },
								{ Key = "Panda Bear", Image = "rbxassetid://1472571731" },
								{ Key = "Science Bear", Image = "rbxassetid://1489734171" },
								{ Key = "Mother Bear", Image = "rbxassetid://2032949183" },
							},
							Min = 0,
							Max = 1000,
							Default = 500,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Bear Morph",
						},
						{
							Type = "Priority",
							Text = "Token Link",
							Key = "Token Link",
							Images = {
								{ Key = "Token Link", Image = "rbxassetid://1629547638" },
							},
							Min = 0,
							Max = 1000,
							Default = 495,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Token Link",
						},
						{
							Type = "Priority",
							Text = "Inspire",
							Key = "Inspire",
							Images = {
								{ Key = "Inspire", Image = "rbxassetid://2000457501" },
							},
							Min = 0,
							Max = 1000,
							Default = 490,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Inspire",
						},
						{
							Type = "Priority",
							Text = "Buzz Bomb",
							Key = "Buzz Bomb",
							Images = {
								{ Key = "Buzz Bomb", Image = "rbxassetid://1442725244" },
							},
							Min = 0,
							Max = 1000,
							Default = 485,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Buzz Bomb",
						},
						{
							Type = "Priority",
							Text = "Buzz Bomb+",
							Key = "Buzz Bomb+",
							Images = {
								{ Key = "Buzz Bomb+", Image = "rbxassetid://1442764904" },
							},
							Min = 0,
							Max = 1000,
							Default = 480,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Buzz Bomb+",
						},
						{
							Type = "Priority",
							Text = "Blue Boost",
							Key = "Blue Boost",
							Images = {
								{ Key = "Blue Boost", Image = "rbxassetid://1442863423" },
							},
							Min = 0,
							Max = 1000,
							Default = 475,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Blue Boost",
						},
						{
							Type = "Priority",
							Text = "Red Boost",
							Key = "Red Boost",
							Images = {
								{ Key = "Red Boost", Image = "rbxassetid://1442859163" },
							},
							Min = 0,
							Max = 1000,
							Default = 475,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Red Boost",
						},
						{
							Type = "Priority",
							Text = "White Boost",
							Key = "White Boost",
							Images = {
								{ Key = "White Boost", Image = "rbxassetid://3877732821" },
							},
							Min = 0,
							Max = 1000,
							Default = 475,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "White Boost",
						},
						{
							Type = "Priority",
							Text = "Focus",
							Key = "Focus",
							Images = {
								{ Key = "Focus", Image = "rbxassetid://1629649299" },
							},
							Min = 0,
							Max = 1000,
							Default = 465,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Focus",
						},
						{
							Type = "Priority",
							Text = "Pollen Mark",
							Key = "Pollen Mark",
							Images = {
								{ Key = "Pollen Mark", Image = "rbxassetid://2499540966" },
							},
							Min = 0,
							Max = 1000,
							Default = 460,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Pollen Mark",
						},
						{
							Type = "Priority",
							Text = "Honey Mark",
							Key = "Honey Mark",
							Images = {
								{ Key = "Honey Mark", Image = "rbxassetid://2499514197" },
							},
							Min = 0,
							Max = 1000,
							Default = 455,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Honey Mark",
						},
						{
							Type = "Priority",
							Text = "Rage",
							Key = "Rage",
							Images = {
								{ Key = "Rage", Image = "rbxassetid://1442700745" },
							},
							Min = 0,
							Max = 1000,
							Default = 450,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Rage",
						},
						{
							Type = "Priority",
							Text = "Baby Love",
							Key = "Baby Love",
							Images = {
								{ Key = "Baby Love", Image = "rbxassetid://1472256444" },
							},
							Min = 0,
							Max = 1000,
							Default = 445,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Baby Love",
						},
						{
							Type = "Priority",
							Text = "Beamstorm",
							Key = "Beamstorm",
							Images = {
								{ Key = "Beamstorm", Image = "rbxassetid://1671281844" },
							},
							Min = 0,
							Max = 1000,
							Default = 440,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Beamstorm",
						},
						{
							Type = "Priority",
							Text = "Tabby Love",
							Key = "Tabby Love",
							Images = {
								{ Key = "Tabby Love", Image = "rbxassetid://1753904608" },
							},
							Min = 0,
							Max = 1000,
							Default = 435,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Tabby Love",
						},
						{
							Type = "Priority",
							Text = "Scratch",
							Key = "Scratch",
							Images = {
								{ Key = "Scratch", Image = "rbxassetid://1104415222" },
							},
							Min = 0,
							Max = 1000,
							Default = 430,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Scratch",
						},
						{
							Type = "Priority",
							Text = "Glob",
							Key = "Glob",
							Images = {
								{ Key = "Glob", Image = "rbxassetid://177997841" },
							},
							Min = 0,
							Max = 1000,
							Default = 425,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Glob",
						},
						{
							Type = "Priority",
							Text = "Fetch",
							Key = "Fetch",
							Images = {
								{ Key = "Fetch", Image = "rbxassetid://2319100769" },
							},
							Min = 0,
							Max = 1000,
							Default = 420,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Fetch",
						},
						{
							Type = "Priority",
							Text = "Impale",
							Key = "Impale",
							Images = {
								{ Key = "Impale", Image = "rbxassetid://2319083910" },
							},
							Min = 0,
							Max = 1000,
							Default = 415,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Impale",
						},
						{
							Type = "Priority",
							Text = "Red/Blue Pulse",
							Key = "Red/Blue Pulse",
							Images = {
								{ Key = "Red/Blue Pulse", Image = "rbxassetid://1874564120" },
							},
							Min = 0,
							Max = 1000,
							Default = 410,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Red/Blue Pulse",
						},
						{
							Type = "Priority",
							Text = "Blue Bomb",
							Key = "Blue Bomb",
							Images = {
								{ Key = "Blue Bomb", Image = "rbxassetid://1874692303" },
							},
							Min = 0,
							Max = 1000,
							Default = 405,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Blue Bomb",
						},
						{
							Type = "Priority",
							Text = "Red Bomb",
							Key = "Red Bomb",
							Images = {
								{ Key = "Red Bomb", Image = "rbxassetid://1874704640" },
							},
							Min = 0,
							Max = 1000,
							Default = 400,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Red Bomb",
						},
						{
							Type = "Priority",
							Text = "Festive Gift",
							Key = "Festive Gift",
							Images = {
								{ Key = "Festive Gift", Image = "rbxassetid://2652424740" },
							},
							Min = 0,
							Max = 1000,
							Default = 395,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Festive Gift",
						},
						{
							Type = "Priority",
							Text = "Festive Blessing",
							Key = "Festive Blessing",
							Images = {
								{ Key = "Festive Blessing", Image = "rbxassetid://2652424740" },
							},
							Min = 0,
							Max = 1000,
							Default = 390,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Festive Blessing",
						},
						{
							Type = "Priority",
							Text = "Beesmas Cheer",
							Key = "Beesmas Cheer",
							Images = {
								{ Key = "Beesmas Cheer", Image = "rbxassetid://2652364563" },
							},
							Min = 0,
							Max = 1000,
							Default = 385,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Beesmas Cheer",
						},
						{
							Type = "Priority",
							Text = "Rain Cloud",
							Key = "Rain Cloud",
							Images = {
								{ Key = "Rain Cloud", Image = "rbxassetid://3582501342" },
							},
							Min = 0,
							Max = 1000,
							Default = 380,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Rain Cloud",
						},
						{
							Type = "Priority",
							Text = "Tornado",
							Key = "Tornado",
							Images = {
								{ Key = "Tornado", Image = "rbxassetid://3582519526" },
							},
							Min = 0,
							Max = 1000,
							Default = 375,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Tornado",
						},
						{
							Type = "Priority",
							Text = "Inferno",
							Key = "Inferno",
							Images = {
								{ Key = "Inferno", Image = "rbxassetid://4519549299" },
							},
							Min = 0,
							Max = 1000,
							Default = 370,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Inferno",
						},
						{
							Type = "Priority",
							Text = "Flame Fuel",
							Key = "Flame Fuel",
							Images = {
								{ Key = "Flame Fuel", Image = "rbxassetid://4528208186" },
							},
							Min = 0,
							Max = 1000,
							Default = 365,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Flame Fuel",
						},
						{
							Type = "Priority",
							Text = "Summon Frog",
							Key = "Summon Frog",
							Images = {
								{ Key = "Summon Frog", Image = "rbxassetid://4528414666" },
							},
							Min = 0,
							Max = 1000,
							Default = 360,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Summon Frog",
						},
						{
							Type = "Priority",
							Text = "Triangulate",
							Key = "Triangulate",
							Images = {
								{ Key = "Triangulate", Image = "rbxassetid://4519523935" },
							},
							Min = 0,
							Max = 1000,
							Default = 355,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Triangulate",
						},
						{
							Type = "Priority",
							Text = "Mark Surge",
							Key = "Mark Surge",
							Images = {
								{ Key = "Mark Surge", Image = "rbxassetid://4528379338" },
							},
							Min = 0,
							Max = 1000,
							Default = 350,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Mark Surge",
						},
						{
							Type = "Priority",
							Text = "Fuzz Bombs",
							Key = "Fuzz Bombs",
							Images = {
								{ Key = "Fuzz Bombs", Image = "rbxassetid://4889322534" },
							},
							Min = 0,
							Max = 1000,
							Default = 345,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Fuzz Bombs",
						},
						{
							Type = "Priority",
							Text = "Pollen Haze",
							Key = "Pollen Haze",
							Images = {
								{ Key = "Pollen Haze", Image = "rbxassetid://4889470194" },
							},
							Min = 0,
							Max = 1000,
							Default = 340,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Pollen Haze",
						},
						{
							Type = "Priority",
							Text = "Snowglobe Shake",
							Key = "Snowglobe Shake",
							Images = {
								{ Key = "Snowglobe Shake", Image = "rbxassetid://6077155760" },
							},
							Min = 0,
							Max = 1000,
							Default = 335,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Snowglobe Shake",
						},
						{
							Type = "Priority",
							Text = "Festive Mark",
							Key = "Festive Mark",
							Images = {
								{ Key = "Festive Mark", Image = "rbxassetid://6077288982" },
							},
							Min = 0,
							Max = 1000,
							Default = 330,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Festive Mark",
						},
						{
							Type = "Priority",
							Text = "Inflate Baloons",
							Key = "Inflate Baloons",
							Images = {
								{ Key = "Inflate Baloons", Image = "rbxassetid://8083436978" },
							},
							Min = 0,
							Max = 1000,
							Default = 325,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Inflate Baloons",
						},
						{
							Type = "Priority",
							Text = "Surprise Party",
							Key = "Surprise Party",
							Images = {
								{ Key = "Surprise Party", Image = "rbxassetid://8083943936" },
							},
							Min = 0,
							Max = 1000,
							Default = 320,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Surprise Party",
						},
						{
							Type = "Priority",
							Text = "Target Practice",
							Key = "Target Practice",
							Images = {
								{ Key = "Target Practice", Image = "rbxassetid://8173559749" },
							},
							Min = 0,
							Max = 1000,
							Default = 315,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Target Practice",
						},
						{
							Type = "Priority",
							Text = "Glitch",
							Key = "Glitch",
							Images = {
								{ Key = "Glitch", Image = "rbxassetid://5877939956" },
							},
							Min = 0,
							Max = 1000,
							Default = 310,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Glitch",
						},
						{
							Type = "Priority",
							Text = "Mind Hack",
							Key = "Mind Hack",
							Images = {
								{ Key = "Mind Hack", Image = "rbxassetid://5877998606" },
							},
							Min = 0,
							Max = 1000,
							Default = 305,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Mind Hack",
						},
						{
							Type = "Priority",
							Text = "Map Corruption",
							Key = "Map Corruption",
							Images = {
								{ Key = "Map Corruption", Image = "rbxassetid://5877939956" },
							},
							Min = 0,
							Max = 1000,
							Default = 300,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Map Corruption",
						},
						{
							Type = "Priority",
							Text = "Smile",
							Key = "Smile",
							Images = {
								{ Key = "Smile", Image = "rbxassetid://5877939956" },
							},
							Min = 0,
							Max = 1000,
							Default = 295,
							Storage = SETTING.Farming.Priority_Tokens,
							SearchText = "Smile",
						},
					},
				},
			},

			Buttons = {
				{
					Type = "Button",
					Text = "Auto Farm",
					LayoutOrder = 30,
					SearchText = "Auto Farm Farming",
					Default = SETTING.Farming.Auto_Farm,
					Callback = function(enabled)
						SETTING.Farming.Auto_Farm = enabled
					end,
				},
				{
					Type = "Button",
					Text = "Auto Dig",
					LayoutOrder = 40,
					SearchText = "Auto Dig Farming",
					Default = SETTING.Farming.Auto_Dig,
					Callback = function(enabled)
						SETTING.Farming.Auto_Dig = enabled
					end,
				},
				{
					Type = "Button",
					Text = "Auto Sprinkler",
					LayoutOrder = 50,
					SearchText = "Auto Sprinkler Farming",
					Default = SETTING.Farming.Auto_Sprinkler,
					Callback = function(enabled)
						SETTING.Farming.Auto_Sprinkler = enabled
					end,
				},
			},
		},

		RightControls = {
			Buttons = {
				{
					Type = "Button",
					Text = "Auto Sprouts",
					LayoutOrder = 10,
					SearchText = "Auto Sprouts",
					Default = SETTING.Farming.Auto_Sprouts,
					Callback = function(enabled)
						SETTING.Farming.Auto_Sprouts = enabled
					end,
				},
				{
					Type = "Button",
					Text = "ESC Tokens",
					LayoutOrder = 20,
					SearchText = "ESC Tokens",
					Default = SETTING.Farming.ESC_Tokens,
					Callback = function(enabled)
						SETTING.Farming.ESC_Tokens = enabled
					end,
				},
				{
					Type = "Button",
					Text = "Shift Lock",
					LayoutOrder = 30,
					SearchText = "Farm Helper Shift Lock Free Cursor Camera Relative",
					Default = SETTING.Farming.Shift_Lock,
					Callback = function(enabled)
						SETTING.Farming.Shift_Lock = enabled
					end,
				},
				{
					Type = "Button",
					Text = "Wealth Clock",
					LayoutOrder = 40,
					SearchText = "Farm Helper Wealth Clock Hourly Collect E",
					Default = SETTING.Farming.Wealth_Clock,
					Callback = function(enabled)
						SETTING.Farming.Wealth_Clock = enabled
					end,
				},
			},
		},
		SecondaryDouble = {
			LeftTitle = "Face Settings",
			RightTitle = "Convert Settings",
			LeftControls = {
				{
					Type = "Button",
					Text = "Farm Bubbles",
					SearchText = "Face Settings Farm Bubbles",
					Default = SETTING.Farming.Farm_Bubbles,
					Callback = function(enabled)
						SETTING.Farming.Farm_Bubbles = enabled
					end,
				},
				{
					Type = "Button",
					Text = "Farm Petals",
					SearchText = "Face Settings Farm Petals Bloom",
					Default = SETTING.Farming.Farm_Petals,
					Callback = function(enabled)
						SETTING.Farming.Farm_Petals = enabled
					end,
				},
			},
			RightControls = {
				ListsFirst = true,
				Lists = {
					{
						Title = "Mask: Diamond Mask",
						SelectPrefix = "Mask",
						Placeholder = "Diamond Mask",
						SearchText = "Convert Settings Mask Diamond Demon Gummy",
						Items = {
							{
								Type = "Button",
								Text = "Diamond Mask",
								Image = "rbxassetid://2557828875",
								Default = true,
								Callback = function(mask)
									SETTING.Config.Selected_Mask = mask
								end,
							},
							{
								Type = "Button",
								Text = "Demon Mask",
								Image = "rbxassetid://2557829605",
								Callback = function(mask)
									SETTING.Config.Selected_Mask = mask
								end,
							},
							{
								Type = "Button",
								Text = "Gummy Mask",
								Image = "rbxassetid://2557830185",
								Callback = function(mask)
									SETTING.Config.Selected_Mask = mask
								end,
							},
						},
					},
				},
				Controls = {
					{
						Type = "Slider",
						Text = "Convert Pollen %",
						Key = "ConvertPercent",
						Min = 1,
						Max = 100,
						Default = SETTING.Config.Convert_Percent,
						SearchText = "Convert Settings Pollen Percent Capacity",
						Callback = function(value)
							SETTING.Config.Convert_Percent = math.clamp(math.floor(value), 1, 100)
						end,
					},
					{
						Type = "Slider",
						Text = "Convert Time (Minutes)",
						Key = "ConvertMinutes",
						Min = 1,
						Max = 120,
						Default = SETTING.Config.Convert_Minutes,
						SearchText = "Convert Settings Fixed Time Minutes",
						Callback = function(value)
							SETTING.Config.Convert_Minutes = math.clamp(math.floor(value), 1, 120)
						end,
					},
				},
				Buttons = {
					{
						Type = "Button",
						Text = "Convert Balloons",
						SearchText = "Convert Settings Convert Balloons",
						Default = SETTING.Config.Convert_Balloons,
						Callback = function(enabled)
							SETTING.Config.Convert_Balloons = enabled
						end,
					},
					{
						Type = "Button",
						Text = "Auto Honey Mask",
						SearchText = "Convert Settings Auto Honey Mask",
						Default = SETTING.Config.Auto_Honey_Mask,
						Callback = function(enabled)
							SETTING.Config.Auto_Honey_Mask = enabled
						end,
					},
				},
			},
		},

		SecondaryDouble = {
			LeftTitle = "Puffshrooms",
			LeftOpened = true,
			HideRight = true,
			LeftControls = {
				{
					Type = "Button",
					Text = "Auto Puffshrooms",
					Default = SETTING.Farming.Auto_Puffshrooms,
					SearchText = "Puffshrooms Auto Farm Happenings",
					Callback = function(enabled)
						SETTING.Farming.Auto_Puffshrooms = enabled
					end,
				},
				{
					Type = "Button",
					Text = "Collect Puff Loot",
					Default = SETTING.Farming.Puff_Collect_Loot,
					SearchText = "Puffshrooms Collect Loot Tokens",
					Callback = function(enabled)
						SETTING.Farming.Puff_Collect_Loot = enabled
					end,
				},
				{
					Type = "Button",
					Text = "Prefer Rarity",
					Default = SETTING.Farming.Puff_Prefer_Rarity,
					SearchText = "Puffshrooms Prefer Mythic Legendary Epic Rare",
					Callback = function(enabled)
						SETTING.Farming.Puff_Prefer_Rarity = enabled
					end,
				},
				{
					Type = "Slider",
					Text = "Puff Min Level",
					Key = "PuffMinLevel",
					Min = 1,
					Max = 30,
					Default = SETTING.Farming.Puff_Min_Level,
					Callback = function(value)
						SETTING.Farming.Puff_Min_Level = math.floor(value)
					end,
				},
				{
					Type = "Slider",
					Text = "Puff Loot Seconds",
					Key = "PuffLootSeconds",
					Min = 0,
					Max = 30,
					Default = SETTING.Farming.Puff_Loot_Seconds,
					Callback = function(value)
						SETTING.Farming.Puff_Loot_Seconds = math.floor(value)
					end,
				},
				Lists = {
					{
						Title = "Min Rarity",
						SelectPrefix = "Min Rarity",
						Placeholder = SETTING.Farming.Puff_Min_Rarity,
						Items = (function()
							local items = {}
							for _, rarity in ipairs({ "Common", "Rare", "Epic", "Legendary", "Mythic" }) do
								table.insert(items, { Type = "Button", Text = rarity, Default = rarity == SETTING.Farming.Puff_Min_Rarity, Callback = function(selected) SETTING.Farming.Puff_Min_Rarity = selected end })
							end
							return items
						end)(),
					},
					{
						Title = "Puff Fields",
						SelectPrefix = "Puff Fields",
						Placeholder = SETTING.Farming.Puff_Fields,
						Items = (function()
							local items = {}
							for _, fieldName in ipairs({ "All", "Bamboo Field", "Blue Flower Field", "Cactus Field", "Clover Field", "Coconut Field", "Dandelion Field", "Mountain Top Field", "Mushroom Field", "Pepper Patch", "Pine Tree Forest", "Pineapple Patch", "Pumpkin Patch", "Rose Field", "Spider Field", "Strawberry Field", "Stump Field", "Sunflower Field" }) do
								table.insert(items, { Type = "Button", Text = fieldName, Default = fieldName == SETTING.Farming.Puff_Fields, Callback = function(selected) SETTING.Farming.Puff_Fields = selected end })
							end
							return items
						end)(),
					},
				},
			},
		},
	},
	{
		Name = "Combat",
		NavigationButton = "Combat",
		Icon = IMAGES_ALL[5],
		Layout = "Double",
		LeftOpened = true,
		RightOpened = true,
		LeftTitle = "Bosses",
		RightTitle = "Memory Match",
		LeftControls = {
			{
				Type = "Button",
				Text = "Farm Mondo Chick",
				Default = SETTING.Bosses.Farm_Mondo_Chick,
				Inline = true,
				StatusProvider = getMondoTimerText,
				SearchText = "Bosses Mondo Chick Mountain Top Field",
				Callback = function(enabled)
					SETTING.Bosses.Farm_Mondo_Chick = enabled
				end,
			},
			{
				Type = "Button",
				Text = "Collect Tokens Mondo",
				Default = SETTING.Bosses.Collect_Mondo_Tokens,
				Inline = true,
				SearchText = "Bosses Collect Tokens Mondo 30 Seconds",
				Callback = function(enabled)
					SETTING.Bosses.Collect_Mondo_Tokens = enabled
				end,
			},
			{
				Type = "Button",
				Text = "Farm Windy Bee",
				Default = SETTING.Bosses.Farm_Windy_Bee,
				Inline = true,
				SearchText = "Bosses Windy Bee Clouds",
				Callback = function(enabled)
					SETTING.Bosses.Farm_Windy_Bee = enabled
				end,
			},
			{
				Type = "Button",
				Text = "Farm Vicious Bee",
				Default = SETTING.Bosses.Farm_Vicious_Bee,
				Inline = true,
				SearchText = "Bosses Vicious Bee Gifted Spike",
				Callback = function(enabled)
					SETTING.Bosses.Farm_Vicious_Bee = enabled
				end,
			},
			{
				Type = "Button",
				Text = "Farm Stump Snail",
				Default = SETTING.Bosses.Farm_Stump_Snail,
				Inline = true,
				StatusProvider = function()
					return getSpawnerTimerText("StumpSnail")
				end,
				SearchText = "Bosses Stump Snail Stump Field",
				Callback = function(enabled)
					SETTING.Bosses.Farm_Stump_Snail = enabled
				end,
			},
		},
		RightControls = {
			{
				Type = "Button",
				Text = "Auto Memory Match",
				Default = SETTING.MemoryMatch.Auto,
				Inline = true,
				SearchText = "Memory Match Auto Solve Pairs",
				Callback = function(enabled)
					SETTING.MemoryMatch.Auto = enabled
				end,
			},
			{
				Type = "Button",
				Text = "Show Closed Images",
				Default = SETTING.MemoryMatch.Show_Images,
				Inline = true,
				SearchText = "Memory Match Reveal Known Images Cards",
				Callback = function(enabled)
					SETTING.MemoryMatch.Show_Images = enabled
				end,
			},
			{
				Type = "Action",
				Text = "Memory Match",
				Callback = function()
					requestMemoryMatch("Basic")
				end,
			},
			{
				Type = "Action",
				Text = "Mega Memory Match",
				Callback = function()
					requestMemoryMatch("BadgeGuild")
				end,
			},
			{
				Type = "Action",
				Text = "Night Memory Match",
				Callback = function()
					requestMemoryMatch("Night")
				end,
			},
			{
				Type = "Action",
				Text = "Extreme Memory Match",
				Callback = function()
					requestMemoryMatch("35Zone")
				end,
			},
		},
		Controls = {},
		Lists = {},
	},
	{
		Name = "Quests",
		NavigationButton = "Quests",
		Icon = IMAGES_ALL[6],
		Lists = {},
	},
	{
		Name = "Planters",
		NavigationButton = "Planters",
		Icon = IMAGES_ALL[7],
		Lists = {},
	},
	{
		Name = "Toys",
		NavigationButton = "Toys",
		Icon = IMAGES_ALL[8],
		Lists = {},
	},
	{
		Name = "Config",
		NavigationButton = "Config",
		Icon = IMAGES_ALL[9],
		Layout = "Double",
		LeftOpened = true,
		RightOpened = true,
		LeftTitle = "Configuration",
		RightTitle = "Config Settings",
		LeftControls = {
			{
				Type = "Slider",
				Text = "Hive Slot",
				Key = "HiveSlot",
				Min = 1,
				Max = 6,
				Default = SETTING.Config.Hive_Slot,
				SearchText = "Hive Slot Configuration",
				Callback = function(value)
					SETTING.Config.Hive_Slot = math.clamp(math.floor(value), 1, 6)
				end,
			},
			{
				Type = "Button",
				Text = "Auto Hive",
				SearchText = "Auto Hive Configuration",
				Default = SETTING.Config.Auto_Hive,
				Callback = function(enabled)
					SETTING.Config.Auto_Hive = enabled
				end,
			},
			{
				Type = "Button",
				Text = "Auto Rejoin",
				SearchText = "Auto Rejoin Configuration",
				Default = SETTING.Config.Auto_Rejoin,
				Callback = function(enabled)
					SETTING.Config.Auto_Rejoin = enabled
				end,
			},
			{
				Type = "TextBox",
				Text = "VIP Link",
				Key = "VIPServerLink",
				Wide = true,
				Value = SETTING.Config.VIP_Server_Link,
				Placeholder = "Optional private server link",
				SearchText = "VIP Private Server Link Auto Rejoin",
				Callback = function(value)
					SETTING.Config.VIP_Server_Link = tostring(value or ""):match("^%s*(.-)%s*$") or ""
				end,
			},
			{
				Type = "Action",
				Text = "COPY CONFIG",
				SearchText = "Copy Config Export Settings",
				Callback = function(buttonRecord)
					if copyConfigToImportBox then
						copyConfigToImportBox(buttonRecord)
					end
				end,
			},
			{
				Type = "Action",
				Text = "PASTE CONFIG",
				SearchText = "Paste Config Import Settings",
				Callback = function(buttonRecord)
					if loadConfigFromImportBox then
						loadConfigFromImportBox(buttonRecord)
					end
				end,
			},
		},
		RightControls = {
			{
				Type = "Slider",
				Text = "Speed",
				Key = "Speed",
				Min = 5,
				Max = 120,
				Default = SETTING.Config.Speed,
				SearchText = "Speed Config Movement",
				Callback = function(value)
					SETTING.Config.Speed = value
					local character = SERVICE.Player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					if humanoid then
						humanoid.WalkSpeed = value
					end
				end,
			},
			{
				Type = "Label",
				Text = "Normal Speed <=80",
				SearchText = "Speed Warning Recommended",
			},
			{
				Type = "Button",
				Text = "Anti AFK",
				SearchText = "Anti AFK Config",
				Default = SETTING.Config.Anti_AFK,
				Callback = function(enabled)
					SETTING.Config.Anti_AFK = enabled
				end,
			},
			{
				Type = "Button",
				Text = "Show Player List (Tab)",
				SearchText = "Tab Player List Config",
				Default = SETTING.Config.Show_Player_List,
				Callback = function(enabled)
					SETTING.Config.Show_Player_List = enabled
					setPlayerListEnabled(enabled)
				end,
			},
			{
				Type = "Action",
				Text = "CLEAR CACHE",
				SearchText = "CLEAR CACHE",
				Callback = function(buttonRecord)
					if clearRuntimeCaches then
						clearRuntimeCaches(buttonRecord)
					end
				end,
			},
		},
		Controls = {},
		Lists = {},
		SecondarySingle = {
			Title = "Optimization BSS",
			Opened = true,
			Controls = {
				{
					Type = "Button",
					Text = "Minimum Render Distance",
					Default = SETTING.Config.Minimum_Render,
					HalfWide = true,
					SearchText = "Optimization BSS Render Distance Quality",
					Callback = function(enabled)
						SETTING.Config.Minimum_Render = enabled
						setMinimumRender(enabled)
					end,
				},
				{
					Type = "Button",
					Text = "Hide Decorations",
					Default = SETTING.Config.Hide_Decorations,
					HalfWide = true,
					SearchText = "Optimization BSS Decorations",
					Callback = function(enabled)
						SETTING.Config.Hide_Decorations = enabled
						setFoldersHidden({ "Decorations", "FieldDecos" }, enabled)
					end,
				},
				{
					Type = "Button",
					Text = "Hide FieldDecos",
					Default = SETTING.Config.Hide_Field_Decos,
					HalfWide = true,
					SearchText = "Optimization BSS FieldDecos TopTexture Transparency",
					Callback = function(enabled)
						SETTING.Config.Hide_Field_Decos = enabled
						setFieldDecosHidden(enabled)
					end,
				},
				{
					Type = "Button",
					Text = "Hide Fields",
					Default = SETTING.Config.Hide_Fields,
					HalfWide = true,
					SearchText = "Optimization BSS Flowers Fields TopTexture",
					Callback = function(enabled)
						SETTING.Config.Hide_Fields = enabled
						setFieldsHidden(enabled)
					end,
				},
				{
					Type = "Button",
					Text = "Disable Shadows",
					Default = SETTING.Config.Disable_Shadows,
					HalfWide = true,
					SearchText = "Optimization BSS Shadows Lighting",
					Callback = function(enabled)
						SETTING.Config.Disable_Shadows = enabled
						setShadowsDisabled(enabled)
					end,
				},
				{
					Type = "Button",
					Text = "Low Fog & Effects",
					Default = SETTING.Config.Low_Fog_Effects,
					HalfWide = true,
					SearchText = "Optimization BSS FogEnd 200 Effects Terrain",
					Callback = function(enabled)
						SETTING.Config.Low_Fog_Effects = enabled
						setLowFogEffects(enabled)
					end,
				},
			},
		},
	},
}

local MAIN_TWEEN_INFO = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local BUTTON_TWEEN_INFO = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CONFIG_FOLDER = "Arcada"
local CONFIG_FILE_PATH = CONFIG_FOLDER .. "/config.json"
local CONFIG_FILE_FALLBACK_PATH = "Arcada_config.json"

local function clearArray(array)
	for index = #array, 1, -1 do
		array[index] = nil
	end
end

local function clearDictionary(dictionary)
	for key in pairs(dictionary) do
		dictionary[key] = nil
	end
end

local function disconnectConnections(connections)
	for _, connection in ipairs(connections) do
		if connection and connection.Disconnect then
			connection:Disconnect()
		end
	end
end

local function normalizeSearchText(text)
	return string.lower(tostring(text or ""))
end

local function getSearchText(config, fallback)
	return normalizeSearchText((config and config.SearchText) or fallback or "")
end

local function getLayoutOrder(config)
	if type(config) ~= "table" then
		return 0
	end

	local layoutOrder = config.LayoutOrder
	if layoutOrder == nil and type(config.Layout) == "number" then
		layoutOrder = config.Layout
	elseif layoutOrder == nil and type(config.Layout) == "table" then
		layoutOrder = config.Layout.LayoutOrder or config.Layout.Order
	end

	return if type(layoutOrder) == "number" then layoutOrder else 0
end

local function normalizePriorityImageKey(image)
	local text = tostring(image or "")
	text = string.match(text, "^%s*(.-)%s*$") or ""
	local assetId = string.match(text, "rbxassetid://(%d+)")
		or string.match(text, "[?&]id=(%d+)")
		or string.match(text, "^%d+$")

	return if assetId then assetId else string.lower(text)
end

local function getPriorityImages(config)
	local images = {}
	local configuredImages = config.Images
	if type(configuredImages) ~= "table" then
		configuredImages = if config.Image ~= nil then { config.Image } else {}
	end

	for index, configuredImage in ipairs(configuredImages) do
		local image = configuredImage
		local imageKey = tostring(index)
		if type(configuredImage) == "table" then
			image = configuredImage.Image or configuredImage.AssetId or configuredImage.Id
			imageKey = tostring(configuredImage.Key or configuredImage.Name or index)
		end

		if image ~= nil and tostring(image) ~= "" then
			local imageText = tostring(image)
			if string.match(imageText, "^%d+$") then
				imageText = "rbxassetid://" .. imageText
			end
			table.insert(images, {
				Key = imageKey,
				Image = imageText,
				LookupKey = normalizePriorityImageKey(imageText),
			})
		end
	end

	return images
end

-- Returns: priority value, priority group key, matched image key, priority record.
getTokenPriorityByImage = function(image)
	local binding = UI_STATE.PriorityByImage[normalizePriorityImageKey(image)]
	if not binding then
		return nil
	end

	return binding.Record.Value, binding.Record.Key, binding.Image.Key, binding.Record
end

local function hasAncestorNamed(instance, ancestorName)
	local current = instance

	while current do
		if current.Name == ancestorName then
			return true
		end
		current = current.Parent
	end

	return false
end

local function addSearchRecord(record)
	table.insert(UI_STATE.SearchRecords, record)
end

local function getSectionButtons(sectionConfig)
	local buttons = {}

	if type(sectionConfig.Buttons) == "table" then
		for _, itemConfig in ipairs(sectionConfig.Buttons) do
			table.insert(buttons, itemConfig)
		end
	end

	for _, itemConfig in ipairs(sectionConfig) do
		if type(itemConfig) == "table" and itemConfig.Type == "Button" then
			table.insert(buttons, itemConfig)
		end
	end

	return buttons
end

local function getSectionControls(sectionConfig)
	local controls = getSectionButtons(sectionConfig)

	if type(sectionConfig.Controls) == "table" then
		for _, itemConfig in ipairs(sectionConfig.Controls) do
			table.insert(controls, itemConfig)
		end
	end

	return controls
end

local function encodeCurrentConfig()
	if not SERVICE.HttpService then
		return ""
	end

	local success, result = pcall(function()
		return SERVICE.HttpService:JSONEncode({
			Farming = {
				Auto_Farm = SETTING.Farming.Auto_Farm,
				Auto_Sprinkler = SETTING.Farming.Auto_Sprinkler,
				Auto_Dig = SETTING.Farming.Auto_Dig,
				Auto_Sprouts = SETTING.Farming.Auto_Sprouts,
				ESC_Tokens = SETTING.Farming.ESC_Tokens,
				Selected_Field = SETTING.Farming.Selected_Field,
				Farm_Bubbles = SETTING.Farming.Farm_Bubbles,
				Farm_Petals = SETTING.Farming.Farm_Petals,
				Shift_Lock = SETTING.Farming.Shift_Lock,
				Wealth_Clock = SETTING.Farming.Wealth_Clock,
				Auto_Puffshrooms = SETTING.Farming.Auto_Puffshrooms,
				Puff_Collect_Loot = SETTING.Farming.Puff_Collect_Loot,
				Puff_Prefer_Rarity = SETTING.Farming.Puff_Prefer_Rarity,
				Puff_Min_Level = SETTING.Farming.Puff_Min_Level,
				Puff_Min_Rarity = SETTING.Farming.Puff_Min_Rarity,
				Puff_Loot_Seconds = SETTING.Farming.Puff_Loot_Seconds,
				Puff_Fields = SETTING.Farming.Puff_Fields,
				Priority_Tokens = SETTING.Farming.Priority_Tokens,
			},
			Config = {
				Speed = SETTING.Config.Speed,
				Anti_AFK = SETTING.Config.Anti_AFK,
				Selected_Mask = SETTING.Config.Selected_Mask,
				Auto_Honey_Mask = SETTING.Config.Auto_Honey_Mask,
				Convert_Balloons = SETTING.Config.Convert_Balloons,
				Convert_Percent = SETTING.Config.Convert_Percent,
				Convert_Minutes = SETTING.Config.Convert_Minutes,
				Hive_Slot = SETTING.Config.Hive_Slot,
				Auto_Hive = SETTING.Config.Auto_Hive,
				Auto_Rejoin = SETTING.Config.Auto_Rejoin,
				VIP_Server_Link = SETTING.Config.VIP_Server_Link,
				Show_Player_List = SETTING.Config.Show_Player_List,
				Minimum_Render = SETTING.Config.Minimum_Render,
				Hide_Decorations = SETTING.Config.Hide_Decorations,
				Hide_Field_Decos = SETTING.Config.Hide_Field_Decos,
				Hide_Fields = SETTING.Config.Hide_Fields,
				Disable_Shadows = SETTING.Config.Disable_Shadows,
				Low_Fog_Effects = SETTING.Config.Low_Fog_Effects,
			},
			Bosses = {
				Farm_Mondo_Chick = SETTING.Bosses.Farm_Mondo_Chick,
				Collect_Mondo_Tokens = SETTING.Bosses.Collect_Mondo_Tokens,
				Farm_Windy_Bee = SETTING.Bosses.Farm_Windy_Bee,
				Farm_Vicious_Bee = SETTING.Bosses.Farm_Vicious_Bee,
				Farm_Stump_Snail = SETTING.Bosses.Farm_Stump_Snail,
			},
			MemoryMatch = {
				Auto = SETTING.MemoryMatch.Auto,
				Show_Images = SETTING.MemoryMatch.Show_Images,
			},
		})
	end)

	if success then
		return result
	end

	warn(result)
	return ""
end

local function applyImportedConfig(encodedConfig)
	if not SERVICE.HttpService or encodedConfig == "" then
		return false
	end

	local success, data = pcall(function()
		return SERVICE.HttpService:JSONDecode(encodedConfig)
	end)
	if not success or type(data) ~= "table" then
		warn("config decode failed")
		return false
	end

	if type(data.Farming) == "table" then
		if data.Farming.Auto_Farm ~= nil then
			SETTING.Farming.Auto_Farm = data.Farming.Auto_Farm == true
		end
		if data.Farming.Auto_Sprinkler ~= nil then
			SETTING.Farming.Auto_Sprinkler = data.Farming.Auto_Sprinkler == true
		end
		if data.Farming.Auto_Dig ~= nil then
			SETTING.Farming.Auto_Dig = data.Farming.Auto_Dig == true
		end
		if data.Farming.Auto_Sprouts ~= nil then
			SETTING.Farming.Auto_Sprouts = data.Farming.Auto_Sprouts == true
		end
		if data.Farming.ESC_Tokens ~= nil then
			SETTING.Farming.ESC_Tokens = data.Farming.ESC_Tokens == true
		end
		if data.Farming.Selected_Field ~= nil then
			SETTING.Farming.Selected_Field = tostring(data.Farming.Selected_Field)
		end
		if data.Farming.Farm_Bubbles ~= nil then
			SETTING.Farming.Farm_Bubbles = data.Farming.Farm_Bubbles == true
		end
		if data.Farming.Farm_Petals ~= nil then
			SETTING.Farming.Farm_Petals = data.Farming.Farm_Petals == true
		end
		if data.Farming.Shift_Lock ~= nil then
			SETTING.Farming.Shift_Lock = data.Farming.Shift_Lock == true
		end
		if data.Farming.Wealth_Clock ~= nil then
			SETTING.Farming.Wealth_Clock = data.Farming.Wealth_Clock == true
		end
		if data.Farming.Auto_Puffshrooms ~= nil then
			SETTING.Farming.Auto_Puffshrooms = data.Farming.Auto_Puffshrooms == true
		end
		if data.Farming.Puff_Collect_Loot ~= nil then
			SETTING.Farming.Puff_Collect_Loot = data.Farming.Puff_Collect_Loot == true
		end
		if data.Farming.Puff_Prefer_Rarity ~= nil then
			SETTING.Farming.Puff_Prefer_Rarity = data.Farming.Puff_Prefer_Rarity == true
		end
		SETTING.Farming.Puff_Min_Level =
			math.clamp(math.floor(tonumber(data.Farming.Puff_Min_Level) or SETTING.Farming.Puff_Min_Level), 1, 30)
		SETTING.Farming.Puff_Loot_Seconds =
			math.clamp(math.floor(tonumber(data.Farming.Puff_Loot_Seconds) or SETTING.Farming.Puff_Loot_Seconds), 0, 30)
		if data.Farming.Puff_Min_Rarity ~= nil then
			SETTING.Farming.Puff_Min_Rarity = tostring(data.Farming.Puff_Min_Rarity)
		end
		if data.Farming.Puff_Fields ~= nil then
			SETTING.Farming.Puff_Fields = tostring(data.Farming.Puff_Fields)
		end
		if type(data.Farming.Priority_Tokens) == "table" then
			for key, priority in pairs(data.Farming.Priority_Tokens) do
				local numericPriority = tonumber(priority)
				if numericPriority then
					SETTING.Farming.Priority_Tokens[tostring(key)] = math.clamp(math.floor(numericPriority), 0, 1000)
				end
			end
		end
	end

	if type(data.Config) == "table" then
		if data.Config.Speed ~= nil then
			local speed = tonumber(data.Config.Speed)
			if speed then
				SETTING.Config.Speed = speed
			end
		end
		if data.Config.Anti_AFK ~= nil then
			SETTING.Config.Anti_AFK = data.Config.Anti_AFK == true
		end
		if
			data.Config.Selected_Mask == "Diamond Mask"
			or data.Config.Selected_Mask == "Demon Mask"
			or data.Config.Selected_Mask == "Gummy Mask"
		then
			SETTING.Config.Selected_Mask = data.Config.Selected_Mask
		end
		if data.Config.Auto_Honey_Mask ~= nil then
			SETTING.Config.Auto_Honey_Mask = data.Config.Auto_Honey_Mask == true
		end
		if data.Config.Convert_Balloons ~= nil then
			SETTING.Config.Convert_Balloons = data.Config.Convert_Balloons == true
		end
		if data.Config.Convert_Percent ~= nil then
			SETTING.Config.Convert_Percent =
				math.clamp(math.floor(tonumber(data.Config.Convert_Percent) or 100), 1, 100)
		end
		if data.Config.Convert_Minutes ~= nil then
			SETTING.Config.Convert_Minutes = math.clamp(math.floor(tonumber(data.Config.Convert_Minutes) or 20), 1, 120)
		end
		if data.Config.Hive_Slot ~= nil then
			SETTING.Config.Hive_Slot = math.clamp(math.floor(tonumber(data.Config.Hive_Slot) or 4), 1, 6)
		end
		if data.Config.Auto_Hive ~= nil then
			SETTING.Config.Auto_Hive = data.Config.Auto_Hive == true
		end
		if data.Config.Auto_Rejoin ~= nil then
			SETTING.Config.Auto_Rejoin = data.Config.Auto_Rejoin == true
		end
		if data.Config.VIP_Server_Link ~= nil then
			SETTING.Config.VIP_Server_Link = tostring(data.Config.VIP_Server_Link)
		end
		for _, key in ipairs({
			"Show_Player_List",
			"Minimum_Render",
			"Hide_Decorations",
			"Hide_Field_Decos",
			"Hide_Fields",
			"Disable_Shadows",
			"Low_Fog_Effects",
		}) do
			if data.Config[key] ~= nil then
				SETTING.Config[key] = data.Config[key] == true
			end
		end
	end

	if type(data.Bosses) == "table" then
		for _, key in ipairs({
			"Farm_Mondo_Chick",
			"Collect_Mondo_Tokens",
			"Farm_Windy_Bee",
			"Farm_Vicious_Bee",
			"Farm_Stump_Snail",
		}) do
			if data.Bosses[key] ~= nil then
				SETTING.Bosses[key] = data.Bosses[key] == true
			end
		end
	end
	if type(data.MemoryMatch) == "table" then
		if data.MemoryMatch.Auto ~= nil then
			SETTING.MemoryMatch.Auto = data.MemoryMatch.Auto == true
		end
		if data.MemoryMatch.Show_Images ~= nil then
			SETTING.MemoryMatch.Show_Images = data.MemoryMatch.Show_Images == true
		end
	end

	return true
end

local function getEnvironmentValue(valueName)
	local checks = {}

	table.insert(checks, function()
		if getgenv then
			return getgenv()[valueName]
		end
	end)
	table.insert(checks, function()
		if getrenv then
			return getrenv()[valueName]
		end
	end)
	table.insert(checks, function()
		if getfenv then
			local env = getfenv(0)
			return env and env[valueName]
		end
	end)
	table.insert(checks, function()
		if getfenv then
			local env = getfenv(1)
			return env and env[valueName]
		end
	end)
	table.insert(checks, function()
		if shared then
			return shared[valueName]
		end
	end)
	table.insert(checks, function()
		if _G then
			return _G[valueName]
		end
	end)

	for _, check in ipairs(checks) do
		local success, value = pcall(check)
		if success and value ~= nil then
			return value
		end
	end

	return nil
end

local function callClipboardWriter(writer, text)
	if type(writer) ~= "function" then
		return false
	end

	local success = pcall(writer, text)
	return success == true
end

local function callDirectClipboardWriter(writerName, text)
	local success = false
	if writerName == "setclipboard" then
		success = pcall(function()
			setclipboard(text)
		end)
	elseif writerName == "toclipboard" then
		success = pcall(function()
			toclipboard(text)
		end)
	elseif writerName == "set_clipboard" then
		success = pcall(function()
			set_clipboard(text)
		end)
	end

	return success == true
end

local function writeClipboard(text)
	text = tostring(text or "")
	if text == "" then
		return false
	end

	if callDirectClipboardWriter("setclipboard", text) then
		return true
	end
	if callDirectClipboardWriter("toclipboard", text) then
		return true
	end
	if callDirectClipboardWriter("set_clipboard", text) then
		return true
	end

	if callClipboardWriter(getEnvironmentValue("setclipboard"), text) then
		return true
	end
	if callClipboardWriter(getEnvironmentValue("toclipboard"), text) then
		return true
	end
	if callClipboardWriter(getEnvironmentValue("set_clipboard"), text) then
		return true
	end

	local syn = getEnvironmentValue("syn")
	if type(syn) == "table" then
		if callClipboardWriter(syn.write_clipboard, text) then
			return true
		end
		if callClipboardWriter(syn.set_clipboard, text) then
			return true
		end
	end

	local clipboard = getEnvironmentValue("clipboard") or getEnvironmentValue("Clipboard")
	if type(clipboard) == "table" then
		if callClipboardWriter(clipboard.set, text) then
			return true
		end
		if callClipboardWriter(clipboard.write, text) then
			return true
		end
		if callClipboardWriter(clipboard.Set, text) then
			return true
		end
		if callClipboardWriter(clipboard.Write, text) then
			return true
		end
	end

	if SERVICE.GuiService then
		local success = pcall(function()
			if SERVICE.GuiService.CopyTextToClipboard then
				SERVICE.GuiService:CopyTextToClipboard(text)
			else
				error("CopyTextToClipboard unavailable")
			end
		end)
		if success then
			return true
		end
	end

	if SERVICE.StarterGui then
		local success = pcall(function()
			SERVICE.StarterGui:SetCore("SetClipboard", text)
		end)
		if success then
			return true
		end
	end

	return false
end

local function readClipboard()
	local readers = {
		getEnvironmentValue("getclipboard"),
		getEnvironmentValue("get_clipboard"),
	}

	table.insert(readers, function()
		return getclipboard()
	end)
	table.insert(readers, function()
		return get_clipboard()
	end)

	local syn = getEnvironmentValue("syn")
	if type(syn) == "table" then
		table.insert(readers, syn.read_clipboard)
		table.insert(readers, syn.get_clipboard)
	end

	local clipboard = getEnvironmentValue("clipboard") or getEnvironmentValue("Clipboard")
	if type(clipboard) == "table" then
		table.insert(readers, clipboard.get)
		table.insert(readers, clipboard.read)
		table.insert(readers, clipboard.Get)
		table.insert(readers, clipboard.Read)
	end

	for _, reader in ipairs(readers) do
		if type(reader) == "function" then
			local success, result = pcall(reader)
			if success and type(result) == "string" and result ~= "" then
				return result
			end
		end
	end

	return ""
end

local function ensureConfigFolder()
	local makefolder = getEnvironmentValue("makefolder")
	if type(makefolder) ~= "function" then
		return false
	end

	local isfolder = getEnvironmentValue("isfolder")
	if type(isfolder) == "function" then
		local checkSuccess, exists = pcall(isfolder, CONFIG_FOLDER)
		if checkSuccess and exists then
			return true
		end
	end

	local success = pcall(makefolder, CONFIG_FOLDER)
	return success == true
end

local function writePersistentConfig(encodedConfig)
	encodedConfig = tostring(encodedConfig or "")
	if encodedConfig == "" then
		return false
	end

	local writefile = getEnvironmentValue("writefile")
	if type(writefile) ~= "function" then
		return false
	end

	ensureConfigFolder()

	local success = pcall(writefile, CONFIG_FILE_PATH, encodedConfig)
	if success then
		return true
	end

	success = pcall(writefile, CONFIG_FILE_FALLBACK_PATH, encodedConfig)
	return success == true
end

local function readPersistentConfig()
	local readfile = getEnvironmentValue("readfile")
	if type(readfile) ~= "function" then
		return ""
	end

	local isfile = getEnvironmentValue("isfile")
	local function readPath(path)
		if type(isfile) == "function" then
			local checkSuccess, exists = pcall(isfile, path)
			if checkSuccess and not exists then
				return ""
			end
		end

		local success, result = pcall(readfile, path)
		if success and type(result) == "string" then
			return result
		end

		return ""
	end

	local encodedConfig = readPath(CONFIG_FILE_PATH)
	if encodedConfig ~= "" then
		return encodedConfig
	end

	return readPath(CONFIG_FILE_FALLBACK_PATH)
end

saveCurrentConfig = function()
	local encodedConfig = encodeCurrentConfig()
	if encodedConfig == "" then
		return false
	end

	UI_STATE.LastCopiedConfig = encodedConfig
	return writePersistentConfig(encodedConfig)
end

loadSavedConfig = function()
	local encodedConfig = readPersistentConfig()
	if encodedConfig == "" then
		return false
	end

	local applied = applyImportedConfig(encodedConfig)
	if applied then
		UI_STATE.LastCopiedConfig = encodedConfig
	end

	return applied
end

local pendingConfigSaveVersion = 0
local function scheduleConfigSave(delaySeconds)
	pendingConfigSaveVersion += 1
	local version = pendingConfigSaveVersion

	task.delay(delaySeconds or 0.35, function()
		if version == pendingConfigSaveVersion and saveCurrentConfig then
			saveCurrentConfig()
		end
	end)
end

local function flashButtonLabel(buttonRecord, text, seconds)
	if not buttonRecord or not buttonRecord.Label then
		return
	end

	local label = buttonRecord.Label
	local originalText = label.Text
	label.Text = text
	task.delay(seconds or 1, function()
		if label.Parent then
			label.Text = originalText
		end
	end)
end

local function showPushNotification(text, color, lifetime)
	local container = UI_STATE.PushContainer
	if not container or not container.Parent then
		return
	end

	for index = #UI_STATE.PushNotifications, 1, -1 do
		local item = UI_STATE.PushNotifications[index]
		if not item or not item.Parent then
			table.remove(UI_STATE.PushNotifications, index)
		end
	end
	while #UI_STATE.PushNotifications >= 7 do
		local oldNotification = table.remove(UI_STATE.PushNotifications, 1)
		if oldNotification and oldNotification.Parent then
			oldNotification:Destroy()
		end
	end

	local notification = Instance.new("Frame")
	notification.Name = "Frame"
	notification.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
	notification.BackgroundTransparency = 0.05
	notification.Size = UDim2.new(0, 90, 0, 35)
	notification.ZIndex = 10001
	notification.Parent = container
	table.insert(UI_STATE.PushNotifications, notification)

	addUI(notification, {
		Corner = {
			TopLeftRadius = UDim.new(0.26, 0),
			TopRightRadius = UDim.new(0.26, 0),
			BottomLeftRadius = UDim.new(0.26, 0),
			BottomRightRadius = UDim.new(0.26, 0),
		},
		Shadow = {
			Color = Color3.fromRGB(0, 0, 0),
			BlurRadius = UDim.new(0, 20),
			Transparency = 0.8,
			ZIndex = 9999,
		},
	})

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "TextLabel"
	textLabel.BackgroundTransparency = 1
	textLabel.Position = UDim2.new(0.081, 0, 0.128, 0)
	textLabel.Size = UDim2.new(0.678, 0, 0.739, 0)
	textLabel.ZIndex = 10002
	textLabel.Font = Enum.Font.BuilderSansBold
	textLabel.Text = tostring(text or "")
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.TextScaled = true
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.Parent = notification

	local frameColor = Instance.new("Frame")
	frameColor.Name = "Frame_Color"
	frameColor.BackgroundColor3 = color or Color3.fromRGB(255, 255, 255)
	frameColor.BackgroundTransparency = 0.05
	frameColor.Position = UDim2.new(0.819, 0, 0.357, 0)
	frameColor.Size = UDim2.new(0, 10, 0, 10)
	frameColor.ZIndex = 10003
	frameColor.Parent = notification

	addUI(frameColor, {
		Corner = {
			TopLeftRadius = UDim.new(1, 0),
			TopRightRadius = UDim.new(1, 0),
			BottomLeftRadius = UDim.new(1, 0),
			BottomRightRadius = UDim.new(1, 0),
		},
	})

	task.delay(lifetime or 1.4, function()
		if not notification.Parent then
			return
		end

		local fadeTweens = {
			SERVICE.TweenService:Create(notification, MAIN_TWEEN_INFO, { BackgroundTransparency = 1 }),
			SERVICE.TweenService:Create(textLabel, MAIN_TWEEN_INFO, { TextTransparency = 1 }),
			SERVICE.TweenService:Create(frameColor, MAIN_TWEEN_INFO, { BackgroundTransparency = 1 }),
		}

		local completedConnection
		completedConnection = fadeTweens[1].Completed:Connect(function()
			if completedConnection then
				completedConnection:Disconnect()
			end
			if notification.Parent then
				notification:Destroy()
			end
		end)

		for _, tween in ipairs(fadeTweens) do
			tween:Play()
		end
	end)
end

local CACHE_CLEAR_INTERVAL = 10 * 60

clearRuntimeCaches = function(buttonRecord)
	local clearedCount = 0
	for path in pairs(REMOTE_MODULE_CACHE) do
		REMOTE_MODULE_CACHE[path] = nil
		clearedCount += 1
	end
	if buttonRecord then
		flashButtonLabel(buttonRecord, "CLEARED", 1.1)
		showPushNotification(("Cache is cleared: %d"):format(clearedCount), Color3.fromRGB(105, 255, 135))
	end
	return clearedCount
end

local cacheCleanupToken = {}
BOOTSTRAP_ENVIRONMENT.__ARCADA_CACHE_CLEANUP_TOKEN = cacheCleanupToken
task.spawn(function()
	while BOOTSTRAP_ENVIRONMENT.__ARCADA_CACHE_CLEANUP_TOKEN == cacheCleanupToken do
		task.wait(CACHE_CLEAR_INTERVAL)
		if BOOTSTRAP_ENVIRONMENT.__ARCADA_CACHE_CLEANUP_TOKEN == cacheCleanupToken then
			clearRuntimeCaches()
		end
	end
end)

local function showConfigPasteFallback(buttonRecord)
	if UI_STATE.ConfigPasteFrame and UI_STATE.ConfigPasteFrame.Parent then
		UI_STATE.ConfigPasteFrame:Destroy()
	end

	local screenGui = getScreenGui()
	local popup = Instance.new("Frame")
	popup.Name = "ConfigPasteFrame"
	popup.Active = true
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
	popup.BackgroundTransparency = 0.05
	popup.Position = UDim2.new(0.5, 0, 0.5, 0)
	popup.Size = UDim2.new(0, 360, 0, 160)
	popup.ZIndex = 20000
	popup.Parent = screenGui
	UI_STATE.ConfigPasteFrame = popup

	addUI(popup, {
		Corner = {
			TopLeftRadius = UDim.new(0, 8),
			TopRightRadius = UDim.new(0, 8),
			BottomLeftRadius = UDim.new(0, 8),
			BottomRightRadius = UDim.new(0, 8),
		},
		Shadow = {
			Color = Color3.fromRGB(0, 0, 0),
			BlurRadius = UDim.new(0, 20),
			Transparency = 0.65,
			ZIndex = 19999,
		},
	})

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0.05, 0, 0.06, 0)
	title.Size = UDim2.new(0.72, 0, 0, 24)
	title.ZIndex = 20001
	title.Font = Enum.Font.BuilderSansBold
	title.Text = "PASTE CONFIG"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = popup

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.BackgroundColor3 = Color3.fromRGB(54, 54, 59)
	closeButton.BackgroundTransparency = 0.6
	closeButton.Position = UDim2.new(0.88, 0, 0.06, 0)
	closeButton.Size = UDim2.new(0, 28, 0, 24)
	closeButton.ZIndex = 20001
	closeButton.Font = Enum.Font.BuilderSansBold
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.TextScaled = true
	closeButton.Parent = popup

	addUI(closeButton, {
		Corner = UDim.new(0, 6),
	})

	local textBox = Instance.new("TextBox")
	textBox.Name = "TextBox"
	textBox.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
	textBox.BackgroundTransparency = 0.1
	textBox.ClearTextOnFocus = false
	textBox.MultiLine = true
	textBox.PlaceholderText = "Ctrl+V config here"
	textBox.Position = UDim2.new(0.05, 0, 0.28, 0)
	textBox.Size = UDim2.new(0.9, 0, 0, 70)
	textBox.ZIndex = 20001
	textBox.Font = Enum.Font.BuilderSans
	textBox.Text = ""
	textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
	textBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
	textBox.TextSize = 14
	textBox.TextWrapped = true
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.TextYAlignment = Enum.TextYAlignment.Top
	textBox.Parent = popup

	addUI(textBox, {
		Corner = UDim.new(0, 6),
	})

	local applyButton = Instance.new("TextButton")
	applyButton.Name = "Apply"
	applyButton.BackgroundColor3 = Color3.fromRGB(54, 54, 59)
	applyButton.BackgroundTransparency = 0.35
	applyButton.Position = UDim2.new(0.05, 0, 0.78, 0)
	applyButton.Size = UDim2.new(0.9, 0, 0, 26)
	applyButton.ZIndex = 20001
	applyButton.Font = Enum.Font.BuilderSansBold
	applyButton.Text = "APPLY"
	applyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	applyButton.TextScaled = true
	applyButton.Parent = popup

	addUI(applyButton, {
		Corner = UDim.new(0, 6),
	})

	local function closePopup()
		if popup.Parent then
			popup:Destroy()
		end
		if UI_STATE.ConfigPasteFrame == popup then
			UI_STATE.ConfigPasteFrame = nil
		end
	end

	local function applyText()
		local encodedConfig = textBox.Text
		local applied = applyImportedConfig(encodedConfig)
		if applied then
			UI_STATE.LastCopiedConfig = encodedConfig
			if updateConfigControls then
				updateConfigControls()
			end
			if saveCurrentConfig then
				saveCurrentConfig()
			end
			flashButtonLabel(buttonRecord, "PASTED", 1.1)
			showPushNotification("Config pasted", Color3.fromRGB(105, 255, 135))
			closePopup()
		else
			flashButtonLabel(buttonRecord, "PASTE FAILED", 1.1)
			showPushNotification("Paste failed", Color3.fromRGB(255, 90, 90))
		end
	end

	closeButton.MouseButton1Click:Connect(closePopup)
	applyButton.MouseButton1Click:Connect(applyText)
	textBox.FocusLost:Connect(function(enterPressed)
		if enterPressed and textBox.Text ~= "" then
			applyText()
		end
	end)

	task.defer(function()
		if textBox.Parent then
			textBox:CaptureFocus()
		end
	end)
end

local function CreateFrameTemplate_1(parent, textlabel, name)
	local Frame = Instance.new("Frame")
	Frame.Name = name
	Frame.AutomaticSize = Enum.AutomaticSize.Y
	Frame.BackgroundTransparency = 1
	Frame.LayoutOrder = 1
	Frame.BorderSizePixel = 0
	Frame.Size = UDim2.new(0, 527, 0, 140)
	Frame.Parent = parent
	Frame.ZIndex = 10003

	addUI(Frame, {
		Layout = {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0, 0),
		},
	})

	--// Tab
	local Tab = Instance.new("Frame")
	Tab.Name = "Tab"
	Tab.Active = true
	Tab.BackgroundColor3 = Color3.fromRGB(30, 30, 33)
	Tab.BackgroundTransparency = 0.6
	Tab.Size = UDim2.new(0.966, 0, 0, 24)
	Tab.Parent = Frame
	Tab.ZIndex = 10003

	addUI(Tab, {
		Corner = {
			TopLeftRadius = UDim.new(0, 0),
			TopRightRadius = UDim.new(0, 0),
			BottomLeftRadius = UDim.new(0.3, 0),
			BottomRightRadius = UDim.new(0.3, 0),
		},
	})

	local TextLabel = Instance.new("TextLabel")
	TextLabel.Name = "TextLabel"
	TextLabel.BackgroundTransparency = 1
	TextLabel.Position = UDim2.new(0.021, 0, 0.247, 0)
	TextLabel.Size = UDim2.new(0.334, 0, 0.592, 0)
	TextLabel.ZIndex = 10004
	TextLabel.Font = Enum.Font.BuilderSansBold
	TextLabel.Text = textlabel
	TextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	TextLabel.TextScaled = true
	TextLabel.TextXAlignment = Enum.TextXAlignment.Left
	TextLabel.Parent = Tab

	local Tab_Button = Instance.new("TextButton")
	Tab_Button.Name = "Tab_Button"
	Tab_Button.AnchorPoint = Vector2.new(0.5, 0.5)
	Tab_Button.BackgroundTransparency = 1
	Tab_Button.Position = UDim2.new(0.971, 0, 0.523, 0)
	Tab_Button.Size = UDim2.new(0.055, 0, 1, 0)
	Tab_Button.ZIndex = 10004
	Tab_Button.Font = Enum.Font.BuilderSansBold
	Tab_Button.Text = ">"
	Tab_Button.TextColor3 = Color3.fromRGB(255, 255, 255)
	Tab_Button.TextScaled = true
	Tab_Button.Parent = Tab

	--// Panel
	local Panel = Instance.new("ScrollingFrame")
	Panel.Name = "Panel"
	Panel.AutomaticSize = Enum.AutomaticSize.XY
	Panel.BorderSizePixel = 0
	Panel.BackgroundColor3 = Color3.fromRGB(30, 30, 33)
	Panel.BackgroundTransparency = 0.8
	Panel.Size = UDim2.new(0.965, 0, 0.267, 0)
	Panel.ZIndex = 10003
	Panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	Panel.CanvasSize = UDim2.new(0, 0, 0, 0)
	Panel.Parent = Frame
	Panel.ScrollBarImageColor3 = Color3.fromRGB(38, 38, 38)
	Panel.ScrollBarThickness = 6
	Panel.ScrollBarImageTransparency = 1
	Panel.ClipsDescendants = true

	addUI(Panel, {
		Layout = {
			FillDirection = Enum.FillDirection.Horizontal,
			Wraps = true,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0.02, 0),
		},
		Corner = {
			TopLeftRadius = UDim.new(0, 0),
			TopRightRadius = UDim.new(0, 0),
			BottomLeftRadius = UDim.new(0.04, 0),
			BottomRightRadius = UDim.new(0.04, 0),
		},
	})

	local UIPadding = Instance.new("UIPadding")
	UIPadding.Parent = Panel
	UIPadding.PaddingBottom = UDim.new(0, 0)
	UIPadding.PaddingLeft = UDim.new(0.02, 0)
	UIPadding.PaddingRight = UDim.new(0.02, 0)
	UIPadding.PaddingTop = UDim.new(0, 0)

	return Frame, Panel, Tab, Tab_Button
end

local function CreateFrameTemplate_2(parent, leftTextLabel, rightTextLabel, name)
	local Frame = Instance.new("Frame")
	Frame.Name = name
	Frame.AutomaticSize = Enum.AutomaticSize.Y
	Frame.BackgroundTransparency = 1
	Frame.LayoutOrder = 0
	Frame.BorderSizePixel = 0
	Frame.Size = UDim2.new(0, 540, 0, 103)
	Frame.Parent = parent
	Frame.ZIndex = 10003

	addUI(Frame, {
		Layout = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0, 0),
		},
	})

	local function CreateTemplate(textlabel)
		local Frame_2 = Instance.new("Frame")
		Frame_2.Name = "Frame-Template"
		Frame_2.AutomaticSize = Enum.AutomaticSize.Y
		Frame_2.BackgroundTransparency = 1
		Frame_2.BorderSizePixel = 0
		Frame_2.Size = UDim2.new(0, 261, 0, 79)
		Frame_2.Parent = Frame
		Frame_2.ZIndex = 10003

		addUI(Frame_2, {
			Layout = {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Top,
				Padding = UDim.new(0, 0),
			},
		})

		--// Tab
		local Tab = Instance.new("Frame")
		Tab.Name = "Tab"
		Tab.Active = true
		Tab.BackgroundColor3 = Color3.fromRGB(30, 30, 33)
		Tab.BackgroundTransparency = 0.6
		Tab.Size = UDim2.new(0.952, 0, 0, 24)
		Tab.Parent = Frame_2
		Tab.ZIndex = 10003

		addUI(Tab, {
			Corner = {
				TopLeftRadius = UDim.new(0, 0),
				TopRightRadius = UDim.new(0, 0),
				BottomLeftRadius = UDim.new(0.3, 0),
				BottomRightRadius = UDim.new(0.3, 0),
			},
		})

		local TextLabel = Instance.new("TextLabel")
		TextLabel.Name = "TextLabel"
		TextLabel.BackgroundTransparency = 1
		TextLabel.Position = UDim2.new(0.035, 0, 0.247, 0)
		TextLabel.Size = UDim2.new(0.32, 0, 0.592, 0)
		TextLabel.ZIndex = 10004
		TextLabel.Font = Enum.Font.BuilderSansBold
		TextLabel.Text = textlabel
		TextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		TextLabel.TextScaled = true
		TextLabel.TextXAlignment = Enum.TextXAlignment.Left
		TextLabel.Parent = Tab

		local Tab_Button = Instance.new("TextButton")
		Tab_Button.Name = "Tab_Button"
		Tab_Button.AnchorPoint = Vector2.new(0.5, 0.5)
		Tab_Button.BackgroundTransparency = 1
		Tab_Button.Position = UDim2.new(0.947, 0, 0.523, 0)
		Tab_Button.Size = UDim2.new(0.103, 0, 1, 0)
		Tab_Button.ZIndex = 10004
		Tab_Button.Font = Enum.Font.BuilderSansBold
		Tab_Button.Text = ">"
		Tab_Button.TextColor3 = Color3.fromRGB(255, 255, 255)
		Tab_Button.TextScaled = true
		Tab_Button.Parent = Tab

		--// Panel
		local Panel = Instance.new("ScrollingFrame")
		Panel.Name = "Panel"
		Panel.AutomaticSize = Enum.AutomaticSize.XY
		Panel.BorderSizePixel = 0
		Panel.BackgroundColor3 = Color3.fromRGB(30, 30, 33)
		Panel.BackgroundTransparency = 0.8
		Panel.Size = UDim2.new(0.942, 0, 0.137, 0)
		Panel.ZIndex = 10003
		Panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
		Panel.CanvasSize = UDim2.new(0, 0, 0, 0)
		Panel.Parent = Frame_2
		Panel.ScrollBarImageColor3 = Color3.fromRGB(38, 38, 38)
		Panel.ScrollBarThickness = 6
		Panel.ScrollBarImageTransparency = 1
		Panel.ClipsDescendants = true

		addUI(Panel, {
			Layout = {
				FillDirection = Enum.FillDirection.Horizontal,
				Wraps = true,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				VerticalAlignment = Enum.VerticalAlignment.Top,
				Padding = UDim.new(0.02, 0),
			},
			Corner = {
				TopLeftRadius = UDim.new(0.04, 0),
				TopRightRadius = UDim.new(0.04, 0),
				BottomLeftRadius = UDim.new(0, 0),
				BottomRightRadius = UDim.new(0, 0),
			},
		})

		local UIPadding = Instance.new("UIPadding")
		UIPadding.Parent = Panel
		UIPadding.PaddingBottom = UDim.new(0, 0)
		UIPadding.PaddingLeft = UDim.new(0.02, 0)
		UIPadding.PaddingRight = UDim.new(0.02, 0)
		UIPadding.PaddingTop = UDim.new(0, 0)

		return {
			Frame = Frame_2,
			Panel = Panel,
			Tab = Tab,
			TabButton = Tab_Button,
		}
	end

	return Frame, {
		CreateTemplate(leftTextLabel),
		CreateTemplate(rightTextLabel),
	}
end

local function createButtonTemplate(parent)
	local Template_Button = Instance.new("Frame")
	local useAutoSize = hasAncestorNamed(parent, "Frame-Template-Double-Farming")
	Template_Button.Name = "Template_Button"
	Template_Button.BackgroundTransparency = 1
	Template_Button.Size = if useAutoSize then UDim2.new(0, 0, 0, 24) else UDim2.new(0.217, 0, 1, 0)
	Template_Button.ZIndex = 10004
	Template_Button.Visible = false
	Template_Button.Parent = parent
	if useAutoSize then
		Template_Button.AutomaticSize = Enum.AutomaticSize.XY
	end

	if not useAutoSize then
		local uiaspect = Instance.new("UIAspectRatioConstraint")
		uiaspect.Parent = Template_Button
		uiaspect.AspectRatio = 3.2
		uiaspect.AspectType = Enum.AspectType.FitWithinMaxSize
		uiaspect.DominantAxis = Enum.DominantAxis.Width
	end

	addUI(Template_Button, {
		Layout = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = if useAutoSize then UDim.new(0, 6) else UDim.new(0.06, 0),
		},
	})

	local TextLabel = Instance.new("TextLabel")
	TextLabel.Name = "TextLabel"
	TextLabel.BackgroundTransparency = 1
	TextLabel.Size = if useAutoSize then UDim2.new(0, 0, 0, 18) else UDim2.new(0.657, 0, 0.412, 0)
	TextLabel.AutomaticSize = if useAutoSize then Enum.AutomaticSize.XY else Enum.AutomaticSize.None
	TextLabel.LayoutOrder = 1
	TextLabel.ZIndex = 10005
	TextLabel.Font = Enum.Font.BuilderSans
	TextLabel.Text = ""
	TextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	TextLabel.TextScaled = not useAutoSize
	TextLabel.TextSize = 14
	TextLabel.TextWrapped = false
	TextLabel.TextXAlignment = Enum.TextXAlignment.Left
	TextLabel.Parent = Template_Button

	local TextButton = Instance.new("TextButton")
	TextButton.Name = "TextButton"
	TextButton.AnchorPoint = Vector2.new(0.5, 0.5)
	TextButton.BackgroundColor3 = Color3.fromRGB(54, 54, 59)
	TextButton.BackgroundTransparency = 0.6
	TextButton.Size = if useAutoSize then UDim2.new(0, 22, 0, 22) else UDim2.new(0.22, 0, 0.705, 0)
	TextButton.LayoutOrder = 0
	TextButton.ZIndex = 10005
	TextButton.Text = ""
	TextButton.Parent = Template_Button

	addUI(TextButton, {
		Corner = {
			TopLeftRadius = UDim.new(0.2, 0),
			TopRightRadius = UDim.new(0.2, 0),
			BottomLeftRadius = UDim.new(0.2, 0),
			BottomRightRadius = UDim.new(0.2, 0),
		},
	})

	local ImageLabel = Instance.new("ImageLabel")
	ImageLabel.Name = "ImageLabel"
	ImageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	ImageLabel.BackgroundTransparency = 1
	ImageLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	ImageLabel.Size = UDim2.new(0.594, 0, 0.607, 0)
	ImageLabel.ZIndex = 10006
	ImageLabel.Image = IMAGES_ALL[10]
	ImageLabel.ImageTransparency = 1
	ImageLabel.ScaleType = Enum.ScaleType.Fit
	ImageLabel.Parent = TextButton

	return Template_Button
end

local function setButtonState(buttonRecord, enabled, shouldCall)
	if not buttonRecord then
		return
	end

	buttonRecord.Enabled = enabled == true
	UI_STATE.ButtonStates[buttonRecord.Id] = buttonRecord.Enabled

	if buttonRecord.Button then
		buttonRecord.Button.BackgroundTransparency = if buttonRecord.Enabled then 0.25 else 0.6
	end
	if buttonRecord.Indicator then
		buttonRecord.Indicator.ImageTransparency = if buttonRecord.Enabled then 0 else 1
	end
	if buttonRecord.Label then
		buttonRecord.Label.TextColor3 = if buttonRecord.Enabled
			then Color3.fromRGB(255, 255, 255)
			else Color3.fromRGB(200, 200, 200)
	end

	if shouldCall and buttonRecord.Callback then
		local success, message = pcall(buttonRecord.Callback, buttonRecord.Enabled, buttonRecord)
		if not success then
			warn(message)
		end
	end

	if shouldCall then
		showPushNotification(
			("%s %s"):format(buttonRecord.Text or "Button", if buttonRecord.Enabled then "ON" else "OFF"),
			if buttonRecord.Enabled then Color3.fromRGB(105, 255, 135) else Color3.fromRGB(255, 90, 90)
		)
		scheduleConfigSave()
	end
end

local toggleList

local function selectListButton(listRecord, buttonRecord, shouldNotify)
	if not listRecord or not buttonRecord then
		return
	end

	for _, otherButton in ipairs(listRecord.Buttons) do
		setButtonState(otherButton, otherButton == buttonRecord, false)
	end

	listRecord.SelectedButton = buttonRecord
	listRecord.SelectedText = buttonRecord.Text

	if listRecord.Label then
		local prefix = listRecord.SelectPrefix or listRecord.Title
		listRecord.Label.Text = ("%s: %s"):format(prefix, buttonRecord.Text)
	end

	if buttonRecord.Callback then
		local success, message = pcall(buttonRecord.Callback, buttonRecord.Text, buttonRecord)
		if not success then
			warn(message)
		end
	end

	if toggleList and listRecord.Opened then
		toggleList(listRecord, false)
	end

	if shouldNotify then
		showPushNotification(
			("%s: %s"):format(listRecord.SelectPrefix or listRecord.Title or "Selected", buttonRecord.Text),
			Color3.fromRGB(105, 255, 135)
		)
		scheduleConfigSave()
	end
end

local function createButton(parent, template, sectionRecord, listRecord, itemConfig)
	if not parent or not template or type(itemConfig) ~= "table" then
		return nil
	end

	local gui = template:Clone()
	if itemConfig.Inline then
		local aspect = gui:FindFirstChildOfClass("UIAspectRatioConstraint")
		if aspect then
			aspect:Destroy()
		end
		gui.AutomaticSize = Enum.AutomaticSize.XY
		gui.Size = UDim2.new(0, 0, 0, 28)
		local inlineText = gui:FindFirstChild("TextLabel")
		local inlineButton = gui:FindFirstChild("TextButton")
		if inlineButton and inlineButton:IsA("TextButton") then
			inlineButton.AnchorPoint = Vector2.zero
			inlineButton.Size = UDim2.new(0, 22, 0, 22)
		end
		if inlineText and inlineText:IsA("TextLabel") then
			inlineText.AutomaticSize = Enum.AutomaticSize.XY
			inlineText.Size = UDim2.new(0, 0, 0, 18)
			inlineText.TextScaled = false
			inlineText.TextSize = 14
		end
	elseif itemConfig.Wide then
		local aspect = gui:FindFirstChildOfClass("UIAspectRatioConstraint")
		if aspect then
			aspect:Destroy()
		end
		gui.Size = UDim2.new(0.94, 0, 0, 28)
	elseif itemConfig.HalfWide then
		local aspect = gui:FindFirstChildOfClass("UIAspectRatioConstraint")
		if aspect then
			aspect:Destroy()
		end
		gui.Size = UDim2.new(0.45, 0, 0, 28)
		local halfButton = gui:FindFirstChild("TextButton")
		if halfButton and halfButton:IsA("TextButton") then
			halfButton.AnchorPoint = Vector2.zero
			halfButton.Size = UDim2.new(0, 22, 0, 22)
		end
	end
	gui.LayoutOrder = getLayoutOrder(itemConfig)
	gui.Visible = true
	gui.Parent = parent

	local textLabel = gui:FindFirstChild("TextLabel")
	local textButton = gui:FindFirstChild("TextButton")
	local indicator = textButton and textButton:FindFirstChild("ImageLabel")

	if textLabel then
		textLabel.Text = itemConfig.Text or "Button"
	end
	local statusLabel = nil
	if type(itemConfig.StatusProvider) == "function" then
		statusLabel = Instance.new("TextLabel")
		statusLabel.Name = "StatusLabel"
		statusLabel.BackgroundTransparency = 1
		statusLabel.Size = UDim2.new(0, 0, 0, 18)
		statusLabel.AutomaticSize = Enum.AutomaticSize.XY
		statusLabel.LayoutOrder = 2
		statusLabel.ZIndex = 10006
		statusLabel.Font = Enum.Font.BuilderSans
		statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		statusLabel.TextSize = 14
		statusLabel.TextXAlignment = Enum.TextXAlignment.Left
		statusLabel.Parent = gui
		task.spawn(function()
			while statusLabel.Parent do
				local success, value = pcall(itemConfig.StatusProvider)
				statusLabel.Text = if success then tostring(value) else "--:--:--"
				task.wait(1)
			end
		end)
	end

	local buttonRecord = {
		Id = ("%s/%s/%s/%d"):format(
			sectionRecord.Name,
			listRecord.Title,
			tostring(itemConfig.Text),
			#UI_STATE.Buttons + 1
		),
		Type = "Button",
		Text = itemConfig.Text or "Button",
		Gui = gui,
		Button = textButton,
		Label = textLabel,
		Indicator = indicator,
		StatusLabel = statusLabel,
		Section = sectionRecord,
		List = listRecord,
		Callback = itemConfig.Callback,
		IsAction = itemConfig.Type == "Action" or itemConfig.Mode == "Action",
		Enabled = false,
		Connections = {},
	}

	table.insert(UI_STATE.Buttons, buttonRecord)
	table.insert(listRecord.Buttons, buttonRecord)

	if textButton then
		table.insert(
			buttonRecord.Connections,
			textButton.MouseButton1Click:Connect(function()
				if buttonRecord.IsAction then
					if buttonRecord.Callback then
						local success, message = pcall(buttonRecord.Callback, buttonRecord)
						if not success then
							warn(message)
						end
					end
					textButton.BackgroundTransparency = 0.25
					SERVICE.TweenService
						:Create(textButton, MAIN_TWEEN_INFO, {
							BackgroundTransparency = 0.6,
						})
						:Play()
					return
				end
				setButtonState(buttonRecord, not buttonRecord.Enabled, true)
			end)
		)
	end

	if buttonRecord.IsAction then
		setButtonState(buttonRecord, false, false)
	else
		setButtonState(buttonRecord, itemConfig.Default == true, false)
	end

	addSearchRecord({
		Kind = "Button",
		Title = buttonRecord.Text,
		SearchText = getSearchText(itemConfig, buttonRecord.Text),
		Section = sectionRecord,
		List = if listRecord.IsButtonGroup then nil else listRecord,
		Button = buttonRecord,
		TargetGui = gui,
	})

	return buttonRecord
end

local function createTextBoxControl(parent, sectionRecord, itemConfig)
	if not parent or type(itemConfig) ~= "table" then
		return nil
	end

	local frame = Instance.new("Frame")
	frame.Name = "Template_Input"
	frame.BackgroundTransparency = 1
	frame.Size = if itemConfig.Wide then UDim2.new(0.94, 0, 0, 30) else UDim2.new(0.45, 0, 0, 30)
	frame.ZIndex = 10004
	frame.Parent = parent

	addUI(frame, {
		Layout = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0.04, 0),
		},
	})

	local label = Instance.new("TextLabel")
	label.Name = "TextLabel"
	label.BackgroundTransparency = 1
	label.Size = if itemConfig.Wide then UDim2.new(0.22, 0, 0.7, 0) else UDim2.new(0.38, 0, 0.7, 0)
	label.LayoutOrder = 0
	label.ZIndex = 10005
	label.Font = Enum.Font.BuilderSans
	label.Text = itemConfig.Text or "Input"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame

	local textBox = Instance.new("TextBox")
	textBox.Name = "TextBox"
	textBox.BackgroundColor3 = Color3.fromRGB(54, 54, 59)
	textBox.BackgroundTransparency = 0.6
	textBox.Size = if itemConfig.Wide then UDim2.new(0.74, 0, 0.78, 0) else UDim2.new(0.58, 0, 0.78, 0)
	textBox.LayoutOrder = 1
	textBox.ZIndex = 10005
	textBox.ClearTextOnFocus = false
	textBox.Font = Enum.Font.BuilderSans
	textBox.Text = itemConfig.Value or ""
	textBox.PlaceholderText = itemConfig.Placeholder or ""
	textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
	textBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
	textBox.TextScaled = true
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.Parent = frame

	addUI(textBox, {
		Corner = {
			TopLeftRadius = UDim.new(0.2, 0),
			TopRightRadius = UDim.new(0.2, 0),
			BottomLeftRadius = UDim.new(0.2, 0),
			BottomRightRadius = UDim.new(0.2, 0),
		},
	})

	if itemConfig.Key then
		UI_STATE.ConfigInputs[itemConfig.Key] = textBox
	end

	textBox.FocusLost:Connect(function()
		if itemConfig.Callback then
			local success, message = pcall(itemConfig.Callback, textBox.Text, textBox)
			if not success then
				warn(message)
			end
		end
		scheduleConfigSave()
	end)

	addSearchRecord({
		Kind = "Input",
		Title = itemConfig.Text or "Input",
		SearchText = getSearchText(itemConfig, itemConfig.Text),
		Section = sectionRecord,
		TargetGui = frame,
	})

	return frame, textBox
end

local function createLabelControl(parent, sectionRecord, itemConfig)
	if not parent or type(itemConfig) ~= "table" then
		return nil
	end

	local frame = Instance.new("Frame")
	frame.Name = "Template_Label"
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = getLayoutOrder(itemConfig)
	frame.Size = if itemConfig.Wide then UDim2.new(0.94, 0, 0, 20) else UDim2.new(0.4, 0, 0, 20)
	frame.ZIndex = 10004
	frame.Parent = parent

	addUI(frame, {
		Layout = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
		},
	})

	if itemConfig.Image then
		local imageLabel = Instance.new("ImageLabel")
		imageLabel.Name = "ImageLabel"
		imageLabel.BackgroundTransparency = 1
		imageLabel.Size = UDim2.new(0, 22, 0, 16)
		imageLabel.LayoutOrder = 0
		imageLabel.ZIndex = 10005
		imageLabel.Image = itemConfig.Image
		imageLabel.ScaleType = Enum.ScaleType.Fit
		imageLabel.Parent = frame
	end

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "TextLabel"
	textLabel.BackgroundTransparency = 1
	textLabel.Size = if itemConfig.Image then UDim2.new(1, -28, 0, 16) else UDim2.new(1, 0, 0, 16)
	textLabel.LayoutOrder = 1
	textLabel.ZIndex = 10005
	textLabel.Font = Enum.Font.BuilderSans
	textLabel.Text = itemConfig.Text or ""
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.TextScaled = true
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.Parent = frame

	if itemConfig.OnCreated then
		local success, message = pcall(itemConfig.OnCreated, frame, textLabel)
		if not success then
			warn(message)
		end
	end

	addSearchRecord({
		Kind = "Label",
		Title = itemConfig.Text or "Label",
		SearchText = getSearchText(itemConfig, itemConfig.Text),
		Section = sectionRecord,
		TargetGui = frame,
	})

	return frame, textLabel
end

local function createSliderControl(parent, sectionRecord, itemConfig)
	if not parent or type(itemConfig) ~= "table" then
		return nil
	end

	local minValue = itemConfig.Min or 0
	local maxValue = itemConfig.Max or 100
	local value = math.clamp(itemConfig.Default or minValue, minValue, maxValue)

	local frame = Instance.new("Frame")
	frame.Name = "Template_Slider"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(0.94, 0, 0, 44)
	frame.ZIndex = 10004
	frame.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "TextLabel"
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 0, 0, 4)
	label.Size = UDim2.new(1, 0, 0, 14)
	label.ZIndex = 10005
	label.Font = Enum.Font.BuilderSansBold
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame

	local track = Instance.new("TextButton")
	track.Name = "TextButton"
	track.BackgroundColor3 = Color3.fromRGB(54, 54, 59)
	track.BackgroundTransparency = 0.6
	track.Position = UDim2.new(0, 0, 0, 28)
	track.Size = UDim2.new(1, 0, 0, 6)
	track.ZIndex = 10005
	track.Text = ""
	track.Parent = frame

	addUI(track, {
		Corner = UDim.new(0.5, 0),
	})

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	fill.BackgroundTransparency = 0.2
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.ZIndex = 10006
	fill.Parent = track

	addUI(fill, {
		Corner = UDim.new(0.5, 0),
	})

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.Position = UDim2.new(0, 0, 0.5, 0)
	knob.Size = UDim2.new(0, 18, 0, 18)
	knob.ZIndex = 10007
	knob.Parent = track

	addUI(knob, {
		Corner = UDim.new(1, 0),
	})

	local sliderRecord = {
		Key = itemConfig.Key,
		Frame = frame,
		Label = label,
		Track = track,
		Fill = fill,
		Knob = knob,
		Min = minValue,
		Max = maxValue,
		Value = value,
		Callback = itemConfig.Callback,
		Dragging = false,
	}

	local function setSliderValue(nextValue, shouldCall)
		value = math.clamp(math.floor((nextValue or minValue) + 0.5), minValue, maxValue)
		sliderRecord.Value = value
		local alpha = if maxValue == minValue then 0 else (value - minValue) / (maxValue - minValue)
		label.Text = ("%s: %d"):format(itemConfig.Text or "Slider", value)
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)

		if shouldCall and sliderRecord.Callback then
			local success, message = pcall(sliderRecord.Callback, value, sliderRecord)
			if not success then
				warn(message)
			end
		end
		if shouldCall then
			scheduleConfigSave()
		end
	end

	local function setFromInput(input, shouldCall)
		local trackWidth = math.max(track.AbsoluteSize.X, 1)
		local alpha = math.clamp((input.Position.X - track.AbsolutePosition.X) / trackWidth, 0, 1)
		setSliderValue(minValue + ((maxValue - minValue) * alpha), shouldCall)
	end

	track.MouseButton1Down:Connect(function(x)
		sliderRecord.Dragging = true
		setSliderValue(
			minValue
				+ (
					(maxValue - minValue)
					* math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
				),
			true
		)
	end)

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			sliderRecord.Dragging = true
			setFromInput(input, true)
		end
	end)

	track.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			sliderRecord.Dragging = false
		end
	end)

	SERVICE.UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			sliderRecord.Dragging = false
		end
	end)

	SERVICE.UserInputService.InputChanged:Connect(function(input)
		if not sliderRecord.Dragging then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			setFromInput(input, true)
		end
	end)

	if itemConfig.Key then
		UI_STATE.Sliders[itemConfig.Key] = sliderRecord
	end

	setSliderValue(value, false)

	addSearchRecord({
		Kind = "Slider",
		Title = itemConfig.Text or "Slider",
		SearchText = getSearchText(itemConfig, itemConfig.Text),
		Section = sectionRecord,
		TargetGui = frame,
	})

	return sliderRecord
end

copyConfigToImportBox = function(buttonRecord)
	local encodedConfig = encodeCurrentConfig()
	UI_STATE.LastCopiedConfig = encodedConfig
	if saveCurrentConfig then
		saveCurrentConfig()
	end

	local copied = writeClipboard(encodedConfig)
	flashButtonLabel(buttonRecord, if copied then "COPIED" else "COPY FAILED", 1.1)
	showPushNotification(
		if copied then "Config copied" else "Copy failed",
		if copied then Color3.fromRGB(105, 255, 135) else Color3.fromRGB(255, 90, 90)
	)
	return copied
end

loadConfigFromImportBox = function(buttonRecord)
	local clipboardConfig = readClipboard()
	if clipboardConfig == "" then
		flashButtonLabel(buttonRecord, "PASTE", 1.1)
		showPushNotification("Paste config", Color3.fromRGB(255, 255, 255))
		showConfigPasteFallback(buttonRecord)
		return false
	end

	local applied = applyImportedConfig(clipboardConfig)
	if applied then
		UI_STATE.LastCopiedConfig = clipboardConfig
	end
	if applied and updateConfigControls then
		updateConfigControls()
	end
	if applied and saveCurrentConfig then
		saveCurrentConfig()
	end
	flashButtonLabel(buttonRecord, if applied then "PASTED" else "PASTE FAILED", 1.1)
	showPushNotification(
		if applied then "Config pasted" else "Paste failed",
		if applied then Color3.fromRGB(105, 255, 135) else Color3.fromRGB(255, 90, 90)
	)
	return applied
end

updateConfigControls = function()
	local speedBox = UI_STATE.ConfigInputs.Speed
	if speedBox then
		speedBox.Text = tostring(SETTING.Config.Speed)
	end
	local speedSlider = UI_STATE.Sliders.Speed
	if speedSlider then
		local alpha = if speedSlider.Max == speedSlider.Min
			then 0
			else (SETTING.Config.Speed - speedSlider.Min) / (speedSlider.Max - speedSlider.Min)
		speedSlider.Value = SETTING.Config.Speed
		speedSlider.Label.Text = ("Speed: %d"):format(SETTING.Config.Speed)
		speedSlider.Fill.Size = UDim2.new(math.clamp(alpha, 0, 1), 0, 1, 0)
		speedSlider.Knob.Position = UDim2.new(math.clamp(alpha, 0, 1), 0, 0.5, 0)
	end
	local hiveSlider = UI_STATE.Sliders.HiveSlot
	if hiveSlider then
		local alpha = (SETTING.Config.Hive_Slot - hiveSlider.Min) / (hiveSlider.Max - hiveSlider.Min)
		hiveSlider.Value = SETTING.Config.Hive_Slot
		hiveSlider.Label.Text = ("Hive Slot: %d"):format(SETTING.Config.Hive_Slot)
		hiveSlider.Fill.Size = UDim2.new(math.clamp(alpha, 0, 1), 0, 1, 0)
		hiveSlider.Knob.Position = UDim2.new(math.clamp(alpha, 0, 1), 0, 0.5, 0)
	end
	local vipLinkBox = UI_STATE.ConfigInputs.VIPServerLink
	if vipLinkBox then
		vipLinkBox.Text = SETTING.Config.VIP_Server_Link
	end
	local puffRarityBox = UI_STATE.ConfigInputs.PuffMinRarity
	if puffRarityBox then
		puffRarityBox.Text = SETTING.Farming.Puff_Min_Rarity
	end
	local puffFieldsBox = UI_STATE.ConfigInputs.PuffFields
	if puffFieldsBox then
		puffFieldsBox.Text = SETTING.Farming.Puff_Fields
	end
	for key, value in pairs({
		ConvertPercent = SETTING.Config.Convert_Percent,
		ConvertMinutes = SETTING.Config.Convert_Minutes,
		PuffMinLevel = SETTING.Farming.Puff_Min_Level,
		PuffLootSeconds = SETTING.Farming.Puff_Loot_Seconds,
	}) do
		local slider = UI_STATE.Sliders[key]
		if slider then
			local alpha = if slider.Max == slider.Min then 0 else (value - slider.Min) / (slider.Max - slider.Min)
			slider.Value = value
			local title = if key == "ConvertPercent"
				then "Convert Pollen %"
				elseif key == "ConvertMinutes" then "Convert Time (Minutes)"
				elseif key == "PuffMinLevel" then "Puff Min Level"
				else "Puff Loot Seconds"
			slider.Label.Text = ("%s: %d"):format(title, value)
			slider.Fill.Size = UDim2.new(math.clamp(alpha, 0, 1), 0, 1, 0)
			slider.Knob.Position = UDim2.new(math.clamp(alpha, 0, 1), 0, 0.5, 0)
		end
	end
	for _, priorityRecord in pairs(UI_STATE.PriorityInputs) do
		local storedValue = priorityRecord.Storage and priorityRecord.Storage[priorityRecord.Key]
		if storedValue ~= nil and priorityRecord.SetValue then
			priorityRecord.SetValue(storedValue, false)
		end
	end
	local character = SERVICE.Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = SETTING.Config.Speed
	end

	for _, buttonRecord in ipairs(UI_STATE.Buttons) do
		if buttonRecord.Text == "Auto Farm" then
			setButtonState(buttonRecord, SETTING.Farming.Auto_Farm, false)
		elseif buttonRecord.Text == "Auto Dig" then
			setButtonState(buttonRecord, SETTING.Farming.Auto_Dig, false)
		elseif buttonRecord.Text == "Auto Sprinkler" then
			setButtonState(buttonRecord, SETTING.Farming.Auto_Sprinkler, false)
		elseif buttonRecord.Text == "Farm Bubbles" then
			setButtonState(buttonRecord, SETTING.Farming.Farm_Bubbles, false)
		elseif buttonRecord.Text == "Farm Petals" then
			setButtonState(buttonRecord, SETTING.Farming.Farm_Petals, false)
		elseif buttonRecord.Text == "Auto Sprouts" then
			setButtonState(buttonRecord, SETTING.Farming.Auto_Sprouts, false)
		elseif buttonRecord.Text == "ESC Tokens" then
			setButtonState(buttonRecord, SETTING.Farming.ESC_Tokens, false)
		elseif buttonRecord.Text == "Shift Lock" then
			setButtonState(buttonRecord, SETTING.Farming.Shift_Lock, false)
		elseif buttonRecord.Text == "Wealth Clock" then
			setButtonState(buttonRecord, SETTING.Farming.Wealth_Clock, false)
		elseif buttonRecord.Text == "Auto Puffshrooms" then
			setButtonState(buttonRecord, SETTING.Farming.Auto_Puffshrooms, false)
		elseif buttonRecord.Text == "Collect Puff Loot" then
			setButtonState(buttonRecord, SETTING.Farming.Puff_Collect_Loot, false)
		elseif buttonRecord.Text == "Prefer Rarity" then
			setButtonState(buttonRecord, SETTING.Farming.Puff_Prefer_Rarity, false)
		elseif buttonRecord.Text == "Anti AFK" then
			setButtonState(buttonRecord, SETTING.Config.Anti_AFK, false)
		elseif buttonRecord.Text == "Auto Honey Mask" then
			setButtonState(buttonRecord, SETTING.Config.Auto_Honey_Mask, false)
		elseif buttonRecord.Text == "Convert Balloons" then
			setButtonState(buttonRecord, SETTING.Config.Convert_Balloons, false)
		elseif buttonRecord.Text == "Auto Hive" then
			setButtonState(buttonRecord, SETTING.Config.Auto_Hive, false)
		elseif buttonRecord.Text == "Auto Rejoin" then
			setButtonState(buttonRecord, SETTING.Config.Auto_Rejoin, false)
		elseif buttonRecord.Text == "Show Player List (Tab)" then
			setButtonState(buttonRecord, SETTING.Config.Show_Player_List, false)
		elseif buttonRecord.Text == "Minimum Render Distance" then
			setButtonState(buttonRecord, SETTING.Config.Minimum_Render, false)
		elseif buttonRecord.Text == "Hide Decorations" then
			setButtonState(buttonRecord, SETTING.Config.Hide_Decorations, false)
		elseif buttonRecord.Text == "Hide FieldDecos" then
			setButtonState(buttonRecord, SETTING.Config.Hide_Field_Decos, false)
		elseif buttonRecord.Text == "Hide Fields" then
			setButtonState(buttonRecord, SETTING.Config.Hide_Fields, false)
		elseif buttonRecord.Text == "Disable Shadows" then
			setButtonState(buttonRecord, SETTING.Config.Disable_Shadows, false)
		elseif buttonRecord.Text == "Low Fog & Effects" then
			setButtonState(buttonRecord, SETTING.Config.Low_Fog_Effects, false)
		elseif buttonRecord.Text == "Farm Mondo Chick" then
			setButtonState(buttonRecord, SETTING.Bosses.Farm_Mondo_Chick, false)
		elseif buttonRecord.Text == "Collect Tokens Mondo" then
			setButtonState(buttonRecord, SETTING.Bosses.Collect_Mondo_Tokens, false)
		elseif buttonRecord.Text == "Farm Windy Bee" then
			setButtonState(buttonRecord, SETTING.Bosses.Farm_Windy_Bee, false)
		elseif buttonRecord.Text == "Farm Vicious Bee" then
			setButtonState(buttonRecord, SETTING.Bosses.Farm_Vicious_Bee, false)
		elseif buttonRecord.Text == "Farm Stump Snail" then
			setButtonState(buttonRecord, SETTING.Bosses.Farm_Stump_Snail, false)
		elseif buttonRecord.Text == "Auto Memory Match" then
			setButtonState(buttonRecord, SETTING.MemoryMatch.Auto, false)
		elseif buttonRecord.Text == "Show Closed Images" then
			setButtonState(buttonRecord, SETTING.MemoryMatch.Show_Images, false)
		end
	end
	setPlayerListEnabled(SETTING.Config.Show_Player_List)
	setMinimumRender(SETTING.Config.Minimum_Render)
	setFoldersHidden({ "Decorations", "FieldDecos" }, SETTING.Config.Hide_Decorations)
	setFieldDecosHidden(SETTING.Config.Hide_Field_Decos)
	setFieldsHidden(SETTING.Config.Hide_Fields)
	setShadowsDisabled(SETTING.Config.Disable_Shadows)
	setLowFogEffects(SETTING.Config.Low_Fog_Effects)

	if SETTING.Farming.Selected_Field then
		for _, listRecord in ipairs(UI_STATE.Lists) do
			if listRecord.IsSelector and listRecord.SelectPrefix == "Field" then
				for _, buttonRecord in ipairs(listRecord.Buttons) do
					if buttonRecord.Text == SETTING.Farming.Selected_Field then
						selectListButton(listRecord, buttonRecord)
						break
					end
				end
			end
		end
	end
	for _, listRecord in ipairs(UI_STATE.Lists) do
		if listRecord.IsSelector and listRecord.SelectPrefix == "Mask" then
			for _, buttonRecord in ipairs(listRecord.Buttons) do
				if buttonRecord.Text == SETTING.Config.Selected_Mask then
					selectListButton(listRecord, buttonRecord)
					break
				end
			end
		end
	end
end

local function createPriorityInput(parent, sectionRecord, listRecord, itemConfig)
	if not parent or type(itemConfig) ~= "table" then
		return nil
	end

	local key = tostring(itemConfig.Key or itemConfig.Text or (#listRecord.PriorityItems + 1))
	local minValue = math.floor(tonumber(itemConfig.Min) or 0)
	local maxValue = math.floor(tonumber(itemConfig.Max) or 1000)
	maxValue = math.max(minValue, maxValue)
	local storage = if type(itemConfig.Storage) == "table" then itemConfig.Storage else nil
	local initialValue = (storage and storage[key]) or itemConfig.Default or minValue
	local sequence = #listRecord.PriorityItems + 1
	local priorityImages = getPriorityImages(itemConfig)

	local frame = Instance.new("Frame")
	frame.Name = "Priority-" .. key
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(0.95, 0, 0, 28)
	frame.ZIndex = 10011
	frame.Parent = parent

	addUI(frame, {
		Layout = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0.02, 0),
		},
	})

	local visibleImageCount = math.min(#priorityImages, 3)
	local imagesWidth = if visibleImageCount > 0 then (visibleImageCount * 22) - 2 else 0
	local imageStrip = Instance.new("ScrollingFrame")
	imageStrip.Name = "Images"
	imageStrip.LayoutOrder = 0
	imageStrip.Active = #priorityImages > visibleImageCount
	imageStrip.AutomaticCanvasSize = Enum.AutomaticSize.X
	imageStrip.BackgroundTransparency = 1
	imageStrip.BorderSizePixel = 0
	imageStrip.CanvasSize = UDim2.new(0, 0, 0, 0)
	imageStrip.ClipsDescendants = true
	imageStrip.ScrollBarThickness = 0
	imageStrip.ScrollingDirection = Enum.ScrollingDirection.X
	imageStrip.Size = UDim2.new(0, imagesWidth, 0, 22)
	imageStrip.Visible = visibleImageCount > 0
	imageStrip.ZIndex = 10011
	imageStrip.Parent = frame

	addUI(imageStrip, {
		Layout = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 2),
		},
	})

	for index, priorityImage in ipairs(priorityImages) do
		local imageLabel = Instance.new("ImageLabel")
		imageLabel.Name = "Image-" .. priorityImage.Key
		imageLabel.LayoutOrder = index
		imageLabel.BackgroundTransparency = 1
		imageLabel.Size = UDim2.new(0, 20, 0, 20)
		imageLabel.ZIndex = 10011
		imageLabel.Image = priorityImage.Image
		imageLabel.ScaleType = Enum.ScaleType.Fit
		imageLabel:SetAttribute("PriorityGroup", key)
		imageLabel:SetAttribute("PriorityImageKey", priorityImage.Key)
		imageLabel.Parent = imageStrip
	end

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "TextLabel"
	textLabel.LayoutOrder = 1
	textLabel.BackgroundTransparency = 1
	textLabel.Size = UDim2.new(1, -(imagesWidth + 70), 0, 16)
	textLabel.ZIndex = 10011
	textLabel.Font = Enum.Font.BuilderSans
	textLabel.Text = itemConfig.Text or key
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.TextScaled = true
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.Parent = frame

	local textBox = Instance.new("TextBox")
	textBox.Name = "Priority"
	textBox.LayoutOrder = 2
	textBox.BackgroundColor3 = Color3.fromRGB(54, 54, 59)
	textBox.BackgroundTransparency = 1
	textBox.Size = UDim2.new(0, 52, 0, 16)
	textBox.ZIndex = 10011
	textBox.ClearTextOnFocus = false
	textBox.Font = Enum.Font.BuilderSansBold
	textBox.PlaceholderText = ("%d-%d"):format(minValue, maxValue)
	textBox.Text = ""
	textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
	textBox.TextScaled = true
	textBox.TextXAlignment = Enum.TextXAlignment.Center
	textBox.Parent = frame

	addUI(textBox, {
		Corner = UDim.new(0, 5),
	})

	local priorityRecord = {
		Type = "Priority",
		Key = key,
		Text = itemConfig.Text or key,
		Value = minValue,
		Min = minValue,
		Max = maxValue,
		Gui = frame,
		Input = textBox,
		Label = textLabel,
		Images = priorityImages,
		Storage = storage,
		Section = sectionRecord,
		List = listRecord,
	}

	local tieOrder = getLayoutOrder(itemConfig)
	if tieOrder == 0 then
		tieOrder = sequence
	end
	tieOrder = math.clamp(math.floor(tieOrder), 0, 9999)

	local function setValue(rawValue, shouldCall)
		local numericValue = tonumber(rawValue)
		if not numericValue then
			numericValue = priorityRecord.Value
		end
		numericValue = math.clamp(math.floor(numericValue), minValue, maxValue)

		priorityRecord.Value = numericValue
		textBox.Text = tostring(numericValue)
		frame.LayoutOrder = ((maxValue - numericValue) * 10000) + tieOrder

		if storage then
			storage[key] = numericValue
		end
		if shouldCall and itemConfig.Callback then
			local success, message = pcall(itemConfig.Callback, numericValue, priorityRecord)
			if not success then
				warn(message)
			end
		end
		if shouldCall then
			scheduleConfigSave()
		end
	end

	priorityRecord.SetValue = setValue
	table.insert(listRecord.PriorityItems, priorityRecord)
	UI_STATE.PriorityInputs[("%s/%s/%s"):format(sectionRecord.Name, listRecord.Title, key)] = priorityRecord
	for _, priorityImage in ipairs(priorityImages) do
		if priorityImage.LookupKey ~= "" then
			UI_STATE.PriorityByImage[priorityImage.LookupKey] = {
				Record = priorityRecord,
				Image = priorityImage,
			}
		end
	end

	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		local filteredText = string.gsub(textBox.Text, "[^%d]", "")
		if filteredText ~= textBox.Text then
			textBox.Text = filteredText
		end
	end)
	textBox.FocusLost:Connect(function()
		setValue(textBox.Text, true)
	end)

	setValue(initialValue, false)

	addSearchRecord({
		Kind = "Input",
		Title = priorityRecord.Text,
		SearchText = getSearchText(itemConfig, priorityRecord.Text),
		Section = sectionRecord,
		List = listRecord,
		TargetGui = frame,
	})

	return priorityRecord
end

local function createListButton(parent, sectionRecord, listRecord, itemConfig)
	if not parent or type(itemConfig) ~= "table" then
		return nil
	end

	local Frame_List = Instance.new("Frame")
	Frame_List.Name = "Frame"
	Frame_List.BackgroundTransparency = 1
	Frame_List.LayoutOrder = getLayoutOrder(itemConfig)
	Frame_List.Size = UDim2.new(0.95, 0, 0, 28)
	Frame_List.ZIndex = 10103
	Frame_List.Parent = parent

	addUI(Frame_List, {
		Layout = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0.02, 0),
		},
	})

	local ImageLabel = Instance.new("ImageLabel")
	ImageLabel.Name = "ImageLabel"
	ImageLabel.LayoutOrder = 0
	ImageLabel.BackgroundTransparency = 1
	ImageLabel.Size = UDim2.new(0, 22, 0, 22)
	ImageLabel.ZIndex = 10105
	ImageLabel.Image = itemConfig.Image or ""
	ImageLabel.ScaleType = Enum.ScaleType.Fit
	ImageLabel.Parent = Frame_List

	local TextLabel = Instance.new("TextLabel")
	TextLabel.Name = "TextLabel"
	TextLabel.LayoutOrder = 1
	TextLabel.BackgroundTransparency = 1
	TextLabel.Size = UDim2.new(1, -58, 0, 16)
	TextLabel.ZIndex = 10104
	TextLabel.Font = Enum.Font.BuilderSans
	TextLabel.Text = itemConfig.Text or "Button"
	TextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	TextLabel.TextScaled = true
	TextLabel.TextXAlignment = Enum.TextXAlignment.Left
	TextLabel.Parent = Frame_List

	local TextButton = Instance.new("TextButton")
	TextButton.Name = "TextButton"
	TextButton.LayoutOrder = 2
	TextButton.BackgroundColor3 = Color3.fromRGB(54, 54, 59)
	TextButton.BackgroundTransparency = 0.6
	TextButton.Size = UDim2.new(0, 24, 0, 24)
	TextButton.ZIndex = 10104
	TextButton.Text = ""
	TextButton.Parent = Frame_List

	addUI(TextButton, {
		Corner = {
			TopLeftRadius = UDim.new(0.2, 0),
			TopRightRadius = UDim.new(0.2, 0),
			BottomLeftRadius = UDim.new(0.2, 0),
			BottomRightRadius = UDim.new(0.2, 0),
		},
	})

	local Indicator = Instance.new("ImageLabel")
	Indicator.Name = "ImageLabel"
	Indicator.BackgroundTransparency = 1
	Indicator.Position = UDim2.new(0.22, 0, 0.196, 0)
	Indicator.Size = UDim2.new(0.594, 0, 0.607, 0)
	Indicator.ZIndex = 10105
	Indicator.Image = IMAGES_ALL[10]
	Indicator.ImageTransparency = 1
	Indicator.ScaleType = Enum.ScaleType.Fit
	Indicator.Parent = TextButton

	local buttonRecord = {
		Id = ("%s/%s/%s/%d"):format(
			sectionRecord.Name,
			listRecord.Title,
			tostring(itemConfig.Text),
			#UI_STATE.Buttons + 1
		),
		Type = "Button",
		Text = itemConfig.Text or "Button",
		Gui = Frame_List,
		Button = TextButton,
		Label = TextLabel,
		Indicator = Indicator,
		Section = sectionRecord,
		List = listRecord,
		Callback = itemConfig.Callback,
		Enabled = false,
		Connections = {},
	}

	table.insert(UI_STATE.Buttons, buttonRecord)
	table.insert(listRecord.Buttons, buttonRecord)

	table.insert(
		buttonRecord.Connections,
		TextButton.MouseButton1Click:Connect(function()
			if listRecord.IsSelector then
				selectListButton(listRecord, buttonRecord, true)
			else
				setButtonState(buttonRecord, not buttonRecord.Enabled, true)
			end
		end)
	)

	setButtonState(buttonRecord, itemConfig.Default == true, false)

	addSearchRecord({
		Kind = "Button",
		Title = buttonRecord.Text,
		SearchText = getSearchText(itemConfig, buttonRecord.Text),
		Section = sectionRecord,
		List = listRecord,
		Button = buttonRecord,
		TargetGui = Frame_List,
	})

	return buttonRecord
end

local function createListTemplate(parent)
	local Template_List = Instance.new("Frame")
	Template_List.Name = "Template-List"
	Template_List.BackgroundTransparency = 1
	Template_List.Size = UDim2.new(0, 248, 0, 28)
	Template_List.ZIndex = 10099
	Template_List.Visible = false
	Template_List.Parent = parent

	addUI(Template_List, {
		Layout = {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0, 0),
		},
	})

	local Frame = Instance.new("Frame")
	Frame.Name = "Frame"
	Frame.BackgroundTransparency = 1
	Frame.ClipsDescendants = true
	Frame.Position = UDim2.new(0, 0, 0, 0)
	Frame.Size = UDim2.new(0, 231, 0, 28)
	Frame.ZIndex = 10100
	Frame.Parent = Template_List

	addUI(Frame, {
		Layout = {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0, 0),
		},
	})

	local Tab = Instance.new("Frame")
	Tab.Name = "Tab"
	Tab.Active = true
	Tab.BackgroundColor3 = Color3.fromRGB(30, 30, 33)
	Tab.BackgroundTransparency = 0.6
	Tab.Size = UDim2.new(0.993, 0, 0, 24)
	Tab.ZIndex = 10101
	Tab.Parent = Frame

	addUI(Tab, {
		Corner = {
			TopLeftRadius = UDim.new(0, 0),
			TopRightRadius = UDim.new(0, 0),
			BottomLeftRadius = UDim.new(0.3, 0),
			BottomRightRadius = UDim.new(0.3, 0),
		},
	})

	local TextLabel = Instance.new("TextLabel")
	TextLabel.Name = "TextLabel"
	TextLabel.BackgroundTransparency = 1
	TextLabel.Position = UDim2.new(0.047, 0, 0.247, 0)
	TextLabel.Size = UDim2.new(0.711, 0, 0.592, 0)
	TextLabel.ZIndex = 10102
	TextLabel.Font = Enum.Font.BuilderSansBold
	TextLabel.Text = ""
	TextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	TextLabel.TextScaled = true
	TextLabel.TextXAlignment = Enum.TextXAlignment.Left
	TextLabel.Parent = Tab

	local TextButton = Instance.new("TextButton")
	TextButton.Name = "TextButton"
	TextButton.AnchorPoint = Vector2.new(0.5, 0.5)
	TextButton.BackgroundTransparency = 1
	TextButton.Position = UDim2.new(0.948, 0, 0.422, 0)
	TextButton.Size = UDim2.new(0.103, 0, 1, 0)
	TextButton.ZIndex = 10102
	TextButton.Font = Enum.Font.BuilderSansBold
	TextButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	TextButton.TextScaled = true
	TextButton.Text = ">"
	TextButton.TextXAlignment = Enum.TextXAlignment.Center
	TextButton.Parent = Tab

	local List = Instance.new("ScrollingFrame")
	List.Name = "List"
	List.BackgroundColor3 = Color3.fromRGB(19, 20, 20)
	List.BackgroundTransparency = 0
	List.Size = UDim2.new(1, 0, 0, 0)
	List.ZIndex = 10102
	List.Parent = Frame
	List.BorderSizePixel = 0
	List.ClipsDescendants = true
	List.AutomaticCanvasSize = Enum.AutomaticSize.Y
	List.CanvasSize = UDim2.new(0, 0, 0, 0)
	List.ScrollBarImageColor3 = Color3.fromRGB(38, 38, 38)
	List.ScrollBarThickness = 2
	List.Visible = true

	addUI(List, {
		Layout = {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0, 4),
		},
		Corner = {
			TopLeftRadius = UDim.new(0, 0),
			TopRightRadius = UDim.new(0, 0),
			BottomLeftRadius = UDim.new(0.04, 0),
			BottomRightRadius = UDim.new(0.04, 0),
		},
	})

	return Template_List
end

local function refreshListRecordSizes(listRecord)
	if not listRecord then
		return
	end

	local listHeight = 0
	local list = listRecord.List
	if list then
		local layout = list:FindFirstChildOfClass("UIListLayout")
		if layout then
			listHeight = layout.AbsoluteContentSize.Y
		end
	end

	local itemCount = #listRecord.Buttons + #listRecord.PriorityItems
	if listHeight <= 0 and itemCount > 0 then
		listHeight = (itemCount * 28) + math.max(itemCount - 1, 0) * 4
	end

	if listHeight > 0 then
		listHeight = math.min(244, math.max(34, math.ceil(listHeight)))
	end

	local headerHeight = listRecord.HeaderHeight or 28
	local openHeight = headerHeight + listHeight

	listRecord.ClosedGuiSize = UDim2.new(0, 248, 0, headerHeight)
	listRecord.OpenGuiSize = UDim2.new(0, 248, 0, openHeight)
	listRecord.ClosedFrameSize = UDim2.new(0, 231, 0, headerHeight)
	listRecord.OpenFrameSize = UDim2.new(0, 231, 0, openHeight)
	listRecord.ClosedListSize = UDim2.new(1, 0, 0, 0)
	listRecord.OpenListSize = UDim2.new(1, 0, 0, listHeight)

	if not listRecord.Tweening then
		if listRecord.Gui then
			listRecord.Gui.Size = if listRecord.Opened then listRecord.OpenGuiSize else listRecord.ClosedGuiSize
		end
		if listRecord.Frame then
			listRecord.Frame.Size = if listRecord.Opened then listRecord.OpenFrameSize else listRecord.ClosedFrameSize
		end
		if listRecord.List then
			listRecord.List.Size = if listRecord.Opened then listRecord.OpenListSize else listRecord.ClosedListSize
		end
	end
end

local function refreshListContainerLayout(listRecord)
	local gui = listRecord and listRecord.Gui
	local slot = gui and gui:FindFirstAncestor("Frame-Template")
	local panel = slot and slot:FindFirstChild("Panel")
	if not slot or not panel or not panel:IsA("ScrollingFrame") then
		return
	end
	local layout = panel:FindFirstChildOfClass("UIListLayout")
	local padding = panel:FindFirstChildOfClass("UIPadding")
	local panelHeight = layout and layout.AbsoluteContentSize.Y or 0
	if padding then
		panelHeight += padding.PaddingTop.Offset + padding.PaddingBottom.Offset
	end
	panelHeight = math.max(1, math.ceil(panelHeight))
	panel.AutomaticSize = Enum.AutomaticSize.None
	panel.Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset, 0, panelHeight)
	slot.AutomaticSize = Enum.AutomaticSize.None
	slot.Size = UDim2.new(slot.Size.X.Scale, slot.Size.X.Offset, 0, 24 + panelHeight)

	local row = slot.Parent
	if row and row:IsA("Frame") then
		local rowHeight = 0
		for _, sibling in ipairs(row:GetChildren()) do
			if sibling:IsA("Frame") and sibling.Name == "Frame-Template" then
				rowHeight = math.max(rowHeight, sibling.Size.Y.Offset)
			end
		end
		row.AutomaticSize = Enum.AutomaticSize.None
		row.Size = UDim2.new(row.Size.X.Scale, row.Size.X.Offset, 0, rowHeight)
	end
end

function toggleList(listRecord, forceOpened)
	if not listRecord or listRecord.Tweening then
		if listRecord then
			listRecord.QueuedState = if forceOpened ~= nil then forceOpened == true else not listRecord.Opened
		end
		return
	end

	local nextOpened = if forceOpened ~= nil then forceOpened == true else not listRecord.Opened
	if listRecord.Opened == nextOpened then
		return
	end

	refreshListRecordSizes(listRecord)

	listRecord.Tweening = true
	listRecord.Opened = nextOpened

	local listSize = if nextOpened then listRecord.OpenListSize else listRecord.ClosedListSize
	local frameSize = if nextOpened then listRecord.OpenFrameSize else listRecord.ClosedFrameSize
	local guiSize = if nextOpened then listRecord.OpenGuiSize else listRecord.ClosedGuiSize
	local rotation = if nextOpened then 90 else 0

	local tweens = {}
	if listRecord.Gui then
		table.insert(tweens, SERVICE.TweenService:Create(listRecord.Gui, MAIN_TWEEN_INFO, { Size = guiSize }))
	end
	if listRecord.Frame then
		table.insert(tweens, SERVICE.TweenService:Create(listRecord.Frame, MAIN_TWEEN_INFO, { Size = frameSize }))
	end
	if listRecord.List then
		table.insert(tweens, SERVICE.TweenService:Create(listRecord.List, MAIN_TWEEN_INFO, { Size = listSize }))
	end
	if listRecord.ToggleButton then
		table.insert(
			tweens,
			SERVICE.TweenService:Create(listRecord.ToggleButton, BUTTON_TWEEN_INFO, { Rotation = rotation })
		)
	end

	if #tweens == 0 then
		listRecord.Tweening = false
		return
	end

	local completedConnection
	completedConnection = tweens[1].Completed:Connect(function(playbackState)
		if completedConnection then
			completedConnection:Disconnect()
		end
		if playbackState ~= Enum.PlaybackState.Completed then
			return
		end
		listRecord.Tweening = false
		if listRecord.QueuedState ~= nil then
			local queuedState = listRecord.QueuedState
			listRecord.QueuedState = nil
			task.defer(function()
				toggleList(listRecord, queuedState)
			end)
		end
	end)

	for _, tween in ipairs(tweens) do
		tween:Play()
	end
	task.spawn(function()
		for _ = 1, 20 do
			refreshListContainerLayout(listRecord)
			SERVICE.RunService.Heartbeat:Wait()
		end
		refreshListContainerLayout(listRecord)
	end)
end

local function createList(parent, template, sectionRecord, listConfig)
	if not parent or not template or type(listConfig) ~= "table" then
		return nil
	end

	local gui = template:Clone()
	gui.LayoutOrder = getLayoutOrder(listConfig)
	gui.Visible = true
	gui.Parent = parent

	local frame = gui:FindFirstChild("Frame")
	local tab = frame and frame:FindFirstChild("Tab")
	local label = tab and tab:FindFirstChild("TextLabel")
	local toggleButton = tab and tab:FindFirstChild("TextButton")
	local list = frame and frame:FindFirstChild("List")

	local selectPrefix = listConfig.SelectPrefix
	local placeholder = listConfig.Placeholder or "SELECT ONE"
	if not selectPrefix and string.find(listConfig.Title or "", "SELECT ONE", 1, true) then
		selectPrefix = string.match(listConfig.Title, "^(.-):")
	end
	local isSelector = selectPrefix ~= nil

	if label then
		label.Text = if isSelector then ("%s: %s"):format(selectPrefix, placeholder) else listConfig.Title or "List"
	end

	local listRecord = {
		Type = "List",
		Title = listConfig.Title or "List",
		Label = label,
		IsSelector = isSelector,
		SelectPrefix = selectPrefix,
		Placeholder = placeholder,
		SelectedButton = nil,
		SelectedText = nil,
		Gui = gui,
		Frame = frame,
		Tab = tab,
		List = list,
		ToggleButton = toggleButton,
		Section = sectionRecord,
		Buttons = {},
		PriorityItems = {},
		Opened = false,
		Tweening = false,
		QueuedState = nil,
		HeaderHeight = 28,
		ClosedGuiSize = UDim2.new(0, 248, 0, 28),
		OpenGuiSize = UDim2.new(0, 248, 0, 28),
		ClosedFrameSize = UDim2.new(0, 231, 0, 28),
		OpenFrameSize = UDim2.new(0, 231, 0, 28),
		ClosedListSize = UDim2.new(1, 0, 0, 0),
		OpenListSize = UDim2.new(1, 0, 0, 0),
		Connections = {},
	}

	table.insert(UI_STATE.Lists, listRecord)
	table.insert(sectionRecord.Lists, listRecord)

	if list then
		list.Size = listRecord.ClosedListSize
		if type(listConfig.Items) == "table" then
			for _, itemConfig in ipairs(listConfig.Items) do
				if itemConfig.Type == "Button" then
					createListButton(list, sectionRecord, listRecord, itemConfig)
				elseif itemConfig.Type == "Priority" then
					createPriorityInput(list, sectionRecord, listRecord, itemConfig)
				end
			end
		end
	end

	task.defer(function()
		refreshListRecordSizes(listRecord)
	end)

	if listRecord.IsSelector then
		for _, buttonRecord in ipairs(listRecord.Buttons) do
			if buttonRecord.Enabled then
				listRecord.SelectedButton = buttonRecord
				listRecord.SelectedText = buttonRecord.Text
				if listRecord.Label then
					listRecord.Label.Text = ("%s: %s"):format(listRecord.SelectPrefix, buttonRecord.Text)
				end
				break
			end
		end
	end

	if toggleButton then
		table.insert(
			listRecord.Connections,
			toggleButton.MouseButton1Click:Connect(function()
				toggleList(listRecord)
			end)
		)
	end
	if tab then
		table.insert(
			listRecord.Connections,
			tab.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					toggleList(listRecord)
				end
			end)
		)
	end

	addSearchRecord({
		Kind = "List",
		Title = listRecord.Title,
		SearchText = getSearchText(listConfig, listRecord.Title),
		Section = sectionRecord,
		List = listRecord,
		TargetGui = gui,
	})

	return listRecord
end

local function scrollToGui(gui)
	if not UI_STATE.MainPanel or not gui then
		return
	end

	task.defer(function()
		if not UI_STATE.MainPanel or not gui.Parent then
			return
		end
		local offsetY = gui.AbsolutePosition.Y
			- UI_STATE.MainPanel.AbsolutePosition.Y
			+ UI_STATE.MainPanel.CanvasPosition.Y
		UI_STATE.MainPanel.CanvasPosition = Vector2.new(0, math.max(0, offsetY - 16))
	end)
end

local function highlightGui(gui)
	if not gui then
		return
	end

	local target = gui:FindFirstChild("TextButton", true) or gui:FindFirstChild("Tab", true) or gui
	if not target or not target:IsA("GuiObject") then
		return
	end

	local originalTransparency = target.BackgroundTransparency
	target.BackgroundTransparency = math.clamp(originalTransparency - 0.35, 0, 1)
	SERVICE.TweenService
		:Create(target, MAIN_TWEEN_INFO, {
			BackgroundTransparency = originalTransparency,
		})
		:Play()
end

local function setActiveSection(sectionName)
	if not sectionName then
		return
	end

	for name, sectionRecord in pairs(UI_STATE.Sections) do
		sectionRecord.Frame.Visible = name == sectionName
	end

	for name, navRecord in pairs(UI_STATE.NavigationButtons) do
		local isActive = name == sectionName
		navRecord.Button.BackgroundTransparency = if isActive then 0.6 else 1
	end

	UI_STATE.ActiveSection = sectionName
	if sectionName ~= "__Search" then
		UI_STATE.LastContentSection = sectionName
	end
end

local function clearSearchResults()
	for _, frame in ipairs(UI_STATE.SearchResultFrames) do
		if frame and frame.Parent then
			frame:Destroy()
		end
	end
	clearArray(UI_STATE.SearchResultFrames)
end

local function openSearchRecord(record)
	UI_STATE.SuppressSearchUpdate = true
	if UI_STATE.SearchBox then
		UI_STATE.SearchBox.Text = "Search"
	end
	UI_STATE.SuppressSearchUpdate = false
	clearSearchResults()

	if record.Section then
		setActiveSection(record.Section.Name)
	end
	if record.List then
		toggleList(record.List, true)
	end
	local targetGui = record.TargetGui or (record.Button and record.Button.Gui) or (record.List and record.List.Gui)
	scrollToGui(targetGui)
	highlightGui(targetGui)
end

local function connectGuiButtons(parent, callback)
	if not parent then
		return
	end

	if parent:IsA("GuiButton") then
		parent.MouseButton1Click:Connect(callback)
	end
	for _, descendant in ipairs(parent:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			descendant.MouseButton1Click:Connect(callback)
		end
	end
end

local function prepareSearchListPreview(listPreview, record)
	local frame = listPreview and listPreview:FindFirstChild("Frame")
	local tab = frame and frame:FindFirstChild("Tab")
	local toggleButton = tab and tab:FindFirstChild("TextButton")
	local list = frame and frame:FindFirstChild("List")
	if not frame or not list then
		return
	end

	listPreview.Visible = true
	listPreview.ClipsDescendants = true
	frame.ClipsDescendants = true
	list.ClipsDescendants = true

	local opened = false
	local tweening = false
	local queued = false
	local lastToggleAt = 0
	local headerHeight = (record.List and record.List.HeaderHeight) or 28
	local listHeight = 34

	local function refreshSizes()
		local layout = list:FindFirstChildOfClass("UIListLayout")
		if layout and layout.AbsoluteContentSize.Y > 0 then
			listHeight = math.min(244, math.max(34, math.ceil(layout.AbsoluteContentSize.Y)))
		elseif record.List and record.List.OpenListSize then
			listHeight = math.max(34, record.List.OpenListSize.Y.Offset)
		end
	end

	local function setPreviewSize(isOpened)
		local nextListHeight = if isOpened then listHeight else 0
		local nextHeight = headerHeight + nextListHeight
		listPreview.Size = UDim2.new(listPreview.Size.X.Scale, listPreview.Size.X.Offset, 0, nextHeight)
		frame.Size = UDim2.new(frame.Size.X.Scale, frame.Size.X.Offset, 0, nextHeight)
		list.Size = UDim2.new(1, 0, 0, nextListHeight)
		if toggleButton then
			toggleButton.Rotation = if isOpened then 90 else 0
		end
	end

	local function togglePreview()
		local now = os.clock()
		if now - lastToggleAt < 0.05 then
			return
		end
		lastToggleAt = now

		if tweening then
			queued = true
			return
		end

		refreshSizes()
		opened = not opened
		tweening = true
		local nextListHeight = if opened then listHeight else 0
		local nextHeight = headerHeight + nextListHeight

		local tweens = {
			SERVICE.TweenService:Create(listPreview, MAIN_TWEEN_INFO, {
				Size = UDim2.new(listPreview.Size.X.Scale, listPreview.Size.X.Offset, 0, nextHeight),
			}),
			SERVICE.TweenService:Create(frame, MAIN_TWEEN_INFO, {
				Size = UDim2.new(frame.Size.X.Scale, frame.Size.X.Offset, 0, nextHeight),
			}),
			SERVICE.TweenService:Create(list, MAIN_TWEEN_INFO, {
				Size = UDim2.new(1, 0, 0, nextListHeight),
			}),
		}
		if toggleButton then
			table.insert(
				tweens,
				SERVICE.TweenService:Create(toggleButton, BUTTON_TWEEN_INFO, {
					Rotation = if opened then 90 else 0,
				})
			)
		end

		local completedConnection
		completedConnection = tweens[1].Completed:Connect(function(playbackState)
			if completedConnection then
				completedConnection:Disconnect()
			end
			if playbackState ~= Enum.PlaybackState.Completed then
				return
			end

			tweening = false
			if queued then
				queued = false
				task.defer(togglePreview)
			end
		end)

		for _, tween in ipairs(tweens) do
			tween:Play()
		end
	end

	setPreviewSize(false)
	task.defer(function()
		if listPreview.Parent then
			refreshSizes()
			setPreviewSize(opened)
		end
	end)

	if toggleButton then
		toggleButton.MouseButton1Click:Connect(togglePreview)
	end
	if tab then
		tab.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				togglePreview()
			end
		end)
	end
	if list then
		connectGuiButtons(list, function()
			openSearchRecord(record)
		end)
	end
end

local function createSearchResult(record)
	if not UI_STATE.SearchContent or not record then
		return
	end

	local frame = Instance.new("Frame")
	frame.Name = "Frame-Template"
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(0, 527, 0, 0)
	frame.ZIndex = 10003
	frame.Parent = UI_STATE.SearchContent
	table.insert(UI_STATE.SearchResultFrames, frame)

	addUI(frame, {
		Layout = {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0, 4),
		},
	})

	local sectionButton = Instance.new("TextButton")
	sectionButton.Name = "TextButton"
	sectionButton.BackgroundColor3 = Color3.fromRGB(30, 30, 33)
	sectionButton.BackgroundTransparency = 0.6
	sectionButton.Size = UDim2.new(0.966, 0, 0, 24)
	sectionButton.ZIndex = 10010
	sectionButton.Font = Enum.Font.BuilderSansBold
	sectionButton.Text = tostring((record.Section and record.Section.Name) or "Section")
	sectionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	sectionButton.TextScaled = true
	sectionButton.TextXAlignment = Enum.TextXAlignment.Left
	sectionButton.Parent = frame

	addUI(sectionButton, {
		Corner = {
			TopLeftRadius = UDim.new(0.3, 0),
			TopRightRadius = UDim.new(0.3, 0),
			BottomLeftRadius = UDim.new(0, 0),
			BottomRightRadius = UDim.new(0, 0),
		},
	})
	sectionButton.MouseButton1Click:Connect(function()
		openSearchRecord(record)
	end)

	local targetGui = record.TargetGui or (record.Button and record.Button.Gui) or (record.List and record.List.Gui)
	if not targetGui then
		return
	end

	local preview = targetGui:Clone()
	preview.Visible = true
	preview.LayoutOrder = 1
	preview.Parent = frame

	if record.Kind == "List" then
		prepareSearchListPreview(preview, record)
	else
		connectGuiButtons(preview, function()
			openSearchRecord(record)
		end)
		preview.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				openSearchRecord(record)
			end
		end)
	end
end

local function createSearchEmptyResult()
	if not UI_STATE.SearchContent then
		return
	end

	local frame = Instance.new("Frame")
	frame.Name = "Frame-Template"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(0, 527, 0, 32)
	frame.ZIndex = 10003
	frame.Parent = UI_STATE.SearchContent
	table.insert(UI_STATE.SearchResultFrames, frame)

	local label = Instance.new("TextLabel")
	label.Name = "TextLabel"
	label.BackgroundColor3 = Color3.fromRGB(54, 54, 59)
	label.BackgroundTransparency = 0.6
	label.Size = UDim2.new(0.966, 0, 0, 28)
	label.ZIndex = 10010
	label.Font = Enum.Font.BuilderSansBold
	label.Text = "No results"
	label.TextColor3 = Color3.fromRGB(161, 161, 161)
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame

	addUI(label, {
		Corner = UDim.new(0.2, 0),
	})
end

local function updateSearchResults(rawText)
	if UI_STATE.SuppressSearchUpdate then
		return
	end

	local query = normalizeSearchText(rawText)
	if query == "" or query == "search" then
		clearSearchResults()
		setActiveSection(UI_STATE.LastContentSection or UI_STATE.SectionOrder[1])
		return
	end

	clearSearchResults()
	setActiveSection("__Search")

	local resultsCount = 0
	for _, record in ipairs(UI_STATE.SearchRecords) do
		if string.find(record.SearchText, query, 1, true) then
			createSearchResult(record)
			resultsCount += 1
		end
	end

	if resultsCount == 0 then
		createSearchEmptyResult()
	end
end

local function setupFrameTemplateToggle(templateRecord, defaultOpened)
	if not templateRecord or not templateRecord.Panel or not templateRecord.TabButton then
		return
	end

	local panel = templateRecord.Panel
	local tabButton = templateRecord.TabButton
	local tab = templateRecord.Tab
	local tabCorner = tab and tab:FindFirstChildOfClass("UICorner")
	local panelXScale = panel.Size.X.Scale
	local panelXOffset = panel.Size.X.Offset
	local panelAutomaticSize = panel.AutomaticSize

	local toggle
	local opened = defaultOpened ~= false
	local tweening = false
	local queuedClick = false
	local openedSize = panel.Size
	local closedSize = UDim2.new(panelXScale, panelXOffset, 0, 0)

	local function lockTabSize()
		if not tab or templateRecord.TabSizeLocked then
			return
		end

		local parentHeight = if tab.Parent then tab.Parent.Size.Y.Offset else 0
		local tabHeight = math.max(math.floor((tab.Size.Y.Scale * parentHeight) + tab.Size.Y.Offset + 0.5), 1)
		tab.Size = UDim2.new(tab.Size.X.Scale, tab.Size.X.Offset, 0, tabHeight)
		templateRecord.TabSizeLocked = true
	end

	local function getPanelContentHeight()
		local height = math.max(panel.AbsoluteSize.Y, panel.Size.Y.Offset)
		local layout = panel:FindFirstChildOfClass("UIListLayout")
		if layout then
			height = math.max(height, layout.AbsoluteContentSize.Y)
		end

		local padding = panel:FindFirstChildOfClass("UIPadding")
		if padding then
			height += padding.PaddingTop.Offset + padding.PaddingBottom.Offset
		end

		return math.max(math.ceil(height), 20)
	end

	local function refreshPanelSizes(applyCurrentState, freezeAutomaticSize)
		lockTabSize()
		openedSize = UDim2.new(panelXScale, panelXOffset, 0, getPanelContentHeight())
		closedSize = UDim2.new(panelXScale, panelXOffset, 0, 0)
		panel.AutomaticSize = if freezeAutomaticSize or not opened then Enum.AutomaticSize.None else panelAutomaticSize
		panel.ClipsDescendants = true
		panel.Visible = true

		if applyCurrentState and not tweening then
			panel.Size = if opened then openedSize else closedSize
		end
	end

	local function setTabCorner(isOpened)
		if not tabCorner then
			return
		end
		local bottomRadius = if isOpened then UDim.new(0, 0) else UDim.new(0.3, 0)
		tabCorner.BottomLeftRadius = bottomRadius
		tabCorner.BottomRightRadius = bottomRadius
		tabCorner.TopLeftRadius = UDim.new(0.3, 0)
		tabCorner.TopRightRadius = UDim.new(0.3, 0)
	end

	local function finishAnimation(playbackState, completedConnection)
		if completedConnection then
			completedConnection:Disconnect()
		end
		if playbackState ~= Enum.PlaybackState.Completed then
			return
		end

		if opened then
			tabButton.Rotation = 90
			panel.Visible = true
			panel.AutomaticSize = panelAutomaticSize
		else
			tabButton.Rotation = 0
			panel.AutomaticSize = Enum.AutomaticSize.None
			setTabCorner(false)
		end

		tweening = false
		if queuedClick then
			queuedClick = false
			task.defer(function()
				if tabButton.Parent and panel.Parent then
					toggle()
				end
			end)
		end
	end

	toggle = function()
		if tweening then
			queuedClick = true
			return
		end

		refreshPanelSizes(false, true)
		tweening = true
		opened = not opened
		panel.Visible = true
		panel.AutomaticSize = Enum.AutomaticSize.None

		local panelTween = SERVICE.TweenService:Create(panel, MAIN_TWEEN_INFO, {
			Size = if opened then openedSize else closedSize,
		})
		local buttonTween = SERVICE.TweenService:Create(tabButton, BUTTON_TWEEN_INFO, {
			Rotation = if opened then 90 else 0,
		})
		local completedConnection
		completedConnection = panelTween.Completed:Connect(function(playbackState)
			finishAnimation(playbackState, completedConnection)
		end)

		if opened then
			setTabCorner(true)
		end

		panelTween:Play()
		buttonTween:Play()
	end

	refreshPanelSizes(false, not opened)
	if not opened then
		panel.AutomaticSize = Enum.AutomaticSize.None
		panel.Size = closedSize
		tabButton.Rotation = 0
		setTabCorner(false)
	else
		panel.AutomaticSize = panelAutomaticSize
		panel.Size = openedSize
		tabButton.Rotation = 90
		setTabCorner(true)
	end

	task.defer(function()
		if panel.Parent then
			refreshPanelSizes(true, not opened)
		end
	end)

	tabButton.MouseButton1Click:Connect(toggle)
end

local function createSection(parent, sectionConfig)
	if not parent or type(sectionConfig) ~= "table" then
		return nil
	end

	local sectionFrame = Instance.new("Frame")
	sectionFrame.Name = "Section-" .. tostring(sectionConfig.Name)
	sectionFrame.AutomaticSize = Enum.AutomaticSize.Y
	sectionFrame.BackgroundTransparency = 1
	sectionFrame.Size = UDim2.new(1, 0, 0, 0)
	sectionFrame.Visible = false
	sectionFrame.ZIndex = 10002
	sectionFrame.Parent = parent

	addUI(sectionFrame, {
		Layout = {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0, 6),
		},
	})

	local panel
	local controlsPanel
	local listsPanel
	local templateFrame
	local templateSlots

	if sectionConfig.Layout == "Double" then
		local doubleFrame, slots = CreateFrameTemplate_2(
			sectionFrame,
			sectionConfig.LeftTitle or sectionConfig.Name,
			sectionConfig.RightTitle or sectionConfig.Name,
			"Frame-Template-Double-Farming"
		)
		templateFrame = doubleFrame
		templateSlots = slots
		listsPanel = slots and slots[1] and slots[1].Panel
		if sectionConfig.ControlsSlot == "Left" then
			controlsPanel = listsPanel
		else
			controlsPanel = slots and slots[2] and slots[2].Panel
		end
		panel = listsPanel or controlsPanel
	else
		templateFrame, panel = CreateFrameTemplate_1(
			sectionFrame,
			sectionConfig.Title or sectionConfig.Name,
			"Frame-Template-Small-Farming"
		)
		if sectionConfig.CompactPrimary then
			templateFrame.Size = UDim2.new(0, 527, 0, 0)
		end
		if sectionConfig.VerticalControls then
			local layout = panel and panel:FindFirstChildOfClass("UIListLayout")
			if layout then
				layout.FillDirection = Enum.FillDirection.Vertical
				layout.Wraps = false
				layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
				layout.Padding = UDim.new(0, 3)
			end
		end
		controlsPanel = panel
		listsPanel = panel
	end

	if not panel then
		return nil
	end

	controlsPanel = controlsPanel or panel
	listsPanel = listsPanel or panel
	if sectionConfig.ControlsPosition == "AfterLists" and controlsPanel == listsPanel then
		local panelLayout = panel:FindFirstChildOfClass("UIListLayout")
		if panelLayout then
			panelLayout.FillDirection = Enum.FillDirection.Horizontal
			panelLayout.Wraps = true
			panelLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		end
	end
	local listTemplate = createListTemplate(listsPanel)
	local listTemplatesByPanel = {
		[listsPanel] = listTemplate,
	}

	local sectionRecord = {
		Name = sectionConfig.Name,
		Config = sectionConfig,
		Frame = sectionFrame,
		Panel = panel,
		TemplateFrame = templateFrame,
		ListTemplate = listTemplate,
		Lists = {},
	}

	UI_STATE.Sections[sectionRecord.Name] = sectionRecord
	table.insert(UI_STATE.SectionOrder, sectionRecord.Name)

	local sectionControls = getSectionControls(sectionConfig)
	local leftControls = sectionConfig.LeftControls or {}
	local rightControls = sectionConfig.RightControls or {}

	local function createControlsOnPanel(targetPanel, controls)
		if not targetPanel or #controls == 0 then
			return
		end

		local buttonTemplate = nil
		local buttonGroup = {
			Title = sectionRecord.Name,
			Buttons = {},
			IsButtonGroup = true,
			Section = sectionRecord,
		}
		sectionRecord.ButtonGroup = buttonGroup

		for _, itemConfig in ipairs(controls) do
			if itemConfig.Type == "TextBox" then
				createTextBoxControl(targetPanel, sectionRecord, itemConfig)
			elseif itemConfig.Type == "Label" then
				createLabelControl(targetPanel, sectionRecord, itemConfig)
			elseif itemConfig.Type == "Slider" then
				createSliderControl(targetPanel, sectionRecord, itemConfig)
			elseif itemConfig.Type == "Button" or itemConfig.Type == "Action" then
				buttonTemplate = buttonTemplate or createButtonTemplate(targetPanel)
				createButton(targetPanel, buttonTemplate, sectionRecord, buttonGroup, itemConfig)
			end
		end
	end

	local function createListsOnPanel(targetPanel, lists)
		if not targetPanel or type(lists) ~= "table" then
			return
		end

		local targetListTemplate = listTemplatesByPanel[targetPanel]
		if not targetListTemplate then
			targetListTemplate = createListTemplate(targetPanel)
			listTemplatesByPanel[targetPanel] = targetListTemplate
		end

		for _, listConfig in ipairs(lists) do
			createList(targetPanel, targetListTemplate, sectionRecord, listConfig)
		end
	end

	local function createPanelContent(targetPanel, content)
		if not targetPanel or type(content) ~= "table" then
			return
		end

		local controls = content
		if type(content.Buttons) == "table" or type(content.Controls) == "table" then
			controls = {}

			for _, itemConfig in ipairs(content) do
				table.insert(controls, itemConfig)
			end
			for _, itemConfig in ipairs(content.Buttons or {}) do
				table.insert(controls, itemConfig)
			end
			for _, itemConfig in ipairs(content.Controls or {}) do
				table.insert(controls, itemConfig)
			end
		end

		if content.ListsFirst then
			createListsOnPanel(targetPanel, content.Lists)
			createControlsOnPanel(targetPanel, controls)
		else
			createControlsOnPanel(targetPanel, controls)
			createListsOnPanel(targetPanel, content.Lists)
		end
	end

	local function createSectionControls()
		createControlsOnPanel(controlsPanel, sectionControls)
	end

	local function createSectionLists()
		createListsOnPanel(listsPanel, sectionConfig.Lists)
	end

	if sectionConfig.ControlsPosition == "AfterLists" then
		createSectionLists()
		createSectionControls()
	else
		createSectionControls()
		createSectionLists()
	end

	createPanelContent(listsPanel, leftControls)
	createPanelContent(controlsPanel, rightControls)

	local secondary = sectionConfig.SecondaryDouble
	if type(secondary) == "table" then
		local _, secondarySlots = CreateFrameTemplate_2(
			sectionFrame,
			secondary.LeftTitle or "Settings",
			secondary.RightTitle or "Settings",
			"Frame-Template-Double-Farming"
		)
		if secondarySlots then
			if secondary.HideRight and secondarySlots[2] and secondarySlots[2].Frame then
				secondarySlots[2].Frame.Visible = false
			end
			for _, slot in ipairs(secondarySlots) do
				local layout = slot.Panel and slot.Panel:FindFirstChildOfClass("UIListLayout")
				if layout then
					layout.FillDirection = Enum.FillDirection.Vertical
					layout.Wraps = false
					layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
					layout.VerticalAlignment = Enum.VerticalAlignment.Top
					layout.Padding = UDim.new(0, 3)
				end
			end
			createPanelContent(secondarySlots[1] and secondarySlots[1].Panel, secondary.LeftControls or {})
			createPanelContent(secondarySlots[2] and secondarySlots[2].Panel, secondary.RightControls or {})
			setupFrameTemplateToggle(secondarySlots[1], secondary.LeftOpened ~= false)
			if not secondary.HideRight then
				setupFrameTemplateToggle(secondarySlots[2], secondary.RightOpened ~= false)
			end
		end
	end

	local secondarySingle = sectionConfig.SecondarySingle
	if type(secondarySingle) == "table" then
		local secondaryFrame, secondaryPanel, secondaryTab, secondaryButton =
			CreateFrameTemplate_1(sectionFrame, secondarySingle.Title or "Settings", "Frame-Template-Secondary")
		secondaryFrame.LayoutOrder = 2
		local layout = secondaryPanel and secondaryPanel:FindFirstChildOfClass("UIListLayout")
		if layout then
			layout.FillDirection = Enum.FillDirection.Horizontal
			layout.Wraps = true
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
			layout.VerticalAlignment = Enum.VerticalAlignment.Top
			layout.Padding = UDim.new(0, 3)
		end
		createPanelContent(secondaryPanel, secondarySingle.Controls or {})
		setupFrameTemplateToggle({
			Frame = secondaryFrame,
			Panel = secondaryPanel,
			Tab = secondaryTab,
			TabButton = secondaryButton,
		}, secondarySingle.Opened ~= false)
	end

	if sectionConfig.Layout == "Double" and templateSlots then
		setupFrameTemplateToggle(templateSlots[1], sectionConfig.LeftOpened)
		setupFrameTemplateToggle(templateSlots[2], sectionConfig.RightOpened)
	else
		setupFrameTemplateToggle({
			Frame = templateFrame,
			Panel = panel,
			Tab = templateFrame and templateFrame:FindFirstChild("Tab"),
			TabButton = templateFrame and templateFrame:FindFirstChild("Tab") and templateFrame
				:FindFirstChild("Tab")
				:FindFirstChild("Tab_Button"),
		}, sectionConfig.FrameOpened)
	end

	return sectionRecord
end

local function createSearchSection(parent)
	local searchFrame = Instance.new("Frame")
	searchFrame.Name = "Section-Search"
	searchFrame.AutomaticSize = Enum.AutomaticSize.Y
	searchFrame.BackgroundTransparency = 1
	searchFrame.Size = UDim2.new(1, 0, 0, 0)
	searchFrame.Visible = false
	searchFrame.ZIndex = 10002
	searchFrame.Parent = parent

	addUI(searchFrame, {
		Layout = {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0, 6),
		},
	})

	local sectionRecord = {
		Name = "__Search",
		Frame = searchFrame,
		Lists = {},
	}
	UI_STATE.Sections.__Search = sectionRecord
	UI_STATE.SearchSection = sectionRecord
	UI_STATE.SearchContent = searchFrame
	return sectionRecord
end

local function makeDraggable(targetFrame, dragHandle)
	if not targetFrame or not dragHandle or not SERVICE.UserInputService then
		return
	end

	local dragging = false
	local dragInput = nil
	local dragStart = nil
	local startPosition = nil

	local function update(input)
		if not dragging or not dragStart or not startPosition then
			return
		end
		local delta = input.Position - dragStart
		targetFrame.Position = UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y
		)
	end

	dragHandle.InputBegan:Connect(function(input)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		dragging = true
		dragStart = input.Position
		startPosition = targetFrame.Position

		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end)

	dragHandle.InputChanged:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragInput = input
		end
	end)

	SERVICE.UserInputService.InputChanged:Connect(function(input)
		if input == dragInput then
			update(input)
		end
	end)
end

local function createNavigationButton(parent, sectionName, label, image, layoutOrder)
	local button = Instance.new("TextButton")
	button.Name = "Button-" .. tostring(layoutOrder + 1)
	button.Parent = parent
	button.Size = UDim2.new(0.925, 0, 0.05, 0)
	button.BackgroundColor3 = Color3.fromRGB(30, 30, 33)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.LayoutOrder = layoutOrder
	button.ZIndex = 10002

	local corner = Instance.new("UICorner")
	corner.BottomLeftRadius = UDim.new(0, 0)
	corner.BottomRightRadius = UDim.new(0.4, 0)
	corner.TopLeftRadius = UDim.new(0, 0)
	corner.TopRightRadius = UDim.new(0.4, 0)
	corner.Parent = button

	addUI(button, {
		Layout = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0.06, 0),
		},
	})

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "TextLabel"
	textLabel.Parent = button
	textLabel.Size = UDim2.new(0.607, 0, 0.662, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.BuilderSansBold
	textLabel.Text = label
	textLabel.TextScaled = true
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.LayoutOrder = 1
	textLabel.ZIndex = 10003

	local imageLabel = Instance.new("ImageLabel")
	imageLabel.Name = "Image"
	imageLabel.Parent = button
	imageLabel.Size = UDim2.new(0.14, 0, 0.6, 0)
	imageLabel.ImageColor3 = Color3.fromRGB(255, 255, 255)
	imageLabel.Image = image
	imageLabel.ScaleType = Enum.ScaleType.Fit
	imageLabel.BackgroundTransparency = 1
	imageLabel.LayoutOrder = 0
	imageLabel.ZIndex = 10003

	local navRecord = {
		Button = button,
		TextLabel = textLabel,
		ImageLabel = imageLabel,
	}

	button.MouseButton1Click:Connect(function()
		if UI_STATE.SearchBox and UI_STATE.SearchBox.Text ~= "Search" then
			UI_STATE.SuppressSearchUpdate = true
			UI_STATE.SearchBox.Text = "Search"
			UI_STATE.SuppressSearchUpdate = false
			clearSearchResults()
		end
		setActiveSection(sectionName)
	end)

	UI_STATE.NavigationButtons[sectionName] = navRecord
	return navRecord
end

--// Create MainMenu //--
local function CreateMainMenu()
	local Main_Frame = getScreenGui():FindFirstChild("EggHuntLayer")
	local Tab_Button = nil
	local Main = nil

	clearDictionary(UI_STATE.Sections)
	clearArray(UI_STATE.SectionOrder)
	clearDictionary(UI_STATE.NavigationButtons)
	clearArray(UI_STATE.Buttons)
	clearArray(UI_STATE.Lists)
	clearArray(UI_STATE.SearchRecords)
	clearArray(UI_STATE.SearchResultFrames)
	clearDictionary(UI_STATE.ButtonStates)
	clearDictionary(UI_STATE.ConfigInputs)
	clearDictionary(UI_STATE.Sliders)
	clearDictionary(UI_STATE.PriorityInputs)
	clearDictionary(UI_STATE.PriorityByImage)
	UI_STATE.ActiveSection = nil
	UI_STATE.LastContentSection = nil
	UI_STATE.MainPanel = nil
	UI_STATE.SearchBox = nil
	UI_STATE.SearchSection = nil
	UI_STATE.SearchContent = nil
	UI_STATE.PushContainer = nil
	if UI_STATE.ConfigPasteFrame and UI_STATE.ConfigPasteFrame.Parent then
		UI_STATE.ConfigPasteFrame:Destroy()
	end
	UI_STATE.ConfigPasteFrame = nil
	clearArray(UI_STATE.PushNotifications)
	UI_STATE.SuppressSearchUpdate = false

	local function CreateTab()
		local Tab = Instance.new("Frame")
		Tab.Name = "Tab"
		Tab.Active = true
		Tab.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
		Tab.BackgroundTransparency = 0.05
		Tab.Size = UDim2.new(1, 0, 0.076, 0)
		Tab.Parent = Main_Frame
		Tab.ZIndex = 10000

		addUI(Tab, {
			Corner = {
				TopLeftRadius = UDim.new(0.3, 0),
				TopRightRadius = UDim.new(0.3, 0),
				BottomLeftRadius = UDim.new(0, 0),
				BottomRightRadius = UDim.new(0, 0),
			},
			Shadow = {
				Color = Color3.fromRGB(0, 0, 0),
				BlurRadius = UDim.new(0, 20),
				Transparency = 0.8,
				ZIndex = 9999,
			},
		})

		Tab_Button = Instance.new("TextButton")
		Tab_Button.Name = "Tab_Button"
		Tab_Button.AnchorPoint = Vector2.new(0.5, 0.5)
		Tab_Button.BackgroundTransparency = 1
		Tab_Button.Position = UDim2.new(0.977, 0, 0.495, 0)
		Tab_Button.Size = UDim2.new(0.046, 0, 1, 0)
		Tab_Button.Font = Enum.Font.BuilderSansBold
		Tab_Button.Text = ">"
		Tab_Button.ZIndex = 10001
		Tab_Button.TextColor3 = Color3.fromRGB(255, 255, 255)
		Tab_Button.TextScaled = true
		Tab_Button.Parent = Tab

		local ImageLabel = Instance.new("ImageLabel")
		ImageLabel.Name = "ImageLabel"
		ImageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		ImageLabel.BackgroundTransparency = 1
		ImageLabel.Position = UDim2.new(0.026, 0, 0.5, 0)
		ImageLabel.Size = UDim2.new(0.026, 0, 0.513, 0)
		ImageLabel.ZIndex = 10001
		ImageLabel.Image = IMAGES_ALL[1]
		ImageLabel.Parent = Tab

		addUI(ImageLabel, {
			Corner = {
				TopLeftRadius = UDim.new(0.4, 0),
				TopRightRadius = UDim.new(0.4, 0),
				BottomLeftRadius = UDim.new(0.4, 0),
				BottomRightRadius = UDim.new(0.4, 0),
			},
		})

		local TextLabel = Instance.new("TextLabel")
		TextLabel.Name = "TextLabel"
		TextLabel.BackgroundTransparency = 1
		TextLabel.Position = UDim2.new(0.049, 0, 0.26, 0)
		TextLabel.Size = UDim2.new(0.23, 0, 0.475, 0)
		TextLabel.Font = Enum.Font.BuilderSansBold
		TextLabel.Text = SERVICE.Version
		TextLabel.ZIndex = 10001
		TextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		TextLabel.TextScaled = true
		TextLabel.TextXAlignment = Enum.TextXAlignment.Left
		TextLabel.Parent = Tab

		makeDraggable(Main_Frame, Tab)
	end

	local function CreateMain()
		Main = Instance.new("Frame")
		Main.Name = "Main"
		Main.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
		Main.BackgroundTransparency = 0.05
		Main.ClipsDescendants = true
		Main.Size = UDim2.new(1, 0, 0.924, 0)
		Main.Parent = Main_Frame
		Main.ZIndex = 10000

		addUI(Main, {
			Corner = {
				TopLeftRadius = UDim.new(0, 0),
				TopRightRadius = UDim.new(0, 0),
				BottomLeftRadius = UDim.new(0.025, 0),
				BottomRightRadius = UDim.new(0.025, 0),
			},
			Shadow = {
				Color = Color3.fromRGB(0, 0, 0),
				BlurRadius = UDim.new(0, 20),
				Transparency = 0.8,
				ZIndex = 9999,
			},
		})

		addUI(Main, {
			Layout = {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				Padding = UDim.new(0, 0),
			},
		})

		local Navigation = Instance.new("Frame")
		Navigation.Name = "Navigation"
		Navigation.BackgroundTransparency = 1
		Navigation.Size = UDim2.new(0.196, 0, 1, 0)
		Navigation.ZIndex = 10001
		Navigation.ClipsDescendants = true
		Navigation.Parent = Main

		addUI(Navigation, {
			Layout = {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				Padding = UDim.new(0.02, 0),
			},
		})

		local Button_Search = Instance.new("TextButton")
		Button_Search.Name = "Button-1"
		Button_Search.Parent = Navigation
		Button_Search.Size = UDim2.new(0.925, 0, 0.05, 0)
		Button_Search.BackgroundTransparency = 1
		Button_Search.Text = ""
		Button_Search.LayoutOrder = 0
		Button_Search.ZIndex = 10002

		local Button_Textbox = Instance.new("TextBox")
		Button_Textbox.Name = "Search"
		Button_Textbox.Parent = Button_Search
		Button_Textbox.Size = UDim2.new(0.607, 0, 0.662, 0)
		Button_Textbox.BackgroundTransparency = 1
		Button_Textbox.ZIndex = 10003
		Button_Textbox.ClearTextOnFocus = true
		Button_Textbox.Text = "Search"
		Button_Textbox.Font = Enum.Font.BuilderSansMedium
		Button_Textbox.TextColor3 = Color3.fromRGB(66, 66, 66)
		Button_Textbox.TextWrapped = false
		Button_Textbox.LayoutOrder = 1
		Button_Textbox.TextXAlignment = Enum.TextXAlignment.Left
		Button_Textbox.TextYAlignment = Enum.TextYAlignment.Center
		Button_Textbox.TextScaled = true
		Button_Textbox.TextEditable = true
		UI_STATE.SearchBox = Button_Textbox

		addUI(Button_Search, {
			Layout = {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0.06, 0),
			},
		})

		local imageLabel = Instance.new("ImageLabel")
		imageLabel.Name = "Image"
		imageLabel.Parent = Button_Search
		imageLabel.Size = UDim2.new(0.14, 0, 0.6, 0)
		imageLabel.ImageColor3 = Color3.fromRGB(66, 66, 66)
		imageLabel.Image = IMAGES_ALL[2]
		imageLabel.ScaleType = Enum.ScaleType.Fit
		imageLabel.BackgroundTransparency = 1
		imageLabel.LayoutOrder = 0
		imageLabel.ZIndex = 10003

		for index, sectionConfig in ipairs(Sections) do
			createNavigationButton(
				Navigation,
				sectionConfig.Name,
				sectionConfig.NavigationButton or sectionConfig.Name,
				sectionConfig.Icon,
				index
			)
		end

		local Frame_Player = Instance.new("Frame")
		Frame_Player.Name = "Frame_Player"
		Frame_Player.Parent = Navigation
		Frame_Player.Size = UDim2.new(0.865, 0, 0.239, 0)
		Frame_Player.BackgroundTransparency = 1
		Frame_Player.LayoutOrder = #Sections + 2
		Frame_Player.ZIndex = 10002

		local ImageLabel_Player = Instance.new("ImageLabel")
		ImageLabel_Player.Name = "ImageLabel"
		ImageLabel_Player.Parent = Frame_Player
		ImageLabel_Player.Size = UDim2.new(0, 39, 0, 39)
		ImageLabel_Player.Position = UDim2.new(0.075, 0, 0.524, 0)
		ImageLabel_Player.BackgroundTransparency = 1
		ImageLabel_Player.ZIndex = 10002

		local corner = Instance.new("UICorner")
		corner.Name = "UICorner"
		corner.Parent = ImageLabel_Player
		corner.CornerRadius = UDim.new(1, 0)

		local textLabelOther = Instance.new("TextLabel")
		textLabelOther.Name = "TextLabel_Other"
		textLabelOther.Parent = Frame_Player
		textLabelOther.Size = UDim2.new(0.44, 0, 0.111, 0)
		textLabelOther.Position = UDim2.new(0.438, 0, 0.581, 0)
		textLabelOther.BackgroundTransparency = 1
		textLabelOther.Font = Enum.Font.BuilderSansBold
		textLabelOther.Text = "Welcome!"
		textLabelOther.TextScaled = true
		textLabelOther.TextXAlignment = Enum.TextXAlignment.Left
		textLabelOther.TextColor3 = Color3.fromRGB(66, 66, 66)
		textLabelOther.ZIndex = 10002

		local textLabelPlayer = Instance.new("TextLabel")
		textLabelPlayer.Name = "TextLabel_Player"
		textLabelPlayer.Parent = Frame_Player
		textLabelPlayer.Size = UDim2.new(0.544, 0, 0.133, 0)
		textLabelPlayer.Position = UDim2.new(0.43, 0, 0.692, 0)
		textLabelPlayer.BackgroundTransparency = 1
		textLabelPlayer.Font = Enum.Font.BuilderSansBold
		textLabelPlayer.Text = "@" .. SERVICE.Player.Name
		textLabelPlayer.TextScaled = true
		textLabelPlayer.TextXAlignment = Enum.TextXAlignment.Left
		textLabelPlayer.TextColor3 = Color3.fromRGB(161, 161, 161)
		textLabelPlayer.ZIndex = 10002

		local success, image = pcall(function()
			return SERVICE.Players:GetUserThumbnailAsync(
				SERVICE.Player.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
		end)

		if success and Frame_Player.Parent ~= nil then
			ImageLabel_Player.Image = image
		end

		local Panel = Instance.new("ScrollingFrame")
		Panel.Name = "Panel"
		Panel.Parent = Main
		Panel.Size = UDim2.new(0.804, 0, 1, 0)
		Panel.BackgroundTransparency = 1
		Panel.CanvasSize = UDim2.new(0, 0, 0, 0)
		Panel.BorderSizePixel = 0
		Panel.ScrollBarImageColor3 = Color3.fromRGB(38, 38, 38)
		Panel.ScrollBarThickness = 6
		Panel.ScrollingEnabled = true
		Panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
		Panel.ClipsDescendants = true
		Panel.ZIndex = 10001
		UI_STATE.MainPanel = Panel

		addUI(Panel, {
			Layout = {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Top,
				Padding = UDim.new(0.02, 0),
			},
		})

		for _, sectionConfig in ipairs(Sections) do
			createSection(Panel, sectionConfig)
		end
		createSearchSection(Panel)

		Button_Textbox:GetPropertyChangedSignal("Text"):Connect(function()
			updateSearchResults(Button_Textbox.Text)
		end)
		Button_Textbox.FocusLost:Connect(function()
			if Button_Textbox.Text == "" then
				UI_STATE.SuppressSearchUpdate = true
				Button_Textbox.Text = "Search"
				UI_STATE.SuppressSearchUpdate = false
				updateSearchResults("")
			end
		end)
	end

	local function SetupTabToggle()
		if not Tab_Button or not Main then
			warn(WARNING_LIST[4])
			return
		end

		local tab = Main_Frame:FindFirstChild("Tab")
		local tabCorner = tab and tab:FindFirstChildOfClass("UICorner")
		if not tabCorner then
			warn(WARNING_LIST[4])
			return
		end

		local tabSizeLocked = false
		local function lockMainTabSize()
			if tabSizeLocked then
				return
			end
			local tabHeight = tab.AbsoluteSize.Y
			if tabHeight > 0 then
				tab.Size = UDim2.new(tab.Size.X.Scale, tab.Size.X.Offset, 0, tabHeight)
				tabSizeLocked = true
			end
		end
		lockMainTabSize()
		task.defer(lockMainTabSize)

		local toggle
		local opened = true
		local tweening = false
		local queuedClick = false
		local openedSize = Main.Size
		local closedSize = UDim2.new(openedSize.X.Scale, openedSize.X.Offset, 0, 0)

		local mainOpenTween = SERVICE.TweenService:Create(Main, MAIN_TWEEN_INFO, {
			Size = openedSize,
		})
		local mainCloseTween = SERVICE.TweenService:Create(Main, MAIN_TWEEN_INFO, {
			Size = closedSize,
		})
		local buttonOpenTween = SERVICE.TweenService:Create(Tab_Button, BUTTON_TWEEN_INFO, {
			Rotation = 360,
		})
		local buttonCloseTween = SERVICE.TweenService:Create(Tab_Button, BUTTON_TWEEN_INFO, {
			Rotation = 180,
		})

		local function setTabCorner(isOpened)
			local bottomRadius = if isOpened then UDim.new(0, 0) else UDim.new(0.3, 0)
			tabCorner.BottomLeftRadius = bottomRadius
			tabCorner.BottomRightRadius = bottomRadius
			tabCorner.TopLeftRadius = UDim.new(0.3, 0)
			tabCorner.TopRightRadius = UDim.new(0.3, 0)
		end

		local function finishAnimation(playbackState)
			if playbackState ~= Enum.PlaybackState.Completed then
				return
			end
			if opened then
				Tab_Button.Rotation = 0
				Main.Visible = true
			else
				Tab_Button.Rotation = 180
				setTabCorner(false)
			end
			tweening = false
			if queuedClick then
				queuedClick = false
				task.defer(function()
					if Tab_Button.Parent and Main.Parent then
						toggle()
					end
				end)
			end
		end

		mainOpenTween.Completed:Connect(finishAnimation)
		mainCloseTween.Completed:Connect(finishAnimation)

		toggle = function()
			if tweening then
				queuedClick = true
				return
			end
			lockMainTabSize()
			tweening = true
			opened = not opened
			Main.Visible = true
			if opened then
				Tab_Button.Rotation = 180
				mainOpenTween:Play()
				buttonOpenTween:Play()

				setTabCorner(true)
			else
				Tab_Button.Rotation = 0
				mainCloseTween:Play()
				buttonCloseTween:Play()
			end
		end

		Tab_Button.MouseButton1Click:Connect(toggle)
	end

	local pushContainer = Instance.new("Frame")
	pushContainer.Name = "Push"
	pushContainer.BackgroundTransparency = 1
	pushContainer.Size = UDim2.new(0.983, 0, 0.141, 0)
	pushContainer.ZIndex = 10000
	pushContainer.LayoutOrder = 2
	pushContainer.Parent = Main_Frame
	UI_STATE.PushContainer = pushContainer

	addUI(pushContainer, {
		Layout = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 4),
		},
	})

	if not Main_Frame then
		warn(WARNING_LIST[1])
		return
	end

	addUI(Main_Frame, {
		Layout = {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0, 0),
		},
	})

	CreateTab()
	CreateMain()
	SetupTabToggle()
	if loadSavedConfig then
		loadSavedConfig()
	end
	setActiveSection(UI_STATE.SectionOrder[1])
	if updateConfigControls then
		updateConfigControls()
	end
end

local rebuildingInterface = false

local function rebuildInterface()
	if rebuildingInterface then
		return
	end

	rebuildingInterface = true
	local success, message = xpcall(function()
		CreateMainFrame()
		CreateMainMenu()
	end, debug.traceback)
	rebuildingInterface = false

	if not success then
		warn(message)
	end
end

table.insert(
	bootstrapConnections,
	SERVICE.Player.CharacterAdded:Connect(function()
		-- Older Arcada builds rebuilt immediately on respawn and could win the
		-- race against a newly loaded build. Rebuild last, after PlayerGui and
		-- the character have settled, so the current interface is authoritative.
		task.delay(1, function()
			if BOOTSTRAP_ENVIRONMENT.__ARCADA_BOOTSTRAP_RUNTIME_TOKEN == bootstrapRuntimeToken then
				rebuildInterface()
			end
		end)
	end)
)

if SERVICE.Player.Character then
	task.defer(rebuildInterface)
end

BOOTSTRAP_ENVIRONMENT.__ARCADA_BOOTSTRAP_CLEANUP = function()
	if BOOTSTRAP_ENVIRONMENT.__ARCADA_BOOTSTRAP_RUNTIME_TOKEN == bootstrapRuntimeToken then
		BOOTSTRAP_ENVIRONMENT.__ARCADA_BOOTSTRAP_RUNTIME_TOKEN = nil
	end
	if BOOTSTRAP_ENVIRONMENT.__ARCADA_FARMING_BRIDGE_TOKEN == farmingBridgeToken then
		BOOTSTRAP_ENVIRONMENT.__ARCADA_FARMING_BRIDGE_TOKEN = nil
	end
	for _, connection in ipairs(bootstrapConnections) do
		if connection and connection.Disconnect then
			connection:Disconnect()
		end
	end
	table.clear(bootstrapConnections)
	if type(Home) == "table" and type(Home.Stop) == "function" then
		pcall(Home.Stop)
	end
	local screenGui = SERVICE.PlayerGui:FindFirstChild(SCREEN_GUI_NAME)
	local frame = screenGui and screenGui:FindFirstChild("EggHuntLayer")
	if frame then
		frame:Destroy()
	end
end

task.spawn(function()
	local lastEncoded = ""
	while BOOTSTRAP_ENVIRONMENT.__ARCADA_FARMING_BRIDGE_TOKEN == farmingBridgeToken do
		local prioritiesByAsset = {}
		for assetId, binding in pairs(UI_STATE.PriorityByImage) do
			local record = binding.Record
			if record then
				prioritiesByAsset[assetId] = tonumber(record.Value) or 0
			end
		end
		local success, encoded = pcall(SERVICE.HttpService.JSONEncode, SERVICE.HttpService, prioritiesByAsset)
		if success and encoded ~= lastEncoded and next(prioritiesByAsset) ~= nil then
			lastEncoded = encoded
			LocalPlayer:SetAttribute("ArcadaPriorityTokens", encoded)
		end
		task.wait(0.5)
	end
end)
