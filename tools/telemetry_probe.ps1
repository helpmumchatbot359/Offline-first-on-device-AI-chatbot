# telemetry_probe.ps1
#
# WHAT THIS DOES (beginner friendly)
# ----------------------------------
# It talks to the real backend, using YOUR login, and sends the exact telemetry
# shapes the app sends. Then it prints the HTTP status and the server's reply.
#
# Why: the phone cannot tell you why a row is missing if the server never
# explains. This script makes the server speak.
#
# HOW TO RUN
# ----------
#   $env:PROBE_EMAIL="lily@example.com"
#   $env:PROBE_PASSWORD="your-password"
#   powershell -ExecutionPolicy Bypass -File tools/telemetry_probe.ps1
#
# Optional:
#   powershell -ExecutionPolicy Bypass -File tools/telemetry_probe.ps1 -BaseUrl "https://..." -ApiKey "..."
#
# NOTE: every request body is written to a temp file and sent with curl
# "--data-binary @file". That avoids a Windows PowerShell bug where quotes
# inside an argument are stripped, which makes the server answer
# "Invalid JSON body".

param(
  [string]$BaseUrl = "https://d2g5avlpkj63xl.cloudfront.net",
  [string]$ApiKey = "Z1j4FUC6aFx3",
  [string]$Email = $env:PROBE_EMAIL,
  [string]$Password = $env:PROBE_PASSWORD,
  [string]$ChatId = "user-probe-chat"
)

$ErrorActionPreference = "Stop"
$BaseUrl = $BaseUrl.TrimEnd("/")

if ([string]::IsNullOrWhiteSpace($Email) -or [string]::IsNullOrWhiteSpace($Password)) {
  Write-Host ""
  Write-Host "Missing login." -ForegroundColor Yellow
  Write-Host 'Set it first, e.g.:'
  Write-Host '  $env:PROBE_EMAIL="your@email.com"'
  Write-Host '  $env:PROBE_PASSWORD="your-password"'
  Write-Host 'Then run this script again.'
  exit 1
}

if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
  Write-Host "curl.exe was not found. It ships with Windows 10/11." -ForegroundColor Red
  exit 1
}

$workDir = Join-Path $env:TEMP "telemetry_probe"
New-Item -ItemType Directory -Force -Path $workDir | Out-Null

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$date  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

# Write UTF-8 WITHOUT BOM (a BOM would also make the server say "Invalid JSON").
function Write-BodyFile {
  param([string]$Name, [string]$Json)
  $path = Join-Path $workDir $Name
  [System.IO.File]::WriteAllText($path, $Json, (New-Object System.Text.UTF8Encoding($false)))
  return $path
}

function Send-Json {
  param(
    [string]$Name,
    [string]$Url,
    [string]$Json,
    [string]$Token
  )

  $bodyFile = Write-BodyFile "$([guid]::NewGuid().ToString('N')).json" $Json
  $respFile = Join-Path $workDir "response.txt"

  $curlArgs = @(
    "-sS",
    "-o", $respFile,
    "-w", "%{http_code}",
    "-X", "POST", $Url,
    "-H", "X-API-KEY: $ApiKey",
    "-H", "Content-Type: application/json",
    "--data-binary", "@$bodyFile"
  )
  if (-not [string]::IsNullOrWhiteSpace($Token)) {
    $curlArgs += @("-H", "Authorization: Bearer $Token")
  }

  $code = (& curl.exe @curlArgs | Out-String).Trim()
  $text = if (Test-Path $respFile) { Get-Content -Raw $respFile } else { "" }

  $color = "Red"
  if ($code -eq "200" -or $code -eq "201") { $color = "Green" }

  Write-Host ""
  Write-Host "== $Name" -ForegroundColor Cyan
  Write-Host "HTTP $code" -ForegroundColor $color
  if ([string]::IsNullOrWhiteSpace($text)) {
    Write-Host "(empty reply)"
  } else {
    Write-Host $text.Trim()
  }
  return $code
}

# ---------------------------------------------------------------------------
# 1) Login -> JWT (the same token the app stores)
# ---------------------------------------------------------------------------
Write-Host "Logging in as $Email ..."

$loginJson = [ordered]@{ email = $Email; password = $Password } | ConvertTo-Json -Compress
$loginCode = Send-Json "LOGIN" "$BaseUrl/user/login" $loginJson ""

$loginText = Get-Content -Raw (Join-Path $workDir "response.txt")
if ($loginCode -ne "200") {
  Write-Host ""
  Write-Host "Login failed (HTTP $loginCode)." -ForegroundColor Red
  exit 1
}

