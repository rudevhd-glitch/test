local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local environment = if type(getgenv) == "function" then getgenv() else shared
if type(environment) ~= "table" then environment = _G end
if type(environment.__ARCADA_MEMORY_CLEANUP) == "function" then
	pcall(environment.__ARCADA_MEMORY_CLEANUP)
end

local token = {}
environment.__ARCADA_MEMORY_TOKEN = token
local connections = {}
local revealed = {}
local matched = {}
local currentTurn = {}
local pending = {}
local currentGameType = "Basic"
local maxTiles = 16
local active = false

local gameSizes = {
	Basic = 16,
	BadgeGuild = 16,
	Night = 16,
	["35Zone"] = 20,
}

local events = ReplicatedStorage:WaitForChild("Events", 10)
local memoryEvent = events and events:WaitForChild("MemoryMatchEvent", 10)
local toyNames = {
	Basic = "Memory Match",
	BadgeGuild = "Mega Memory Match",
	Night = "Night Memory Match",
	["35Zone"] = "Extreme Memory Match",
}

local function fire(packet)
	if not memoryEvent then return false end
	if memoryEvent:IsA("RemoteEvent") then
		return pcall(memoryEvent.FireServer, memoryEvent, packet)
	elseif memoryEvent:IsA("RemoteFunction") then
		return pcall(memoryEvent.InvokeServer, memoryEvent, packet)
	end
	return false
end

local function getMemoryFrame()
	local screenGui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("ScreenGui")
	local layer = screenGui and screenGui:FindFirstChild("MinigameLayer")
	return layer and layer:FindFirstChild("MemoryMatchFrame")
end

local function getTiles()
	local frame = getMemoryFrame()
	local grid = frame and frame:FindFirstChild("GuiGrid", true)
	local tiles = {}
	if not grid then return tiles end
	for _, child in ipairs(grid:GetChildren()) do
		if child:IsA("GuiObject") then table.insert(tiles, child) end
	end
	table.sort(tiles, function(a, b)
		if a.LayoutOrder == b.LayoutOrder then return a.Name < b.Name end
		return a.LayoutOrder < b.LayoutOrder
	end)
	return tiles
end

local function clearOverlays()
	local gui = player:FindFirstChild("PlayerGui")
	if not gui then return end
	for _, object in ipairs(gui:GetDescendants()) do
		if object.Name == "ArcadaMemoryReveal" then object:Destroy() end
	end
end

local function updateOverlay(index)
	if player:GetAttribute("ArcadaShowMemoryImages") ~= true then return end
	local tiles = getTiles()
	local tile = tiles[index]
	if not tile then return end
	local sourceImage = tile:FindFirstChild("ObjImage", true)
	if not sourceImage or not sourceImage:IsA("ImageLabel") or sourceImage.Image == "" then return end
	local overlay = tile:FindFirstChild("ArcadaMemoryReveal")
	if not overlay then
		overlay = Instance.new("ImageLabel")
		overlay.Name = "ArcadaMemoryReveal"
		overlay.BackgroundColor3 = Color3.fromRGB(35, 39, 47)
		overlay.BackgroundTransparency = 0.08
		overlay.BorderSizePixel = 0
		overlay.Position = UDim2.fromScale(0.08, 0.08)
		overlay.Size = UDim2.fromScale(0.84, 0.84)
		overlay.ScaleType = Enum.ScaleType.Fit
		overlay.ZIndex = 100
		overlay.Parent = tile
	end
	overlay.Image = sourceImage.Image
end

local function refreshOverlays()
	if player:GetAttribute("ArcadaShowMemoryImages") ~= true then
		clearOverlays()
		return
	end
	for index in pairs(revealed) do updateOverlay(index) end
end

local function selectTile(index)
	if not active or pending[index] or matched[index] then return false end
	pending[index] = true
	return fire({ Action = "SelectTile", TileIndex = index })
end

local function findKnownPair(excluded)
	local byType = {}
	for index, tileType in pairs(revealed) do
		if not matched[index] and index ~= excluded and not pending[index] then
			byType[tileType] = byType[tileType] or {}
			table.insert(byType[tileType], index)
		end
	end
	for _, indexes in pairs(byType) do
		if #indexes >= 2 then return indexes[1], indexes[2] end
	end
	return nil
end

local function nextUnknown()
	for index = 1, maxTiles do
		if not revealed[index] and not pending[index] and not matched[index] then return index end
	end
	return nil
