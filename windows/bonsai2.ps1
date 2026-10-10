# Bonsai 2 27B on Windows: start the model, or check its speed.
#   start-bonsai.bat  runs  bonsai2.ps1 start   the chat page at http://127.0.0.1:8080
#   bench-bonsai.bat  runs  bonsai2.ps1 bench   a results block, saved next to this file and copied to the clipboard
#   bonsai2.ps1 print                           shows the server command lines and changes nothing
# install.ps1 from github.com/sudoingX/bonsai2-small-gpu puts this file here, with its settings in bonsai2.json.
param([string]$Mode = 'start')

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$inv  = [Globalization.CultureInfo]::InvariantCulture
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg  = Get-Content (Join-Path $here 'bonsai2.json') -Raw | ConvertFrom-Json
$exe  = Join-Path $here "$($cfg.build)\bin\llama-server.exe"
$smi  = "$env:SystemRoot\System32\nvidia-smi.exe"
if (-not (Test-Path $smi)) { $c = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue; if ($c) { $smi = $c.Source } }

$env:CUDA_DEVICE_ORDER = 'PCI_BUS_ID'
$env:CUDA_VISIBLE_DEVICES = "$($cfg.gpuIndex)"
$env:GGML_CUDA_BATCH_INVARIANT = '1'

function Get-VramMiB([string]$field) {
    if ($env:BONSAI_FAKE_FREE -and $field -eq 'memory.free') { return [int]$env:BONSAI_FAKE_FREE }
    $v = & $smi "--query-gpu=$field" --format=csv,noheader,nounits -i "$($cfg.gpuIndex)"
    return [int]("$(@($v)[0])".Trim())
}

# 8 GB cards: --fit is too careful with the lean file (it stops at 16K), so pick the window from free VRAM.
# The lean file with the head uses about 7,150 MiB at 16K and 7,900 MiB at 64K (sweeps/rtx3000Ada-8gb.md).
function Get-Context8gb {
    $free = Get-VramMiB 'memory.free'
    if ($free -ge 7950) { return 65536 }
    if ($free -ge 7700) { return 49152 }
    if ($free -ge 7450) { return 32768 }
    return 16384
}

# start mode serves on 127.0.0.1 unless BONSAI_HOST says otherwise (0.0.0.0 = your network, set BONSAI_API_KEY with it)
function Get-ServerArgs([int]$port, [bool]$head, [bool]$chat) {
    $bindHost = if ($chat -and $env:BONSAI_HOST) { $env:BONSAI_HOST } else { '127.0.0.1' }
    $a = @('-m', (Join-Path $here "models\$($cfg.model)"), '-ngl', '99', '-fa', 'on', '-np', '1', '-ctk', 'q4_0', '-ctv', 'q4_0', '--jinja',
           '--alias', 'bonsai-2-27b', '--host', $bindHost, '--port', "$port")
    if ($chat -and $env:BONSAI_API_KEY) { $a += @('--api-key', $env:BONSAI_API_KEY) }
    if ($cfg.mmproj) { $a += @('--mmproj', (Join-Path $here "models\$($cfg.mmproj)")) }
    if ($cfg.tier -eq '8gb') { $a += @('-c', "$(Get-Context8gb)", '--fit', 'off') }
    else { $a += @('--fit', 'on', '--fit-target', '1024', '--fit-ctx', '16384') }
    if ($head) { $a += @('--spec-type', 'draft-mtp', '--spec-draft-n-max', "$($cfg.nmax)") }
    if ($chat) { $a += @('--reasoning-effort', 'medium', '--temp', '1.0', '--top-p', '0.95', '--top-k', '20') }
    return ,$a
}

