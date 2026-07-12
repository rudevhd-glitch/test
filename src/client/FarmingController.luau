local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")

local player = Players.LocalPlayer
local events = ReplicatedStorage:WaitForChild("Events", 10)

local runtimeEnvironment = shared
if type(getgenv) == "function" then
	local success, environment = pcall(getgenv)
	if success and type(environment) == "table" then
		runtimeEnvironment = environment
	end
end
if type(runtimeEnvironment) ~= "table" then
	runtimeEnvironment = _G
end
if type(runtimeEnvironment.__ARCADA_FARMING_CLEANUP) == "function" then
	pcall(runtimeEnvironment.__ARCADA_FARMING_CLEANUP)
end
local runtimeToken = {}
runtimeEnvironment.__ARCADA_FARMING_RUNTIME_TOKEN = runtimeToken

local function clientCall(eventName: string, ...): (boolean, any)
	local arguments = table.pack(...)
	local event = events and events:FindFirstChild(eventName)
	if event and event:IsA("RemoteFunction") then
		return pcall(function()
			return event:InvokeServer(table.unpack(arguments, 1, arguments.n))
		end)
	elseif event and event:IsA("RemoteEvent") then
		local success, message = pcall(function()
			event:FireServer(table.unpack(arguments, 1, arguments.n))
		end)
		return success, message
	end
	return false, "event unavailable: " .. eventName
end

local Config = {
	MovementSpeed = 90,
	TravelClearance = 35,
	-- Avoid flooding request/response remotes while still keeping continuous dig active.
	DigInterval = 0.15,
	FieldArrivalHeight = 4,
	HiveArrivalHeight = 4,
	FieldEdgeMargin = 4,
	TokenReachDistance = 5.5,
	TokenBlacklistTime = 2,
	PhantomTokenTimeout = 1.2,
	TokenPursuitTimeout = 5,
	PhantomTokenBlacklistTime = 20,
	HiveClaimTimeout = 6,
	FailedHiveBlacklistTime = 10,
	MonsterJumpDelay = 1,
	MonsterJumpInterval = 1.5,
	TokenESPDistance = 100,
	TokenLineDistance = 50,
	TokenESPUpdateInterval = 0.5,
	SproutTokenCollectionTime = 15,
	StatsCacheTime = 5,
	SessionStatsInterval = 10,
	KeepAliveInterval = 30,
	FarmTick = 0.12,
	ConversionClearTime = 3,
	ConversionStartTimeout = 10,
	ConversionRetryDelay = 1.5,
	ConversionStallTimeout = 12,
	OutsideFieldReturnDelay = 0,
	FarmStuckTimeout = 0.25,
	RoamInterval = 1.5,
	SproutArrivalDistance = 7,
}

local FarmingState = {
	AutoFarm = false,
	AutoDig = false,
	AutoSprinkler = false,
	ESCTokens = false,
	AutoSprouts = false,
	PriorityTokens = true,
	FarmBubbles = false,
	FarmPetals = false,
	ShiftLock = false,
	WealthClock = false,
	AutoPuffshrooms = false,
	PuffCollectLoot = true,
	PuffPreferRarity = true,
	PuffMinLevel = 1,
	PuffMinRarity = "Common",
	PuffLootSeconds = 12,
	PuffFields = "All",
	FarmMondo = false,
	CollectMondoTokens = false,
	FarmWindyBee = false,
	FarmViciousBee = false,
	FarmStumpSnail = false,
	ConvertPercent = 100,
	ConvertMinutes = 20,
	ConvertBalloons = true,
	AutoHoneyMask = false,
	SelectedMask = "Diamond Mask",
	AutoHive = true,
	HiveSlot = 4,
	AntiAFK = false,
	SelectedField = nil,
	Mode = "Idle",
}

local cache = { FlowerZones = {}, Collectibles = {}, Monsters = {}, Sprouts = {}, HivePlatforms = {}, Honeycombs = {} }
local folders = {}
local connections = {}
local folderConnections = {}
local characterConnections = {}
local tokenAssetCache = setmetatable({}, { __mode = "k" })
local phantomTokens = setmetatable({}, { __mode = "k" })
local recentlyVisitedTokens = setmetatable({}, { __mode = "k" })
local failedHives = {}
local espRecords = {}
local fieldDecoState = setmetatable({}, { __mode = "k" })
local fieldDecoFolder = nil
local fieldDecoConnection = nil
local bubbleCandidates = setmetatable({}, { __mode = "k" })
local bubbleFolder = nil
local bubbleConnections = {}
local petalCandidates = setmetatable({}, { __mode = "k" })
local petalFolder = nil
local petalConnections = {}
local petalTargetStarted = setmetatable({}, { __mode = "k" })
local warnTimes = {}
local actionId = 0
local movementId = 0
local moving = false
local transitCollisionState = setmetatable({}, { __mode = "k" })
local transitAnchoredState = false
local lastDig = 0
local lastJump = 0
local lastDamageAt = -math.huge
local monsterEncounterAt = nil
local lastKeepAlive = 0
local lastSprinklerField = nil
local lastSprinklerAttempt = 0
local statsCache, statsCacheAt = nil, 0
local currentToken = nil
local currentTokenStarted = 0
local currentTokenClosest = math.huge
local currentBubble = nil
local currentBubbleStarted = 0
local farmTargetPreference = nil
local sproutContext = nil
local bossContext = nil
local puffContext = nil
local puffMetadataCache = setmetatable({}, { __mode = "k" })
local bossHintCache = {}
local bossHoverPosition = nil
local priorityCache = {}
local priorityCacheRaw = ""
local roamTarget = nil
local roamTargetAt = 0
local outsideFieldSince = nil
local fieldEnteredAt = nil
local fieldCapacityCheckField = nil
local lastFarmPosition = nil
local lastFarmProgressAt = 0
local converting = false
local conversionStarted = false
local conversionClearSince = nil
local conversionAttemptAt = 0
local conversionStartPollen = nil
local conversionProgressObserved = false
local skipPartialConversionUntilField = false
local conversionHoneyMaskEquipped = false
local conversionFieldMaskRestored = false
local conversionStopRequested = false
local conversionLastProgressAt = 0
local lastConversionCompletedAt = os.clock()
local lastWealthClockAttempt = -math.huge
local wealthClockNextAt = tonumber(player:GetAttribute("ArcadaWealthClockNextAt"))
if not wealthClockNextAt or wealthClockNextAt <= 0 then
	-- os.clock() is the Roblox client session uptime, so 3600 means one hour
	-- after joining even when Arcada is loaded later.
	wealthClockNextAt = 3600
	player:SetAttribute("ArcadaWealthClockNextAt", wealthClockNextAt)
end
local setFarmingState
local walkTo
local cachedHoneyTextBox = nil
local cachedHoneyButton = nil
local sessionTokensCollected = 0
local sessionSproutsBroken = 0
local sessionMonstersKilled = 0
local sessionMaxPollen = 0
local sessionMaxBalloonPollen = 0
local sessionMaxBalloonBlessing = 0

local function normalizeStatName(name: string): string
	return string.lower(name):gsub("[^%w]", "")
end

local function collectNamedNumbers(root: any, wantedNames: { [string]: boolean }): { [string]: number }
	local result = {}
	for wantedName in pairs(wantedNames) do
		result[wantedName] = 0
	end
	if type(root) ~= "table" then
		return result
	end
	local visited = {}
	local function visit(value: any, depth: number)
		if type(value) ~= "table" or visited[value] or depth > 5 then
			return
		end
		visited[value] = true
		for key, child in pairs(value) do
			local normalized = normalizeStatName(tostring(key))
			if wantedNames[normalized] then
				local numeric = tonumber(child)
				if not numeric and type(child) == "table" then
					numeric = tonumber(child.Value) or tonumber(child.Amount) or tonumber(child.Stacks)
				end
				result[normalized] = math.max(result[normalized] or 0, numeric or 0)
			end
			visit(child, depth + 1)
		end
	end
	visit(root, 0)
	return result
end

local publishedSessionStats = {}
local function publishAttribute(name: string, value: any)
	if publishedSessionStats[name] ~= value then
		publishedSessionStats[name] = value
		if player:GetAttribute(name) ~= value then
			player:SetAttribute(name, value)
		end
	end
end

local function publishSessionStats()
	publishAttribute("ArcadaSessionTokens", sessionTokensCollected)
	publishAttribute("ArcadaSessionMaxPollen", sessionMaxPollen)
	publishAttribute("ArcadaSessionMaxBalloon", sessionMaxBalloonPollen)
	publishAttribute("ArcadaSessionMaxBalloonBlessing", sessionMaxBalloonBlessing)
	publishAttribute("ArcadaSessionSprouts", sessionSproutsBroken)
	publishAttribute("ArcadaSessionMonsters", sessionMonstersKilled)
end
publishSessionStats()

local function throttledWarn(key: string, ...)
	local now = os.clock()
	if now - (warnTimes[key] or 0) >= 5 then
		warnTimes[key] = now
		warn("[FarmingController]", ...)
	end
end

local function disconnectAll(list)
	for _, connection in ipairs(list) do
		connection:Disconnect()
	end
	table.clear(list)
end

local function preventIdleKick()
	if not FarmingState.AntiAFK then
		return
	end
	local camera = workspace.CurrentCamera
	local cameraCFrame = if camera then camera.CFrame else CFrame.new()
	local success, message = pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:Button2Down(Vector2.new(0, 0), cameraCFrame)
		task.wait(0.1)
		VirtualUser:Button2Up(Vector2.new(0, 0), cameraCFrame)
	end)
	if not success then
		throttledWarn("anti-afk", "Anti-AFK input failed:", message)
	end
end

local function getCharacter(): Model?
	return player.Character
end
local function getRootPart(): BasePart?
	local root = getCharacter() and getCharacter():FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end
local function getHumanoid(): Humanoid?
	local humanoid = getCharacter() and getCharacter():FindFirstChildOfClass("Humanoid")
	return humanoid
end

local function applyShiftLockMode()
	local success, userGameSettings = pcall(function()
		return UserSettings():GetService("UserGameSettings")
	end)
	if success and userGameSettings then
		pcall(function()
			userGameSettings.RotationType = if FarmingState.ShiftLock
				then Enum.RotationType.CameraRelative
				else Enum.RotationType.MovementRelative
		end)
	end
	if FarmingState.ShiftLock then
		pcall(function()
			game:GetService("UserInputService").MouseBehavior = Enum.MouseBehavior.Default
		end)
	end
end

local function retrievePlayerStats(): any
	if statsCache and os.clock() - statsCacheAt < Config.StatsCacheTime then
		return statsCache
	end
	local ok, result = clientCall("RetrievePlayerStats")
	if ok and type(result) == "table" then
		statsCache, statsCacheAt = result, os.clock()
		return result
	end
	throttledWarn("stats", "Failed to retrieve stats:", result)
	return nil
end

local function hasEquippedSprinkler(): boolean
	local stats = retrievePlayerStats()
	local value = stats and stats.EquippedSprinkler
	return value ~= nil and value ~= false and value ~= "" and value ~= 0
end

local function getEquippedCollectorName(): string?
	local stats = retrievePlayerStats()
	local value = stats and stats.EquippedCollector
	if type(value) ~= "string" or value == "" then
		return nil
	end
	return value
end

local function valueTargetsPlayer(value: any): boolean
	return value == player
		or value == player.Character
		or tostring(value) == player.Name
		or tostring(value) == tostring(player.UserId)
end

local function getHiveOwner(hiveModel: Instance): any
	local owner = hiveModel and hiveModel:FindFirstChild("Owner", true)
	if not owner then
		return nil
	end
	if owner:IsA("ValueBase") then
		return (owner :: any).Value
	end
	return owner:GetAttribute("Value")
end

local function isHiveUnowned(hiveModel: Instance): boolean
	local owner = getHiveOwner(hiveModel)
	return owner == nil or owner == "" or owner == "nil" or owner == 0 or owner == "0"
end

local getOwnedHive: () -> Instance?

local function getHiveNameFromPlatform(platform: Instance): string?
	local value = platform:FindFirstChild("Hive", true)
	if value and value:IsA("ValueBase") then
		local hiveValue = (value :: any).Value
		return if typeof(hiveValue) == "Instance" then hiveValue.Name else tostring(hiveValue)
	end
	return nil
end

local function getHiveFromPlatform(platform: Instance): Instance?
	local value = platform:FindFirstChild("Hive", true)
	if value and value:IsA("ValueBase") then
		local hiveValue = (value :: any).Value
		if typeof(hiveValue) == "Instance" then
			return hiveValue
		end
		local wantedName = tostring(hiveValue)
		local wantedSlot = tonumber(string.match(wantedName, "(%d+)"))
		for hive in pairs(cache.Honeycombs) do
			local hiveSlot = tonumber(string.match(hive.Name, "(%d+)"))
			if hive.Name == wantedName or (wantedSlot and hiveSlot == wantedSlot) then
				return hive
			end
		end
	end
	return nil
end

local function getHivePlatform(hive: Instance): Instance?
	local hiveSlot = tonumber(string.match(hive.Name, "(%d+)"))
	for platform in pairs(cache.HivePlatforms) do
		local platformHiveName = getHiveNameFromPlatform(platform)
		local platformSlot = tonumber(string.match(platformHiveName or platform.Name, "(%d+)"))
		if platform.Parent and (platformHiveName == hive.Name or (hiveSlot ~= nil and platformSlot == hiveSlot)) then
			return platform
		end
	end
	return nil
end

