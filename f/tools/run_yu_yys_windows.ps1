param(
  [ValidateSet("help","preflight","prepare","train","evaluate","report","all")][string]$Mode="help",
  [string]$Dir0="D:/",
  [string]$AnalysisRoot="",
  [string]$AnalysisProject="yy_cad_yu_yys_legacy257",
  [string]$RawProteinFile="D:/data/ukb/phe/raw/prot_full_unimputed.tsv",
  [string]$PhenotypeRds="D:/data/ukb/phe/Rdata/all.rds",
  [string]$PanelMappingFile="D:/data.BIG/gwas/ppp/olink_protein_map_3k_v1.tsv",
  [string]$RscriptExe=$env:YU_RSCRIPT,
  [string]$PythonExe=$env:YU_PYTHON,
  [int]$Workers=16,
  [int]$BootstrapN=1000,
  [switch]$Resume,
  [switch]$Force
)

$CodeDir=Split-Path -Parent $PSScriptRoot
$ProjectDir=Split-Path -Parent $CodeDir
$RFile=Join-Path $ProjectDir "f/entry/99_run_yu_yys.R"
$Config=Join-Path $ProjectDir "f/config/defaults.json"
if(-not $AnalysisRoot){$AnalysisRoot=Join-Path $Dir0 "analysis"}
$AnalysisDir=Join-Path $AnalysisRoot $AnalysisProject
$LogDir=Join-Path $AnalysisDir "00_logs"; New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
function Resolve-Runtime([string]$Explicit,[string[]]$Preferred,[string[]]$Commands,[string]$Label){
  if($Explicit){if(-not(Test-Path $Explicit -PathType Leaf)){throw "$Label override not found: $Explicit"};return (Resolve-Path $Explicit).Path}
  foreach($path in $Preferred){if($path -and (Test-Path $path -PathType Leaf)){return (Resolve-Path $path).Path}}
  foreach($command in $Commands){$resolved=Get-Command $command -ErrorAction SilentlyContinue | Select-Object -First 1;if($resolved){return $resolved.Source}}
  throw "$Label was not found. Supply its explicit path or set the matching YU_* environment variable."
}
$pythonPreferred=@();if($env:USERPROFILE){$pythonPreferred+=Join-Path $env:USERPROFILE "anaconda3/envs/yu_proteomic_repo_py39/python.exe";$pythonPreferred+=Join-Path $env:USERPROFILE "miniconda3/envs/yu_proteomic_repo_py39/python.exe"}
$Rscript=Resolve-Runtime $RscriptExe @("C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe","C:/Program Files/R/R-4.3.2/bin/x64/Rscript.exe") @("Rscript.exe","Rscript") "Rscript"
$Python=Resolve-Runtime $PythonExe $pythonPreferred @("python.exe","python3.exe","python") "Python 3.9 with LightGBM"

function Invoke-RStage([string]$Stage){
  $log=Join-Path $LogDir ("{0}_{1}.log" -f $Stage,(Get-Date -Format "yyyyMMdd_HHmmss"))
  $args=@("--vanilla",$RFile,"--mode=$Stage","--dir0=$Dir0","--analysis_root=$AnalysisRoot","--analysis_project=$AnalysisProject","--raw_protein_file=$RawProteinFile","--phenotype_rds=$PhenotypeRds","--panel_mapping_file=$PanelMappingFile","--workers=$Workers","--bootstrap_n=$BootstrapN")
  if($Resume){$args+="--resume=true"}; if($Force){$args+="--force=true"}
  Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | R stage=$Stage | log=$log"
  $old=$ErrorActionPreference; $ErrorActionPreference="Continue"; & $Rscript @args 2>&1 | Tee-Object -FilePath $log; $code=$LASTEXITCODE; $ErrorActionPreference=$old
  if($code -ne 0){throw "R stage $Stage failed with exit code $code. See $log"}
}
function Invoke-Train {
  $log=Join-Path $LogDir ("train_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss")); $py=Join-Path $ProjectDir "f/python/02_train_lightgbm.py"
  $args=@($py,"--analysis-dir",$AnalysisDir,"--config",$Config,"--workers",$Workers); if($Resume){$args+="--resume"}
  Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Python LightGBM | log=$log"
  $old=$ErrorActionPreference; $ErrorActionPreference="Continue"; & $Python @args 2>&1 | Tee-Object -FilePath $log; $code=$LASTEXITCODE; $ErrorActionPreference=$old
  if($code -ne 0){throw "Python train failed with exit code $code. See $log"}
}

if($Mode -eq "help"){Invoke-RStage "help"; exit 0}
switch($Mode){
  "preflight" {Invoke-RStage "preflight"}
  "prepare" {Invoke-RStage "prepare"}
  "train" {Invoke-Train}
  "evaluate" {Invoke-RStage "evaluate"}
  "report" {Invoke-RStage "report"}
  "all" {Invoke-RStage "preflight"; Invoke-RStage "prepare"; Invoke-Train; Invoke-RStage "evaluate"; Invoke-RStage "report"}
}
Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | COMPLETE mode=$Mode | analysis=$AnalysisDir"
