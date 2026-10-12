# Bonsai 2 27B on Windows, one line in PowerShell:
#   irm https://raw.githubusercontent.com/sudoingX/local-ai-on-your-gaming-gpu/main/install.ps1 | iex
# It finds your NVIDIA card, picks the build and the model file for its VRAM, downloads them from
# Hugging Face, checks every SHA256, writes start-bonsai.bat, bench-bonsai.bat and a desktop
# shortcut, then starts the model and opens the chat page in your browser.
# AMD Radeon (beta): with no NVIDIA card it looks for a Radeon and takes PrismML's Vulkan build instead.
# Optional, set before the line: $env:BONSAI_DIR (default %USERPROFILE%\bonsai2), $env:BONSAI_PORT (default 8899).

function Install-Bonsai2 {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $inv = [Globalization.CultureInfo]::InvariantCulture

    $release = 'v1.2-windows'
    $ref     = if ($env:BONSAI_REF) { $env:BONSAI_REF } else { 'main' }
    $hf      = 'https://huggingface.co/sudoingx/Ternary-Bonsai-2-27B-PTQ1_0-MTP-GGUF/resolve/main'
    $prism   = 'https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/resolve/main'
    $hub     = "https://raw.githubusercontent.com/sudoingX/local-ai-on-your-gaming-gpu/$ref"
    $dir     = if ($env:BONSAI_DIR) { $env:BONSAI_DIR } else { Join-Path $env:USERPROFILE 'bonsai2' }
    $port    = if ($env:BONSAI_PORT) { [int]$env:BONSAI_PORT } else { 8899 }
    $test    = [bool]$env:BONSAI_TEST   # CI only: skips the big downloads and the start

    $builds = @{
        rtx50   = @{ zip = 'bonsai2-small-gpu-windows-x64-cuda13.3-sm120-ff41412';     driver = 580.0;  cards = 'RTX 50' }
        rtx3040 = @{ zip = 'bonsai2-small-gpu-windows-x64-cuda12.4-sm86-sm89-ff41412'; driver = 551.61; cards = 'RTX 30 and 40' }
        # Turing (RTX 20): the same v1.1 code built for sm_75 (a matrix entry in the fork's bonsai2-windows workflow)
        rtx20   = @{ zip = 'bonsai2-small-gpu-windows-x64-cuda12.4-sm75-ff41412';     driver = 551.61; cards = 'RTX 20' }
        # AMD Radeon (beta): PrismML's own Windows Vulkan build of the same fork, from its GitHub release, pinned by SHA256
        radeon  = @{ zip = 'llama-prism-b10772-e8fd209-bin-win-vulkan-x64'; cards = 'AMD Radeon, Vulkan'
                     url = 'https://github.com/PrismML-Eng/llama.cpp/releases/download/prism-b10772-e8fd209/llama-prism-b10772-e8fd209-bin-win-vulkan-x64.zip'
                     sha = 'f365ad7c56fb9df8805eb4f701bd068ee36c61da894dc7c52f48644d1fa2b625' }
    }
    $mmproj    = 'Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf'
    $mmprojSha = '6807ede61d570bb86ba34b756a0fa109edc33668604de867c6ea6d8f1d631903'

    Write-Host ''
    Write-Host 'Bonsai 2 27B for small GPUs, Windows installer' -ForegroundColor Cyan
    Write-Host 'github.com/sudoingX/local-ai-on-your-gaming-gpu'
    Write-Host ''

    # AMD Radeon (beta), when no NVIDIA card answers: every AMD display adapter, its VRAM from the driver's registry key
    # (Win32_VideoController.AdapterRAM stops at 4 GB), the one with the most VRAM wins. An APU (under 2 GB of its own and
    # more than 16 GB shared, which Windows sets to half the RAM) counts as a 16 GB card.
    # CI: BONSAI_FAKE_AMD = 'name, VRAM MiB, shared MiB, driver' rows separated by ';'.
    function Get-Radeon {
        $cards = @()
        if ($env:BONSAI_FAKE_AMD) {
            foreach ($r in ($env:BONSAI_FAKE_AMD -split ';')) {
                $f = @($r.Split(',') | ForEach-Object { $_.Trim() })
                if ($f.Count -ge 4) { $cards += [pscustomobject]@{ Name = $f[0]; MiB = [int]$f[1]; SharedMiB = [int]$f[2]; Driver = $f[3] } }
            }
        } else {
            $class = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
            try { $adapters = @(Get-CimInstance Win32_VideoController); $shared = [int]((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 2MB) }
            catch { Write-Host ('Could not list the display adapters: {0}' -f $_.Exception.Message); $adapters = @() }
            foreach ($vc in $adapters) {
                if ("$($vc.AdapterCompatibility)" -notmatch 'Advanced Micro Devices' -and "$($vc.Name)" -notmatch 'Radeon') { continue }
                $p = $null
                try {
                    $drvKey = (Get-PnpDeviceProperty -InstanceId $vc.PNPDeviceID -KeyName 'DEVPKEY_Device_Driver' -ErrorAction Stop).Data
                    $p = Get-ItemProperty -Path (Join-Path $class (($drvKey -split '\\')[-1])) -ErrorAction Stop
                } catch {
                    $p = Get-ChildItem $class -ErrorAction SilentlyContinue | ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
                        Where-Object { "$($_.DriverDesc)" -eq "$($vc.Name)" } | Select-Object -First 1
                }
                $bytes = [double]$vc.AdapterRAM
                if ($p) {
                    foreach ($v in @($p.'HardwareInformation.qwMemorySize', $p.'HardwareInformation.MemorySize')) {
                        $n = 0
                        if ($v -is [byte[]]) { if ($v.Length -ge 8) { $n = [double][BitConverter]::ToUInt64($v, 0) } elseif ($v.Length -ge 4) { $n = [double][BitConverter]::ToUInt32($v, 0) } }
                        elseif ($v) { $n = [double]$v }
                        if ($n -gt $bytes) { $bytes = $n }
                    }
                }
                $ver = if ($p -and $p.RadeonSoftwareVersion) { "$($p.RadeonSoftwareVersion)" } else { "$($vc.DriverVersion)" }
                $cards += [pscustomobject]@{ Name = "$($vc.Name)".Trim(); MiB = [int]($bytes / 1MB); SharedMiB = $shared; Driver = $ver }
            }
        }
        $c = @($cards) | Sort-Object MiB -Descending | Select-Object -First 1
        if ($c) { $c | Add-Member -NotePropertyName Apu -NotePropertyValue ($c.MiB -lt 2048 -and $c.SharedMiB -gt 16384) }
        return $c
    }

    # 1. the card (the one with the most VRAM if there are several)
    $smi = $null
    if ($env:BONSAI_FAKE_GPU) {
        $rows = @($env:BONSAI_FAKE_GPU)
    } else {
        $rows = @()
        $cmd = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
        if ($cmd) { $smi = $cmd.Source } elseif (Test-Path "$env:SystemRoot\System32\nvidia-smi.exe") { $smi = "$env:SystemRoot\System32\nvidia-smi.exe" }
        if ($smi) { $rows = @(& $smi --query-gpu=index,name,memory.total,driver_version,compute_cap --format=csv,noheader,nounits) }
    }
    $gpus = foreach ($r in $rows) {
        $f = @($r.Split(',') | ForEach-Object { $_.Trim() })
        if ($f.Count -lt 5) { continue }
        [pscustomobject]@{ Index = [int]$f[0]; Name = $f[1]; MiB = [int]$f[2]; Driver = $f[3]; CC = [double]::Parse($f[4], $inv) }
    }
    $g = @($gpus) | Sort-Object MiB -Descending | Select-Object -First 1
    # no NVIDIA card answers: an AMD Radeon (beta)?
    $amd = $false
    if (-not $g -and -not $env:BONSAI_FAKE_GPU) { $g = Get-Radeon; $amd = [bool]$g }
    if (-not $g) {
        if (-not $smi -and -not $env:BONSAI_FAKE_GPU) { Write-Host 'No NVIDIA driver found. Install the latest driver from nvidia.com, then run this again.' -ForegroundColor Red; return }
        Write-Host 'Could not read the card from nvidia-smi.' -ForegroundColor Red; return
    }
    Write-Host ('Card:   {0}, {1} MiB, driver {2}' -f $g.Name, $g.MiB, $g.Driver)
    if ($amd) {
        $apuNote = if ($g.Apu) { (', an APU: {0} MiB of shared memory counts as its VRAM' -f $g.SharedMiB) } else { '' }
        Write-Host ('        AMD Radeon, beta{0}' -f $apuNote)
    }

    # 2. the build for this card
    if ($amd) { $b = $builds.radeon }
    elseif ($g.CC -ge 12.0) { $b = $builds.rtx50 }
    elseif ($g.CC -ge 8.6 -and $g.CC -lt 9.0) { $b = $builds.rtx3040 }
    elseif ($g.CC -ge 7.5 -and $g.CC -lt 8.0) { $b = $builds.rtx20 }
    else { Write-Host ('This card (compute {0}) is not covered by the prebuilt builds yet, they cover RTX 20, 30, 40 and 50.' -f $g.CC.ToString($inv)) -ForegroundColor Red; return }
    if ($amd) {
        # the Vulkan build links the Microsoft C++ runtime and does not carry it; most gaming PCs have it from their games
        $sys32 = Join-Path $env:SystemRoot 'System32'
        if (-not ((Test-Path (Join-Path $sys32 'vcruntime140_1.dll')) -and (Test-Path (Join-Path $sys32 'msvcp140.dll')))) {
            Write-Host 'The Radeon build needs the Microsoft Visual C++ Redistributable (x64), install it from' -ForegroundColor Red
            Write-Host '  https://aka.ms/vs/17/release/vc_redist.x64.exe' -ForegroundColor Red
            Write-Host 'then run this again. The Vulkan driver comes with the AMD Adrenalin driver.' -ForegroundColor Red
            return
        }
    } else {
        $parts = $g.Driver.Split('.')
        $minor = if ($parts.Count -gt 1) { $parts[1] } else { '0' }
        $drv = [double]::Parse(($parts[0] + '.' + $minor), $inv)
        if ($drv -lt $b.driver) { Write-Host ('Driver {0} is too old for the {1} build. Update to {2} or newer from nvidia.com, then run this again.' -f $g.Driver, $b.cards, $b.driver.ToString($inv)) -ForegroundColor Red; return }
    }

    # 3. the model file for this much VRAM (a Radeon APU counts as 16 GB)
    if ($g.MiB -ge 15000 -or $g.Apu) { $tier = '16gb'; $model = 'Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf';      $vision = $true;  $nmax = 1 }
    elseif ($g.MiB -ge 11500) { $tier = '12gb'; $model = 'Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf';      $vision = $false; $nmax = 1 }
    elseif ($g.MiB -ge 7500)  { $tier = '8gb';  $model = 'Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf'; $vision = $false; $nmax = 2 }
    elseif ($amd -and $g.MiB -lt 2048) {
        Write-Host ('This Radeon has {0} MiB of its own memory and {1} MiB shared. Bonsai 2 27B needs a card with 8 GB or more,' -f $g.MiB, $g.SharedMiB) -ForegroundColor Red
        Write-Host 'or an APU with more than 16 GB shared (32 GB of RAM or more).' -ForegroundColor Red
        return
    }
    else { Write-Host ('Bonsai 2 27B needs a card with 8 GB or more, this one has {0} MiB.' -f $g.MiB) -ForegroundColor Red; return }
    # on Vulkan the head drafts 2 tokens on every tier (n-max 2 decoded 15 to 16% faster than n-max 1 on the Radeon 8060S)
    if ($amd) { $nmax = 2 }
    # RTX 20: the head drafts 1 token on every tier (on an RTX 2070 Super n-max 1 decoded within 5% of n-max 2 with a 150 MiB
    # smaller server, which buys the 48K window on an 8 GB card)
    if (-not $amd -and $b -eq $builds.rtx20) { $nmax = 1 }
    $visionNote = if ($vision) { ', with vision' } else { '' }
    Write-Host ('Build:  {0} ({1})' -f $b.zip, $b.cards)
    Write-Host ('Model:  {0}, {1} tier{2}' -f $model, $tier, $visionNote)
    Write-Host ('Folder: {0}' -f $dir)
    Write-Host ''

    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'models') | Out-Null
    $root = [IO.Path]::GetPathRoot((Resolve-Path $dir).Path)
    $free = (New-Object IO.DriveInfo $root).AvailableFreeSpace
    $skipModel = [bool]$env:BONSAI_SKIP_MODEL   # CI only: the real zip download and unpack, without the 7 GB model
    $need = if ($skipModel) { 2GB } else { 10GB }
    if (-not $test -and $free -lt $need) { Write-Host ('Not enough disk space on {0}: about {1:N0} GB is needed, {2:N1} GB is free.' -f $root, ($need / 1GB), ($free / 1GB)) -ForegroundColor Red; return }

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
        $needs = if ($amd) { @($model) } else { @("$($b.zip).zip", $model) }
        foreach ($need in $needs) { if (-not $sums.ContainsKey($need)) { throw "SHA256SUMS on Hugging Face has no line for $need" } }

        if ($amd) { Write-Host 'Downloading the build from GitHub and the model from Hugging Face (about 8 GB the first time, it resumes if it stops):' }
        else { Write-Host 'Downloading from Hugging Face (about 8 GB the first time, it resumes if it stops):' }
        $zipPath = Join-Path $dir "$($b.zip).zip"
        $exe = Join-Path $dir "$($b.zip)\bin\llama-server.exe"
        $zipUrl = "$hf/$($b.zip).zip"; $zipSha = $sums["$($b.zip).zip"]; $unzipTo = $dir
        if ($amd) {   # PrismML's zip has no folder of its own and no bin folder
            $exe = Join-Path $dir "$($b.zip)\llama-server.exe"; $zipUrl = $b.url; $zipSha = $b.sha; $unzipTo = Join-Path $dir $b.zip
        }
        if (-not (Test-Path $exe)) {
            Get-Verified $zipUrl $zipPath $zipSha
            Write-Host "  unzip $($b.zip).zip"
            New-Item -ItemType Directory -Force -Path $unzipTo | Out-Null
            $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            & tar.exe -xf $zipPath -C $unzipTo
            $ErrorActionPreference = $old
            if (-not (Test-Path $exe)) { Expand-Archive -Path $zipPath -DestinationPath $unzipTo -Force }
            if (-not (Test-Path $exe)) { throw "unzip failed, $exe is missing" }
            Remove-Item $zipPath -Force
        } else {
            Write-Host "  ok    $($b.zip) (already unpacked)"
        }
        if ($amd) {
            $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            $null = & $exe --version 2>&1
            $rc = $LASTEXITCODE; $ErrorActionPreference = $old
            if ($rc -ne 0) {
                Write-Host ('The Radeon build does not start here (exit code {0}). Install the Microsoft Visual C++ Redistributable (x64)' -f $rc) -ForegroundColor Red
                Write-Host 'from https://aka.ms/vs/17/release/vc_redist.x64.exe and update the AMD Adrenalin driver, then run this again.' -ForegroundColor Red
                return
            }
        }
        if (-not $skipModel) {
            Get-Verified "$hf/$model" (Join-Path $dir "models\$model") $sums[$model]
            if ($vision) { Get-Verified "$prism/$mmproj" (Join-Path $dir "models\$mmproj") $mmprojSha }
        }
    }

    # 5. the launcher, its settings and the two .bat files
    Get-HubFile 'windows/bonsai2.ps1' (Join-Path $dir 'bonsai2.ps1')
    Get-HubFile 'prompts/vision_check.png' (Join-Path $dir 'vision_check.png')
    if ($amd) {
        $cfg = [ordered]@{
            release   = $release
            backend   = 'vulkan'
            build     = $b.zip
            tier      = $tier
            model     = $model
            mmproj    = $(if ($vision) { $mmproj } else { $null })
            nmax      = $nmax
            port      = $port
            gpuName   = $g.Name
            gpuMiB    = $g.MiB
            sharedMiB = $g.SharedMiB
            apu       = [bool]$g.Apu
            driver    = $g.Driver
        }
    } else {
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
    if ($amd) { Write-Host 'Radeon support is in beta: run the speed check once and share the result, it sets the numbers for every Radeon owner.' }
    if (-not $test -and -not $env:BONSAI_NO_START) {
        Write-Host ''
        Write-Host 'Starting it now in a new window, the chat page opens when the model is loaded.'
        Start-Process -FilePath (Join-Path $dir 'start-bonsai.bat') -WorkingDirectory $dir
    }
}

Install-Bonsai2