try {
  $token = ($loginText | ConvertFrom-Json).access_token
} catch {
  $token = $null
}
if ([string]::IsNullOrWhiteSpace($token)) {
  Write-Host "Login replied without access_token:" -ForegroundColor Red
  Write-Host $loginText
  exit 1
}
Write-Host "Got a token ($($token.Length) characters)." -ForegroundColor Green

# ---------------------------------------------------------------------------
# 2) PROBE A - the shape from test_api.sh (known-good baseline)
#    If this fails, the problem is NOT the app payload; it is the account,
#    the endpoint, or the network.
# ---------------------------------------------------------------------------
$probeA = @"
[{"event_uuid":"event-probe-A-$stamp","event_type":"offline_started","chat_id":"$ChatId","date":"$date","connectivity":"offline","metadata":{"previous_connectivity":"online","network_type":"wifi","source":"telemetry-probe"}}]
"@
$codeA = Send-Json "PROBE A: minimal offline_started (baseline)" "$BaseUrl/v1/telemetry" $probeA.Trim() $token

# ---------------------------------------------------------------------------
# 3) PROBE B - EXACTLY what this app now sends for an offline answer:
#    no null fields, device envelope included, full timing metadata.
# ---------------------------------------------------------------------------
$probeB = @"
[{"event_uuid":"event-probe-B-$stamp","event_type":"offline_inference","chat_id":"$ChatId","date":"$date","model_version":"gemma-4-e2b-mobile","latency_ms":12000,"outcome":"success","connectivity":"offline","metadata":{"device":{"manufacturer":"unknown","brand":"unknown","model":"unknown","device":"unknown","android_api":0,"android_release":"unknown","cpu_abi":"unknown","cpu_cores":0,"ram_total_mb":0,"ram_class":"unknown","backend":"cpu","platform":"android"},"memory":{"available_mb_at_start":1079,"total_mb":8192,"threshold_mb":200,"low_memory_at_start":false,"process_pss_mb_at_start":1200,"peak_process_pss_mb":1500,"available_mb_at_end":900,"process_pss_mb_at_end":1450},"thermal":{"status_at_start":2,"status_name_at_start":"moderate","headroom_at_start":0.4,"status_at_end":3,"status_name_at_end":"severe","headroom_at_end":0.2},"battery":{"percent":80,"temperature_c":31.5,"charging":false,"plugged":false},"tool_used":false,"retrieved_passage_count":0,"output_chars":512,"streamed":true,"model_load_ms":3900,"time_to_first_token_ms":1200,"time_to_first_token_from_request_ms":5100,"stream_duration_ms":10800,"generation_duration_ms":8100,"source":"telemetry-probe"}}]
"@
$codeB = Send-Json "PROBE B: full offline_inference with device envelope" "$BaseUrl/v1/telemetry" $probeB.Trim() $token

# ---------------------------------------------------------------------------
# 4) PROBE C - the OLD broken shape: a null optional field.
#    This proves whether the server refuses nulls (the original suspect).
#    Only sent when PROBE B worked, so it can never block a real row.
# ---------------------------------------------------------------------------
$codeC = "skipped"
if ($codeB -eq "200" -or $codeB -eq "201") {
  $probeC = @"
[{"event_uuid":"event-probe-C-$stamp","event_type":"offline_inference","chat_id":"$ChatId","date":"$date","model_version":"gemma-4-e2b-mobile","latency_ms":9000,"outcome":"success","error_code":null,"connectivity":"offline","metadata":{"tool_used":false,"retrieved_passage_count":0,"error_stage":null,"source":"telemetry-probe"}}]
"@
  $codeC = Send-Json "PROBE C: same event but WITH null fields (old app shape)" "$BaseUrl/v1/telemetry" $probeC.Trim() $token
}

# ---------------------------------------------------------------------------
# 5) Verdict
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "================ VERDICT ================" -ForegroundColor Cyan
Write-Host "PROBE A (baseline)        : HTTP $codeA"
Write-Host "PROBE B (app shape)       : HTTP $codeB"
Write-Host "PROBE C (with nulls)      : HTTP $codeC"
Write-Host ""
if (($codeB -eq "200" -or $codeB -eq "201")) {
  Write-Host "The server ACCEPTS the app's payload." -ForegroundColor Green
  Write-Host "=> The backend format is fine. The phone simply was not uploading."
  Write-Host "   The new 60-second retry + immediate upload fixes that."
} else {
  Write-Host "The server REFUSES the app's payload." -ForegroundColor Red
  Write-Host "=> Send the HTTP status and the reply above to the backend engineer."
  Write-Host "   That message names the field they want changed."
}
Write-Host ""
Write-Host "Probe event uuids (search for these in the telemetry table):"
Write-Host "  event-probe-A-$stamp"
Write-Host "  event-probe-B-$stamp"
Write-Host "  event-probe-C-$stamp  (only if sent)"
