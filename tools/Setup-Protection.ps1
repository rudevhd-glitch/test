$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$prometheusDirectory = Join-Path $projectRoot "tools\Prometheus"
$fengariDirectory = Join-Path $projectRoot "tools\fengari"

if (-not (Test-Path -LiteralPath $prometheusDirectory -PathType Container)) {
	git clone --depth 1 https://github.com/prometheus-lua/Prometheus.git $prometheusDirectory
	if ($LASTEXITCODE -ne 0) {
		throw "Failed to download Prometheus"
	}
}

npm install --prefix $fengariDirectory
if ($LASTEXITCODE -ne 0) {
	throw "Failed to install Fengari"
}

Write-Host "Protection tools are ready."
