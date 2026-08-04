param(
  [string]$ProjectDir = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
  [string]$RscriptExe = $env:YU_RSCRIPT,
  [string]$PythonExe = $env:YU_PYTHON,
  [string]$CondaExe = $env:YU_CONDA,
  [string]$EnvironmentName = "yu_proteomic_repo_py39"
)

$ErrorActionPreference = "Stop"

function Find-Executable {
  param([string]$Explicit, [string[]]$Preferred, [string[]]$Commands, [string]$Label)
  if ($Explicit) {
    if (-not (Test-Path $Explicit -PathType Leaf)) { throw "$Label override not found: $Explicit" }
    return (Resolve-Path $Explicit).Path
  }
  foreach ($path in $Preferred) {
    if ($path -and (Test-Path $path -PathType Leaf)) { return (Resolve-Path $path).Path }
  }
  foreach ($command in $Commands) {
    $resolved = Get-Command $command -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($resolved) { return $resolved.Source }
  }
  return $null
}

$rscript = Find-Executable $RscriptExe @(
  "C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe",
  "C:/Program Files/R/R-4.3.2/bin/x64/Rscript.exe"
) @("Rscript.exe", "Rscript") "Rscript"
if (-not $rscript) { throw "Rscript was not found. Install R >=4.3 or supply -RscriptExe." }

$preferredConda = @()
if ($env:USERPROFILE) {
  $preferredConda += Join-Path $env:USERPROFILE "anaconda3/Scripts/conda.exe"
  $preferredConda += Join-Path $env:USERPROFILE "miniconda3/Scripts/conda.exe"
}
$preferredConda += @("C:/ProgramData/anaconda3/Scripts/conda.exe", "C:/ProgramData/miniconda3/Scripts/conda.exe")
$conda = Find-Executable $CondaExe $preferredConda @("conda.exe", "conda") "Conda"

$preferredPython = @()
if ($env:USERPROFILE) {
  $preferredPython += Join-Path $env:USERPROFILE "anaconda3/envs/$EnvironmentName/python.exe"
  $preferredPython += Join-Path $env:USERPROFILE "miniconda3/envs/$EnvironmentName/python.exe"
}
$preferredPython += @(
  "C:/ProgramData/anaconda3/envs/$EnvironmentName/python.exe",
  "C:/ProgramData/miniconda3/envs/$EnvironmentName/python.exe"
)
$python = Find-Executable $PythonExe $preferredPython @() "Python"

if (-not $python) {
  if (-not $conda) {
    throw "The frozen Python 3.9 environment is absent and Conda was not found. Install Miniconda or supply -CondaExe."
  }
  $setup = Join-Path $ProjectDir "f/tools/setup_yu_reproduction_python_windows.ps1"
  & $setup -CondaExe $conda -EnvironmentName $EnvironmentName
  if ($LASTEXITCODE -ne 0) { throw "Frozen Python environment setup failed." }
  $condaRoot = Split-Path -Parent (Split-Path -Parent $conda)
  $python = Join-Path $condaRoot "envs/$EnvironmentName/python.exe"
}

$requirements = Join-Path $ProjectDir "f/config/requirements-py39.txt"
& $python -m pip install --disable-pip-version-check --no-input -r $requirements
if ($LASTEXITCODE -ne 0) { throw "Python dependency installation failed." }

$manifestDir = Join-Path $ProjectDir "dist/dependency_manifests"
New-Item -ItemType Directory -Force -Path $manifestDir | Out-Null
$rInstaller = Join-Path $ProjectDir "f/tools/install_yu_r_dependencies.R"
$rManifest = Join-Path $manifestDir "r_dependencies.txt"
& $rscript --vanilla $rInstaller $ProjectDir $rManifest
if ($LASTEXITCODE -ne 0) { throw "R dependency installation failed." }

$pythonManifest = Join-Path $manifestDir "python_environment.json"
$code = "import json,sys,lightgbm,sklearn,pandas,numpy,scipy; print(json.dumps(dict(python='.'.join(map(str,sys.version_info[:3])),lightgbm=lightgbm.__version__,sklearn=sklearn.__version__,pandas=pandas.__version__,numpy=numpy.__version__,scipy=scipy.__version__),indent=2))"
& $python -c $code | Set-Content -Encoding UTF8 $pythonManifest
if ($LASTEXITCODE -ne 0) { throw "Python dependency validation failed." }

Write-Host "YU DEPENDENCY INSTALL PASS"
Write-Host "  Rscript : $rscript"
Write-Host "  Python  : $python"
Write-Host "  Manifest: $manifestDir"
Write-Host "Set YU_RSCRIPT and YU_PYTHON to these paths when automatic discovery is unavailable."
