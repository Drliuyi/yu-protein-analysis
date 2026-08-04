$ErrorActionPreference = "Stop"
$runner = Join-Path $PSScriptRoot "tools/run_yu_steps_windows.ps1"
if (-not (Test-Path $runner -PathType Leaf)) {
  throw "Yu step runner not found: $runner"
}
& $runner @args