end

local function continueAuto()
	if not active or player:GetAttribute("ArcadaAutoMemoryMatch") ~= true then return end
	if #currentTurn == 0 then
		local first, second = findKnownPair(nil)
		if first then
			selectTile(first)
			task.delay(0.65, function() selectTile(second) end)
			return
		end
		local unknown = nextUnknown()
		if unknown then selectTile(unknown) end
	elseif #currentTurn == 1 then
		local first = currentTurn[1]
		local wantedType = revealed[first]
		if wantedType then
			for index, tileType in pairs(revealed) do
				if index ~= first and tileType == wantedType and not matched[index] and not pending[index] then
					selectTile(index)
					return
				end
			end
		end
		local unknown = nextUnknown()
		if unknown then selectTile(unknown) end
	end
end

local function resetGame(gameType)
	table.clear(revealed)
	table.clear(matched)
	table.clear(currentTurn)
	table.clear(pending)
	clearOverlays()
	currentGameType = gameType or "Basic"
	maxTiles = gameSizes[currentGameType] or 16
	active = true
end

local function startGame(gameType)
	resetGame(gameType)
	local toys = workspace:FindFirstChild("Toys")
	local toy = toys and toys:FindFirstChild(toyNames[currentGameType])
	local platform = toy and toy:FindFirstChild("Platform", true)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if platform and platform:IsA("BasePart") and root and root:IsA("BasePart") then
		local landingHeight = platform.Size.Y / 2 + root.Size.Y / 2 + 2
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.CFrame = platform.CFrame * CFrame.new(0, landingHeight, 0)
		root.Anchored = true
		local touch = environment.firetouchinterest
		if type(touch) == "function" then
			pcall(touch, root, platform, 0)
			pcall(touch, root, platform, 1)
		end
		local prompt = toy:FindFirstChildWhichIsA("ProximityPrompt", true)
		local firePrompt = environment.fireproximityprompt
		if prompt and type(firePrompt) == "function" then pcall(firePrompt, prompt) end
		task.delay(1.25, function()
			if root.Parent and root.Anchored then
				root.AssemblyLinearVelocity = Vector3.zero
				root.Anchored = false
			end
		end)
	end
	task.delay(0.35, function()
		fire({ Action = "Start", GameType = currentGameType })
		task.delay(1, continueAuto)
	end)
end

if memoryEvent and memoryEvent:IsA("RemoteEvent") then
	table.insert(connections, memoryEvent.OnClientEvent:Connect(function(packet)
		if type(packet) ~= "table" then return end
		if packet.Action == "RevealTile" and type(packet.TileIndex) == "number" then
			local index = packet.TileIndex
			pending[index] = nil
			if type(packet.TileType) == "string" then revealed[index] = packet.TileType end
			table.insert(currentTurn, index)
			task.delay(0.15, function() updateOverlay(index) end)
			if #currentTurn >= 2 then
				local first, second = currentTurn[1], currentTurn[2]
				if revealed[first] and revealed[first] == revealed[second] then
					matched[first], matched[second] = true, true
				end
				table.clear(currentTurn)
				task.delay(0.8, continueAuto)
			else
				task.delay(0.35, continueAuto)
			end
		end
	end))
end

table.insert(connections, player:GetAttributeChangedSignal("ArcadaMemoryStartRequest"):Connect(function()
	local request = tostring(player:GetAttribute("ArcadaMemoryStartRequest") or "")
	local gameType = request:match("^([^:]+)")
	if gameType and gameSizes[gameType] then startGame(gameType) end
end))
table.insert(connections, player:GetAttributeChangedSignal("ArcadaShowMemoryImages"):Connect(refreshOverlays))

task.spawn(function()
	local previousFrame = nil
	while environment.__ARCADA_MEMORY_TOKEN == token do
		local frame = getMemoryFrame()
		if frame and frame ~= previousFrame then
			previousFrame = frame
			if not active then resetGame(currentGameType) end
			task.delay(0.8, continueAuto)
		elseif not frame then
			previousFrame = nil
		end
		task.wait(0.5)
	end
end)

environment.__ARCADA_MEMORY_CLEANUP = function()
	if environment.__ARCADA_MEMORY_TOKEN == token then environment.__ARCADA_MEMORY_TOKEN = nil end
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
	clearOverlays()
end

return true
