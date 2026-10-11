param(
    [string]$Python = "python",
    [switch]$Dev
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$venvPython = Join-Path $projectRoot ".venv\Scripts\python.exe"

if (-not (Test-Path -LiteralPath $venvPython)) {
    & $Python -m venv (Join-Path $projectRoot ".venv")
    if ($LASTEXITCODE -ne 0) { throw "Could not create the Python environment." }
}

$requirements = if ($Dev) { "requirements-dev.txt" } else { "requirements.txt" }
& $venvPython -m pip install --disable-pip-version-check -r (Join-Path $projectRoot $requirements)
if ($LASTEXITCODE -ne 0) { throw "Dependency installation failed." }

Write-Host "Windows agent environment is ready: $venvPython"
