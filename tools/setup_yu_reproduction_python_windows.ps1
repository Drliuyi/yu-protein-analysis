param(
  [string]$CondaExe = "C:/Users/Dr.Liuyi/anaconda3/Scripts/conda.exe",
  [string]$EnvironmentName = "yu_proteomic_repo_py39"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $CondaExe)) { throw "Conda executable not found: $CondaExe" }

$CondaRoot = Split-Path -Parent (Split-Path -Parent $CondaExe)
$PythonExe = Join-Path $CondaRoot ("envs/{0}/python.exe" -f $EnvironmentName)
if (-not (Test-Path $PythonExe)) {
  & $CondaExe create -y -n $EnvironmentName python=3.9 pip
  if ($LASTEXITCODE -ne 0) { throw "Failed to create conda environment $EnvironmentName" }
}

& $PythonExe -m pip install --disable-pip-version-check --no-input `
  numpy==1.26.4 scipy==1.11.4 pandas==2.1.4 scikit-learn==1.3.2 lightgbm==3.3.2
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
