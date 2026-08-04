param(
  [string]$CondaExe = $env:YU_CONDA,
  [string]$EnvironmentName = "yu_proteomic_repo_py39",
  [string]$RequirementsFile = (Join-Path (Split-Path -Parent $PSScriptRoot) "config/requirements-py39.txt")
)

$ErrorActionPreference = "Stop"
if (-not $CondaExe) {
  $preferred = @()
  if ($env:USERPROFILE) {
    $preferred += Join-Path $env:USERPROFILE "anaconda3/Scripts/conda.exe"
    $preferred += Join-Path $env:USERPROFILE "miniconda3/Scripts/conda.exe"
  }
  $preferred += @("C:/ProgramData/anaconda3/Scripts/conda.exe", "C:/ProgramData/miniconda3/Scripts/conda.exe")
  $CondaExe = $preferred | Where-Object { Test-Path $_ -PathType Leaf } | Select-Object -First 1
}
if (-not $CondaExe -or -not (Test-Path $CondaExe -PathType Leaf)) {
  throw "Conda executable not found. Supply -CondaExe or set YU_CONDA."
}
if (-not (Test-Path $RequirementsFile -PathType Leaf)) { throw "Frozen requirements file not found: $RequirementsFile" }

$CondaRoot = Split-Path -Parent (Split-Path -Parent $CondaExe)
$PythonExe = Join-Path $CondaRoot ("envs/{0}/python.exe" -f $EnvironmentName)
if (-not (Test-Path $PythonExe)) {
  & $CondaExe create -y -n $EnvironmentName python=3.9 pip
  if ($LASTEXITCODE -ne 0) { throw "Failed to create conda environment $EnvironmentName" }
}

& $PythonExe -m pip install --disable-pip-version-check --no-input -r $RequirementsFile
if ($LASTEXITCODE -ne 0) { throw "Failed to install the frozen reproduction packages." }

$code = "import json,sys,lightgbm,sklearn,pandas,numpy,scipy; print(json.dumps(dict(python='.'.join(map(str,sys.version_info[:3])),lightgbm=lightgbm.__version__,sklearn=sklearn.__version__,pandas=pandas.__version__,numpy=numpy.__version__,scipy=scipy.__version__)))"
$json = & $PythonExe -c $code
if ($LASTEXITCODE -ne 0) { throw "Frozen Python environment import check failed." }
$environment = $json | ConvertFrom-Json
$majorMinor = (($environment.python -split '\.')[0..1] -join '.')
if ($majorMinor -ne "3.9" -or $environment.lightgbm -ne "3.3.2") {
  throw "Version contract failed: $json"
}

Write-Host "READY: $PythonExe"
Write-Host $json
