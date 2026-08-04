param(
  [Alias("Steps")]
  [string]$Step = "help",
  [string]$Dir0 = $(if ($env:YU_DIR0) { $env:YU_DIR0 } else { "" }),
  [string]$AnalysisRoot = $(if ($env:YU_OUTDIR) { $env:YU_OUTDIR } else { "" }),
  [string]$AnalysisProject = "yu_proteomic_repo_v3",
  [string]$ProjectDir = $(if ($env:YU_PROJECT_DIR) { $env:YU_PROJECT_DIR } else { "" }),
  [string]$ScriptRoot = $(if ($env:YU_SCRIPT_ROOT) { $env:YU_SCRIPT_ROOT } else { "" }),
  [string]$PheDir = $(if ($env:YU_PHEDIR) { $env:YU_PHEDIR } else { "" }),
  [string]$RawProteinFile = "",
  [string]$PhenotypeRds = "",
  [string]$RawPhenotypeFile = "",
  [string]$PanelMappingFile = "",
  [string]$SupplementWorkbookFile = "",
  [string]$SupplementMethodsFile = "",
  [string]$OlinkProcessingStartDateFile = "",
  [string]$CmrFeatureFile = "",
  [string]$PqtlRoot = "",
  [string]$MrOutcomeLookupDir = "",
  [string]$RscriptExe = $(if ($env:YU_RSCRIPT) { $env:YU_RSCRIPT } else { "" }),
  [string]$PythonExe = $(if ($env:YU_PYTHON) { $env:YU_PYTHON } else { "" }),
  [string]$CondaExe = $(if ($env:YU_CONDA) { $env:YU_CONDA } else { "" }),
  [Alias("EndpointSubset")]
  [string]$Disease = "all",
  [int]$Workers = 16,
  [int]$CoxJobs = 4,
  [int]$CmrJobs = 4,
  [int]$ModelJobs = 3,
  [int]$BootstrapN = 1000,
  [int]$CmestJobs = 8,
  [int]$CmestPilotBoot = 20,
  [int]$ScoreJobs = 2,
  [int]$AssociationJobs = 4,
  [int]$MemoryMb = 48000,
  [ValidateSet("Auto", "DirectNas", "StreamZspace")]
  [string]$GenotypeMode = "DirectNas",
  [string]$WindowsNasRoot = "",
  [string]$NasMountRoot = "/mnt/z/projects/genotype_pc_nas/imputed_pgen_autosomes",
  [Alias("PredictionPanelMode")]
  [ValidateSet("local_reselected", "published_257", "custom")]
  [string]$ProteinPanel = "local_reselected",
  [Alias("CustomProteinPanelFile")]
  [string]$ModelProteinFile = "",
  [Alias("CustomProteins")]
  [string]$ModelProteins = "",
  [string]$Figure4ExtraProject = "",
  [string]$Figure4ExtraOutcome = "",
  [string]$Figure4ExtraLabel = "",
  [int]$StringRequiredScore = 700,
  [int]$SystemsTopN = 15,
  [int]$SystemsMaxTf = 46,
  [double]$SystemsFdr = 0.05,
  [switch]$Resume,
  [switch]$Force,
  [switch]$ConfirmHeavy,
  [switch]$PlanOnly,
  [ValidateSet("Auto", "Dialog", "Console", "Off")]
  [string]$PathPromptMode = "Auto",
  [string]$PathConfig = $(if ($env:YU_PATH_CONFIG) { $env:YU_PATH_CONFIG } else { "" }),
  [switch]$ResetPaths,
  [switch]$AllowConcurrentHeavyJob,
  [switch]$KeepStreamedGenotype
)

$ErrorActionPreference = "Stop"

function Get-DefaultPathConfig {
  if ($PathConfig) { return $PathConfig }
  if ($env:LOCALAPPDATA) {
    return Join-Path $env:LOCALAPPDATA "YuProteinAnalysis/paths.json"
  }
  return Join-Path $HOME ".yu_protein_analysis/paths.json"
}

$PathConfig = Get-DefaultPathConfig
if ($ResetPaths -and (Test-Path $PathConfig -PathType Leaf)) {
  Remove-Item $PathConfig -Force
  Write-Host "Removed saved path profile: $PathConfig"
}

$SavedPathMap = [ordered]@{}
if (Test-Path $PathConfig -PathType Leaf) {
  try {
    $savedObject = Get-Content $PathConfig -Raw | ConvertFrom-Json
    foreach ($property in $savedObject.PSObject.Properties) {
      if ($property.Name -notin @("schema_version", "updated_at")) {
        $SavedPathMap[$property.Name] = [string]$property.Value
      }
    }
  } catch {
    throw "Saved path profile is invalid: $PathConfig. Use -ResetPaths to rebuild it. $($_.Exception.Message)"
  }
}

function Get-SavedPath([string]$Key) {
  if ($SavedPathMap.Contains($Key) -and -not [string]::IsNullOrWhiteSpace($SavedPathMap[$Key])) {
    return [string]$SavedPathMap[$Key]
  }
  return ""
}

$PathSources = @{}
function Initialize-PathValue([string]$Name, [string]$CurrentValue, [string]$ProfileKey, [string]$DefaultValue) {
  if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
    $PathSources[$Name] = "argument_or_environment"
    return $CurrentValue
  }
  $saved = Get-SavedPath $ProfileKey
  if ($saved) {
    $PathSources[$Name] = "saved_profile"
    return $saved
  }
  $PathSources[$Name] = "huang_default"
  return $DefaultValue
}

function Normalize-Slash([string]$Path) {
  if (-not $Path) { return "" }
  $normalized = ($Path -replace "\\", "/").Trim()
  if ($normalized -match "^[A-Za-z]:/$") { return $normalized }
  return $normalized.TrimEnd("/")
}