function Join-Args($a) {
    ($a | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
}

$port = [int]$cfg.port
if ($env:BONSAI_PORT) { $port = [int]$env:BONSAI_PORT }

if ($Mode -eq 'print') {
    Write-Host ('start: "{0}" {1}' -f $exe, (Join-Args (Get-ServerArgs $port $true $true)))
    Write-Host ('bench: "{0}" {1}' -f $exe, (Join-Args (Get-ServerArgs 8091 $true $false)))
    return
}

if ($Mode -eq 'start') {
    if (Get-Process llama-server -ErrorAction SilentlyContinue) {
        Write-Host 'Bonsai is already running, opening the chat page.'
        Start-Process "http://127.0.0.1:$port"
        return
    }
    Write-Host 'Bonsai 2 27B is loading, the chat page opens in your browser when it is ready.' -ForegroundColor Cyan
    Write-Host "Chat page:       http://127.0.0.1:$port"
    Write-Host "API for agents:  http://127.0.0.1:$port/v1  (OpenAI compatible, model bonsai-2-27b, any API key unless you set BONSAI_API_KEY)"
    Write-Host 'Close this window to stop it.'
    Write-Host ''
    $poll = "for(`$i=0;`$i -lt 900;`$i++){try{`$null=Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 http://127.0.0.1:$port/health;Start-Process http://127.0.0.1:$port;break}catch{Start-Sleep 1}}"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($poll))
    Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile -EncodedCommand $enc"
    $ErrorActionPreference = 'Continue'
    $a = Get-ServerArgs $port $true $true
    & $exe @a
    return
}

if ($Mode -ne 'bench') { Write-Host "Unknown mode $Mode, use start, bench or print."; return }

# ---- bench: the same checks as the Linux sweeps, head on then head off ----
if (Get-Process llama-server -ErrorAction SilentlyContinue) {
    Write-Host 'Bonsai is already running, close its window first, then run the speed check again.' -ForegroundColor Red
    return
}
$bport = 8091
$base = "http://127.0.0.1:$bport"
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
Write-Host 'Bonsai 2 27B speed check, about 3 to 5 minutes. Close games and video apps first.' -ForegroundColor Cyan

function Start-Server([bool]$head) {
    $tag = if ($head) { 'head' } else { 'nohead' }
    $log = Join-Path $here "bench-server-$tag.log"
    $p = Start-Process -FilePath $exe -ArgumentList (Join-Args (Get-ServerArgs $bport $head $false)) -NoNewWindow -PassThru `
        -RedirectStandardError $log -RedirectStandardOutput "$log.out"
    for ($i = 0; $i -lt 900; $i++) {
        if ($p.HasExited) { throw "the server stopped while loading, the reason is at the end of $log" }
        try { $null = Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 "$base/health"; return $p } catch { Start-Sleep 1 }
    }
    throw "the server did not come up in 15 minutes, see $log"
}
function Stop-Server($p) {
    if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force; $null = $p.WaitForExit(30000) }
    Start-Sleep 2
}
function Ask([object[]]$messages, [int]$max) {
    $body = @{ messages = $messages; max_tokens = $max; temperature = 0; top_k = 1; seed = 42; chat_template_kwargs = @{ enable_thinking = $false } } | ConvertTo-Json -Depth 12
    $r = Invoke-RestMethod -Method Post -Uri "$base/v1/chat/completions" -ContentType 'application/json; charset=utf-8' `
        -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 1800
    [pscustomobject]@{ Text = [string]$r.choices[0].message.content; TokS = [double]$r.timings.predicted_per_second
                       DraftN = [int]$r.timings.draft_n; DraftOk = [int]$r.timings.draft_n_accepted }
}
function Get-Median([double[]]$x) {
    $s = @($x | Sort-Object); $n = $s.Count
    if ($n % 2) { return $s[[int][math]::Floor($n / 2)] }
    return ($s[$n / 2 - 1] + $s[$n / 2]) / 2
}
function Format-TokS([double]$v) { $v.ToString('0.0', $inv) }

$identity = 'Explain in about 150 words why speculative decoding with a multi-token prediction head can be lossless under greedy decoding.'
$speed = 'Write a detailed explanation of how a GPU runs a matrix-vector multiply: memory bandwidth, warps, caching and why decode is bandwidth bound.'
$img = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $here 'vision_check.png')))
$visionMsg = @(@{ role = 'user'; content = @(
    @{ type = 'image_url'; image_url = @{ url = "data:image/png;base64,$img" } },
    @{ type = 'text'; text = "This chart has a group called 'fresh chat' with three bars. Give the three tok/s values as JSON with keys stock, kernel, kernel_plus_head. Only the JSON." }) })

