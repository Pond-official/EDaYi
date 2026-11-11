# verify.ps1 - One-command pre-commit verification (task 13).
# Runs in sequence (fail fast on first broken gate):
#   1. Storage key contract check (task 11, tools/check_storage_keys.mjs)
#   2. DevEco Code Linter (code-linter.json5), gating on Error severity
#      (warnings are report-only; a small known-false-positive baseline is allowed)
#   3. Pond module unit tests (hypium) via the DevEco-bundled hvigorw
#
# Usage (repo root):
#   powershell -ExecutionPolicy Bypass -File scripts\verify.ps1
# Exit code 0 = all gates passed.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

# DevEco-bundled toolchain paths (no local hvigorw wrapper in this repo).
$NodeExe = 'C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe'
$HvigorwJs = 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js'
$TestResultFile = Join-Path $repoRoot 'products\Pond\.test\default\intermediates\test\coverage_data\test_result.txt'

# Known Code Linter Error-severity false positives (file base name + rule).
# Do not add entries without a written justification in docs/开发规范.md.
$KnownLintErrors = @(
  # requestEnableNotification has callback+Promise dual overloads in the SDK;
  # the eslint parser resolves the void overload, so `await` is flagged although
  # the Promise form exists and the await is valid. Recorded, not fixed (工单铁律).
  'ReminderScheduler.ets|@typescript-eslint/await-thenable'
)

$failed = $false

function Write-Step($msg) { Write-Host ''; Write-Host "==== $msg ====" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[PASS] $msg" -ForegroundColor Green }
function Write-Bad($msg)  { Write-Host "[FAIL] $msg" -ForegroundColor Red }

# ---- Gate 1: storage key contract (task 11) -------------------------------
Write-Step 'Gate 1/3: storage key contract (node tools/check_storage_keys.mjs)'
& node 'tools\check_storage_keys.mjs'
if ($LASTEXITCODE -ne 0) {
  Write-Bad 'storage key contract violated - register the key in constants/StorageKeys.ets'
  $failed = $true
} else {
  Write-Ok 'storage key contract'
}
if ($failed) { exit 1 }

# ---- Gate 2: Code Linter (Error severity gate, warnings report-only) -------
Write-Step 'Gate 2/3: DevEco Code Linter (code-linter.json5)'
$lintJson = Join-Path $env:TEMP "verify-lint-$PID.json"
if (Test-Path $lintJson) { Remove-Item $lintJson -Force }
& devecocli check lint --format json --output-path $lintJson
if (-not (Test-Path $lintJson)) {
  Write-Bad 'Code Linter produced no report file'
  exit 1
}
$lintReport = Get-Content $lintJson -Raw | ConvertFrom-Json
Remove-Item $lintJson -Force
$lintErrors = @()
$lintWarnings = @()
foreach ($issue in $lintReport.issues) {
  $basename = Split-Path -Leaf $issue.file
  $signature = "$basename|$($issue.rule)"
  if ($issue.severity -eq 'Error') {
    if ($KnownLintErrors -notcontains $signature) { $lintErrors += $issue }
  } else {
    $lintWarnings += $issue
  }
}
Write-Host ("Code Linter: {0} issue(s) total, {1} new error(s), {2} warning(s) (report-only)" -f `
  $lintReport.summary.issues, $lintErrors.Count, $lintWarnings.Count)
foreach ($w in $lintWarnings) {
  Write-Host ("  warn: {0}:{1} {2} {3}" -f (Split-Path -Leaf $w.file), $w.line, $w.rule, $w.message) `
    -ForegroundColor Yellow
}
foreach ($e in $lintErrors) {
  Write-Host ("  ERROR: {0}:{1} {2} {3}" -f (Split-Path -Leaf $e.file), $e.line, $e.rule, $e.message) `
    -ForegroundColor Red
}
if ($lintErrors.Count -gt 0) {
  Write-Bad 'Code Linter reported new Error-severity issues'
  $failed = $true
} else {
  Write-Ok 'Code Linter (no new errors)'
}
if ($failed) { exit 1 }

# ---- Gate 3: unit tests (hypium, Pond module) ------------------------------
Write-Step 'Gate 3/3: unit tests (hypium, module Pond)'
& $NodeExe $HvigorwJs --mode module -p product=default -p module=Pond@default test
if ($LASTEXITCODE -ne 0) {
  Write-Bad 'hvigor test task failed'
  exit 1
}
if (-not (Test-Path $TestResultFile)) {
  Write-Bad "test result file not found: $TestResultFile"
  exit 1
}
$summaryLine = (Get-Content $TestResultFile | Where-Object { $_ -match '^Tests run:' } | Select-Object -Last 1)
Write-Host $summaryLine
if ($summaryLine -match 'Tests run: (\d+), Failure: (\d+), Error: (\d+), Pass: (\d+)') {
  $run = [int]$Matches[1]; $failureCount = [int]$Matches[2]; $errorCount = [int]$Matches[3]; $pass = [int]$Matches[4]
  if ($failureCount -eq 0 -and $errorCount -eq 0 -and $pass -eq $run -and $run -gt 0) {
    Write-Ok "unit tests ($pass/$run)"
    Write-Host ''
    Write-Host 'All gates passed.' -ForegroundColor Green
    exit 0
  }
  Write-Bad 'unit tests did not fully pass'
  exit 1
}
Write-Bad 'could not parse test summary line'
exit 1