function Save-PathProfile {
  $parent = Split-Path -Parent $PathConfig
  if ($parent -and -not (Test-Path $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $profile = [ordered]@{
    schema_version = 1
    updated_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  }
  foreach ($key in @($SavedPathMap.Keys | Sort-Object)) {
    $profile[$key] = $SavedPathMap[$key]
  }
  $profile | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 $PathConfig
}

function Remember-Path([string]$Key, [string]$Path) {
  if (-not $Key -or -not $Path) { return }
  $SavedPathMap[$Key] = Normalize-Slash $Path
  Save-PathProfile
  Write-Host "Saved $Key as the local default: $($SavedPathMap[$Key])"
}

$projectFromScript = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Dir0 = Initialize-PathValue "Dir0" $Dir0 "dir0" "D:/"
$ScriptRoot = Initialize-PathValue "ScriptRoot" $ScriptRoot "script_root" "D:/scripts"
$ProjectDir = if ($ProjectDir) { $ProjectDir } else { $projectFromScript }
$PheDir = Initialize-PathValue "PheDir" $PheDir "phe_dir" ""
$AnalysisRoot = Initialize-PathValue "AnalysisRoot" $AnalysisRoot "analysis_root" ""
$RawProteinFile = Initialize-PathValue "RawProteinFile" $RawProteinFile "raw_protein_file" ""
$PhenotypeRds = Initialize-PathValue "PhenotypeRds" $PhenotypeRds "phenotype_rds" ""
$RawPhenotypeFile = Initialize-PathValue "RawPhenotypeFile" $RawPhenotypeFile "raw_phenotype_file" ""
$PanelMappingFile = Initialize-PathValue "PanelMappingFile" $PanelMappingFile "panel_mapping_file" ""
$SupplementWorkbookFile = Initialize-PathValue "SupplementWorkbookFile" $SupplementWorkbookFile "supplement_workbook_file" (Join-Path $ProjectDir "references/raw/pwaf072_supplementary_table_1.xlsx")
$SupplementMethodsFile = Initialize-PathValue "SupplementMethodsFile" $SupplementMethodsFile "supplement_methods_file" (Join-Path $ProjectDir "references/raw/pwaf072_supplementary_figure_1.pdf")
$OlinkProcessingStartDateFile = Initialize-PathValue "OlinkProcessingStartDateFile" $OlinkProcessingStartDateFile "olink_processing_start_date_file" (Join-Path $ProjectDir "references/raw/olink_processing_start_date.dat")
$CmrFeatureFile = Initialize-PathValue "CmrFeatureFile" $CmrFeatureFile "cmr_feature_file" ""
$PqtlRoot = Initialize-PathValue "PqtlRoot" $PqtlRoot "pqtl_root" ""
$MrOutcomeLookupDir = Initialize-PathValue "MrOutcomeLookupDir" $MrOutcomeLookupDir "mr_outcome_lookup_dir" ""
$WindowsNasRoot = Initialize-PathValue "WindowsNasRoot" $WindowsNasRoot "windows_nas_root" "Z:/projects/genotype_pc_nas/imputed_pgen_autosomes"

$Dir0 = Normalize-Slash $Dir0
$ScriptRoot = Normalize-Slash $ScriptRoot
$ProjectDir = Normalize-Slash $ProjectDir

$PathOverrides = @{
  PheDir = $PathSources.PheDir -ne "huang_default"
  AnalysisRoot = $PathSources.AnalysisRoot -ne "huang_default"
  RawProteinFile = $PathSources.RawProteinFile -ne "huang_default"
  PhenotypeRds = $PathSources.PhenotypeRds -ne "huang_default"
  RawPhenotypeFile = $PathSources.RawPhenotypeFile -ne "huang_default"
  PanelMappingFile = $PathSources.PanelMappingFile -ne "huang_default"
  SupplementWorkbookFile = $PathSources.SupplementWorkbookFile -ne "huang_default"
  SupplementMethodsFile = $PathSources.SupplementMethodsFile -ne "huang_default"
  OlinkProcessingStartDateFile = $PathSources.OlinkProcessingStartDateFile -ne "huang_default"
  CmrFeatureFile = $PathSources.CmrFeatureFile -ne "huang_default"
  PqtlRoot = $PathSources.PqtlRoot -ne "huang_default"
  MrOutcomeLookupDir = $PathSources.MrOutcomeLookupDir -ne "huang_default"
}

function Set-DerivedPaths {
  if (-not $PathOverrides.PheDir) {
    $script:PheDir = Join-Path $Dir0 "data/ukb/phe"
  }
  if (-not $PathOverrides.AnalysisRoot) { $script:AnalysisRoot = Join-Path $Dir0 "analysis" }
  if (-not $PathOverrides.RawProteinFile) { $script:RawProteinFile = Join-Path $PheDir "raw/prot_full_unimputed.tsv" }
  if (-not $PathOverrides.PhenotypeRds) { $script:PhenotypeRds = Join-Path $PheDir "Rdata/all.rds" }
  if (-not $PathOverrides.RawPhenotypeFile) { $script:RawPhenotypeFile = Join-Path $PheDir "pheno.tsv.gz" }
  if (-not $PathOverrides.PanelMappingFile) {
    $script:PanelMappingFile = Join-Path $Dir0 "data.BIG/gwas/ppp/olink_protein_map_3k_v1.tsv"
  }
  if (-not $PathOverrides.CmrFeatureFile) {
    $script:CmrFeatureFile = Join-Path $AnalysisRoot "sleepchart_reproduction/data/mribag_features/heart/feature.tsv"
  }
  if (-not $PathOverrides.PqtlRoot) { $script:PqtlRoot = Join-Path $Dir0 "ppp/clean" }
  $script:AnalysisDir = Join-Path $AnalysisRoot $AnalysisProject
  if (-not $PathOverrides.MrOutcomeLookupDir) {
    $script:MrOutcomeLookupDir = Join-Path $AnalysisDir "11_mr/outcome_lookup"
  }
}

Set-DerivedPaths

$FullRunner = Join-Path $ProjectDir "f/tools/run_yu_full_reproduction_windows.ps1"
$PrsRunner = Join-Path $ProjectDir "f/tools/run_yu_prs_windows.ps1"
$InstallRunner = Join-Path $ProjectDir "f/tools/install_yu_dependencies_windows.ps1"
$PackageRunner = Join-Path $ProjectDir "f/tools/package_yu_project.ps1"

$StepCatalog = @(
  [pscustomobject]@{ Id = 1; Name = "Sources and preflight"; Requires = "none"; Resource = "light"; Action = "sources -> preflight" },
  [pscustomobject]@{ Id = 2; Name = "Incident cohort"; Requires = "1"; Resource = "light"; Action = "cohort" },
  [pscustomobject]@{ Id = 3; Name = "Full-panel Cox associations"; Requires = "2"; Resource = "heavy"; Action = "cox_parallel" },
  [pscustomobject]@{ Id = 4; Name = "Protein selection and prediction"; Requires = "3"; Resource = "heavy"; Action = "select -> train -> evaluate" },
  [pscustomobject]@{ Id = 5; Name = "CMR associations"; Requires = "2"; Resource = "heavy"; Action = "cmr_parallel" },
  [pscustomobject]@{ Id = 6; Name = "Mendelian randomization"; Requires = "3"; Resource = "medium"; Action = "mr_prepare -> mr_run" },
  [pscustomobject]@{ Id = 7; Name = "Mediation candidate analysis"; Requires = "3"; Resource = "medium"; Action = "mediation_prepare -> mediation_run" },
  [pscustomobject]@{ Id = 8; Name = "Article-matched CMAverse mediation"; Requires = "7"; Resource = "very heavy"; Action = "cmest pilot -> parallel shards -> merge" },
  [pscustomobject]@{ Id = 9; Name = "PRS-protein reconstruction"; Requires = "2"; Resource = "very heavy"; Action = "PRS preflight -> GWAS -> score -> associate -> figure" },
  [pscustomobject]@{ Id = 10; Name = "Enrichment, TF and PPI systems biology"; Requires = "3,9"; Resource = "medium/network"; Action = "Figure 6B-D systems pipeline" },
  [pscustomobject]@{ Id = 11; Name = "Final figures and report"; Requires = "4,5,6,8,10"; Resource = "light"; Action = "Figures 1-6 -> report" }
)

function Show-StepHelp {
  Write-Host @'
Yu/Chen proteomic reproduction - step runner

Usage:
  -Step 1                 Run one step.
  -Step "1,2,3,4"         Run selected steps in numeric order.
  -Step "1-4"             Run a continuous range.
  -Step core              Alias for steps 1-4.
  -Step downstream        Alias for steps 5-10.
  -Step all               Run steps 1-11; requires -ConfirmHeavy.
  -Step finalize          Run steps 10-11 and verify the complete Figure 1-6 package.
  -Step doctor            Read-only code, runtime, package and core-input check.
  -Step install           Install the frozen Python and required R environments.
  -Step package           Build a source-only ZIP plus SHA256 manifest.
  -Step status            Read-only monitor for the full and PRS workflows.
  -Step paths             Show Huang-lab defaults and the saved local profile.
  -Step setup             Resolve the core paths interactively, save them, and exit.
  -PlanOnly               Print resolved paths and actions without computation.
  -PathPromptMode Auto|Dialog|Console|Off
                           Auto uses a Windows picker for missing paths and
                           falls back to a console prompt over SSH. Off makes
                           automation fail immediately instead of prompting.
  -ResetPaths              Delete the saved local path profile and start again
                           from the Huang-lab D:/ defaults.
  -RscriptExe PATH         Optional Rscript override; otherwise YU_RSCRIPT,
                           PATH and standard Windows R locations are searched.
  -PythonExe PATH          Optional frozen Python 3.9 override; otherwise
                           YU_PYTHON, PATH and standard Conda locations are searched.
  -CondaExe PATH           Optional Conda override used by -Step install;
                           YU_CONDA is the equivalent environment variable.

Disease and model-protein controls:
  -Disease all|cad|heart_failure|cad,heart_failure
                           Select one or more configured outcome IDs.
  -ProteinPanel local_reselected|published_257|custom
                           Select the protein panel entering prediction models.
  -ModelProteinFile PATH   CSV/TSV/TXT custom panel; use feature_id,
                           local_feature, protein or a single column.
  -ModelProteins "A,B,C"   Inline feature IDs or uniquely mapped protein symbols.
  -Figure4ExtraProject NAME
                           Append one or more semicolon-separated completed
                           analysis projects to Figure 4A without changing them.
  -Figure4ExtraOutcome ID  Source outcome ID per extra project; semicolon-separated.
  -Figure4ExtraLabel TEXT  Display label per extra project; semicolon-separated.

Canonical scope:
  The main step runner always uses YYScoreMode=off. Historical YYScore code is
  retained for audit but is not part of the frozen Yu/Chen reproduction.
  Disease-specific or custom-panel runs must use a new -AnalysisProject so the
  frozen yu_proteomic_repo_v3 results are never overwritten.
  Step 9 remains the article-fixed 13-outcome PRS reconstruction; -Disease and
  -ProteinPanel do not alter that separate module.

Important:
  Steps 8 and 9 require -ConfirmHeavy because CMAverse and genotype scoring are
  long-running. -Resume reuses valid stage markers and completed shards.

Huang-lab defaults (no path arguments needed):
  DIR0          D:/
  scripts       D:/scripts
  phenotype     D:/data/ukb/phe/Rdata/all.rds
  protein       D:/data/ukb/phe/raw/prot_full_unimputed.tsv
  analysis      D:/analysis
  genotype      Z:/projects/genotype_pc_nas/imputed_pgen_autosomes

If a required default is missing, the runner asks only for paths used by the
selected steps and saves the answer in the local path profile. The next run
reuses it automatically. The lower-level analysis scripts remain non-interactive.

First-time path setup without computation:
  .\yu.ps1 -Step setup

Routine command:
  .\yu.ps1 -Step "1-4" -Resume

Disease-specific custom-panel example:
  powershell -NoProfile -ExecutionPolicy Bypass `
    -File .\yu.ps1 -Step "1-4" -AnalysisProject yu_hf_custom_v1 `
    -Disease heart_failure -ProteinPanel custom `
    -ModelProteinFile D:/files/model_proteins_hf.csv `
    -Workers 16 -CoxJobs 4 -ModelJobs 3 -Resume

Append that completed custom-panel run to the frozen Figure 4A:
  powershell -NoProfile -ExecutionPolicy Bypass `
    -File .\yu.ps1 -Step figures -AnalysisProject yu_proteomic_repo_v3 `
    -Figure4ExtraProject yu_avs_jiang4_v1 `
    -Figure4ExtraOutcome aortic_valve_stenosis `
    -Figure4ExtraLabel "Aortic valve stenosis (four-protein panel)" -Force
'@
  $StepCatalog | Format-Table Id, Name, Requires, Resource, Action -AutoSize
  $outcomeFile = Join-Path $ProjectDir "f/config/outcomes.csv"
  if (Test-Path $outcomeFile) {
    Write-Host "`nConfigured disease IDs"
    Import-Csv $outcomeFile | Format-Table outcome_id, outcome_label -AutoSize
  }
}

function Get-RequestedDiseases {
  $outcomeFile = Join-Path $ProjectDir "f/config/outcomes.csv"
  Assert-File $outcomeFile "Outcome configuration"
  $all = @(Import-Csv $outcomeFile)
  if ($Disease.Trim().ToLowerInvariant() -eq "all") { return @($all.outcome_id) }
  $requested = @($Disease.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
  if ($requested.Count -eq 0) { throw "Disease cannot be empty. Use -Disease all or configured outcome IDs." }
  $unknown = @($requested | Where-Object { $_ -notin $all.outcome_id })
  if ($unknown.Count -gt 0) {
    throw "Unknown disease IDs: $($unknown -join ', '). Run -Step help for configured IDs."
  }
  return $requested
}

function Assert-ModelPanelRequest {
  if ($ProteinPanel -ne "custom") {
    if ($ModelProteinFile -or $ModelProteins) {
      throw "-ModelProteinFile/-ModelProteins require -ProteinPanel custom."
    }
    return
  }
  if (-not $ModelProteinFile -and -not $ModelProteins) {
    throw "-ProteinPanel custom requires -ModelProteinFile and/or -ModelProteins."
  }
}

function Resolve-Steps([string]$Spec) {
  $value = $Spec.Trim().ToLowerInvariant()
  if ($value -in @("help", "status", "doctor", "install", "package")) { return @() }
  if ($value -eq "all") { return @(1..11) }
  if ($value -eq "core") { return @(1..4) }
  if ($value -eq "downstream") { return @(5..10) }
  if ($value -eq "figures") { return @(11) }
  if ($value -eq "finalize") { return @(10, 11) }

  $resolved = @()
  foreach ($token in @($value -split "[,; ]+" | Where-Object { $_ })) {
    if ($token -match "^(\d+)-(\d+)$") {
      $start = [int]$Matches[1]
      $end = [int]$Matches[2]
      if ($start -gt $end) { throw "Invalid descending step range: $token" }
      $resolved += @($start..$end)
    } elseif ($token -match "^\d+$") {
      $resolved += [int]$token
    } else {
      throw "Unknown step token: $token. Use -Step help."
    }
  }
  $invalid = @($resolved | Where-Object { $_ -lt 1 -or $_ -gt 11 })
  if ($invalid.Count -gt 0) { throw "Steps must be between 1 and 11: $($invalid -join ', ')" }
  return @($resolved | Sort-Object -Unique)
}

function Show-ResolvedPlan([int[]]$SelectedSteps) {
  Write-Host ""
  Write-Host "Resolved roots"
  Write-Host "  DIR0          : $Dir0"
  Write-Host "  PHEDIR        : $PheDir"
  Write-Host "  SCRIPT_ROOT   : $ScriptRoot"
  Write-Host "  PROJECT_DIR   : $ProjectDir"
  Write-Host "  ANALYSIS_ROOT : $AnalysisRoot"
  Write-Host "  ANALYSIS_DIR  : $AnalysisDir"
  Write-Host "  PROTEIN       : $RawProteinFile"
  Write-Host "  PHENOTYPE     : $PhenotypeRds"
  Write-Host "  RAW PHENOTYPE : $RawPhenotypeFile"
  Write-Host "  PANEL MAP     : $PanelMappingFile"
  Write-Host "  SUPP TABLES   : $SupplementWorkbookFile"
  Write-Host "  SUPP METHODS  : $SupplementMethodsFile"
  Write-Host "  OLINK DATES   : $OlinkProcessingStartDateFile"
  Write-Host "  CMR FEATURES  : $CmrFeatureFile"
  Write-Host "  pQTL ROOT     : $PqtlRoot"
  Write-Host "  GENOTYPE      : $WindowsNasRoot"
  Write-Host "  PATH PROMPT   : $PathPromptMode"
  Write-Host "  PATH PROFILE  : $PathConfig"
  Write-Host "  DISEASE       : $Disease"
  Write-Host "  PROTEIN PANEL : $ProteinPanel"
  if ($ModelProteinFile) { Write-Host "  MODEL FILE    : $ModelProteinFile" }
  if ($ModelProteins) { Write-Host "  INLINE MODELS : $ModelProteins" }
  if ($Figure4ExtraProject) { Write-Host "  FIG4 EXTRAS   : $Figure4ExtraProject" }
  Write-Host ""
  Write-Host "Execution plan"
  $StepCatalog | Where-Object { $_.Id -in $SelectedSteps } |
    Format-Table Id, Name, Requires, Resource, Action -AutoSize
  Write-Host "Frozen options: YYScoreMode=off; Disease=$Disease; ProteinPanel=$ProteinPanel; Resume=$($Resume.IsPresent)"
  if (9 -in $SelectedSteps) {
    Write-Warning "Step 9 is the fixed 13-outcome PRS reconstruction and ignores Disease/ProteinPanel."
  }
}

function Assert-File([string]$Path, [string]$Label) {
  if (-not (Test-Path $Path -PathType Leaf)) { throw "$Label not found: $Path" }
}

function Get-NearestExistingDirectory([string]$Path, [ValidateSet("Leaf", "Container")] [string]$PathType) {
  if (-not $Path) { return "" }
  $candidate = if ($PathType -eq "Leaf") { Split-Path -Parent $Path } else { $Path }
  while ($candidate) {
    if (Test-Path $candidate -PathType Container) { return $candidate }
    $parent = Split-Path -Parent $candidate
    if (-not $parent -or $parent -eq $candidate) { break }
    $candidate = $parent
  }
  return ""
}

function Request-ExistingPath(
  [string]$CurrentPath,
  [string]$Label,
  [ValidateSet("Leaf", "Container")] [string]$PathType,
  [string]$ProfileKey = ""
) {
  if ($PathPromptMode -eq "Off") {
    throw "$Label not found: $CurrentPath. Supply the matching path argument or use -PathPromptMode Auto."
  }

  $useDialog = $PathPromptMode -eq "Dialog" -or (
    $PathPromptMode -eq "Auto" -and
    $env:OS -eq "Windows_NT" -and
    -not $env:SSH_CONNECTION -and
    [Environment]::UserInteractive
  )
  if ($useDialog) {
    try {
      Add-Type -AssemblyName System.Windows.Forms
      $initialDirectory = Get-NearestExistingDirectory $CurrentPath $PathType
      if ($PathType -eq "Leaf") {
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = "$Label not found - select the correct file"
        $dialog.Filter = "All files (*.*)|*.*"
        if ($initialDirectory) { $dialog.InitialDirectory = $initialDirectory }
        if ($CurrentPath) { $dialog.FileName = Split-Path -Leaf $CurrentPath }
        $result = $dialog.ShowDialog()
        $selected = if ($result -eq [System.Windows.Forms.DialogResult]::OK) { $dialog.FileName } else { "" }
        $dialog.Dispose()
      } else {
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "$Label not found - select the correct folder"
        $dialog.ShowNewFolderButton = $false
        if ($initialDirectory) { $dialog.SelectedPath = $initialDirectory }
        $result = $dialog.ShowDialog()
        $selected = if ($result -eq [System.Windows.Forms.DialogResult]::OK) { $dialog.SelectedPath } else { "" }
        $dialog.Dispose()
      }
      if ($selected -and (Test-Path $selected -PathType $PathType)) {
        $selected = Normalize-Slash $selected
        Remember-Path $ProfileKey $selected
        return $selected
      }
      throw "$Label selection was cancelled."
    } catch {
      if ($PathPromptMode -eq "Dialog") { throw }
      Write-Warning "Windows path dialog was unavailable: $($_.Exception.Message)"
    }
  }

  if ([Console]::IsInputRedirected) {
    throw "$Label not found: $CurrentPath. Input is redirected, so an interactive path cannot be requested."
  }
  while ($true) {
    Write-Warning "$Label not found at the default path: $CurrentPath"
    $selected = Read-Host "Enter an existing $PathType path for $Label (Q to cancel)"
    if ($selected -match "^(?i:q|quit|exit)$") { throw "$Label selection was cancelled." }
    $selected = Normalize-Slash $selected
    if (Test-Path $selected -PathType $PathType) {
      Remember-Path $ProfileKey $selected
      return $selected
    }
    Write-Warning "The selected path does not exist or has the wrong type: $selected"
  }
}

function Resolve-RequiredPath(
  [string]$CurrentPath,
  [string]$Label,
  [ValidateSet("Leaf", "Container")] [string]$PathType,
  [string]$ProfileKey = ""
) {
  $CurrentPath = Normalize-Slash $CurrentPath
  if ($CurrentPath -and (Test-Path $CurrentPath -PathType $PathType)) { return $CurrentPath }
  if ($PlanOnly) {
    Write-Warning "$Label is missing and would be requested before execution: $CurrentPath"
    return $CurrentPath
  }
  return Request-ExistingPath $CurrentPath $Label $PathType $ProfileKey
}

function Resolve-SelectedInputPaths([int[]]$SelectedSteps) {
  $script:Dir0 = Resolve-RequiredPath $Dir0 "Huang-lab logical drive root" "Container" "dir0"
  Set-DerivedPaths
  $script:AnalysisRoot = Resolve-RequiredPath $AnalysisRoot "Analysis output root" "Container" "analysis_root"
  $PathOverrides.AnalysisRoot = $true
  Set-DerivedPaths

  $fullInputSteps = @(1, 2, 3, 4, 5, 7)
  $needsFullInputs = @($SelectedSteps | Where-Object { $_ -in $fullInputSteps }).Count -gt 0
  if ($needsFullInputs) {
    $script:PheDir = Resolve-RequiredPath $PheDir "UKB phenotype folder" "Container" "phe_dir"
    $PathOverrides.PheDir = $true
    Set-DerivedPaths
    if (-not $PathOverrides.RawProteinFile) { $script:RawProteinFile = Join-Path $PheDir "raw/prot_full_unimputed.tsv" }
    if (-not $PathOverrides.PhenotypeRds) { $script:PhenotypeRds = Join-Path $PheDir "Rdata/all.rds" }
    $script:RawProteinFile = Resolve-RequiredPath $RawProteinFile "Unimputed protein table" "Leaf" "raw_protein_file"
    $script:PhenotypeRds = Resolve-RequiredPath $PhenotypeRds "Phenotype RDS" "Leaf" "phenotype_rds"
    $script:RawPhenotypeFile = Resolve-RequiredPath $RawPhenotypeFile "Raw phenotype file" "Leaf" "raw_phenotype_file"
    $script:PanelMappingFile = Resolve-RequiredPath $PanelMappingFile "Protein mapping file" "Leaf" "panel_mapping_file"
  }
  if (@($SelectedSteps | Where-Object { $_ -in @(1, 7, 8, 11) }).Count -gt 0) {
    $script:SupplementWorkbookFile = Resolve-RequiredPath $SupplementWorkbookFile "Official supplementary Tables S1-S26" "Leaf" "supplement_workbook_file"
  }
  if (1 -in $SelectedSteps) {
    $script:SupplementMethodsFile = Resolve-RequiredPath $SupplementMethodsFile "Official supplementary methods PDF" "Leaf" "supplement_methods_file"
  }
  if (@($SelectedSteps | Where-Object { $_ -in @(1, 2) }).Count -gt 0) {
    $script:OlinkProcessingStartDateFile = Resolve-RequiredPath $OlinkProcessingStartDateFile "Olink processing start-date table" "Leaf" "olink_processing_start_date_file"
  }
  if (9 -in $SelectedSteps) {
    $script:RawProteinFile = Resolve-RequiredPath $RawProteinFile "Unimputed protein table" "Leaf" "raw_protein_file"
    $script:PhenotypeRds = Resolve-RequiredPath $PhenotypeRds "Phenotype RDS" "Leaf" "phenotype_rds"
    if ($GenotypeMode -eq "DirectNas") {
      $script:WindowsNasRoot = Resolve-RequiredPath $WindowsNasRoot "Direct NAS genotype root" "Container" "windows_nas_root"
    }
  }
  if (5 -in $SelectedSteps) {
    $script:CmrFeatureFile = Resolve-RequiredPath $CmrFeatureFile "CMR feature table" "Leaf" "cmr_feature_file"
  }
  if (6 -in $SelectedSteps) {
    $script:PqtlRoot = Resolve-RequiredPath $PqtlRoot "pQTL root" "Container" "pqtl_root"
  }
  if ($ProteinPanel -eq "custom" -and -not $ModelProteins) {
    if (-not $ModelProteinFile) { $script:ModelProteinFile = Join-Path $Dir0 "files/model_proteins.csv" }
    $script:ModelProteinFile = Resolve-RequiredPath $ModelProteinFile "Custom model-protein file" "Leaf"
  }
}

function Save-ResolvedPathProfile([int[]]$SelectedSteps) {
  $values = [ordered]@{
    dir0 = $Dir0
    script_root = $ScriptRoot
    analysis_root = $AnalysisRoot
    windows_nas_root = $WindowsNasRoot
  }
  if (@($SelectedSteps | Where-Object { $_ -in @(1, 2, 3, 4, 5, 7, 9) }).Count -gt 0) {
    $values.phe_dir = $PheDir
    $values.raw_protein_file = $RawProteinFile
    $values.phenotype_rds = $PhenotypeRds
  }
  if (@($SelectedSteps | Where-Object { $_ -in @(1, 2, 3, 4, 5, 7) }).Count -gt 0) {
    $values.raw_phenotype_file = $RawPhenotypeFile
    $values.panel_mapping_file = $PanelMappingFile
  }
  if (@($SelectedSteps | Where-Object { $_ -in @(1, 7, 8, 11) }).Count -gt 0) {
    $values.supplement_workbook_file = $SupplementWorkbookFile
  }
  if (1 -in $SelectedSteps) { $values.supplement_methods_file = $SupplementMethodsFile }
  if (@($SelectedSteps | Where-Object { $_ -in @(1, 2) }).Count -gt 0) {
    $values.olink_processing_start_date_file = $OlinkProcessingStartDateFile
  }
  if (5 -in $SelectedSteps) { $values.cmr_feature_file = $CmrFeatureFile }
  if (6 -in $SelectedSteps) { $values.pqtl_root = $PqtlRoot }
  foreach ($item in $values.GetEnumerator()) {
    if ($item.Value) { $SavedPathMap[$item.Key] = Normalize-Slash ([string]$item.Value) }
  }
  Save-PathProfile
  Write-Host "Saved resolved paths: $PathConfig"
}

function Invoke-FullMode([string]$Mode) {
  $arguments = @{
    Mode = $Mode
    Dir0 = $Dir0
    AnalysisRoot = $AnalysisRoot
    AnalysisProject = $AnalysisProject
    RawProteinFile = $RawProteinFile
    CmrFeatureFile = $CmrFeatureFile
    PhenotypeRds = $PhenotypeRds
    RawPhenotypeFile = $RawPhenotypeFile
    PanelMappingFile = $PanelMappingFile
    SupplementWorkbookFile = $SupplementWorkbookFile
    SupplementMethodsFile = $SupplementMethodsFile
    OlinkProcessingStartDateFile = $OlinkProcessingStartDateFile
    PqtlRoot = $PqtlRoot
    MrOutcomeLookupDir = $MrOutcomeLookupDir
    EndpointSubset = $Disease
    Workers = $Workers
    CoxJobs = $CoxJobs
    CmrJobs = $CmrJobs
    ModelJobs = $ModelJobs
    BootstrapN = $BootstrapN
    CmestJobs = $CmestJobs
    CmestPilotBoot = $CmestPilotBoot
    PredictionPanelMode = $ProteinPanel
    CustomProteinPanelFile = $ModelProteinFile
    CustomProteins = $ModelProteins
    Figure4ExtraProject = $Figure4ExtraProject
    Figure4ExtraOutcome = $Figure4ExtraOutcome
    Figure4ExtraLabel = $Figure4ExtraLabel
    YYScoreMode = "off"
    StringRequiredScore = $StringRequiredScore
    SystemsTopN = $SystemsTopN
    SystemsMaxTf = $SystemsMaxTf
    SystemsFdr = $SystemsFdr
    RscriptExe = $RscriptExe
    PythonExe = $PythonExe
    Resume = $Resume.IsPresent
    Force = $Force.IsPresent
    AllowConcurrentHeavyJob = $AllowConcurrentHeavyJob.IsPresent
  }
  & $FullRunner @arguments
}

function Invoke-PrsAll {
  $arguments = @{
    Mode = "all"
    Dir0 = $Dir0
    AnalysisRoot = $AnalysisRoot
    AnalysisProject = $AnalysisProject
    RawProteinFile = $RawProteinFile
    PhenotypeRds = $PhenotypeRds
    Workers = $Workers
    ScoreJobs = $ScoreJobs
    AssociationJobs = $AssociationJobs
    MemoryMb = $MemoryMb
    GenotypeMode = $GenotypeMode
    WindowsNasRoot = $WindowsNasRoot
    NasMountRoot = $NasMountRoot
    Resume = $Resume.IsPresent
    Force = $Force.IsPresent
    ConfirmHeavy = $ConfirmHeavy.IsPresent
    KeepStreamedGenotype = $KeepStreamedGenotype.IsPresent
    RscriptExe = $RscriptExe
    PythonExe = $PythonExe
  }
  & $PrsRunner @arguments
}

function Invoke-Step([int]$Id) {
  switch ($Id) {
    1 { Invoke-FullMode "sources"; Invoke-FullMode "preflight" }
    2 { Invoke-FullMode "cohort" }
    3 { Invoke-FullMode "cox_parallel" }
    4 { Invoke-FullMode "select"; Invoke-FullMode "train"; Invoke-FullMode "evaluate" }
    5 { Invoke-FullMode "cmr_parallel" }
    6 { Invoke-FullMode "mr_prepare"; Invoke-FullMode "mr_run" }
    7 { Invoke-FullMode "mediation_prepare"; Invoke-FullMode "mediation_run" }
    8 { Invoke-FullMode "mediation_cmest_pilot"; Invoke-FullMode "mediation_cmest_parallel" }
    9 { Invoke-PrsAll }
    10 { Invoke-FullMode "figure6_systems" }
    11 {
      Assert-FinalFigureInputs
      Invoke-FullMode "figures"
      Invoke-FullMode "systems_figures"
      Invoke-FullMode "report"
      Assert-FinalFigurePackage
    }
    default { throw "Unsupported step: $Id" }
  }
}

function Assert-FinalFigureInputs {
  $required = @(
    (Join-Path $AnalysisDir "14_enrichment/enrichment_results.csv"),
    (Join-Path $AnalysisDir "14_enrichment/local_cox_systems/figure6c_cvd_protein_tf_edges.csv"),
    (Join-Path $AnalysisDir "14_enrichment/local_cox_systems/figure6d_main_cluster_nodes.csv"),
    (Join-Path $AnalysisDir "14_enrichment/local_cox_systems/figure6d_main_cluster_edges.csv.gz"),
    (Join-Path $AnalysisDir "15_figures/figure6a_local_prs_protein_heatmap.png")
  )
  $missing = @($required | Where-Object { -not (Test-Path $_ -PathType Leaf) })
  if ($missing.Count -gt 0) {
    throw "Final Figure 1-6 inputs are incomplete. Run -Step finalize (or 10-11) after Steps 1-9. Missing:`n$($missing -join "`n")"
  }
}

function Assert-FinalFigurePackage {
  $prefixes = @(
    "figure1_workflow",
    "figure2_incident_protein_associations",
    "figure3_local_cmr",
    "figure4_prediction_and_importance",
    "figure5_local_mr_and_mediation",
    "figure6abcd_local_systems_biology"
  )
  $missing = @()
  foreach ($prefix in $prefixes) {
    foreach ($extension in @("pdf", "png", "tiff")) {
      $path = Join-Path $AnalysisDir ("15_figures/{0}.{1}" -f $prefix, $extension)
      if (-not (Test-Path $path -PathType Leaf) -or (Get-Item $path).Length -le 0) { $missing += $path }
    }
  }
  $report = Join-Path $AnalysisDir "17_report/RESULTS_AND_QC.md"
  if (-not (Test-Path $report -PathType Leaf) -or (Get-Item $report).Length -le 0) { $missing += $report }
  if ($missing.Count -gt 0) {
    throw "Final deliverable validation failed; missing or empty files:`n$($missing -join "`n")"
  }
  Write-Host "FINAL FIGURE PACKAGE PASS | Figures 1-6 available as PDF, PNG and TIFF."
}

$stepMode = $Step.Trim().ToLowerInvariant()
if ($stepMode -eq "help") {
  Show-StepHelp
  exit 0
}

if ($stepMode -eq "paths") {
  Show-ResolvedPlan @()
  if (Test-Path $PathConfig -PathType Leaf) {
    Write-Host "`nSaved local path profile"
    Get-Content $PathConfig
  } else {
    Write-Host "`nNo saved local path profile yet. Missing paths will be requested on the first run."
  }
  exit 0
}

if ($stepMode -eq "setup") {
  $SetupSteps = @(1, 2, 3, 4)
  Resolve-SelectedInputPaths $SetupSteps
  Save-ResolvedPathProfile $SetupSteps
  Show-ResolvedPlan @()
  Write-Host "`nPath setup complete. No analysis was started."
  exit 0
}

if ($stepMode -eq "install") {
  if (-not (Test-Path $InstallRunner -PathType Leaf)) { throw "Dependency installer not found: $InstallRunner" }
  & $InstallRunner -RscriptExe $RscriptExe -PythonExe $PythonExe -CondaExe $CondaExe
  exit $LASTEXITCODE
}

if ($stepMode -eq "package") {
  if (-not (Test-Path $PackageRunner -PathType Leaf)) { throw "Package runner not found: $PackageRunner" }
  & $PackageRunner -ProjectDir $ProjectDir
  exit $LASTEXITCODE
}

if (-not (Test-Path $FullRunner -PathType Leaf)) { throw "Full runner not found: $FullRunner" }
if (-not (Test-Path $PrsRunner -PathType Leaf)) { throw "PRS runner not found: $PrsRunner" }

if ($stepMode -eq "status") {
  Invoke-FullMode "monitor"
  & $PrsRunner -Mode monitor -Dir0 $Dir0 -AnalysisRoot $AnalysisRoot -AnalysisProject $AnalysisProject
  exit 0
}

if ($stepMode -eq "doctor") {
  $DoctorSteps = @(1, 2, 3, 4)
  Resolve-SelectedInputPaths $DoctorSteps
  Show-ResolvedPlan $DoctorSteps
  Invoke-FullMode "doctor"
  exit $LASTEXITCODE
}

$SelectedSteps = @(Resolve-Steps $Step)
if ($SelectedSteps.Count -eq 0) { throw "No steps selected." }
$RequestedDiseases = @(Get-RequestedDiseases)
$Disease = if ($Disease.Trim().ToLowerInvariant() -eq "all") { "all" } else { $RequestedDiseases -join "," }
Resolve-SelectedInputPaths $SelectedSteps
if (-not $PlanOnly) { Save-ResolvedPathProfile $SelectedSteps }
Assert-ModelPanelRequest
Show-ResolvedPlan $SelectedSteps
if ($PlanOnly) { exit 0 }

if (($Disease -ne "all" -or $ProteinPanel -ne "local_reselected") -and $AnalysisProject -eq "yu_proteomic_repo_v3") {
  throw "The frozen yu_proteomic_repo_v3 project is protected. Use a new -AnalysisProject for disease-specific or alternate-panel runs."
}

if ((8 -in $SelectedSteps -or 9 -in $SelectedSteps) -and -not $ConfirmHeavy) {
  throw "Steps 8 and 9 are long-running. Review with -PlanOnly, then add -ConfirmHeavy."
}

$fullInputSteps = @(1, 2, 3, 4, 5, 7)
if (@($SelectedSteps | Where-Object { $_ -in $fullInputSteps }).Count -gt 0) {
  Assert-File $RawProteinFile "Unimputed protein table"
  Assert-File $PhenotypeRds "Phenotype RDS"
  Assert-File $RawPhenotypeFile "Raw phenotype file"
  Assert-File $PanelMappingFile "Protein mapping file"
}
if (9 -in $SelectedSteps) {
  Assert-File $RawProteinFile "Unimputed protein table"
  Assert-File $PhenotypeRds "Phenotype RDS"
}
if (5 -in $SelectedSteps) { Assert-File $CmrFeatureFile "CMR feature table" }
if (6 -in $SelectedSteps -and -not (Test-Path $PqtlRoot -PathType Container)) {
  throw "pQTL root not found: $PqtlRoot"
}

$LogDir = Join-Path $AnalysisDir "00_logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
$StateFile = Join-Path $LogDir ("step_runner_{0}.json" -f $RunId)
$State = [ordered]@{
  run_id = $RunId
  status = "RUNNING"
  requested = $Step
  selected_steps = @($SelectedSteps)
  completed_steps = @()
  current_step = $null
  started_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  ended_at = $null
  dir0 = $Dir0
  project_dir = $ProjectDir
  analysis_root = $AnalysisRoot
  analysis_dir = $AnalysisDir
  disease = $Disease
  disease_ids = @($RequestedDiseases)
  prediction_panel_mode = $ProteinPanel
  model_protein_file = $ModelProteinFile
  model_proteins_inline = $ModelProteins
  figure4_extra_project = $Figure4ExtraProject
  figure4_extra_outcome = $Figure4ExtraOutcome
  figure4_extra_label = $Figure4ExtraLabel
  raw_protein_file = $RawProteinFile
  phenotype_rds = $PhenotypeRds
  raw_phenotype_file = $RawPhenotypeFile
  panel_mapping_file = $PanelMappingFile
  supplement_workbook_file = $SupplementWorkbookFile
  supplement_methods_file = $SupplementMethodsFile
  olink_processing_start_date_file = $OlinkProcessingStartDateFile
  cmr_feature_file = $CmrFeatureFile
  pqtl_root = $PqtlRoot
  windows_nas_root = $WindowsNasRoot
  rscript_exe = $RscriptExe
  python_exe = $PythonExe
  path_prompt_mode = $PathPromptMode
  yys_score_mode = "off"
  error = $null
}

function Save-State {
  $State | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $StateFile
}

Save-State
try {
  foreach ($id in $SelectedSteps) {
    $definition = $StepCatalog | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    $State.current_step = $id
    Save-State
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | STEP $id START | $($definition.Name)"
    Invoke-Step $id
    $State.completed_steps = @($State.completed_steps) + $id
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | STEP $id DONE | $($definition.Name)"
    Save-State
  }
  $State.status = "PASS"
  $State.current_step = $null
  $State.ended_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  Save-State
} catch {
  $State.status = "ERROR"
  $State.error = $_.Exception.Message
  $State.ended_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  Save-State
  throw
}

Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | COMPLETE | steps=$($SelectedSteps -join ',') | analysis=$AnalysisDir"
Write-Host "State: $StateFile"
