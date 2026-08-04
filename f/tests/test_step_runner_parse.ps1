param(
  [string]$ProjectDir = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

$ErrorActionPreference = "Stop"
$files = @(
  (Join-Path $ProjectDir "yu.ps1"),
  (Join-Path $ProjectDir "f/tools/run_yu_steps_windows.ps1"),
  (Join-Path $ProjectDir "f/tools/run_yu_full_reproduction_windows.ps1"),
  (Join-Path $ProjectDir "f/tools/run_yu_prs_windows.ps1"),
  (Join-Path $ProjectDir "f/tools/run_yu_yys_windows.ps1"),
  (Join-Path $ProjectDir "f/tools/run_yu_yys_v2_lightgbm_windows.ps1"),
  (Join-Path $ProjectDir "f/tools/install_yu_dependencies_windows.ps1"),
  (Join-Path $ProjectDir "f/tools/setup_yu_reproduction_python_windows.ps1"),
  (Join-Path $ProjectDir "f/tools/package_yu_project.ps1")
)

foreach ($file in $files) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile(
    $file,
    [ref]$tokens,
    [ref]$errors
  ) | Out-Null
  if ($errors.Count -gt 0) {
    $messages = @($errors | ForEach-Object { $_.Message }) -join "; "
    throw "PowerShell parse failed for $file`: $messages"
  }
}

Write-Host "YU STEP RUNNER POWERSHELL PARSE TEST PASSED"