getOwnedHive = function(): Instance?
	for hive in pairs(cache.Honeycombs) do
		if hive.Parent and valueTargetsPlayer(getHiveOwner(hive)) then
			return hive
		end
	end
	for platform in pairs(cache.HivePlatforms) do
		if platform.Parent and valueTargetsPlayer(getHiveOwner(platform)) then
			return getHiveFromPlatform(platform)
		end
	end
	return nil
end

local function isHiveClaimAvailable(hive: Instance): boolean
	if not isHiveUnowned(hive) then
		return false
	end
	local platform = getHivePlatform(hive)
	return platform == nil or isHiveUnowned(platform)
end

local function getAvailableHives(): { Instance }
	local result = {}
	local included = {}
	for hive in pairs(cache.Honeycombs) do
		local name = hive.Name
		if hive.Parent and isHiveClaimAvailable(hive) and (failedHives[name] or 0) < os.clock() then
			table.insert(result, hive)
			included[hive] = true
		end
	end
	-- Some game versions expose the claim arrow only in HivePlatforms and the
	-- Honeycomb itself has no Patharrow. Resolve its linked Hive value instead.
	for platform in pairs(cache.HivePlatforms) do
		local hive = platform.Parent and getHiveFromPlatform(platform)
		if
			hive
			and not included[hive]
			and isHiveClaimAvailable(hive)
			and (failedHives[hive.Name] or 0) < os.clock()
		then
			table.insert(result, hive)
			included[hive] = true
		end
	end
	return result
end

local function getHiveClaimPosition(hive: Instance): Vector3?
	local platform = getHivePlatform(hive)
	if platform then
		local prompt = platform:FindFirstChildWhichIsA("ProximityPrompt", true)
		local promptPart = prompt and prompt.Parent
		if promptPart and promptPart:IsA("BasePart") then
			return promptPart.Position + Vector3.new(0, 3, 0)
		end
		if platform:IsA("BasePart") then
			return platform.Position + Vector3.new(0, 3, 0)
		end
		local part = platform:FindFirstChildWhichIsA("BasePart", true)
		if part then
			return part.Position + Vector3.new(0, 3, 0)
		end
	end
	local patharrow = hive:FindFirstChild("Patharrow")
	local base = patharrow and patharrow:FindFirstChild("Base")
	return if base and base:IsA("BasePart") then base.Position + Vector3.new(0, Config.HiveArrivalHeight, 0) else nil
end

local function cancelMovement()
	movementId += 1
	moving = false
end

local function setTransitPhysics(enabled: boolean)
	local character = getCharacter()
	local root = getRootPart()
	if not character or not root then
		return
	end
	if enabled then
		table.clear(transitCollisionState)
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("BasePart") then
				transitCollisionState[descendant] = descendant.CanCollide
				descendant.CanCollide = false
				descendant.AssemblyLinearVelocity = Vector3.zero
				descendant.AssemblyAngularVelocity = Vector3.zero
			end
		end
		transitAnchoredState = root.Anchored
		root.Anchored = true
	else
		-- Farming movement must never leave the character glued in place. A
		-- character that was anchored by another transient game effect is also
		-- released when Arcada hands control back to the Humanoid.
		root.Anchored = false
		for part, canCollide in pairs(transitCollisionState) do
			if part.Parent then
				part.CanCollide = canCollide
			end
		end
		table.clear(transitCollisionState)
	end
end

local function moveRootSegment(targetCFrame: CFrame, speed: number, myId: number): boolean
	local root = getRootPart()
	if not root then
		return false
	end
	local startCFrame = root.CFrame
	local distance = (startCFrame.Position - targetCFrame.Position).Magnitude
	local duration = math.max(distance / math.max(speed, 1), 0.01)
	local startedAt = os.clock()
	repeat
		if movementId ~= myId or not root.Parent then
			return false
		end
		local alpha = math.clamp((os.clock() - startedAt) / duration, 0, 1)
		root.CFrame = startCFrame:Lerp(targetCFrame, alpha)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		if alpha >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	until false
	return true
end

local function moveCharacterSmoothly(targetCFrame: CFrame, options: any?): boolean
	cancelMovement()
	local myId = movementId
	local root = getRootPart()
	local character = getCharacter()
	if not root or not character then
		return false
	end
	moving = true
	setTransitPhysics(true)
	local speed = math.max(tonumber(options and options.Speed) or Config.MovementSpeed, 1)
	local success, completed = pcall(moveRootSegment, targetCFrame, speed, myId)
	setTransitPhysics(false)
	moving = false
	if not success then
		throttledWarn("movement", "Movement failed:", completed)
		return false
	end
	return completed == true and movementId == myId
end

local function interactWithHive(hiveModel: Instance): boolean
	local attempted = false
	local hiveSlot = tonumber(string.match(hiveModel.Name, "(%d+)"))
	local platform = getHivePlatform(hiveModel)
	local prompt = (platform and platform:FindFirstChildWhichIsA("ProximityPrompt", true))
		or hiveModel:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then
		attempted = true
		local firePrompt = runtimeEnvironment.fireproximityprompt
		if type(firePrompt) == "function" then
			pcall(firePrompt, prompt)
		else
			pcall(function()
				prompt:InputHoldBegin()
				task.wait(math.max(prompt.HoldDuration, 0.05) + 0.05)
				prompt:InputHoldEnd()
			end)
		end
		task.wait(0.25)
		if valueTargetsPlayer(getHiveOwner(hiveModel)) then
			return true
		end
	end
	local inputOk, inputManager = pcall(game.GetService, game, "VirtualInputManager")
	if inputOk and inputManager then
		attempted = true
		local virtualInputManager = inputManager :: any
		pcall(function()
			virtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
			task.wait(0.06)
			virtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
		end)
		task.wait(0.2)
		if valueTargetsPlayer(getHiveOwner(hiveModel)) then
			return true
		end
	end
	local requests = {
		{ "ClaimHive", hiveModel },
		{ "ClaimHive", hiveModel.Name },
		{ "PlayerHiveCommand", "ClaimHive", hiveModel.Name },
		{ "PlayerHiveCommand", hiveModel.Name },
	}
	if hiveSlot then
		table.insert(requests, 1, { "ClaimHive", hiveSlot })
		table.insert(requests, { "PlayerHiveCommand", "ClaimHive", hiveSlot })
	end
	for _, request in ipairs(requests) do
		if events and events:FindFirstChild(request[1]) then
			attempted = true
			clientCall(table.unpack(request))
			task.wait(0.15)
			if valueTargetsPlayer(getHiveOwner(hiveModel)) then
				return true
			end
		end
	end
	if not attempted then
		throttledWarn("hive-event", "Hive interaction event was not found")
	end
	return valueTargetsPlayer(getHiveOwner(hiveModel))
end

