param(
	[ValidateSet("Compatible", "Weak", "Medium")]
	[string]$Preset = "Compatible",
	[ValidateSet("ArcadaGuardSecurity", "Kaleidoscope", "None")]
	[string]$Encryption = "ArcadaGuardSecurity",
	[string]$MasterSeed = $env:ARCADA_MASTER_SEED,
	[string]$BuildId = (Get-Date -Format "yyyyMMdd-HHmmss"),
	[string]$NonceHex,
	[bool]$ProtectBootstrap = $true
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$sourceDirectory = Join-Path $projectRoot "src\client"
$outputDirectory = Join-Path $projectRoot "dist"
$prometheusDirectory = Join-Path $projectRoot "tools\Prometheus"
$fengari = Join-Path $projectRoot "tools\fengari\node_modules\.bin\fengari.cmd"
$runnerPath = Join-Path $prometheusDirectory ".arcada-protect.lua"
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot "Kaleidoscope-Encryption.ps1")

# Keep Kaleidoscope as a backwards-compatible command-line alias.
$arcadaGuardEnabled = $Encryption -in @("ArcadaGuardSecurity", "Kaleidoscope")

if ($arcadaGuardEnabled -and [string]::IsNullOrWhiteSpace($MasterSeed)) {
	$temporarySeed = [byte[]]::new(32)
	$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
	try { $rng.GetBytes($temporarySeed) } finally { $rng.Dispose() }
	$MasterSeed = [BitConverter]::ToString($temporarySeed) -replace '-', ''
	Write-Warning "ARCADA_MASTER_SEED is not set; this build uses an ephemeral master seed and cannot be reproduced."
}

$buildNonce = $null
if (-not [string]::IsNullOrWhiteSpace($NonceHex)) {
	if ($NonceHex -notmatch '^[0-9a-fA-F]{16,}$' -or ($NonceHex.Length % 2) -ne 0) {
		throw "NonceHex must be an even-length hexadecimal value containing at least 8 bytes"
	}
	$buildNonce = [byte[]]::new($NonceHex.Length / 2)
	for ($i = 0; $i -lt $buildNonce.Length; $i++) {
		$buildNonce[$i] = [Convert]::ToByte($NonceHex.Substring($i * 2, 2), 16)
	}
}
if ($arcadaGuardEnabled -and -not $buildNonce) {
	$buildNonce = [byte[]]::new(16)
	$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
	try { $rng.GetBytes($buildNonce) } finally { $rng.Dispose() }
}

if (-not (Test-Path -LiteralPath $fengari -PathType Leaf)) {
	throw "Fengari is missing. Run: npm install --prefix tools/fengari"
}
if (-not (Test-Path -LiteralPath (Join-Path $prometheusDirectory "src\prometheus.lua") -PathType Leaf)) {
	throw "Prometheus is missing from tools/Prometheus"
}

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
foreach ($legacyName in @("client.luau", "FarmingController.luau")) {
	$legacyPath = Join-Path $outputDirectory $legacyName
	if (Test-Path -LiteralPath $legacyPath) {
		Remove-Item -LiteralPath $legacyPath -Force
	}
}
$nativeLuauNames = @("FarmingController.luau", "MemoryMatch.luau")
$sourceFiles = Get-ChildItem -LiteralPath $sourceDirectory -File -Filter "*.luau" |
	Where-Object { $_.Name -notlike "*.client.luau" -and $_.Name -notin $nativeLuauNames } |
	Sort-Object Name
$luauClientFiles = Get-ChildItem -LiteralPath $sourceDirectory -File -Filter "*.luau" |
	Where-Object { $_.Name -like "*.client.luau" -or $_.Name -in $nativeLuauNames } |
	Sort-Object Name

