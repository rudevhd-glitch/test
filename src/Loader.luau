local OWNER = "rudevhd-glitch"
local REPOSITORY = "testload"
local BRANCH = "main"

local url = ("https://raw.githubusercontent.com/%s/%s/%s/Client.luau?cache=%d"):format(
	OWNER,
	REPOSITORY,
	BRANCH,
	os.time()
)

local ok, source = pcall(function()
	return game:HttpGet(url)
end)
if not ok or type(source) ~= "string" or source == "" then
	error("Arcada Loader: failed to download Client.luau: " .. tostring(source), 0)
end

local compiler = loadstring or load
if type(compiler) ~= "function" then
	error("Arcada Loader: loadstring is unavailable", 0)
end

local chunk, compileError = compiler(source, "@Arcada/Client.luau")
if type(chunk) ~= "function" then
	error("Arcada Loader: Client.luau compile failed: " .. tostring(compileError), 0)
end

return chunk()