local function claimHive(): boolean
	if getOwnedHive() then
		return true
	end
	local availableHives = getAvailableHives()
	local preferredSlot = math.clamp(math.floor(FarmingState.HiveSlot or 4), 1, 6)
	local preferredIndex = nil
	for index, hive in ipairs(availableHives) do
		local platform = getHivePlatform(hive)
		local candidateSlot = tonumber(string.match(hive.Name, "(%d+)"))
			or (platform and tonumber(string.match(platform.Name, "(%d+)")))
		if candidateSlot == preferredSlot then
			preferredIndex = index
			break
		end
	end
	while #availableHives > 0 do
		local index = preferredIndex or math.random(1, #availableHives)
		local hive = table.remove(availableHives, index)
		preferredIndex = nil
		local claimPosition = getHiveClaimPosition(hive)
		if claimPosition and moveCharacterSmoothly(CFrame.new(claimPosition)) then
			interactWithHive(hive)
			local timeout = os.clock() + Config.HiveClaimTimeout
			repeat
				task.wait(0.2)
			until valueTargetsPlayer(getHiveOwner(hive)) or os.clock() >= timeout
			if valueTargetsPlayer(getHiveOwner(hive)) then
				return true
			end
			failedHives[hive.Name] = os.clock() + Config.FailedHiveBlacklistTime
		end
	end
	return false
end

local function getSpawnPosition(): Vector3?
	local spawn = player:FindFirstChild("SpawnPos")
	if not spawn or not spawn:IsA("ValueBase") then
		return nil
	end
	local value = (spawn :: any).Value
	if typeof(value) == "CFrame" then
		return value.Position
	end
	if typeof(value) == "Vector3" then
		return value
	end
	return nil
end

local function getHiveStandingPosition(hive: Instance): Vector3?
	local spawnPosition = getSpawnPosition()
	if spawnPosition then
		return spawnPosition
	end
	local patharrow = hive:FindFirstChild("Patharrow")
	local base = patharrow and patharrow:FindFirstChild("Base")
	return if base and base:IsA("BasePart") then base.Position + Vector3.new(0, Config.HiveArrivalHeight, 0) else nil
end

local function getPollenAndCapacity(): (number, number)
	local coreStats = player:FindFirstChild("CoreStats")
	local pollenValue = coreStats and coreStats:FindFirstChild("Pollen")
	local capacityValue = coreStats and coreStats:FindFirstChild("Capacity")
	local pollen = pollenValue and tonumber((pollenValue :: any).Value) or 0
	local capacity = capacityValue and tonumber((capacityValue :: any).Value) or 0
	return pollen or 0, capacity or 0
end

local function getHoneyMakingStatus(): (string?, GuiButton?)
	if cachedHoneyTextBox and cachedHoneyTextBox.Parent then
		local status = string.lower(string.gsub(cachedHoneyTextBox.Text, "^%s*(.-)%s*$", "%1"))
		-- A second label can change to Stop Making Honey while the cached small
		-- label still says Make Honey, so only short-circuit the active state.
		if status == "stop making honey" then
			return status, if cachedHoneyButton and cachedHoneyButton.Parent then cachedHoneyButton else nil
		end
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil, nil
	end
	local makeHoneyTextBox, makeHoneyButton = nil, nil
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant.Name == "ActivateButton" then
			local button = if descendant:IsA("GuiButton")
				then descendant
				else descendant:FindFirstChildWhichIsA("GuiButton", true)
			for _, textName in ipairs({ "TextBox", "BigTextBox" }) do
				local textBox = descendant:FindFirstChild(textName, true)
				if textBox and (textBox:IsA("TextBox") or textBox:IsA("TextLabel")) then
					local status = string.lower(string.gsub(textBox.Text, "^%s*(.-)%s*$", "%1"))
					if status == "stop making honey" then
						cachedHoneyTextBox = textBox
						cachedHoneyButton = button
						return status, button
					elseif status == "make honey" then
						makeHoneyTextBox = textBox
						makeHoneyButton = button
					end
				end
			end
		end
	end
	if makeHoneyTextBox then
		cachedHoneyTextBox = makeHoneyTextBox
		cachedHoneyButton = makeHoneyButton
		return "make honey", makeHoneyButton
	end
	return nil, nil
end

local function equipMask(maskName: string): boolean
	if maskName == "" then
		return false
	end
	local ok, result = clientCall("ItemPackageEvent", "Equip", {
		Category = "Accessory",
		Type = maskName,
	})
	return ok and result ~= false
end

local function hasHiveBalloon(): boolean
	local balloons = workspace:FindFirstChild("Balloons")
	local hiveBalloons = balloons and balloons:FindFirstChild("HiveBalloons")
	local spawnPosition = getSpawnPosition()
	if not hiveBalloons or not spawnPosition then
		return false
	end
	for _, balloon in ipairs(hiveBalloons:GetChildren()) do
		local root = balloon:FindFirstChild("BalloonRoot")
		if root and root:IsA("BasePart") and math.abs(root.Position.X - spawnPosition.X) <= 4 then
			return true
		end
	end
	return false
end

local function getHiveBalloonAmount(): number
	local balloons = workspace:FindFirstChild("Balloons")
	local hiveBalloons = balloons and balloons:FindFirstChild("HiveBalloons")
	local spawnPosition = getSpawnPosition()
	if not hiveBalloons or not spawnPosition then
		return 0
	end
	local best = 0
	for _, balloon in ipairs(hiveBalloons:GetChildren()) do
		local root = balloon:FindFirstChild("BalloonRoot")
		if root and root:IsA("BasePart") and math.abs(root.Position.X - spawnPosition.X) <= 4 then
			for name, value in pairs(balloon:GetAttributes()) do
				local lowered = string.lower(name)
				if
					string.find(lowered, "pollen", 1, true)
					or string.find(lowered, "amount", 1, true)
					or string.find(lowered, "capacity", 1, true)
					or string.find(lowered, "size", 1, true)
				then
					best = math.max(best, tonumber(value) or 0)
				end
			end
			for _, valueObject in ipairs(balloon:GetDescendants()) do
				if valueObject:IsA("ValueBase") then
					local lowered = string.lower(valueObject.Name)
					if
						string.find(lowered, "pollen", 1, true)
						or string.find(lowered, "amount", 1, true)
						or string.find(lowered, "capacity", 1, true)
						or string.find(lowered, "size", 1, true)
					then
						best = math.max(best, tonumber((valueObject :: any).Value) or 0)
					end
				end
			end
		end
	end
	return best
end

local function emulateInteractionKey(): boolean
	local ok, inputManager = pcall(game.GetService, game, "VirtualInputManager")
	if not ok or not inputManager then
		return false
	end
	local virtualInputManager = inputManager :: any
	return pcall(function()
		virtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
		task.wait(0.06)
		virtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
	end)
end

local function runWealthClock(): boolean
	local now = os.clock()
	if not FarmingState.WealthClock or converting or now < wealthClockNextAt or now - lastWealthClockAttempt < 30 then
		return false
	end
	local wealthClock = workspace:FindFirstChild("Wealth Clock")
	local platform = wealthClock and wealthClock:FindFirstChild("Platform")
	local alertPos = platform and platform:FindFirstChild("AlertPos")
	local alertGui = alertPos and alertPos:FindFirstChild("AlertGui")
	local imageLabel = alertGui and alertGui:FindFirstChild("ImageLabel")
	if not imageLabel or not imageLabel:IsA("GuiObject") or not imageLabel.Visible then
		return false
	end
	local root = getRootPart()
	local platformPosition = nil
	if platform and platform:IsA("BasePart") then
		platformPosition = platform.Position
	elseif platform and platform:IsA("Model") then
		platformPosition = platform:GetPivot().Position
	elseif platform then
		local platformPart = platform:FindFirstChildWhichIsA("BasePart", true)
		platformPosition = platformPart and platformPart.Position or nil
	end
	if not root or not platformPosition then
		return false
	end
	lastWealthClockAttempt = now
	local returnCFrame = root.CFrame
	setFarmingState("CollectingWealthClock")
	local arrival = platformPosition + Vector3.new(0, 4, 0)
	if not moveCharacterSmoothly(CFrame.new(arrival)) then
		return true
	end
	local prompt = platform:FindFirstChildWhichIsA("ProximityPrompt", true)
	local firedPrompt = false
	if prompt and type(runtimeEnvironment.fireproximityprompt) == "function" then
		firedPrompt = pcall(runtimeEnvironment.fireproximityprompt, prompt)
	end
	if not firedPrompt then
		emulateInteractionKey()
	end
	local collected = false
	for _ = 1, 10 do
		task.wait(0.2)
		if not imageLabel.Parent or not imageLabel.Visible then
			collected = true
			break
		end
	end
	if collected then
		-- The next hour starts from the confirmed collection, not from the
		-- toggle time. If collection failed, the 30-second retry remains active.
		wealthClockNextAt = os.clock() + 3600
		player:SetAttribute("ArcadaWealthClockNextAt", wealthClockNextAt)
	end
	moveCharacterSmoothly(returnCFrame)
	return true
end

local function resetConversionState()
	converting = false
	conversionStarted = false
	conversionClearSince = nil
	conversionAttemptAt = 0
	conversionStartPollen = nil
	conversionProgressObserved = false
	skipPartialConversionUntilField = false
	conversionHoneyMaskEquipped = false
	conversionFieldMaskRestored = false
	conversionStopRequested = false
	conversionLastProgressAt = 0
end

local function startHiveConversion(pollen: number)
	sessionMaxPollen = math.max(sessionMaxPollen, pollen)
	sessionMaxBalloonPollen = math.max(sessionMaxBalloonPollen, getHiveBalloonAmount())
	publishSessionStats()
	conversionStarted = true
	conversionAttemptAt = os.clock()
	conversionStartPollen = pollen
	conversionProgressObserved = false
	conversionLastProgressAt = if conversionLastProgressAt > 0 then conversionLastProgressAt else os.clock()
	local status, makeHoneyButton = getHoneyMakingStatus()
	if status == "stop making honey" then
		return
	end
	local buttonActivated = makeHoneyButton ~= nil and pcall(function()
		makeHoneyButton:Activate()
	end)
	local keyPressed = if buttonActivated then true else emulateInteractionKey()
	local nextStatus = status
	for _ = 1, 8 do
		task.wait(0.15)
		nextStatus = getHoneyMakingStatus()
		if nextStatus == "stop making honey" then
			break
		end
	end
	-- Never send a second toggle after a UI/key interaction: the prompt can
	-- update late, and a second toggle immediately cancels honey making.
	if not buttonActivated and not keyPressed then
		clientCall("PlayerHiveCommand", "ToggleHoneyMaking")
	end
end

local function runHiveConversion(hive: Instance): boolean
	local root = getRootPart()
	local hivePosition = getHiveStandingPosition(hive)
	if not root or not hivePosition then
		return false
	end
	if (root.Position - hivePosition).Magnitude > 8 then
		setFarmingState("MovingToHive")
		lastSprinklerField = nil
		moveCharacterSmoothly(CFrame.new(hivePosition))
		return false
	end

	local pollen = getPollenAndCapacity()
	if not conversionStarted then
		if FarmingState.AutoHoneyMask and not conversionHoneyMaskEquipped then
			setFarmingState("EquippingHoneyMask")
			equipMask("Honey Mask")
			conversionHoneyMaskEquipped = true
			task.wait(0.2)
			return false
		end
		setFarmingState("StartingConversion")
		startHiveConversion(pollen)
		return false
	end
	if conversionStartPollen and pollen < conversionStartPollen then
		conversionProgressObserved = true
		conversionLastProgressAt = os.clock()
	end
	local honeyStatus = getHoneyMakingStatus()
	if honeyStatus == "stop making honey" then
		conversionLastProgressAt = os.clock()
	end
	if
		honeyStatus ~= "stop making honey"
		and (pollen > 0 or (FarmingState.ConvertBalloons and hasHiveBalloon()))
		and os.clock() - conversionAttemptAt >= Config.ConversionRetryDelay
	then
		setFarmingState("RetryingConversion")
		startHiveConversion(pollen)
		return false
	end
	if conversionLastProgressAt > 0 and os.clock() - conversionLastProgressAt >= Config.ConversionStallTimeout then
		setFarmingState("ConversionStalled")
		resetConversionState()
		return true
	end

	setFarmingState("ConvertingAtHive")
	local conversionDone = pollen <= 0 and (not FarmingState.ConvertBalloons or not hasHiveBalloon())
	if conversionDone then
		if not FarmingState.ConvertBalloons and honeyStatus == "stop making honey" and not conversionStopRequested then
			setFarmingState("StoppingBalloonConversion")
			emulateInteractionKey()
			conversionStopRequested = true
			return false
		end
		conversionClearSince = conversionClearSince or os.clock()
		if os.clock() - conversionClearSince >= Config.ConversionClearTime then
			if FarmingState.AutoHoneyMask and not conversionFieldMaskRestored then
				setFarmingState("RestoringFieldMask")
				equipMask(FarmingState.SelectedMask)
				conversionFieldMaskRestored = true
				return false
			end
			lastConversionCompletedAt = os.clock()
			resetConversionState()
			return true
		end
	else
		conversionClearSince = nil
	end
	return false
end

local function getSelectedFieldPart(): BasePart?
	local field = folders.FlowerZones
		and FarmingState.SelectedField
		and folders.FlowerZones:FindFirstChild(FarmingState.SelectedField)
	return if field and field:IsA("BasePart") then field else nil
end
local function isPositionInsideField(position: Vector3, field: BasePart, edgeMargin: number?): boolean
	local p = field.CFrame:PointToObjectSpace(position)
	local margin = if edgeMargin == nil then Config.FieldEdgeMargin else edgeMargin
	return math.abs(p.X) <= math.max(0, field.Size.X / 2 - margin)
		and math.abs(p.Z) <= math.max(0, field.Size.Z / 2 - margin)
end
local function getFieldCenterPosition(field: BasePart): Vector3
	return field.CFrame:PointToWorldSpace(Vector3.new(0, field.Size.Y / 2 + 3, 0))
end
local function getFieldLandingPosition(field: BasePart, worldPosition: Vector3): Vector3
	local localPosition = field.CFrame:PointToObjectSpace(worldPosition)
	local halfX = math.max(0, field.Size.X / 2 - Config.FieldEdgeMargin)
	local halfZ = math.max(0, field.Size.Z / 2 - Config.FieldEdgeMargin)
	return field.CFrame:PointToWorldSpace(
		Vector3.new(
			math.clamp(localPosition.X, -halfX, halfX),
			field.Size.Y / 2 + 3,
			math.clamp(localPosition.Z, -halfZ, halfZ)
		)
	)
end
local function getRandomPointInsideField(field: BasePart): Vector3
	-- Keep roaming biased toward the middle instead of repeatedly walking along
	-- the dangerous outer rim. Averaging two samples gives a triangular center bias.
	local x = ((math.random() + math.random()) / 2 - 0.5) * math.max(1, field.Size.X - Config.FieldEdgeMargin * 2)
	local z = ((math.random() + math.random()) / 2 - 0.5) * math.max(1, field.Size.Z - Config.FieldEdgeMargin * 2)
	return field.CFrame:PointToWorldSpace(Vector3.new(x, field.Size.Y / 2 + 3, z))
end
local function returnPlayerToField(field: BasePart): boolean
	return moveCharacterSmoothly(CFrame.new(getFieldCenterPosition(field)))
end

local function findDigTool(): Tool?
	local character = getCharacter()
	local collectorName = getEquippedCollectorName()
	if character and collectorName then
		local equipped = character:FindFirstChild(collectorName, true)
		if equipped and equipped:IsA("Tool") then
			return equipped
		end
	end
	if character then
		local equipped = character:FindFirstChildOfClass("Tool") or character:FindFirstChildWhichIsA("Tool", true)
		if equipped then
			return equipped
		end
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack and collectorName then
		local stored = backpack:FindFirstChild(collectorName, true)
		if stored and stored:IsA("Tool") then
			return stored
		end
	end
	return nil
end

local function findDigEvent(tool: Tool?): Instance?
	local clickEvent = tool and tool:FindFirstChild("ClickEvent", true)
	if clickEvent then
		return clickEvent
	end
	local character = getCharacter()
	clickEvent = character and character:FindFirstChild("ClickEvent", true)
	if clickEvent then
		return clickEvent
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	clickEvent = backpack and backpack:FindFirstChild("ClickEvent", true)
	if clickEvent then
		return clickEvent
	end
	return events and (events:FindFirstChild("ToolCollect") or events:FindFirstChild("ClickEvent")) or nil
end

local function activateDigTool(): boolean
	if os.clock() - lastDig < Config.DigInterval then
		return false
	end
	local character = getCharacter()
	local humanoid = getHumanoid()
	local tool = findDigTool()
	if not character or not humanoid then
		return false
	end
	if tool and tool.Parent ~= character then
		humanoid:EquipTool(tool)
		task.wait()
	end
	lastDig = os.clock()
	local activated = false
	if tool and tool.Parent == character then
		activated = pcall(function()
			tool:Activate()
		end)
	end
	local clickEvent = findDigEvent(tool)
	local root = getRootPart()
	local fired = false
	if clickEvent and clickEvent:IsA("RemoteEvent") and root then
		fired = pcall(function()
			clickEvent:FireServer(root.Position)
		end)
	end
	if not activated and not fired then
		throttledWarn("dig-tool", "Auto Dig could not activate the equipped collector")
	end
	return activated or fired
end

local function placeSprinkler(field: BasePart, force: boolean?): boolean
	if (not force and lastSprinklerField == field.Name) or not hasEquippedSprinkler() then
		return not force and lastSprinklerField == field.Name
	end
	-- Forced placement may be retried, but never flood both sprinkler remotes.
	if os.clock() - lastSprinklerAttempt < 1.5 then
		return false
	end
	lastSprinklerAttempt = os.clock()
	local activeOk, activeError = clientCall("PlayerActivesCommand", { Name = "Sprinkler Builder" })
	if not activeOk then
		throttledWarn("sprinkler-active", "Sprinkler Builder activation failed:", activeError)
		return false
	end
	task.wait(0.15)
	local sprinklerOk, sprinklerError = clientCall("PlayerSprinklerCommand")
	if not sprinklerOk then
		throttledWarn("sprinkler", "PlayerSprinklerCommand failed:", sprinklerError)
		return false
	end
	lastSprinklerField = field.Name
	return true
end

local function getTokenPosition(token: Instance): Vector3?
	if token:IsA("BasePart") then
		return token.Position
	end
	if token:IsA("Model") then
		return token:GetPivot().Position
	end
	local part = token:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end

local function setBossHover(position: Vector3?)
	local root = getRootPart()
	if not root then
		return
	end
	local existing = root:FindFirstChild("ArcadaBossHover")
	if not position then
		bossHoverPosition = nil
		if existing then
			existing:Destroy()
		end
		return
	end
	bossHoverPosition = position
	local hover = existing
	if not hover or not hover:IsA("BodyPosition") then
		if hover then
			hover:Destroy()
		end
		hover = Instance.new("BodyPosition")
		hover.Name = "ArcadaBossHover"
		hover.MaxForce = Vector3.new(1e7, 1e7, 1e7)
		hover.P = 25000
		hover.D = 1500
		hover.Parent = root
	end
	hover.Position = position
	local humanoid = getHumanoid()
	if humanoid then
		humanoid.AutoRotate = true
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end

local function getMonsterAvoidRadius(monster: Instance, padding: number): number
	if monster:IsA("Model") then
		local _, size = monster:GetBoundingBox()
		return math.max(size.X, size.Z) / 2 + padding
	end
	local part = if monster:IsA("BasePart") then monster else monster:FindFirstChildWhichIsA("BasePart", true)
	return if part then math.max(part.Size.X, part.Size.Z) / 2 + padding else padding
end

local function getSafestFieldPosition(
	field: BasePart,
	monsterPosition: Vector3,
	radius: number,
	preferred: Vector3
): Vector3
	local best = getFieldLandingPosition(field, monsterPosition + preferred * radius)
	local bestDistance = (best - monsterPosition).Magnitude
	for step = 0, 15 do
		local angle = (math.pi * 2 * step) / 16
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local candidate = getFieldLandingPosition(field, monsterPosition + direction * radius)
		local distance = (candidate - monsterPosition).Magnitude
		if distance > bestDistance then
			best, bestDistance = candidate, distance
		end
	end
	return best
end

local function getEscapeAwayPosition(field: BasePart, monsterPosition: Vector3, radius: number, away: Vector3): Vector3
	local best = getFieldLandingPosition(field, monsterPosition + away * radius)
	local bestDistance = (best - monsterPosition).Magnitude
	for step = -4, 4 do
		local angle = math.rad(step * 18)
		local direction = Vector3.new(
			away.X * math.cos(angle) - away.Z * math.sin(angle),
			0,
			away.X * math.sin(angle) + away.Z * math.cos(angle)
		)
		local candidate = getFieldLandingPosition(field, monsterPosition + direction * radius)
		local candidateOffset = Vector3.new(candidate.X - monsterPosition.X, 0, candidate.Z - monsterPosition.Z)
		local distance = candidateOffset.Magnitude
		if candidateOffset:Dot(away) > 0 and distance > bestDistance then
			best, bestDistance = candidate, distance
		end
	end
	return best
end

local function tweenVerticalEmergency(root: BasePart, targetY: number)
	local startY = root.Position.Y
	local delta = targetY - startY
	if math.abs(delta) <= 0.5 then
		return
	end
	local startedAt = os.clock()
	local duration = math.clamp(math.abs(delta) / 900, 0.015, 0.05)
	repeat
		local alpha = math.clamp((os.clock() - startedAt) / duration, 0, 1)
		local position = root.Position
		local y = startY + delta * alpha
		root.CFrame = root.CFrame + Vector3.new(0, y - position.Y, 0)
		root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
		if alpha >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	until false
end
local function getTokenAssetId(token: Instance): string?
	if tokenAssetCache[token] then
		return tokenAssetCache[token]
	end
	local decal = token:FindFirstChild("BackDecal", true)
	if not decal then
		return nil
	end
	local raw = ""
	pcall(function()
		raw = tostring((decal :: any).ColorMapContent or (decal :: any).TextureContent or (decal :: any).Texture or "")
	end)
	local id = raw:match("(%d+)")
	tokenAssetCache[token] = id
	return id
end
local function isTokenInsideField(token: Instance, field: BasePart): boolean
	local position = getTokenPosition(token)
	return position ~= nil and isPositionInsideField(position, field, 0)
end
local function getPriorities(): { [string]: number }
	local raw = player:GetAttribute("ArcadaPriorityTokens")
	if type(raw) ~= "string" then
		return {}
	end
	if raw ~= priorityCacheRaw then
		priorityCacheRaw = raw
		local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
		priorityCache = if ok and type(data) == "table" then data else {}
	end
	return priorityCache
end
local function getTokenPriority(token: Instance, mode: string?): number
	local normal = tonumber(getPriorities()[getTokenAssetId(token) or ""]) or 0
	return normal
end
local function chooseNextToken(field: BasePart, mode: string?, excludedToken: Instance?): Instance?
	local root = getRootPart()
	if not root then
		return nil
	end
	local best, bestPriority, bestPlayerDistance = nil, -math.huge, math.huge
	local priorities = getPriorities()
	local nearest = {}
	for token in pairs(cache.Collectibles) do
		local pos = token.Parent and getTokenPosition(token)
		if
			token ~= excludedToken
			and token.Name == "C"
			and pos
			and isPositionInsideField(pos, field, 0)
			and (phantomTokens[token] or 0) < os.clock()
			and (recentlyVisitedTokens[token] or 0) < os.clock()
		then
			local playerDistance = (root.Position - pos).Magnitude
			if not FarmingState.PriorityTokens then
				table.insert(nearest, { Token = token, Distance = playerDistance })
				continue
			end
			local normal = tonumber(priorities[getTokenAssetId(token) or ""]) or 0
			local priority = normal
			if priority > bestPriority or (priority == bestPriority and playerDistance < bestPlayerDistance) then
				best, bestPriority, bestPlayerDistance = token, priority, playerDistance
			end
		end
	end
	if not FarmingState.PriorityTokens and #nearest > 0 then
		table.sort(nearest, function(a, b)
			return a.Distance < b.Distance
		end)
		return nearest[math.random(1, math.min(3, #nearest))].Token
	end
	return best
end
local function markTokenAsPhantom(token: Instance)
	phantomTokens[token] = os.clock() + Config.PhantomTokenBlacklistTime
end

local function isPopStarNearby(): boolean
	local root = getRootPart()
	local particles = workspace:FindFirstChild("Particles")
	local popStars = particles and particles:FindFirstChild("PopStars")
	if not root or not popStars then
		return false
	end
	for _, candidate in ipairs(popStars:GetChildren()) do
		if string.find(string.lower(candidate.Name), "pop star", 1, true) then
			local position = getTokenPosition(candidate)
			if position and (root.Position - position).Magnitude <= 80 then
				return true
			end
		end
	end
	return false
end

local function chooseNearestBubble(field: BasePart): Instance?
	if not FarmingState.FarmBubbles then
		return nil
	end
	local particles = workspace:FindFirstChild("Particles")
	local root = getRootPart()
	if not particles or not root then
		return nil
	end
	if bubbleFolder ~= particles then
		disconnectAll(bubbleConnections)
		table.clear(bubbleCandidates)
		bubbleFolder = particles
		local function trackBubble(descendant: Instance)
			if descendant.Name == "Bubble" and (descendant:IsA("BasePart") or descendant:IsA("Model")) then
				bubbleCandidates[descendant] = true
			end
		end
		for _, descendant in ipairs(particles:GetDescendants()) do
			trackBubble(descendant)
		end
		table.insert(bubbleConnections, particles.DescendantAdded:Connect(trackBubble))
		table.insert(
			bubbleConnections,
			particles.DescendantRemoving:Connect(function(descendant)
				bubbleCandidates[descendant] = nil
			end)
		)
	end
	local best, bestDistance = nil, math.huge
	for bubble in pairs(bubbleCandidates) do
		if bubble.Parent and (recentlyVisitedTokens[bubble] or 0) < os.clock() then
			local position = getTokenPosition(bubble)
			if position and isPositionInsideField(position, field, 0) then
				local distance = (root.Position - position).Magnitude
				if distance < bestDistance then
					best, bestDistance = bubble, distance
				end
			end
		end
	end
	return best
end

local function getBloomHealth(bloom: Instance): number?
	local pistil = bloom:FindFirstChild("Pistil", true)
	local guiAttach = pistil and pistil:FindFirstChild("GuiAttach", true)
	local plantGui = guiAttach and guiAttach:FindFirstChild("PlantHealthGui", true)
	local background = plantGui and plantGui:FindFirstChild("BarBackground", true)
	local statsLabel = background and background:FindFirstChild("StatsLabel", true)
	if not statsLabel or not (statsLabel:IsA("TextLabel") or statsLabel:IsA("TextBox")) then
		return nil
	end
	local current = string.match(statsLabel.Text, "([%d,]+)%s*/")
	return current and tonumber((string.gsub(current, ",", ""))) or nil
end

local function findAncestorBloom(instance: Instance): Instance?
	local current = instance.Parent
	while current do
		if current.Name == "Bloom" and current:IsA("Model") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function isPetalCandidate(instance: Instance): boolean
	return (instance:IsA("BasePart") or instance:IsA("Model"))
		and string.find(string.lower(instance.Name), "petal", 1, true) ~= nil
end

local function runPetalFarm(field: BasePart): boolean
	if not FarmingState.FarmPetals then
		return false
	end
	local root = getRootPart()
	if not root then
		return false
	end
	if petalFolder ~= workspace then
		disconnectAll(petalConnections)
		table.clear(petalCandidates)
		petalFolder = workspace
		local function trackCandidate(descendant: Instance)
			if (descendant.Name == "Bloom" and descendant:IsA("Model")) or isPetalCandidate(descendant) then
				petalCandidates[descendant] = true
			end
		end
		for _, descendant in ipairs(workspace:GetDescendants()) do
			trackCandidate(descendant)
		end
		table.insert(petalConnections, workspace.DescendantAdded:Connect(trackCandidate))
		table.insert(
			petalConnections,
			workspace.DescendantRemoving:Connect(function(descendant)
				petalCandidates[descendant] = nil
				petalTargetStarted[descendant] = nil
			end)
		)
	end

	local nearestPetal, nearestPetalPosition, nearestPetalDistance = nil, nil, math.huge
	local nearestBloom, nearestBloomPosition, nearestBloomDistance = nil, nil, math.huge
	for descendant in pairs(petalCandidates) do
		if not descendant.Parent then
			petalCandidates[descendant] = nil
			continue
		end
		if isPetalCandidate(descendant) then
			local position = getTokenPosition(descendant)
			if
				position
				and (recentlyVisitedTokens[descendant] or 0) < os.clock()
				and isPositionInsideField(position, field, 0)
			then
				local distance = (root.Position - position).Magnitude
				if distance < nearestPetalDistance then
					nearestPetal, nearestPetalPosition, nearestPetalDistance = descendant, position, distance
				end
			end
		elseif descendant.Name == "Bloom" and descendant:IsA("Model") then
			local health = getBloomHealth(descendant)
			local position = getTokenPosition(descendant)
			if health and health > 0 and position and isPositionInsideField(position, field, 0) then
				local distance = (root.Position - position).Magnitude
				if distance < nearestBloomDistance then
					nearestBloom, nearestBloomPosition, nearestBloomDistance = descendant, position, distance
				end
			end
		end
	end

	if nearestPetal and nearestPetalPosition then
		local startedAt = petalTargetStarted[nearestPetal]
		if nearestPetalDistance <= Config.TokenReachDistance then
			recentlyVisitedTokens[nearestPetal] = os.clock() + Config.TokenBlacklistTime
			petalTargetStarted[nearestPetal] = nil
			return false
		elseif startedAt and os.clock() - startedAt >= Config.TokenPursuitTimeout then
			recentlyVisitedTokens[nearestPetal] = os.clock() + Config.PhantomTokenBlacklistTime
			petalTargetStarted[nearestPetal] = nil
			return false
		end
		petalTargetStarted[nearestPetal] = startedAt or os.clock()
		setFarmingState("CollectingPetals")
		walkTo(getFieldLandingPosition(field, nearestPetalPosition))
		return true
	end
	if nearestBloom and nearestBloomPosition then
		setFarmingState("BreakingBloom")
		walkTo(getFieldLandingPosition(field, nearestBloomPosition))
		if nearestBloomDistance <= 8 then
			activateDigTool()
		end
		return true
	end
	return false
end

local function isMonsterTargetingLocalPlayer(monster: Instance): boolean
	local target = monster:FindFirstChild("Target")
	if target and target:IsA("ValueBase") and valueTargetsPlayer((target :: any).Value) then
		return true
	end
	return valueTargetsPlayer(monster:GetAttribute("Target"))
end
local function hasTargetingMonsters(): boolean
	for monster in pairs(cache.Monsters) do
		if monster.Parent and isMonsterTargetingLocalPlayer(monster) then
			return true
		end
	end
	return false
end
local function hasMonsterInField(field: BasePart): boolean
	for monster in pairs(cache.Monsters) do
		local position = monster.Parent and getTokenPosition(monster)
		local humanoid = monster:FindFirstChildOfClass("Humanoid")
		local active = isMonsterTargetingLocalPlayer(monster) or (humanoid ~= nil and humanoid.Health > 0)
		if active and position and isPositionInsideField(position, field, 0) then
			return true
		end
	end
	return false
end

local function getFieldContainingPosition(position: Vector3): BasePart?
	for field in pairs(cache.FlowerZones) do
		if field:IsA("BasePart") and field.Parent and isPositionInsideField(position, field, 0) then
			return field
		end
	end
	return nil
end
local function isSproutAlive(sprout: Instance): boolean
	if not sprout.Parent then
		return false
	end
	local health = sprout:GetAttribute("Health") or (sprout:FindFirstChild("Health") and (sprout.Health :: any).Value)
	return health == nil or tonumber(health) == nil or tonumber(health) > 0
end
local function findNearestSprout(): Instance?
	local root = getRootPart()
	local best, distance = nil, math.huge
	for sprout in pairs(cache.Sprouts) do
		local p = getTokenPosition(sprout)
		if root and p and isSproutAlive(sprout) and (root.Position - p).Magnitude < distance then
			best, distance = sprout, (root.Position - p).Magnitude
		end
	end
	return best
end

local function findFieldByName(name: string): BasePart?
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local folder = folders.FlowerZones or workspace:FindFirstChild("FlowerZones")
	local field = folder and folder:FindFirstChild(name)
	return if field and field:IsA("BasePart") then field else nil
end

local function findBossMonster(name: string): Instance?
	local lowered = string.lower(name)
	for monster in pairs(cache.Monsters) do
		local monsterType = monster.Parent and monster:FindFirstChild("MonsterType")
		local typeName = monsterType and monsterType:IsA("ValueBase") and tostring((monsterType :: any).Value) or ""
		if
			monster.Parent
			and (
				string.find(string.lower(monster.Name), lowered, 1, true)
				or string.find(string.lower(typeName), lowered, 1, true)
			)
		then
			local humanoid = monster:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health > 0 then
				return monster
			end
		end
	end
	return nil
end

local function findBossSpawnHint(kind: string): (Instance?, BasePart?)
	local wanted = string.lower(kind)
	local cached = bossHintCache[wanted]
	if cached and os.clock() - cached.At < 1 then
		if cached.Object and cached.Object.Parent and cached.Field and cached.Field.Parent then
			return cached.Object, cached.Field
		end
		return nil, nil
	end
	for _, folderName in ipairs({ "Clouds", "Particles", "FlyingEntities", "FEMonsters" }) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			for _, object in ipairs(folder:GetDescendants()) do
				local lowerName = string.lower(object.Name)
				if
					string.find(lowerName, wanted, 1, true)
					or (wanted == "vicious" and string.find(lowerName, "spike", 1, true))
				then
					local position = getTokenPosition(object)
					local field = position and getFieldContainingPosition(position)
					if position and field then
						bossHintCache[wanted] = { At = os.clock(), Object = object, Field = field }
						return object, field
					end
				end
			end
		end
	end
	bossHintCache[wanted] = { At = os.clock() }
	return nil, nil
end

local function isBossReady(spawnerName: string): boolean
	local spawners = workspace:FindFirstChild("MonsterSpawners")
	local spawner = spawners and spawners:FindFirstChild(spawnerName)
	local attachment = spawner and spawner:FindFirstChild("TimerAttachment", true)
	local gui = attachment and attachment:FindFirstChild("TimerGui", true)
	local label = gui and gui:FindFirstChild("TimerLabel", true)
	return label ~= nil and label:IsA("GuiObject") and label.Visible == false
end

local function chooseBossToken(field: BasePart, avoidPosition: Vector3?, avoidDistance: number?): Instance?
	local root = getRootPart()
	if not root then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for token in pairs(cache.Collectibles) do
		local position = token.Parent and token.Name == "C" and getTokenPosition(token)
		if
			position
			and isPositionInsideField(position, field, 0)
			and (not avoidPosition or (position - avoidPosition).Magnitude >= (avoidDistance or 0))
			and (recentlyVisitedTokens[token] or 0) < os.clock()
			and (phantomTokens[token] or 0) < os.clock()
		then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = token, distance
			end
		end
	end
	return best
end

local function collectBossTokens(field: BasePart, avoidPosition: Vector3?, avoidDistance: number?): boolean
	local root = getRootPart()
	if not root then
		return true
	end
	local token = bossContext and bossContext.CurrentToken
	local position = token and token.Parent and getTokenPosition(token)
	if
		not position
		or not isPositionInsideField(position, field, 0)
		or (avoidPosition and (position - avoidPosition).Magnitude < (avoidDistance or 0))
	then
		token, position = nil, nil
		if bossContext then
			bossContext.CurrentToken = nil
		end
	end
	if token and position then
		if (root.Position - position).Magnitude <= Config.TokenReachDistance then
			recentlyVisitedTokens[token] = os.clock() + Config.TokenBlacklistTime
			bossContext.CurrentToken = nil
			token = nil
		elseif os.clock() - (bossContext.CurrentTokenStarted or os.clock()) >= Config.TokenPursuitTimeout then
			markTokenAsPhantom(token)
			bossContext.CurrentToken = nil
			token = nil
		end
	end
	if not token then
		token = chooseBossToken(field, avoidPosition, avoidDistance)
		if token then
			bossContext.CurrentToken = token
			bossContext.CurrentTokenStarted = os.clock()
			position = getTokenPosition(token)
		end
	end
	if token and position then
		walkTo(getFieldLandingPosition(field, position))
		return true
	end
	return false
end

local function runBossStateMachine(): boolean
	if converting then
		setBossHover(nil)
		return false
	end
	local pollen, capacity = getPollenAndCapacity()
	local convertThreshold = capacity * (FarmingState.ConvertPercent / 100)
	local timedConvertDue = pollen > 0 and os.clock() - lastConversionCompletedAt >= FarmingState.ConvertMinutes * 60
	if FarmingState.AutoFarm and capacity > 0 and (pollen >= convertThreshold or timedConvertDue) then
		setBossHover(nil)
		return false
	end
	local enabled = FarmingState.FarmMondo
		or FarmingState.FarmWindyBee
		or FarmingState.FarmViciousBee
		or FarmingState.FarmStumpSnail
	if not enabled then
		bossContext = nil
		setBossHover(nil)
		return false
	end
	local now = os.clock()
	if bossContext and bossContext.CollectUntil then
		setBossHover(nil)
		if now >= bossContext.CollectUntil then
			bossContext = nil
			return false
		end
		setFarmingState("CollectingBossTokens")
		if not collectBossTokens(bossContext.Field) then
			walkTo(getRandomPointInsideField(bossContext.Field))
		end
		return true
	end

	local bossType, fieldName, monsterName, spawnHint
	if bossContext and bossContext.Type == "Mondo" and FarmingState.FarmMondo then
		bossType, fieldName, monsterName = "Mondo", "Mountain Top Field", "Mondo Chick"
	elseif bossContext and bossContext.Type == "Windy" and FarmingState.FarmWindyBee then
		bossType, monsterName = "Windy", "Windy Bee"
	elseif bossContext and bossContext.Type == "Vicious" and FarmingState.FarmViciousBee then
		bossType, monsterName = "Vicious", "Vicious Bee"
	elseif bossContext and bossContext.Type == "Stump" and FarmingState.FarmStumpSnail then
		bossType, fieldName, monsterName = "Stump", "Stump Field", "Stump Snail"
	elseif FarmingState.FarmWindyBee and findBossMonster("Windy Bee") then
		bossType, monsterName = "Windy", "Windy Bee"
	elseif FarmingState.FarmViciousBee and findBossMonster("Vicious Bee") then
		bossType, monsterName = "Vicious", "Vicious Bee"
	elseif FarmingState.FarmMondo and findBossMonster("Mondo Chick") then
		bossType, fieldName, monsterName = "Mondo", "Mountain Top Field", "Mondo Chick"
	elseif FarmingState.FarmStumpSnail and isBossReady("StumpSnail") then
		bossType, fieldName, monsterName = "Stump", "Stump Field", "Stump Snail"
	else
		if FarmingState.FarmWindyBee then
			local hintField
			spawnHint, hintField = findBossSpawnHint("windy")
			local hintPosition = spawnHint and getTokenPosition(spawnHint)
			if hintField then
				bossType, monsterName, fieldName = "Windy", "Windy Bee", hintField.Name
			end
		end
		if not bossType and FarmingState.FarmViciousBee then
			local hintField
			spawnHint, hintField = findBossSpawnHint("vicious")
			local hintPosition = spawnHint and getTokenPosition(spawnHint)
			if hintField then
				bossType, monsterName, fieldName = "Vicious", "Vicious Bee", hintField.Name
			end
		end
		if not bossType then
			bossContext = nil
			setBossHover(nil)
			return false
		end
	end
	local monster = findBossMonster(monsterName)
	local monsterPosition = monster and getTokenPosition(monster)
	local field = (monsterPosition and getFieldContainingPosition(monsterPosition))
		or findFieldByName(fieldName)
		or (bossContext and bossContext.Field)
	if not field then
		return false
	end
	if not bossContext or bossContext.Type ~= bossType then
		bossContext = { Type = bossType, Field = field, Seen = false }
	end
	bossContext.Field = field
	local root = getRootPart()
	if not root then
		return true
	end
	if bossType ~= "Windy" and not isPositionInsideField(root.Position, field, 0) then
		bossContext.OutsideSince = bossContext.OutsideSince or now
		if now - bossContext.OutsideSince >= 3 or not bossContext.Seen then
			returnPlayerToField(field)
		end
		return true
	end
	bossContext.OutsideSince = nil
	if not monster then
		setBossHover(nil)
		if bossContext.Seen then
			local duration = if bossType == "Mondo" then 30 else 0
			if duration > 0 and (bossType ~= "Mondo" or FarmingState.CollectMondoTokens) then
				bossContext.CollectUntil = now + duration
				return true
			end
			bossContext = nil
			return false
		end
		setFarmingState("WaitingFor" .. bossType)
		local hintPosition = spawnHint and getTokenPosition(spawnHint)
		walkTo(if hintPosition then getFieldLandingPosition(field, hintPosition) else getFieldCenterPosition(field))
		if bossType == "Stump" and not bossContext.SprinklerPlaced then
			bossContext.SprinklerPlaced = placeSprinkler(field, true)
		end
		return true
	end
	bossContext.Seen = true
	monsterPosition = getTokenPosition(monster)
	if not monsterPosition then
		return true
	end
	if bossType == "Mondo" then
		setBossHover(nil)
		setFarmingState("FarmingMondoChick")
		local offset = root.Position - monsterPosition
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local direction = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(1, 0, 0)
		local distance = flat.Magnitude
		local safeRadius = getMonsterAvoidRadius(monster, 14)
		local preferredRadius = safeRadius + 7
		if distance < safeRadius then
			-- Move on the ray pointing strictly away from Mondo. The whole tween
			-- increases separation, so its path can never cross through the model.
			local escape = getEscapeAwayPosition(field, monsterPosition, preferredRadius, direction)
			moveCharacterSmoothly(CFrame.new(escape), { Speed = 500 })
			bossContext.MondoOrbitTarget = nil
			bossContext.MondoOrbitStarted = nil
			bossContext.MondoOrbitAngle = nil
		elseif distance > safeRadius + 16 then
			bossContext.MondoOrbitStarted = nil
			bossContext.MondoOrbitAngle = nil
			walkTo(getSafestFieldPosition(field, monsterPosition, preferredRadius, direction))
		else
			-- Follow one continuous orbit instead of choosing a random side every
			-- fraction of a second. This removes the visible radial twitching.
			bossContext.MondoOrbitStarted = bossContext.MondoOrbitStarted or now
			bossContext.MondoOrbitAngle = bossContext.MondoOrbitAngle or math.atan2(direction.Z, direction.X)
			local angle = bossContext.MondoOrbitAngle + (now - bossContext.MondoOrbitStarted) * 0.42
			local orbitDirection = Vector3.new(math.cos(angle), 0, math.sin(angle))
			bossContext.MondoOrbitTarget =
				getFieldLandingPosition(field, monsterPosition + orbitDirection * preferredRadius)
			walkTo(bossContext.MondoOrbitTarget)
		end
		activateDigTool()
	elseif bossType == "Windy" then
		setFarmingState("FarmingWindyBee")
		-- Stay directly above the bee. The large vertical separation keeps the
		-- character outside tornado paths while still following a moving Windy.
		local hoverTarget = monsterPosition + Vector3.new(0, 55, 0)
		tweenVerticalEmergency(root, hoverTarget.Y)
		setBossHover(hoverTarget)
		activateDigTool()
	elseif bossType == "Vicious" then
		setFarmingState("FarmingViciousBee")
		-- Vicious spikes are ground hazards, so track the bee from well above it.
		local hoverTarget = monsterPosition + Vector3.new(0, 55, 0)
		tweenVerticalEmergency(root, hoverTarget.Y)
		setBossHover(hoverTarget)
		activateDigTool()
	else
		setBossHover(nil)
		setFarmingState("FarmingStumpSnail")
		if not bossContext.SprinklerPlaced then
			bossContext.SprinklerPlaced = placeSprinkler(field, true)
		end
		local avoidRadius = getMonsterAvoidRadius(monster, 10)
		local flatOffset = Vector3.new(root.Position.X - monsterPosition.X, 0, root.Position.Z - monsterPosition.Z)
		if flatOffset.Magnitude < avoidRadius then
			local centerOffset = getFieldCenterPosition(field) - monsterPosition
			local fallback = Vector3.new(centerOffset.X, 0, centerOffset.Z)
			local direction = if flatOffset.Magnitude > 0.1
				then flatOffset.Unit
				elseif fallback.Magnitude > 0.1 then fallback.Unit
				else Vector3.new(1, 0, 0)
			walkTo(getFieldLandingPosition(field, monsterPosition + direction * (avoidRadius + 3)))
			return true
		end
		if not collectBossTokens(field, monsterPosition, avoidRadius) then
			walkTo(getFieldCenterPosition(field))
		end
		activateDigTool()
	end
	return true
end

local puffRarityRanks = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }
local function getPuffPosition(puff: Instance): Vector3?
	local stem = puff:FindFirstChild("Puffball Stem")
	return if stem and stem:IsA("BasePart") then stem.Position else getTokenPosition(puff)
end

local function getPuffMetadata(puff: Instance): (string, number)
	local cached = puffMetadataCache[puff]
	if cached and os.clock() - cached.At < 1 then
		return cached.Rarity, cached.Level
	end
	local rarity = "Common"
	for name in pairs(puffRarityRanks) do
		if string.find(string.lower(puff.Name), string.lower(name), 1, true) then
			rarity = name
			break
		end
	end
	local level = tonumber(puff:GetAttribute("Level")) or tonumber(puff:GetAttribute("Lvl"))
	if not level then
		for _, object in ipairs(puff:GetDescendants()) do
			if object:IsA("ValueBase") and string.find(string.lower(object.Name), "level", 1, true) then
				level = tonumber((object :: any).Value)
			elseif object:IsA("TextLabel") or object:IsA("TextButton") then
				level = tonumber(
					string.match(object.Text, "[Ll]evel%s*(%d+)") or string.match(object.Text, "[Ll]vl%.?%s*(%d+)")
				)
			end
			if level then
				break
			end
		end
	end
	level = math.clamp(math.floor(level or 1), 1, 30)
	puffMetadataCache[puff] = { At = os.clock(), Rarity = rarity, Level = level }
	return rarity, level
end

local function isPuffFieldAllowed(field: BasePart): boolean
	local raw = string.lower(FarmingState.PuffFields):match("^%s*(.-)%s*$") or "all"
	if raw == "" or raw == "all" or raw == "*" then
		return true
	end
	local wanted = string.lower(field.Name)
	for entry in string.gmatch(raw, "[^,;]+") do
		entry = entry:match("^%s*(.-)%s*$") or ""
		if entry == wanted then
			return true
		end
	end
	return false
end

local function choosePuffshroom(nearestOnly: boolean?): (Instance?, BasePart?)
	local happenings = workspace:FindFirstChild("Happenings")
	local folder = happenings and happenings:FindFirstChild("Puffshrooms")
	local root = getRootPart()
	if not folder or not root then
		return nil, nil
	end
	local minRarity = 1
	for rarityName, rank in pairs(puffRarityRanks) do
		if string.lower(rarityName) == string.lower(FarmingState.PuffMinRarity) then
			minRarity = rank
			break
		end
	end
	local best, bestField, bestScore = nil, nil, -math.huge
	for _, puff in ipairs(folder:GetChildren()) do
		local position = getPuffPosition(puff)
		local field = position and getFieldContainingPosition(position)
		if position and field and isPuffFieldAllowed(field) then
			local rarity, level = getPuffMetadata(puff)
			local rank = puffRarityRanks[rarity] or 1
			if rank >= minRarity and level >= FarmingState.PuffMinLevel then
				local distance = (root.Position - position).Magnitude
				local score = if not nearestOnly and FarmingState.PuffPreferRarity
					then rank * 1000000 + level * 10000 - distance
					else -distance
				if score > bestScore then
					best, bestField, bestScore = puff, field, score
				end
			end
		end
	end
	return best, bestField
end

local function collectPuffLoot(field: BasePart): boolean
	local root = getRootPart()
	if not root or not puffContext then
		return false
	end
	local token = puffContext.LootToken
	local position = token and token.Parent and getTokenPosition(token)
	local lootOrigin = puffContext.LootOrigin
	local lootRadius = 45
	if
		not position
		or not isPositionInsideField(position, field, 0)
		or (lootOrigin and (position - lootOrigin).Magnitude > lootRadius)
	then
		token, position = nil, nil
		puffContext.LootToken = nil
	end
	if token and position then
		if (root.Position - position).Magnitude <= Config.TokenReachDistance then
			recentlyVisitedTokens[token] = os.clock() + Config.TokenBlacklistTime
			puffContext.LootToken = nil
			token = nil
		elseif os.clock() - (puffContext.LootTokenStarted or os.clock()) >= Config.TokenPursuitTimeout then
			markTokenAsPhantom(token)
			puffContext.LootToken = nil
			token = nil
		end
	end
	if not token then
		local bestDistance = math.huge
		for candidate in pairs(cache.Collectibles) do
			local candidatePosition = candidate.Parent and candidate.Name == "C" and getTokenPosition(candidate)
			if
				candidatePosition
				and isPositionInsideField(candidatePosition, field, 0)
				and (not lootOrigin or (candidatePosition - lootOrigin).Magnitude <= lootRadius)
				and (recentlyVisitedTokens[candidate] or 0) < os.clock()
				and (phantomTokens[candidate] or 0) < os.clock()
			then
				local distance = (root.Position - candidatePosition).Magnitude
				if distance < bestDistance then
					token, position, bestDistance = candidate, candidatePosition, distance
				end
			end
		end
		if token then
			puffContext.LootToken = token
			puffContext.LootTokenStarted = os.clock()
			position = getTokenPosition(token)
		end
	end
	if token and position then
		walkTo(getFieldLandingPosition(field, position))
		return true
	end
	return false
end

local function runPuffshroomStateMachine(): boolean
	local chooseNearestNext = false
	if not FarmingState.AutoPuffshrooms or converting then
		puffContext = nil
		return false
	end
	local pollen, capacity = getPollenAndCapacity()
	local threshold = capacity * (FarmingState.ConvertPercent / 100)
	if FarmingState.AutoFarm and capacity > 0 and pollen >= threshold then
		return false
	end
	if puffContext and puffContext.Target and not puffContext.Target.Parent then
		puffContext.LootOrigin = puffContext.LastPosition
		puffContext.Target = nil
		puffContext.LootUntil = os.clock() + FarmingState.PuffLootSeconds
	end
	-- Finish the broken puffshroom's loot window before switching targets. Tokens
	-- can replicate a little later than the puff model is removed.
	if puffContext and puffContext.LootUntil then
		if FarmingState.PuffCollectLoot and os.clock() < puffContext.LootUntil then
			setFarmingState("CollectingPuffshroomLoot")
			if not collectPuffLoot(puffContext.Field) then
				walkTo(getFieldLandingPosition(puffContext.Field, puffContext.LootOrigin or getFieldCenterPosition(puffContext.Field)))
			end
			return true
		end
		chooseNearestNext = true
		puffContext = nil
	end
	local target, field = choosePuffshroom(chooseNearestNext)
	if target and (not puffContext or puffContext.Target ~= target) then
		puffContext = { Target = target, Field = field }
	end
	if target then
		puffContext = puffContext or { Target = target, Field = field }
		puffContext.Target, puffContext.Field, puffContext.LootUntil = target, field, nil
		local root = getRootPart()
		local position = getPuffPosition(target)
		if not root or not position or not field then
			return true
		end
		puffContext.LastPosition = position
		setFarmingState("FarmingPuffshroom")
		if not isPositionInsideField(root.Position, field, 0) then
			returnPlayerToField(field)
		else
			local flatOffset = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
			local distance = flatOffset.Magnitude
			if distance <= 14 and not puffContext.SprinklerPlaced then
				puffContext.SprinklerPlaced = placeSprinkler(field, true)
			end
			local orbitRadius = 10
			if distance > orbitRadius + 5 then
				walkTo(getFieldLandingPosition(field, position))
			else
				puffContext.OrbitStarted = puffContext.OrbitStarted or os.clock()
				puffContext.OrbitAngle = puffContext.OrbitAngle
					or (if distance > 0.1 then math.atan2(flatOffset.Z, flatOffset.X) else 0)
				local angle = puffContext.OrbitAngle + (os.clock() - puffContext.OrbitStarted) * 0.8
				local orbitOffset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * orbitRadius
				walkTo(getFieldLandingPosition(field, position + orbitOffset))
			end
			activateDigTool()
		end
		return true
	end
	puffContext = nil
	return false
end

local function runSproutStateMachine(): boolean
	local now = os.clock()
	local pollen, capacity = getPollenAndCapacity()
	local convertThreshold = capacity * (FarmingState.ConvertPercent / 100)
	local timedConvertDue = pollen > 0 and os.clock() - lastConversionCompletedAt >= FarmingState.ConvertMinutes * 60
	if converting or (FarmingState.AutoFarm and capacity > 0 and (pollen >= convertThreshold or timedConvertDue)) then
		return false
	end
	if sproutContext and sproutContext.CollectUntil then
		if now >= sproutContext.CollectUntil then
			sproutContext = nil
			return false
		end
		setFarmingState("CollectingSproutTokens")
		local field = sproutContext.Field
		local root = getRootPart()
		if not field or not field.Parent or not root then
			return true
		end
		local token = sproutContext.CurrentToken
		local position = token and token.Parent and getTokenPosition(token)
		if
			not position
			or not isPositionInsideField(position, field, 0)
			or (recentlyVisitedTokens[token] or 0) >= now
		then
			token = nil
			sproutContext.CurrentToken = nil
		end
		if token and position then
			local distance = (root.Position - position).Magnitude
			sproutContext.CurrentTokenClosest = math.min(sproutContext.CurrentTokenClosest or math.huge, distance)
			if distance <= Config.TokenReachDistance then
				recentlyVisitedTokens[token] = now + Config.TokenBlacklistTime
				sproutContext.CurrentToken = nil
				token = nil
			elseif
				(sproutContext.CurrentTokenClosest or math.huge) <= Config.TokenReachDistance
				and now - (sproutContext.CurrentTokenStarted or now) > Config.PhantomTokenTimeout
			then
				markTokenAsPhantom(token)
				sproutContext.CurrentToken = nil
				token = nil
			elseif now - (sproutContext.CurrentTokenStarted or now) >= Config.TokenPursuitTimeout then
				markTokenAsPhantom(token)
				sproutContext.CurrentToken = nil
				token = nil
			end
		end
		if not token then
			token = chooseNextToken(field, "Sprout")
			if token then
				sproutContext.CurrentToken = token
				sproutContext.CurrentTokenStarted = now
				sproutContext.CurrentTokenClosest = math.huge
				position = getTokenPosition(token)
			end
		end
		if token and position then
			walkTo(getFieldLandingPosition(field, position))
		else
			local roamPosition = sproutContext.RoamTarget
			if
				not roamPosition
				or now - (sproutContext.RoamTargetAt or 0) >= Config.RoamInterval
				or (root.Position - roamPosition).Magnitude <= 4
			then
				roamPosition = getRandomPointInsideField(field)
				sproutContext.RoamTarget = roamPosition
				sproutContext.RoamTargetAt = now
			end
			walkTo(roamPosition)
		end
		return true
	end

	local sprout = if sproutContext then sproutContext.Sprout else findNearestSprout()
	if sprout and not isSproutAlive(sprout) then
		if sproutContext and sproutContext.Field then
			sproutContext = { Field = sproutContext.Field, CollectUntil = now + Config.SproutTokenCollectionTime }
			return true
		end
		sproutContext = nil
		sprout = nil
	end
	if not sprout then
		sprout = findNearestSprout()
		if not sprout then
			sproutContext = nil
			return false
		end
	end

	local position = getTokenPosition(sprout)
	local field = position and getFieldContainingPosition(position)
	if not position or not field then
		return false
	end
	if not sproutContext or sproutContext.Sprout ~= sprout then
		sproutContext = { Sprout = sprout, Field = field, LastFlightAt = 0 }
	end
	setFarmingState("FarmingSprout")
	local root = getRootPart()
	if not root then
		return true
	end
	local landingPosition = getFieldLandingPosition(field, position)
	if (root.Position - landingPosition).Magnitude > Config.SproutArrivalDistance then
		if now - (sproutContext.LastFlightAt or 0) >= 1 then
			sproutContext.LastFlightAt = now
			moveCharacterSmoothly(CFrame.new(landingPosition))
		end
	else
		if root.Anchored then
			root.Anchored = false
		end
		sproutContext.Engaged = true
		if FarmingState.AutoSprinkler and not sproutContext.SprinklerPlaced then
			setFarmingState("PlacingSproutSprinkler")
			sproutContext.SprinklerPlaced = placeSprinkler(field, true)
			if not sproutContext.SprinklerPlaced then
				return true
			end
		end
		activateDigTool()
	end
	return true
end

local espFolder = Instance.new("Folder")
espFolder.Name = "ArcadaTokenESP"
espFolder.Parent = workspace
local espOriginAttachment = nil
local function getESPOriginAttachment(): Attachment?
	local root = getRootPart()
	if not root then
		return nil
	end
	if espOriginAttachment and espOriginAttachment.Parent == root then
		return espOriginAttachment
	end
	if espOriginAttachment then
		espOriginAttachment:Destroy()
	end
	espOriginAttachment = Instance.new("Attachment")
	espOriginAttachment.Name = "ArcadaTokenESPOrigin"
	espOriginAttachment.Parent = root
	return espOriginAttachment
end
local function removeTokenESP(token: Instance)
	local record = espRecords[token]
	if not record then
		return
	end
	for _, object in pairs(record) do
		if typeof(object) == "Instance" then
			object:Destroy()
		end
	end
	espRecords[token] = nil
end
local function createTokenESP(token: Instance)
	if espRecords[token] then
		return
	end
	local part = if token:IsA("BasePart") then token else token:FindFirstChildWhichIsA("BasePart", true)
	if not part then
		return
	end
	local origin = getESPOriginAttachment()
	if not origin then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Adornee = token
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 0
	highlight.OutlineColor = Color3.fromRGB(0, 255, 90)
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = espFolder
	local toAttachment = Instance.new("Attachment")
	toAttachment.Name = "ArcadaTokenESPTarget"
	toAttachment.Parent = part
	local beam = Instance.new("Beam")
	beam.Attachment0 = origin
	beam.Attachment1 = toAttachment
	beam.Color = ColorSequence.new(Color3.fromRGB(0, 255, 90))
	beam.Width0 = 0.06
	beam.Width1 = 0.06
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Enabled = false
	beam.Parent = espFolder
	espRecords[token] = { Highlight = highlight, TargetAttachment = toAttachment, Beam = beam }
end
local function updateTokenESP(token: Instance)
	local root = getRootPart()
	local pos = getTokenPosition(token)
	if not root or not pos then
		removeTokenESP(token)
		return
	end
	local distance = (root.Position - pos).Magnitude
	if distance > Config.TokenESPDistance then
		removeTokenESP(token)
		return
	end
	createTokenESP(token)
	local r = espRecords[token]
	if r then
		r.Beam.Enabled = distance <= Config.TokenLineDistance
	end
end
local function clearAllTokenESP()
	for token in pairs(espRecords) do
		removeTokenESP(token)
	end
	if espOriginAttachment then
		espOriginAttachment:Destroy()
		espOriginAttachment = nil
	end
end

local function applyConfiguredSpeed()
	local humanoid = getHumanoid()
	local speed = tonumber(player:GetAttribute("ArcadaConfiguredSpeed"))
	if humanoid and speed and speed >= 0 and humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end
end

local function updateFieldDecos(enabled: boolean)
	if enabled then
		local folder = workspace:FindFirstChild("FieldDecos")
		if not folder then
			return
		end
		if fieldDecoFolder == folder and fieldDecoConnection then
			return
		end
		if fieldDecoConnection then
			fieldDecoConnection:Disconnect()
			fieldDecoConnection = nil
		end
		fieldDecoFolder = folder
		local function applyPart(descendant: Instance)
			if not descendant:IsA("BasePart") then
				return
			end
			if not fieldDecoState[descendant] then
				fieldDecoState[descendant] = {
					Transparency = descendant.Transparency,
					CanCollide = descendant.CanCollide,
				}
			end
			descendant.Transparency = 0.5
			descendant.CanCollide = false
		end
		for _, descendant in ipairs(folder:GetDescendants()) do
			applyPart(descendant)
		end
		fieldDecoConnection = folder.DescendantAdded:Connect(applyPart)
		return
	end
	if fieldDecoConnection then
		fieldDecoConnection:Disconnect()
		fieldDecoConnection = nil
	end
	fieldDecoFolder = nil
	for part, state in pairs(fieldDecoState) do
		if part.Parent then
			part.Transparency = state.Transparency
			part.CanCollide = state.CanCollide
		end
		fieldDecoState[part] = nil
	end
end
local speedGuard = false
local function bindSpeedLock(humanoid: Humanoid?)
	disconnectAll(characterConnections)
	disconnectAll(bubbleConnections)
	disconnectAll(petalConnections)
	bubbleFolder = nil
	petalFolder = nil
	table.clear(bubbleCandidates)
	table.clear(petalCandidates)
	humanoid = humanoid or getHumanoid()
	if not humanoid then
		return
	end
	table.insert(
		characterConnections,
		humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			if not speedGuard then
				speedGuard = true
				applyConfiguredSpeed()
				speedGuard = false
			end
		end)
	)
	local lastHealth = humanoid.Health
	table.insert(
		characterConnections,
		humanoid.HealthChanged:Connect(function(health)
			if health < lastHealth then
				lastDamageAt = os.clock()
			end
			lastHealth = health
		end)
	)
	applyConfiguredSpeed()
end

local function cancelCurrentAction()
	actionId += 1
	cancelMovement()
	currentToken = nil
	currentBubble = nil
	farmTargetPreference = nil
end
setFarmingState = function(newState: string)
	if FarmingState.Mode ~= newState then
		FarmingState.Mode = newState
	end
end

local function syncSettings()
	local oldAutoFarm, oldSprouts, oldPuffs =
		FarmingState.AutoFarm, FarmingState.AutoSprouts, FarmingState.AutoPuffshrooms
	local oldMondo, oldWindy, oldVicious, oldStump =
		FarmingState.FarmMondo, FarmingState.FarmWindyBee, FarmingState.FarmViciousBee, FarmingState.FarmStumpSnail
	FarmingState.AutoFarm = player:GetAttribute("ArcadaAutoFarm") == true
	FarmingState.AutoDig = player:GetAttribute("ArcadaAutoDig") == true
	FarmingState.AutoSprinkler = player:GetAttribute("ArcadaAutoSprinkler") == true
	FarmingState.ESCTokens = player:GetAttribute("ArcadaESCTokens") == true
	FarmingState.AutoSprouts = player:GetAttribute("ArcadaAutoSprouts") == true
	FarmingState.AntiAFK = player:GetAttribute("ArcadaAntiAFK") == true
	FarmingState.PriorityTokens = player:GetAttribute("ArcadaPriorityTokensEnabled") ~= false
	FarmingState.FarmBubbles = player:GetAttribute("ArcadaFarmBubbles") == true
	FarmingState.FarmPetals = player:GetAttribute("ArcadaFarmPetals") == true
	FarmingState.ShiftLock = player:GetAttribute("ArcadaShiftLock") == true
	FarmingState.WealthClock = player:GetAttribute("ArcadaWealthClock") == true
	FarmingState.AutoPuffshrooms = player:GetAttribute("ArcadaAutoPuffshrooms") == true
	FarmingState.PuffCollectLoot = player:GetAttribute("ArcadaPuffCollectLoot") ~= false
	FarmingState.PuffPreferRarity = player:GetAttribute("ArcadaPuffPreferRarity") ~= false
	FarmingState.PuffMinLevel = math.clamp(math.floor(tonumber(player:GetAttribute("ArcadaPuffMinLevel")) or 1), 1, 30)
	FarmingState.PuffMinRarity = tostring(player:GetAttribute("ArcadaPuffMinRarity") or "Common")
	FarmingState.PuffLootSeconds =
		math.clamp(math.floor(tonumber(player:GetAttribute("ArcadaPuffLootSeconds")) or 12), 0, 30)
	FarmingState.PuffFields = tostring(player:GetAttribute("ArcadaPuffFields") or "All")
	FarmingState.FarmMondo = player:GetAttribute("ArcadaFarmMondo") == true
	FarmingState.CollectMondoTokens = player:GetAttribute("ArcadaCollectMondoTokens") == true
	FarmingState.FarmWindyBee = player:GetAttribute("ArcadaFarmWindyBee") == true
	FarmingState.FarmViciousBee = player:GetAttribute("ArcadaFarmViciousBee") == true
	FarmingState.FarmStumpSnail = player:GetAttribute("ArcadaFarmStumpSnail") == true
	FarmingState.ConvertPercent = math.clamp(tonumber(player:GetAttribute("ArcadaConvertPercent")) or 100, 1, 100)
	FarmingState.ConvertMinutes = math.clamp(tonumber(player:GetAttribute("ArcadaConvertMinutes")) or 20, 1, 120)
	FarmingState.ConvertBalloons = player:GetAttribute("ArcadaConvertBalloons") ~= false
	FarmingState.AutoHoneyMask = player:GetAttribute("ArcadaAutoHoneyMask") == true
	FarmingState.AutoHive = player:GetAttribute("ArcadaAutoHive") ~= false
	FarmingState.HiveSlot = math.clamp(math.floor(tonumber(player:GetAttribute("ArcadaHiveSlot")) or 4), 1, 6)
	local selectedMask = player:GetAttribute("ArcadaSelectedMask")
	FarmingState.SelectedMask = if selectedMask == "Demon Mask" or selectedMask == "Gummy Mask"
		then selectedMask
		else "Diamond Mask"
	FarmingState.SelectedField = player:GetAttribute("ArcadaSelectedField")
	applyShiftLockMode()
	if (oldAutoFarm and not FarmingState.AutoFarm) or (oldSprouts and not FarmingState.AutoSprouts) then
		cancelCurrentAction()
	end
	if oldPuffs and not FarmingState.AutoPuffshrooms then
		puffContext = nil
		cancelCurrentAction()
	end
	if
		(oldMondo and not FarmingState.FarmMondo)
		or (oldWindy and not FarmingState.FarmWindyBee)
		or (oldVicious and not FarmingState.FarmViciousBee)
		or (oldStump and not FarmingState.FarmStumpSnail)
	then
		bossContext = nil
		setBossHover(nil)
		cancelCurrentAction()
	end
end

walkTo = function(position: Vector3): boolean
	local humanoid = getHumanoid()
	local root = getRootPart()
	if not humanoid or not root or humanoid.Health <= 0 then
		return false
	end
	if root.Anchored then
		root.Anchored = false
	end
	humanoid.AutoRotate = true
	humanoid:MoveTo(position)
	return true
end

local function resetFieldNavigation()
	outsideFieldSince = nil
	fieldEnteredAt = nil
	fieldCapacityCheckField = nil
	lastFarmPosition = nil
	lastFarmProgressAt = os.clock()
	roamTarget = nil
	currentToken = nil
	currentBubble = nil
	farmTargetPreference = nil
end

local function recoverFromFarmStall(field: BasePart, root: BasePart)
	local now = os.clock()
	if not lastFarmPosition or (root.Position - lastFarmPosition).Magnitude >= 1 then
		lastFarmPosition = root.Position
		lastFarmProgressAt = now
		return
	end
	if now - lastFarmProgressAt < Config.FarmStuckTimeout then
		return
	end
	root.Anchored = false
	if currentToken then
		markTokenAsPhantom(currentToken)
	end
	if currentBubble then
		recentlyVisitedTokens[currentBubble] = now + Config.PhantomTokenBlacklistTime
	end
	currentToken = nil
	currentBubble = nil
	farmTargetPreference = nil
	roamTarget = nil
	lastFarmPosition = root.Position
	lastFarmProgressAt = now
	local humanoid = getHumanoid()
	if humanoid then
		roamTarget = getRandomPointInsideField(field)
		roamTargetAt = now
		humanoid:MoveTo(roamTarget)
	end
end

local function runFarmingStateMachine()
	local hive = getOwnedHive()
	local justClaimedHive = false
	if FarmingState.AutoHive and not hive then
		setFarmingState("ClaimingHive")
		if not claimHive() then
			return
		end
		hive = getOwnedHive()
		if not hive then
			return
		end
		justClaimedHive = true
		skipPartialConversionUntilField = true
	end
	-- Invalidate conversion readiness before any optional boss/sprout state can
	-- return early. Every observed exit must earn a fresh two-second period in
	-- the configured field before its capacity is trusted again.
	if FarmingState.AutoFarm and not converting then
		local configuredField = getSelectedFieldPart()
		local configuredRoot = getRootPart()
		if
			configuredField
			and configuredRoot
			and not isPositionInsideField(configuredRoot.Position, configuredField, 0)
		then
			fieldEnteredAt = nil
			fieldCapacityCheckField = nil
		end
	end
	if runWealthClock() then
		return
	end
	if runPuffshroomStateMachine() then
		return
	end
	if runBossStateMachine() then
		return
	end
	if FarmingState.AutoSprouts then
		if runSproutStateMachine() then
			return
		end
	else
		sproutContext = nil
	end
	if not FarmingState.AutoFarm then
		if conversionHoneyMaskEquipped and FarmingState.AutoHoneyMask then
			equipMask(FarmingState.SelectedMask)
		end
		resetConversionState()
		resetFieldNavigation()
		setFarmingState("Idle")
		return
	end
	if not hive then
		setFarmingState("WaitingForHive")
		return
	end
	local pollen, capacity = getPollenAndCapacity()
	local currentRoot = getRootPart()
	local hivePosition = getHiveStandingPosition(hive)
	local atHive = currentRoot ~= nil and hivePosition ~= nil and (currentRoot.Position - hivePosition).Magnitude <= 8
	local selectedFieldBeforeConversion = getSelectedFieldPart()
	if
		not converting
		and not sproutContext
		and selectedFieldBeforeConversion
		and currentRoot
		and not atHive
		and not isPositionInsideField(currentRoot.Position, selectedFieldBeforeConversion, 0)
	then
		setFarmingState("ReturningToFieldBeforeConvertCheck")
		-- Leaving the field invalidates the old capacity grace period. Without
		-- this reset, a jump over the edge could reuse a stale fieldEnteredAt and
		-- accept the game's temporary low capacity as a full backpack.
		fieldEnteredAt = nil
		fieldCapacityCheckField = nil
		returnPlayerToField(selectedFieldBeforeConversion)
		outsideFieldSince = nil
		lastFarmPosition = nil
		return
	end
	if selectedFieldBeforeConversion and currentRoot and not atHive then
		if fieldCapacityCheckField ~= selectedFieldBeforeConversion then
			fieldCapacityCheckField = selectedFieldBeforeConversion
			fieldEnteredAt = os.clock()
		end
	end
	local honeyStatus = getHoneyMakingStatus()
	local honeyInteractionAvailable = honeyStatus == "make honey" or honeyStatus == "stop making honey"
	local shouldConvertAtHive = not justClaimedHive
		and not skipPartialConversionUntilField
		and atHive
		and honeyInteractionAvailable
		and (pollen > 0 or (FarmingState.ConvertBalloons and hasHiveBalloon()))
	local convertThreshold = capacity * (FarmingState.ConvertPercent / 100)
	local fieldCapacityCheckReady = fieldEnteredAt ~= nil and os.clock() - fieldEnteredAt >= 2
	local timedConvertDue = pollen > 0 and os.clock() - lastConversionCompletedAt >= FarmingState.ConvertMinutes * 60
	if
		not converting
		and (
			(fieldCapacityCheckReady and capacity > 0 and (pollen >= convertThreshold or timedConvertDue))
			or shouldConvertAtHive
		)
	then
		converting = true
		conversionStarted = false
		conversionClearSince = nil
		conversionAttemptAt = 0
		conversionStartPollen = nil
		conversionProgressObserved = false
		conversionHoneyMaskEquipped = false
		conversionFieldMaskRestored = false
		conversionStopRequested = false
		conversionLastProgressAt = os.clock()
		currentToken = nil
		currentBubble = nil
	end
	if converting then
		runHiveConversion(hive)
		return
	end
	local field = getSelectedFieldPart()
	if not field then
		setFarmingState("WaitingForField")
		return
	end
	local root = getRootPart()
	if not root then
		return
	end
	if not isPositionInsideField(root.Position, field, 0) then
		fieldEnteredAt = nil
		fieldCapacityCheckField = nil
		lastSprinklerField = nil
		outsideFieldSince = outsideFieldSince or os.clock()
		setFarmingState("OutsideFieldGrace")
		if skipPartialConversionUntilField or os.clock() - outsideFieldSince >= Config.OutsideFieldReturnDelay then
			setFarmingState("MovingToField")
			returnPlayerToField(field)
			outsideFieldSince = nil
			lastFarmPosition = nil
		end
		return
	end
	if fieldCapacityCheckField ~= field then
		fieldCapacityCheckField = field
		fieldEnteredAt = os.clock()
	else
		fieldEnteredAt = fieldEnteredAt or os.clock()
	end
	if os.clock() - fieldEnteredAt < 2 then
		setFarmingState("WaitingForFieldCapacityCheck")
		walkTo(getFieldCenterPosition(field))
		return
	end
	skipPartialConversionUntilField = false
	outsideFieldSince = nil
	-- Field setup always has priority, including when monsters are already
	-- present or the player spawned directly inside the selected field.
	if FarmingState.AutoSprinkler and lastSprinklerField ~= field.Name then
		local fieldCenter = getFieldCenterPosition(field)
		if (root.Position - fieldCenter).Magnitude > 5 then
			setFarmingState("MovingToFieldCenterForSprinkler")
			currentToken = nil
			currentBubble = nil
			roamTarget = nil
			moveCharacterSmoothly(CFrame.new(fieldCenter))
			return
		end
		setFarmingState("PlacingSprinkler")
		placeSprinkler(field)
		-- Never allow token, bubble or monster logic to run during the same
		-- tick as field setup. Farming begins only after placement succeeds.
		return
	end
	if hasMonsterInField(field) then
		monsterEncounterAt = monsterEncounterAt or os.clock()
		setFarmingState("AvoidingMonsters")
		local humanoid = getHumanoid()
		if humanoid then
			-- Keep travelling while jumping; stopping in place lets the character
			-- get pinned against the field edge.
			humanoid:MoveTo(getFieldCenterPosition(field))
		end
		local now = os.clock()
		local jumpWindowStarted = math.max(monsterEncounterAt, lastDamageAt)
		if now - jumpWindowStarted <= 5 and now - lastJump >= Config.MonsterJumpInterval then
			if humanoid then
				humanoid.Jump = true
			end
			lastJump = os.clock()
		end
		return
	end
	monsterEncounterAt = nil
	if runPetalFarm(field) then
		return
	end
	recoverFromFarmStall(field, root)
	setFarmingState("FarmingField")
	local targetFinishedThisTick = false
	local popStarNearby = FarmingState.FarmBubbles and isPopStarNearby()
	if popStarNearby then
		-- A nearby Pop Star makes bubbles the immediate top priority, even if a
		-- normal token was already selected.
		currentToken = nil
		farmTargetPreference = "Bubble"
	elseif currentBubble then
		farmTargetPreference = "Bubble"
	elseif currentToken then
		farmTargetPreference = "Token"
	elseif farmTargetPreference == nil then
		-- Outside Pop Star, bubbles stay enabled but intentionally have only a
		-- small background priority.
		farmTargetPreference = if FarmingState.FarmBubbles and math.random(1, 10) == 1 then "Bubble" else "Token"
	end
	local bubble = currentBubble
	local bubblePosition = bubble and bubble.Parent and getTokenPosition(bubble)
	if
		not bubblePosition
		or not isPositionInsideField(bubblePosition, field, 0)
		or (recentlyVisitedTokens[bubble] or 0) >= os.clock()
	then
		bubble = nil
		currentBubble = nil
	end
	if bubble and bubblePosition then
		local bubbleDistance = (root.Position - bubblePosition).Magnitude
		if bubbleDistance <= Config.TokenReachDistance then
			recentlyVisitedTokens[bubble] = os.clock() + Config.TokenBlacklistTime
			bubble = nil
			currentBubble = nil
			farmTargetPreference = nil
			targetFinishedThisTick = true
		elseif os.clock() - currentBubbleStarted >= Config.TokenPursuitTimeout then
			recentlyVisitedTokens[bubble] = os.clock() + Config.PhantomTokenBlacklistTime
			bubble = nil
			currentBubble = nil
			farmTargetPreference = nil
			targetFinishedThisTick = true
		end
	end
	if not bubble and farmTargetPreference == "Bubble" then
		bubble = chooseNearestBubble(field)
		if bubble then
			currentBubble = bubble
			currentBubbleStarted = os.clock()
			bubblePosition = getTokenPosition(bubble)
		else
			farmTargetPreference = "Token"
		end
	end
	if bubble and bubblePosition then
		setFarmingState("FarmingBubble")
		walkTo(getFieldLandingPosition(field, bubblePosition))
		return
	end
	local token = currentToken
	local pos = token and token.Parent and getTokenPosition(token)
	if not pos or not isPositionInsideField(pos, field, 0) or (recentlyVisitedTokens[token] or 0) >= os.clock() then
		token = nil
		currentToken = nil
	end
	if token and pos then
		local distance = (root.Position - pos).Magnitude
		currentTokenClosest = math.min(currentTokenClosest, distance)
		if distance <= Config.TokenReachDistance then
			recentlyVisitedTokens[token] = os.clock() + Config.TokenBlacklistTime
			currentToken = nil
			token = nil
			farmTargetPreference = nil
			targetFinishedThisTick = true
		elseif
			currentTokenClosest <= Config.TokenReachDistance
			and os.clock() - currentTokenStarted > Config.PhantomTokenTimeout
		then
			markTokenAsPhantom(token)
			currentToken = nil
			token = nil
			farmTargetPreference = nil
			targetFinishedThisTick = true
		elseif os.clock() - currentTokenStarted >= Config.TokenPursuitTimeout then
			markTokenAsPhantom(token)
			currentToken = nil
			token = nil
			farmTargetPreference = nil
			targetFinishedThisTick = true
		end
	end
	if not token and not targetFinishedThisTick then
		token = chooseNextToken(field, nil, nil)
		if token then
			currentToken = token
			farmTargetPreference = "Token"
			currentTokenStarted = os.clock()
			currentTokenClosest = math.huge
			pos = getTokenPosition(token)
		end
	end
	if not token then
		farmTargetPreference = nil
	end
	if token and pos then
		walkTo(getFieldLandingPosition(field, pos))
	else
		if
			not roamTarget
			or os.clock() - roamTargetAt >= Config.RoamInterval
			or (root.Position - roamTarget).Magnitude <= 4
		then
			roamTarget = getRandomPointInsideField(field)
			roamTargetAt = os.clock()
		end
		walkTo(roamTarget)
	end
end

-- Keep late bootstrap locals in a separate function scope.
-- The main chunk is already at Luau's 200-local limit here.
(function()
	local function bindFolder(name: string)
		local folder = workspace:FindFirstChild(name)
		folders[name] = folder
		table.clear(cache[name])
		disconnectAll(folderConnections[name] or {})
		folderConnections[name] = {}
		if not folder then
			return
		end
		for _, child in ipairs(folder:GetChildren()) do
			cache[name][child] = true
		end
		table.insert(
			folderConnections[name],
			folder.ChildAdded:Connect(function(child)
				cache[name][child] = true
			end)
		)
		table.insert(
			folderConnections[name],
			folder.ChildRemoved:Connect(function(child)
				if name == "Sprouts" and sproutContext and sproutContext.Sprout == child and sproutContext.Engaged then
					sessionSproutsBroken += 1
				elseif name == "Monsters" then
					sessionMonstersKilled += 1
				elseif name == "Collectibles" and child.Name == "C" then
					local root, position = getRootPart(), getTokenPosition(child)
					-- Every collectible token is named C. A little replication margin
					-- keeps fast movement from missing tokens that disappear just after touch.
					if root and position and (root.Position - position).Magnitude <= 15 then
						sessionTokensCollected += 1
					end
				end
				publishSessionStats()
				cache[name][child] = nil
				phantomTokens[child] = nil
				removeTokenESP(child)
			end)
		)
	end
	for _, name in ipairs({ "FlowerZones", "Collectibles", "Monsters", "Sprouts", "HivePlatforms", "Honeycombs" }) do
		bindFolder(name)
	end

	table.insert(
		connections,
		workspace.ChildAdded:Connect(function(child)
			if cache[child.Name] then
				bindFolder(child.Name)
			end
		end)
	)
	table.insert(
		connections,
		workspace.ChildRemoved:Connect(function(child)
			if folders[child.Name] == child then
				bindFolder(child.Name)
			end
		end)
	)
	table.insert(
		connections,
		player.CharacterAdded:Connect(function(character)
			cancelCurrentAction()
			local humanoid = character:WaitForChild("Humanoid", 10)
			bindSpeedLock(if humanoid and humanoid:IsA("Humanoid") then humanoid else nil)
		end)
	)
	table.insert(connections, player.Idled:Connect(preventIdleKick))
	bindSpeedLock()

	for _, attributeName in ipairs({
		"ArcadaAutoFarm",
		"ArcadaAutoDig",
		"ArcadaAutoSprinkler",
		"ArcadaAutoSprouts",
		"ArcadaESCTokens",
		"ArcadaPriorityTokensEnabled",
		"ArcadaFarmBubbles",
		"ArcadaFarmPetals",
		"ArcadaShiftLock",
		"ArcadaWealthClock",
		"ArcadaAutoPuffshrooms",
		"ArcadaPuffCollectLoot",
		"ArcadaPuffPreferRarity",
		"ArcadaPuffMinLevel",
		"ArcadaPuffMinRarity",
		"ArcadaPuffLootSeconds",
		"ArcadaPuffFields",
		"ArcadaFarmMondo",
		"ArcadaCollectMondoTokens",
		"ArcadaFarmWindyBee",
		"ArcadaFarmViciousBee",
		"ArcadaFarmStumpSnail",
		"ArcadaConvertPercent",
		"ArcadaConvertMinutes",
		"ArcadaSelectedMask",
		"ArcadaAutoHoneyMask",
		"ArcadaConvertBalloons",
		"ArcadaHiveSlot",
		"ArcadaAutoHive",
		"ArcadaAntiAFK",
		"ArcadaSelectedField",
		"ArcadaConfiguredSpeed",
	}) do
		table.insert(
			connections,
			player:GetAttributeChangedSignal(attributeName):Connect(function()
				syncSettings()
				if attributeName == "ArcadaConfiguredSpeed" then
					applyConfiguredSpeed()
				end
			end)
		)
	end

	syncSettings()

	local function updateSessionStatsSnapshot()
		local pollen = getPollenAndCapacity()
		sessionMaxPollen = math.max(sessionMaxPollen, pollen)
		sessionMaxBalloonPollen = math.max(sessionMaxBalloonPollen, getHiveBalloonAmount())
		for _, descendant in ipairs(player:GetDescendants()) do
			if descendant:IsA("ValueBase") and normalizeStatName(descendant.Name) == "balloonblessing" then
				sessionMaxBalloonBlessing =
					math.max(sessionMaxBalloonBlessing, tonumber((descendant :: any).Value) or 0)
			end
		end
		local playerStats = retrievePlayerStats()
		local numbers = collectNamedNumbers(playerStats, {
			balloonpollen = true,
			hiveballoonpollen = true,
			balloonamount = true,
			balloonblessing = true,
			serveruptime = true,
			serverage = true,
			serverstarttime = true,
			serverstartedat = true,
		})
		sessionMaxBalloonPollen =
			math.max(sessionMaxBalloonPollen, numbers.balloonpollen, numbers.hiveballoonpollen, numbers.balloonamount)
		sessionMaxBalloonBlessing = math.max(sessionMaxBalloonBlessing, numbers.balloonblessing)
		local serverUptime = math.max(numbers.serveruptime, numbers.serverage)
		local serverStartedAt = math.max(numbers.serverstarttime, numbers.serverstartedat)
		if serverStartedAt > 1000000000 then
			serverUptime = math.max(serverUptime, workspace:GetServerTimeNow() - serverStartedAt)
		end
		if serverUptime > 0 then
			publishAttribute("ArcadaServerUptime", math.floor(serverUptime))
		end
		publishSessionStats()
	end

	task.spawn(function()
		while runtimeEnvironment.__ARCADA_FARMING_RUNTIME_TOKEN == runtimeToken do
			updateSessionStatsSnapshot()
			task.wait(Config.SessionStatsInterval)
		end
	end)

	task.spawn(function()
		while runtimeEnvironment.__ARCADA_FARMING_RUNTIME_TOKEN == runtimeToken do
			if FarmingState.AutoDig then
				activateDigTool()
			end
			if
				FarmingState.AntiAFK
				and (FarmingState.AutoFarm or FarmingState.AutoDig or FarmingState.AutoSprouts)
				and os.clock() - lastKeepAlive >= Config.KeepAliveInterval
			then
				lastKeepAlive = os.clock()
				local keepAliveEvent = events and events:FindFirstChild("FarmingKeepAlive")
				if keepAliveEvent then
					clientCall("FarmingKeepAlive", true)
				end
			end
			local success, message = xpcall(runFarmingStateMachine, debug.traceback)
			if not success then
				cancelMovement()
				setTransitPhysics(false)
				currentToken = nil
				roamTarget = nil
				throttledWarn("farm-loop", "Farming tick recovered from an error:", message)
			end
			task.wait(Config.FarmTick)
		end
	end)

	task.spawn(function()
		while runtimeEnvironment.__ARCADA_FARMING_RUNTIME_TOKEN == runtimeToken do
			updateFieldDecos(FarmingState.AutoFarm)
			task.wait(0.5)
		end
		updateFieldDecos(false)
	end)

	task.spawn(function()
		while runtimeEnvironment.__ARCADA_FARMING_RUNTIME_TOKEN == runtimeToken do
			if FarmingState.ESCTokens then
				local field = getSelectedFieldPart()
				if field then
					for token in pairs(cache.Collectibles) do
						if token.Parent and token.Name == "C" and isTokenInsideField(token, field) then
							updateTokenESP(token)
						else
							removeTokenESP(token)
						end
					end
				else
					clearAllTokenESP()
				end
			else
				clearAllTokenESP()
			end
			task.wait(Config.TokenESPUpdateInterval)
		end
	end)

	runtimeEnvironment.__ARCADA_FARMING_CLEANUP = function()
		if runtimeEnvironment.__ARCADA_FARMING_RUNTIME_TOKEN == runtimeToken then
			runtimeEnvironment.__ARCADA_FARMING_RUNTIME_TOKEN = nil
		end
		cancelCurrentAction()
		setBossHover(nil)
		updateFieldDecos(false)
		clearAllTokenESP()
		disconnectAll(connections)
		disconnectAll(characterConnections)
		disconnectAll(bubbleConnections)
		disconnectAll(petalConnections)
		if fieldDecoConnection then
			fieldDecoConnection:Disconnect()
			fieldDecoConnection = nil
		end
		for _, list in pairs(folderConnections) do
			disconnectAll(list)
		end
		if espFolder.Parent then
			espFolder:Destroy()
		end
	end
end)()

-- Returning a value lets this controller run both as a remotely compiled chunk
-- and as a regular ModuleScript when the project is mounted through Rojo.
return true
