# Bonsai 2 27B on Windows, one line in PowerShell:
#   irm https://raw.githubusercontent.com/sudoingX/bonsai2-small-gpu/main/install.ps1 | iex
# It finds your NVIDIA card, picks the build and the model file for its VRAM, downloads them from
# Hugging Face, checks every SHA256, writes start-bonsai.bat, bench-bonsai.bat and a desktop
# shortcut, then starts the model and opens the chat page in your browser.
# Optional, set before the line: $env:BONSAI_DIR (default %USERPROFILE%\bonsai2), $env:BONSAI_PORT (default 8080).

function Install-Bonsai2 {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $inv = [Globalization.CultureInfo]::InvariantCulture

    $release = 'v1.2-windows'
    $ref     = if ($env:BONSAI_REF) { $env:BONSAI_REF } else { 'main' }
    $hf      = 'https://huggingface.co/sudoingx/Ternary-Bonsai-2-27B-PTQ1_0-MTP-GGUF/resolve/main'
    $prism   = 'https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/resolve/main'
    $hub     = "https://raw.githubusercontent.com/sudoingX/bonsai2-small-gpu/$ref"
    $dir     = if ($env:BONSAI_DIR) { $env:BONSAI_DIR } else { Join-Path $env:USERPROFILE 'bonsai2' }
    $port    = if ($env:BONSAI_PORT) { [int]$env:BONSAI_PORT } else { 8080 }
    $test    = [bool]$env:BONSAI_TEST   # CI only: skips the big downloads and the start

    $builds = @{
        rtx50   = @{ zip = 'bonsai2-small-gpu-windows-x64-cuda13.3-sm120-ff41412';     driver = 580.0;  cards = 'RTX 50' }
        rtx3040 = @{ zip = 'bonsai2-small-gpu-windows-x64-cuda12.4-sm86-sm89-ff41412'; driver = 551.61; cards = 'RTX 30 and 40' }
    }
    $mmproj    = 'Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf'
    $mmprojSha = '6807ede61d570bb86ba34b756a0fa109edc33668604de867c6ea6d8f1d631903'

    Write-Host ''
    Write-Host 'Bonsai 2 27B for small GPUs, Windows installer' -ForegroundColor Cyan
    Write-Host 'github.com/sudoingX/bonsai2-small-gpu'
    Write-Host ''

    # 1. the card (the one with the most VRAM if there are several)
    if ($env:BONSAI_FAKE_GPU) {
        $rows = @($env:BONSAI_FAKE_GPU)
    } else {
        $smi = $null
        $cmd = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
        if ($cmd) { $smi = $cmd.Source } elseif (Test-Path "$env:SystemRoot\System32\nvidia-smi.exe") { $smi = "$env:SystemRoot\System32\nvidia-smi.exe" }
        if (-not $smi) { Write-Host 'No NVIDIA driver found. Install the latest driver from nvidia.com, then run this again.' -ForegroundColor Red; return }
        $rows = @(& $smi --query-gpu=index,name,memory.total,driver_version,compute_cap --format=csv,noheader,nounits)
    }
    $gpus = foreach ($r in $rows) {
        $f = @($r.Split(',') | ForEach-Object { $_.Trim() })
        if ($f.Count -lt 5) { continue }
        [pscustomobject]@{ Index = [int]$f[0]; Name = $f[1]; MiB = [int]$f[2]; Driver = $f[3]; CC = [double]::Parse($f[4], $inv) }
    }
    $g = @($gpus) | Sort-Object MiB -Descending | Select-Object -First 1
    if (-not $g) { Write-Host 'Could not read the card from nvidia-smi.' -ForegroundColor Red; return }
    Write-Host ('Card:   {0}, {1} MiB, driver {2}' -f $g.Name, $g.MiB, $g.Driver)

    # 2. the build for this card
    if ($g.CC -ge 12.0) { $b = $builds.rtx50 }
    elseif ($g.CC -ge 8.6 -and $g.CC -lt 9.0) { $b = $builds.rtx3040 }
    else { Write-Host ('This card (compute {0}) is not covered by the prebuilt builds yet, they cover RTX 30, 40 and 50.' -f $g.CC.ToString($inv)) -ForegroundColor Red; return }
    $parts = $g.Driver.Split('.')
    $minor = if ($parts.Count -gt 1) { $parts[1] } else { '0' }
    $drv = [double]::Parse(($parts[0] + '.' + $minor), $inv)
    if ($drv -lt $b.driver) { Write-Host ('Driver {0} is too old for the {1} build. Update to {2} or newer from nvidia.com, then run this again.' -f $g.Driver, $b.cards, $b.driver.ToString($inv)) -ForegroundColor Red; return }

    # 3. the model file for this much VRAM
    if ($g.MiB -ge 15000)     { $tier = '16gb'; $model = 'Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf';      $vision = $true;  $nmax = 1 }
    elseif ($g.MiB -ge 11500) { $tier = '12gb'; $model = 'Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf';      $vision = $false; $nmax = 1 }
    elseif ($g.MiB -ge 7500)  { $tier = '8gb';  $model = 'Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf'; $vision = $false; $nmax = 2 }
    else { Write-Host ('Bonsai 2 27B needs a card with 8 GB or more, this one has {0} MiB.' -f $g.MiB) -ForegroundColor Red; return }
    $visionNote = if ($vision) { ', with vision' } else { '' }
    Write-Host ('Build:  {0} ({1})' -f $b.zip, $b.cards)
    Write-Host ('Model:  {0}, {1} tier{2}' -f $model, $tier, $visionNote)
    Write-Host ('Folder: {0}' -f $dir)
    Write-Host ''

    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'models') | Out-Null
    $root = [IO.Path]::GetPathRoot((Resolve-Path $dir).Path)
    $free = (New-Object IO.DriveInfo $root).AvailableFreeSpace
    if (-not $test -and $free -lt 10GB) { Write-Host ('Not enough disk space on {0}: about 10 GB is needed, {1:N1} GB is free.' -f $root, ($free / 1GB)) -ForegroundColor Red; return }

    function Invoke-Curl([string[]]$curlArgs) {
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = & curl.exe @curlArgs
        $rc = $LASTEXITCODE; $ErrorActionPreference = $old
        return @{ rc = $rc; out = $out }
    }
    function Get-Verified([string]$url, [string]$path, [string]$sha) {
        $leaf = Split-Path $path -Leaf
        if ((Test-Path $path) -and ((Get-FileHash $path -Algorithm SHA256).Hash.ToLower() -eq $sha)) { Write-Host "  ok    $leaf (already here)"; return }
        Write-Host "  get   $leaf"
        $r = Invoke-Curl @('-L', '--fail', '--retry', '5', '--retry-delay', '3', '-C', '-', '-o', "$path.part", $url)
        if ($r.rc -ne 0) { throw "download failed (curl $($r.rc)): $url, run the installer again to resume" }
        $h = (Get-FileHash "$path.part" -Algorithm SHA256).Hash.ToLower()
        if ($h -ne $sha) { Remove-Item "$path.part" -Force; throw "checksum mismatch for $leaf, the download was removed, run the installer again" }
        Move-Item "$path.part" $path -Force
        Write-Host "  ok    $leaf (sha256 checked)"
    }
    function Get-HubFile([string]$rel, [string]$out) {
        if ($env:BONSAI_HUB_DIR) { Copy-Item (Join-Path $env:BONSAI_HUB_DIR $rel) $out -Force; return }
        $r = Invoke-Curl @('-sL', '--fail', '-o', $out, "$hub/$rel")
        if ($r.rc -ne 0) { throw "could not fetch $rel from github" }
    }

    # 4. downloads, every file checked against its SHA256
    if (-not $test) {
        if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { Write-Host 'curl.exe is missing, this needs Windows 10 (1803) or newer.' -ForegroundColor Red; return }
        $sums = @{}
        $r = Invoke-Curl @('-sL', '--fail', "$hf/SHA256SUMS")
        if ($r.rc -ne 0) { throw 'could not read SHA256SUMS from Hugging Face' }
        foreach ($line in @($r.out)) { $p = "$line".Trim() -split '\s+', 2; if ($p.Count -eq 2) { $sums[$p[1].TrimStart('*')] = $p[0].ToLower() } }
        foreach ($need in @("$($b.zip).zip", $model)) { if (-not $sums.ContainsKey($need)) { throw "SHA256SUMS on Hugging Face has no line for $need" } }

        Write-Host 'Downloading from Hugging Face (about 8 GB the first time, it resumes if it stops):'
        $zipPath = Join-Path $dir "$($b.zip).zip"
        $exe = Join-Path $dir "$($b.zip)\bin\llama-server.exe"
        if (-not (Test-Path $exe)) {
            Get-Verified "$hf/$($b.zip).zip" $zipPath $sums["$($b.zip).zip"]
            Write-Host "  unzip $($b.zip).zip"
            $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            & tar.exe -xf $zipPath -C $dir
            $ErrorActionPreference = $old
            if (-not (Test-Path $exe)) { Expand-Archive -Path $zipPath -DestinationPath $dir -Force }
            if (-not (Test-Path $exe)) { throw "unzip failed, $exe is missing" }
            Remove-Item $zipPath -Force
        } else {
            Write-Host "  ok    $($b.zip) (already unpacked)"
        }
        Get-Verified "$hf/$model" (Join-Path $dir "models\$model") $sums[$model]
        if ($vision) { Get-Verified "$prism/$mmproj" (Join-Path $dir "models\$mmproj") $mmprojSha }
    }

    # 5. the launcher, its settings and the two .bat files
    Get-HubFile 'windows/bonsai2.ps1' (Join-Path $dir 'bonsai2.ps1')
    Get-HubFile 'prompts/vision_check.png' (Join-Path $dir 'vision_check.png')
    $cfg = [ordered]@{
        release  = $release
        build    = $b.zip
        tier     = $tier
        model    = $model
        mmproj   = $(if ($vision) { $mmproj } else { $null })
        nmax     = $nmax
        port     = $port
        gpuIndex = $g.Index
        gpuName  = $g.Name
        gpuMiB   = $g.MiB
        driver   = $g.Driver
        cc       = $g.CC.ToString($inv)
    }
    Set-Content -Path (Join-Path $dir 'bonsai2.json') -Value ($cfg | ConvertTo-Json) -Encoding ASCII
    $start = "@echo off`r`ntitle Bonsai 2 27B`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0bonsai2.ps1`" start`r`npause`r`n"
    $bench = "@echo off`r`ntitle Bonsai 2 27B speed check`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0bonsai2.ps1`" bench`r`npause`r`n"
    Set-Content -Path (Join-Path $dir 'start-bonsai.bat') -Value $start -Encoding ASCII -NoNewline
    Set-Content -Path (Join-Path $dir 'bench-bonsai.bat') -Value $bench -Encoding ASCII -NoNewline
    try {
        $ws = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Bonsai 2 27B.lnk'))
        $lnk.TargetPath = Join-Path $dir 'start-bonsai.bat'
        $lnk.WorkingDirectory = $dir
        $lnk.Save()
        Write-Host 'Desktop shortcut: Bonsai 2 27B'
    } catch {
        Write-Host 'No desktop shortcut this time, start it with start-bonsai.bat in the folder below.'
    }

    Write-Host ''
    Write-Host 'Installed.' -ForegroundColor Green
    Write-Host ('Start it:         double-click "Bonsai 2 27B" on your desktop, or {0}' -f (Join-Path $dir 'start-bonsai.bat'))
    Write-Host ('Check your speed: {0}, it saves your results and copies them to the clipboard' -f (Join-Path $dir 'bench-bonsai.bat'))
    Write-Host ('Chat page:        http://127.0.0.1:{0}' -f $port)
    Write-Host ('API for agents:   http://127.0.0.1:{0}/v1 (OpenAI compatible, model bonsai-2-27b, any API key)' -f $port)
    if (-not $test -and -not $env:BONSAI_NO_START) {
        Write-Host ''
        Write-Host 'Starting it now in a new window, the chat page opens when the model is loaded.'
        Start-Process -FilePath (Join-Path $dir 'start-bonsai.bat') -WorkingDirectory $dir
    }
}

Install-Bonsai2
