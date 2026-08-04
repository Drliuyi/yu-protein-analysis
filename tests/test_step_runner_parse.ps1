param(
  [string]$ProjectDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$files = @(
  (Join-Path $ProjectDir "yu.ps1"),
  (Join-Path $ProjectDir "tools/run_yu_steps_windows.ps1"),
  (Join-Path $ProjectDir "tools/package_yu_project.ps1")
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
