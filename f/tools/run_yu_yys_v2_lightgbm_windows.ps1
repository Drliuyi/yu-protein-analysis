param(
  [ValidateSet('inputs','prepare','train','evaluate','all','status','help')]
  [string]$Mode = 'help',
  [string]$Dir0 = 'D:/',
  [string]$AnalysisRoot = '',
  [string]$AnalysisProject = 'yu_proteomic_repo_cad_yysv2_20260721',
  [string]$InputDir = '',
  [int]$Workers = 16,
  [int]$ModelJobs = 3,
  [int]$SplitSeed = 20260715,
  [int]$InnerSeed = 20260716,
  [int]$Seed = 20260721,
  [string]$RscriptExe = $env:YU_RSCRIPT,
  [string]$PythonExe = $env:YU_PYTHON,
  [switch]$Resume
)

$ErrorActionPreference = 'Stop'
$CodeDir = Split-Path -Parent $PSScriptRoot
$ProjectDir = Split-Path -Parent $CodeDir
$Phase3BProject = Join-Path $Dir0 'scripts/yy_cad_phase3B_sparse_yys_prediction'
if (-not $AnalysisRoot) { $AnalysisRoot = Join-Path $Dir0 'analysis' }
$AnalysisDir = Join-Path $AnalysisRoot $AnalysisProject
if (-not $InputDir) { $InputDir = Join-Path $AnalysisDir '00_inputs' }
$CacheDir = Join-Path $AnalysisDir '01_cache'
$LogDir = Join-Path $AnalysisDir '00_logs'

function Resolve-Runtime([string]$Explicit, [string[]]$Preferred, [string[]]$Commands, [string]$Label) {
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
  throw "$Label was not found. Supply its explicit path or set the matching YU_* environment variable."
}

$pythonPreferred = @()
if ($env:USERPROFILE) {
  $pythonPreferred += Join-Path $env:USERPROFILE 'anaconda3/envs/yu_proteomic_repo_py39/python.exe'
  $pythonPreferred += Join-Path $env:USERPROFILE 'miniconda3/envs/yu_proteomic_repo_py39/python.exe'
}
$Rscript = Resolve-Runtime $RscriptExe @(
  'C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe',
  'C:/Program Files/R/R-4.3.2/bin/x64/Rscript.exe'
) @('Rscript.exe', 'Rscript') 'Rscript'
$Python = Resolve-Runtime $PythonExe $pythonPreferred @('python.exe', 'python3.exe', 'python') 'Python 3.9'

if ($Mode -eq 'help') {
  @'
Our CAD outcome: Yu-style LightGBM plus matched YinScore/ABCD-YYS v2

Modes:
  inputs    Split our CAD cohort into 2/3 derivation and 1/3 hold-out; compute
            derivation-only ProtWAS and ABCD-YYS v2. Ten inner folds are saved.
  prepare   Align prot.rds and create a reusable 37,127 x 2,910 float32 cache.
  train     Derivation Bonferroni screen -> preliminary LightGBM -> cumulative
            30% gain panel -> final panel, +YinScore, and +YYScore models.
  evaluate  Hold-out AUC/PR-AUC/Brier, 1/3/5/10-year AUC, C-index,
            calibration, paired DeLong comparisons, and hard QC.
  all       inputs -> prepare -> train -> evaluate.
  status    Show active processes and generated outputs.

No published Yu panel, fixed Yu outcome, fixed Yu split, permutation control,
or other model family is used. The matched YinScore and YYScore models use the
same CAD protein panel and the same number of predictors.
'@ | Write-Output
  exit 0
}

New-Item -ItemType Directory -Force -Path $AnalysisDir,$InputDir,$CacheDir,$LogDir | Out-Null
if (-not (Test-Path $Rscript)) { throw "Rscript not found: $Rscript" }
if (-not (Test-Path $Python)) { throw "Frozen Yu Python not found: $Python" }

function Run-Stage([string]$Stage) {
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $log = Join-Path $LogDir "${Stage}_${stamp}.log"
  if ($Stage -eq 'inputs') {
    $marker = Join-Path $InputDir 'input_manifest.csv'
    if ($Resume -and (Test-Path $marker)) { Write-Output "Resume: inputs already complete"; return }
    & $Rscript --vanilla (Join-Path $ProjectDir 'f/tools/prepare_yys_v2_lightgbm_inputs.R') `
      "--phase1_cache=$AnalysisRoot/yy_cad_phase1_protwas_20260719/cache/phase1_analysis_data.rds" `
      "--phase3b_project=$Phase3BProject" "--out_dir=$InputDir" "--workers=$Workers" `
      "--split_seed=$SplitSeed" "--inner_seed=$InnerSeed" 2>&1 | Tee-Object -FilePath $log
  } elseif ($Stage -eq 'prepare') {
    $marker = Join-Path $CacheDir 'matrix_manifest.csv'
    if ($Resume -and (Test-Path $marker)) { Write-Output "Resume: prepare already complete"; return }
    & $Rscript --vanilla (Join-Path $ProjectDir 'f/tools/prepare_yys_v2_lightgbm_matrix.R') `
      "--prot_rds=$Dir0/data/ukb/phe/Rdata/prot.rds" "--input_dir=$InputDir" `
      "--cache_dir=$CacheDir" 2>&1 | Tee-Object -FilePath $log
  } elseif ($Stage -eq 'train') {
    $marker = Join-Path $AnalysisDir '02_lightgbm/training_manifest.json'
    if ($Resume -and (Test-Path $marker)) { Write-Output "Resume: train already complete"; return }
    & $Python (Join-Path $ProjectDir 'f/python/09_yys_v2_lightgbm.py') `
      --analysis-dir $AnalysisDir --input-dir $InputDir --workers $Workers `
      --model-jobs $ModelJobs --seed $Seed 2>&1 | Tee-Object -FilePath $log
  } elseif ($Stage -eq 'evaluate') {
    & $Rscript --vanilla (Join-Path $ProjectDir 'f/tools/evaluate_yys_v2_lightgbm.R') `
      "--analysis-dir=$AnalysisDir" 2>&1 | Tee-Object -FilePath $log
  }
  if ($LASTEXITCODE -ne 0) { throw "Stage $Stage failed with exit code $LASTEXITCODE. See $log" }
}

if ($Mode -eq 'status') {
  Write-Output "Analysis: $AnalysisDir"
  Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -match '09_yys_v2_lightgbm|prepare_yys_v2_lightgbm'
  } | Select-Object ProcessId,Name,CreationDate,CommandLine | Format-List
  Get-ChildItem (Join-Path $AnalysisDir '02_lightgbm') -ErrorAction SilentlyContinue |
    Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize
  exit 0
}

switch ($Mode) {
  'inputs'   { Run-Stage 'inputs' }
  'prepare'  { Run-Stage 'prepare' }
  'train'    { Run-Stage 'train' }
  'evaluate' { Run-Stage 'evaluate' }
  'all'      { Run-Stage 'inputs'; Run-Stage 'prepare'; Run-Stage 'train'; Run-Stage 'evaluate' }
}
