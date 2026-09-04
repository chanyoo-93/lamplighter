# Lamplighter

Claude Code의 5시간 사용량 창을 매일 정해진 시각에 시작시키는 Windows 작업 스케줄러용 PowerShell 스크립트.

가로등 점등원(lamplighter)이 정해진 시각에 등을 켜듯, 예약된 시각에 `claude -p 'Hi'` 한 번을 보내 창을 "켠다".

## 왜 필요한가

Claude Code의 사용량 한도는 첫 메시지를 보낸 시점부터 5시간 단위 창으로 계산된다. 창이 언제 시작되느냐가 곧 언제 리셋되느냐를 결정하므로, 아침 첫 사용 시각이 들쭉날쭉하면 리셋 시각도 매일 달라진다.

Lamplighter는 이렇게 맞춘다.

| 점등 시각 | 창 |
|---|---|
| 07:00 | 07:00 ~ 12:00 |
| 12:01 | 12:01 ~ 17:01 |

근무 시간이 두 개의 창으로 빈틈없이 덮인다.

## 구성

| 경로 | 역할 |
|---|---|
| `lamp.ps1` | 스크립트 본체 |
| `%LOCALAPPDATA%\Lamplighter\lamp.log` | 실행 로그 |
| `%LOCALAPPDATA%\Lamplighter\state.txt` | 마지막 성공 기록. 형식은 `날짜\|슬롯\|성공시각(ISO 8601)` |

## 동작

1. 현재 시각으로 슬롯을 정한다. 12시 이전은 `am`, 이후는 `pm`.
2. `state.txt`를 읽어 마지막 성공을 확인한다.
3. 오늘 같은 슬롯을 이미 켰으면 `SKIP … already lit`으로 종료한다.
4. 마지막 성공 후 4시간 50분이 지나지 않았으면 `SKIP … deferred`로 종료한다. 이전 창이 아직 열려 있어 지금 보내도 새 창이 시작되지 않기 때문이다. 이때는 상태를 갱신하지 않으므로 다음 트리거에서 다시 시도한다.
5. PATH에서 `claude`를 찾아 `claude -p 'Hi'`를 실행한다.
6. 성공하면 `state.txt`를 갱신하고 응답 앞 100자를 로그에 남긴다. 실패하면 종료 코드와 출력 전체를 로그에 남긴다.

4시간 50분은 5시간에서 10분을 뺀 값이다. 07:00 실행이 부팅 지연 등으로 몇 분 늦어져도 12:01 실행이 막히지 않도록 둔 여유다.

종료 코드는 정상 처리와 SKIP이 0, `claude`를 찾지 못하면 1, 그 외에는 `claude`의 종료 코드를 그대로 돌려준다.

### 로그 형식

```
2026-09-07 07:00:04  OK    am  Hello! How can I help you today?
2026-09-07 07:00:31  SKIP  am already lit
2026-09-08 12:01:03  SKIP  pm deferred, only 4.6h since last lighting
2026-09-09 07:00:02  FAIL  am  exit=1  (claude 출력 전체)
```

## 요구 사항

- Windows 10/11, Windows PowerShell 5.1 (`powershell.exe`)
- Claude Code CLI가 PATH에 있고 로그인된 상태. 터미널에서 `claude -p 'Hi'`가 성공해야 한다.

## 설치

### 1. 스크립트 위치

이 저장소를 원하는 곳에 둔다. 아래 예시는 `C:\cyu\my-lab\lamplighter` 기준이다.

### 2. 예약 작업 등록

관리자 권한 없이 현재 사용자로 등록한다. 이미 등록된 작업이 있으면 `-Force`가 덮어쓴다.

```powershell
$dir = 'C:\cyu\my-lab\lamplighter'

$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dir\lamp.ps1`"" `
    -WorkingDirectory $dir

$days = 'Monday','Tuesday','Wednesday','Thursday','Friday'
$triggers = @(
    (New-ScheduledTaskTrigger -Weekly -DaysOfWeek $days -At '07:00'),
    (New-ScheduledTaskTrigger -Weekly -DaysOfWeek $days -At '12:01')
)

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -WakeToRun `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName 'Lamplighter' `
    -Action $action -Trigger $triggers -Settings $settings -Force
```

`-Argument` 값은 반드시 하나의 문자열로 묶어야 한다. 따옴표 없이 나열하면 위치 인수로 해석되어 `-NoProfile …` 부분이 WorkingDirectory에 들어가는 식으로 깨진다.

노트북에서 배터리 사용 중에도 실행하려면 `New-ScheduledTaskSettingsSet`에 `-AllowStartIfOnBatteries -DontStopIfGoingOnBatteries`를 추가한다. 기본값은 배터리 사용 중 실행 금지다.

### 3. 확인

```powershell
(Get-ScheduledTask -TaskName Lamplighter).Actions | Format-List Execute, Arguments, WorkingDirectory
Get-ScheduledTaskInfo -TaskName Lamplighter | Format-List LastRunTime, LastTaskResult, NextRunTime
```

바로 한 번 실행해 보려면 다음을 쓴다. 실제로 `claude`에 메시지를 보내므로 지금 시각 기준으로 창이 시작된다.

```powershell
Start-ScheduledTask -TaskName Lamplighter
Get-Content "$env:LOCALAPPDATA\Lamplighter\lamp.log"
```

### 옵션: 같은 날 재시도

트리거가 하루 두 번뿐이므로 `deferred`된 슬롯은 그날 다시 시도되지 않는다. 예를 들어 07:00 실행이 07:30으로 밀리면 12:01 실행은 간격 부족으로 넘어가고, 오후 창은 사용자의 첫 메시지 시각에 시작된다.

같은 날 재시도를 원하면 등록 전에 트리거에 반복을 붙인다. 스크립트는 반복 실행에 안전하도록 짜여 있어 이미 켠 슬롯은 `SKIP`으로 끝난다.

```powershell
$rep = New-ScheduledTaskTrigger -Once -At '12:01' `
    -RepetitionInterval (New-TimeSpan -Minutes 10) `
    -RepetitionDuration (New-TimeSpan -Hours 1)
$triggers[1].Repetition = $rep.Repetition   # 12:01 트리거를 10분마다 1시간 동안 반복
```

## 수동 실행

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\lamp.ps1
```

## 주의 사항

- **인코딩**: `lamp.ps1`은 UTF-8 with BOM으로 저장해야 한다. BOM이 없으면 `powershell.exe`가 파일을 ANSI(CP949)로 읽어 한글 주석이 다음 줄을 삼키고, 스크립트가 구문 오류로 실행되지 않는다.
- **로그온 상태**: 작업은 사용자가 로그온한 경우에만 실행되는 방식으로 등록된다. 화면이 잠겨 있어도 실행되지만 로그오프 상태에서는 실행되지 않는다.
- **놓친 실행**: 컴퓨터가 꺼져 있거나 절전 상태여서 놓친 실행은 켜진 뒤 바로 실행된다(`StartWhenAvailable`). 절전 상태에서는 깨워서 실행한다(`WakeToRun`).
- **시간대**: 시스템 로컬 시간을 기준으로 동작한다.

## 제거

```powershell
Unregister-ScheduledTask -TaskName Lamplighter -Confirm:$false
Remove-Item "$env:LOCALAPPDATA\Lamplighter" -Recurse -Force
```
