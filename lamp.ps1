# Lamplighter - Claude 5시간 사용량 창을 정해진 시각에 시작시킨다.
# 사용: powershell -NoProfile -ExecutionPolicy Bypass -File lamp.ps1

$ErrorActionPreference = 'Continue'

$Dir    = Join-Path $env:LOCALAPPDATA 'Lamplighter'
$Log    = Join-Path $Dir 'lamp.log'
$State  = Join-Path $Dir 'state.txt'
$MinGap = New-TimeSpan -Hours 4 -Minutes 50   # 이 시간이 안 지났으면 새 창이 안 열린다
New-Item -ItemType Directory -Force -Path $Dir | Out-Null

function Write-Log([string]$msg) {
    Add-Content -Path $Log -Encoding UTF8 -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)
}

$now   = Get-Date
$today = $now.ToString('yyyy-MM-dd')
$slot  = if ($now.Hour -lt 12) { 'am' } else { 'pm' }   # 07:00 = am, 12:01 = pm

# 이전 상태 읽기: "날짜|슬롯|성공시각"
$lastDate = ''; $lastSlot = ''; $lastTime = $null
if (Test-Path $State) {
    $parts = "$(Get-Content $State -Raw)".Trim() -split '\|'
    if ($parts.Count -eq 3) {
        $lastDate = $parts[0]
        $lastSlot = $parts[1]
        try { $lastTime = [datetime]::Parse($parts[2]) } catch { }
    }
}

# 1) 이 슬롯은 이미 처리했다
if ($lastDate -eq $today -and $lastSlot -eq $slot) {
    Write-Log "SKIP  $slot already lit"
    exit 0
}

# 2) 창이 아직 열려 있으면 지금 찍어도 새 창이 안 열린다 -> 상태를 남기지 않고 다음 트리거에서 다시 시도
if ($lastTime -and (($now - $lastTime) -lt $MinGap)) {
    Write-Log ("SKIP  {0} deferred, only {1:n1}h since last lighting" -f $slot, ($now - $lastTime).TotalHours)
    exit 0
}

$claude = (Get-Command claude -ErrorAction SilentlyContinue).Source
if (-not $claude) {
    Write-Log 'FAIL  claude not found on PATH'
    exit 1
}

$out  = & $claude -p 'Hi' 2>&1 | Out-String -Width 4096
$code = $LASTEXITCODE

if ($code -eq 0) {
    Set-Content -Path $State -Value ("{0}|{1}|{2}" -f $today, $slot, $now.ToString('o'))
    $head = ($out -replace '\s+', ' ').Trim()
    if ($head.Length -gt 100) { $head = $head.Substring(0, 100) }
    Write-Log "OK    $slot  $head"
    exit 0
} else {
    Write-Log "FAIL  $slot  exit=$code  $(($out -replace '\s+', ' ').Trim())"
    exit $code
}