$before = Get-VramMiB 'memory.used'
$res = @{}
$p = $null
try {
    foreach ($head in @($true, $false)) {
        $tag = if ($head) { 'on' } else { 'off' }
        Write-Host "Loading with the speed head $tag..."
        $p = Start-Server $head
        $ctx = (Invoke-RestMethod "$base/props").default_generation_settings.n_ctx
        $loaded = Get-VramMiB 'memory.used'
        Write-Host '  identity run'
        $id = Ask @(@{ role = 'user'; content = $identity }) 400
        $runs = @()
        foreach ($k in 1..3) { Write-Host "  speed run $k of 3"; $runs += Ask @(@{ role = 'user'; content = $speed }) 512 }
        $vis = $null
        if ($head -and $cfg.mmproj) { Write-Host '  vision check'; $vis = Ask $visionMsg 200 }
        $after = Get-VramMiB 'memory.used'
        $res[$tag] = @{ ctx = $ctx; loaded = $loaded; after = $after; id = $id; runs = $runs; vis = $vis }
        Stop-Server $p
        $p = $null
    }
} finally {
    if ($p) { Stop-Server $p }
}

$on = $res['on']; $off = $res['off']
$onT = @($on.runs | ForEach-Object { $_.TokS }); $offT = @($off.runs | ForEach-Object { $_.TokS })
$mOn = Get-Median $onT; $mOff = Get-Median $offT
$gain = [math]::Round(($mOn / $mOff - 1) * 100)
$sign = if ($gain -ge 0) { '+' } else { '' }
$dn = ($on.runs | Measure-Object -Property DraftN -Sum).Sum
$da = ($on.runs | Measure-Object -Property DraftOk -Sum).Sum
$same = if ($on.id.Text -ceq $off.id.Text) { 'yes' } else { 'NO' }
$os = Get-CimInstance Win32_OperatingSystem
$cpu = "$((Get-CimInstance Win32_Processor | Select-Object -First 1).Name)".Trim()
$ram = [math]::Round($os.TotalVisibleMemorySize / 1MB)
$visionNote = if ($cfg.mmproj) { ' + vision' } else { '' }
$lines = @(
    "Bonsai 2 27B, Windows speed check ($stamp, $($cfg.release))",
    "card: $($cfg.gpuName), $($cfg.gpuMiB) MiB, driver $($cfg.driver)",
    "system: $("$($os.Caption)".Trim()) $($os.Version), $cpu, $ram GB RAM",
    "build: $($cfg.build), tier $($cfg.tier), file $($cfg.model)$visionNote",
    "vram in use before start (desktop and other apps): $before MiB",
    "context: $($on.ctx) with the head, $($off.ctx) without",
    "vram with the head: $($on.loaded) MiB loaded, $($on.after) MiB after the runs",
    "speed with the head (mtp n-max $($cfg.nmax)): $(($onT | ForEach-Object { Format-TokS $_ }) -join ' / ') tok/s, median $(Format-TokS $mOn) tok/s, draft $da/$dn accepted",
    "speed without the head: $(($offT | ForEach-Object { Format-TokS $_ }) -join ' / ') tok/s, median $(Format-TokS $mOff) tok/s",
    "head gain: $sign$gain%",
    "same greedy text with and without the head: $same"
)
if ($on.vis) {
    $vals = @([regex]::Matches($on.vis.Text, '\d+(\.\d+)?') | ForEach-Object { [double]::Parse($_.Value, $inv) })
    $hits = @(25.0, 39.8, 50.1 | Where-Object { $want = $_; @($vals | Where-Object { [math]::Abs($_ - $want) -lt 0.05 }).Count -gt 0 }).Count
    $verdict = if ($hits -eq 3) { 'read right' } else { 'missed, it answered: ' + $on.vis.Text.Trim() }
    $lines += "vision check (fresh chat bars 25.0 / 39.8 / 50.1): $verdict"
}
$text = $lines -join "`r`n"
$file = Join-Path $here ('bonsai2-results-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmm'))
Set-Content -Path $file -Value $text -Encoding ASCII
try { Set-Clipboard -Value $text } catch { }
Write-Host ''
Write-Host $text
Write-Host ''
Write-Host "Saved to $file and copied to your clipboard." -ForegroundColor Green
Write-Host 'Share it: paste it in a reply to @sudoingX, or open a pull request with your row at github.com/sudoingX/bonsai2-small-gpu'
