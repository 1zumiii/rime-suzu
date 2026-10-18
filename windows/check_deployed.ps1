# After redeploy: make sure the official spelling rules (esp. abbreviation rules) survived the patches.
# This is the Windows counterpart of tools/verify_build.sh (Weasel has no standalone rime_deployer).
param([string]$RimeDir = (Join-Path $env:APPDATA "Rime"))
$f = Join-Path $RimeDir "build\rime_ice.schema.yaml"
if (-not (Test-Path $f)) { Write-Host "FAIL: $f not found (not deployed yet?)"; exit 1 }
$lines = Get-Content -Encoding UTF8 $f
$inAlg = $false; $n = 0
foreach ($l in $lines) {
  if ($l -match '^  algebra:') { $inAlg = $true; continue }
  if ($inAlg) {
    if ($l -match '^  [a-z_]') { break }
    if ($l -match '^    - ') { $n++ }
  }
}
$abbrev = @($lines | Select-String -SimpleMatch '"abbrev/').Count
$official = 47   # number of official algebra rules in rime_ice.schema.yaml when this was written
if ($abbrev -lt 2 -or $n -lt $official) {
  Write-Host "FAIL: official spelling rules were overwritten (algebra=$n, official=$official, abbrev=$abbrev)"
  Write-Host "Check rime_ice.custom.yaml: never use __patch with a '/+' key; use '__include' instead."
  exit 1
}
# AI switches: when the LLM filter is enabled, ai_rerank and ai_stage2 must both be in the compiled schema.
# (Two lines with the same key such as "switches/@next" collapse into one in YAML; use a single "switches/+" list.)
$text = $lines -join "`n"
if ($text -match 'llm_filter|ai_rerank_filter') {
  foreach ($sw in @("ai_rerank", "ai_stage2")) {
    if ($text -notmatch "(?m)^\s+name: $sw\s*$") {
      Write-Host "FAIL: switch $sw is missing from the compiled schema (use one 'switches/+' list in rime_ice.custom.yaml)"
      exit 1
    }
  }
  Write-Host "OK: switches ai_rerank and ai_stage2 present"
}
Write-Host "OK: algebra=$n (official $official), abbrev=$abbrev"