try {
	foreach ($sourceFile in $sourceFiles) {
		$source = [System.IO.File]::ReadAllText($sourceFile.FullName)
		$fileBuildId = "$BuildId/$($sourceFile.Name)"
		$equals = ""
		while ($source.Contains("]" + $equals + "]")) {
			$equals += "="
		}
		$longStringOpen = "[" + $equals + "["
		$longStringClose = "]" + $equals + "]"
		$marker = "__ARCADA_PROTECTED_OUTPUT_" + [Guid]::NewGuid().ToString("N") + "__"
		if ($arcadaGuardEnabled) {
			$seedMaterial = New-RkvBuildSeed -MasterSeed $MasterSeed -BuildId $fileBuildId -Nonce $buildNonce
			$seed = [int](([uint64](Get-RkvUInt32 -Bytes $seedMaterial -Offset 20) % 2147483645) + 1)
		} else {
			$seed = Get-Random -Minimum 1 -Maximum 2147483646
		}
		$fileName = $sourceFile.Name.Replace("\", "\\").Replace('"', '\"')

		$runner = @"
package.path = "./src/?.lua;./src/?/init.lua;" .. package.path
math.log10 = math.log10 or function(value) return math.log(value) / math.log(10) end
local Prometheus = require("prometheus")
Prometheus.colors.enabled = false
local config
if "$Preset" == "Compatible" then
	config = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{
				Name = "ConstantArray",
				Settings = {
					Threshold = 1,
					StringsOnly = true,
					Shuffle = true,
					Rotate = true,
					LocalWrapperThreshold = 0,
				},
			},
			{ Name = "NumbersToExpressions", Settings = {} },
			{ Name = "WrapInFunction", Settings = {} },
		},
	}
else
	config = Prometheus.Presets["$Preset"]
end
config.LuaVersion = "Lua51"
config.PrettyPrint = false
config.Seed = $seed
for _, step in ipairs(config.Steps or {}) do
	if step.Name == "NumbersToExpressions" then
		step.Settings.NumberRepresentationMutation = false
	end
end
local source = $longStringOpen
$source
$longStringClose
local pipeline = Prometheus.Pipeline:fromConfig(config)
local output = pipeline:apply(source, "$fileName")
print("$marker")
print(output)
"@

		[System.IO.File]::WriteAllText($runnerPath, $runner, $utf8WithoutBom)
		Push-Location $prometheusDirectory
		try {
			$outputLines = @(& $fengari ".arcada-protect.lua" 2>&1 | ForEach-Object { $_.ToString() })
			$exitCode = $LASTEXITCODE
		} finally {
			Pop-Location
		}

		if ($exitCode -ne 0) {
			throw "Prometheus failed for $($sourceFile.Name): $($outputLines -join [Environment]::NewLine)"
		}
		$markerIndex = [Array]::IndexOf([object[]]$outputLines, $marker)
		if ($markerIndex -lt 0 -or $markerIndex + 1 -ge $outputLines.Count) {
			throw "Prometheus returned no protected output for $($sourceFile.Name)"
		}

		$protectedSource = $outputLines[($markerIndex + 1)..($outputLines.Count - 1)] -join [Environment]::NewLine
		if ($arcadaGuardEnabled) {
			$rkvArguments = @{ Source = $protectedSource; MasterSeed = $MasterSeed; BuildId = $fileBuildId }
			$rkvArguments.Nonce = $buildNonce
			$protectedSource = Protect-RkvPayload @rkvArguments
		}
		$outputPath = Join-Path $outputDirectory $sourceFile.Name
		[System.IO.File]::WriteAllText($outputPath, $protectedSource, $utf8WithoutBom)
		Write-Host ("Protected {0} -> dist/{0} ({1:N0} bytes)" -f $sourceFile.Name, $protectedSource.Length)
	}

	foreach ($sourceFile in $luauClientFiles) {
		$source = [System.IO.File]::ReadAllText($sourceFile.FullName)
		$outputName = if ($sourceFile.Name -eq "init.client.luau") {
			"Client.luau"
		} elseif ($sourceFile.Name -eq "FarmingController.luau") {
			"Farming.luau"
		} else {
			$sourceFile.Name
		}
		$fileBuildId = "$BuildId/$outputName"
		$protectedSource = $source
		if ($arcadaGuardEnabled -and ($sourceFile.Name -ne "init.client.luau" -or $ProtectBootstrap)) {
			$rkvArguments = @{ Source = $source; MasterSeed = $MasterSeed; BuildId = $fileBuildId; Nonce = $buildNonce }
			# Native Luau files execute directly on the client. Full-size decoy
			# payloads multiply parsing cost and can freeze low-end clients; the real
			# payload remains encrypted and integrity checked without those copies.
			$rkvArguments.DecoyCount = 0
			if ($sourceFile.Name -eq "init.client.luau") {
				# The bootstrap is encrypted too, but uses a compact hexadecimal
				# container so executor parsers do not receive a multi-megabyte table.
				$rkvArguments.Compact = $true
			}
			$protectedSource = Protect-RkvPayload @rkvArguments
		}
		$outputPath = Join-Path $outputDirectory $outputName
		[System.IO.File]::WriteAllText($outputPath, $protectedSource, $utf8WithoutBom)
		Write-Host ("Protected {0} -> dist/{1} ({2:N0} bytes, native Luau)" -f $sourceFile.Name, $outputName, $protectedSource.Length)
	}

	$loaderPath = Join-Path $projectRoot "src\Loader.luau"
	if (Test-Path -LiteralPath $loaderPath -PathType Leaf) {
		$loaderSource = [System.IO.File]::ReadAllText($loaderPath)
		$loaderOutput = $loaderSource
		if ($arcadaGuardEnabled) {
			$loaderOutput = Protect-RkvPayload `
				-Source $loaderSource `
				-MasterSeed $MasterSeed `
				-BuildId "$BuildId/Loader.luau" `
				-Nonce $buildNonce `
				-DecoyCount 0 `
				-Compact
		}
		[System.IO.File]::WriteAllText(
			(Join-Path $outputDirectory "Loader.luau"),
			$loaderOutput,
			$utf8WithoutBom
		)
		Write-Host ("Protected Loader.luau -> dist/Loader.luau ({0:N0} bytes, compact bootstrap)" -f $loaderOutput.Length)
	}
} finally {
	if (Test-Path -LiteralPath $runnerPath) {
		Remove-Item -LiteralPath $runnerPath -Force
	}
}
