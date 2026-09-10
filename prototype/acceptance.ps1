$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force prototype-results | Out-Null
Start-Transcript -Path prototype-results/acceptance.log
function Require-Success([string]$what) {
    if ($LASTEXITCODE -ne 0) { throw "$what exited $LASTEXITCODE" }
}
function Assert-Arm64PE([string]$path) {
    $stream = [System.IO.File]::OpenRead($path)
    $reader = [System.IO.BinaryReader]::new($stream)
    try {
        $stream.Position = 0x3c
        $offset = $reader.ReadInt32()
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x00004550) { throw "Invalid PE header: $path" }
        $machine = $reader.ReadUInt16()
        if ($machine -ne 0xAA64) { throw "Non-ARM64 binary: $path ($machine)" }
        "AA64: $path"
    } finally { $reader.Dispose() }
}
function Install-Prototype([string]$prefix) {
    $p = Start-Process $script:installer -NoNewWindow -ArgumentList "/InstallationType=JustMe /RegisterPython=0 /AddToPath=0 /S /D=$prefix" -PassThru
    if (-not $p.WaitForExit(300000)) { $p.Kill(); throw 'Installer timeout' }
    if ($p.ExitCode -ne 0) { throw "Installer exited $($p.ExitCode)" }
    & "$prefix/python.exe" -c "import platform,struct; assert platform.machine().lower()=='arm64'; assert struct.calcsize('P')==8; print('Native ARM64 Python verified')"
    Require-Success 'Python architecture'
    Assert-Arm64PE "$prefix/python.exe"
    Assert-Arm64PE "$prefix/Library/bin/mamba.exe"
}
function Uninstall-Prototype([string]$prefix) {
    $u = @(Get-ChildItem -LiteralPath $prefix -Filter 'Uninstall-*.exe')
    if ($u.Count -ne 1) { throw 'Expected one generated uninstaller' }
    # NSIS _?= keeps the uninstaller process synchronous, avoiding the copied temp process.
    $p = Start-Process $u[0].FullName -ArgumentList "/S _?=$prefix" -PassThru
    if (-not $p.WaitForExit(180000)) { $p.Kill(); throw 'Uninstaller timeout' }
    if ($p.ExitCode -ne 0) { throw "Uninstaller exited $($p.ExitCode)" }
    if (Test-Path "$prefix/python.exe") { throw 'Uninstaller left Python installed' }
    if (Test-Path "$prefix/conda-meta") { throw 'Uninstaller left environment metadata' }
    if (-not (Test-Path $script:sentinel)) { throw 'Uninstaller affected unrelated sentinel' }
    'Uninstall removed Python and metadata; unrelated sentinel preserved.'
}
function Save-Shortcuts([string]$prefix, [string]$outName) {
    $shell = New-Object -ComObject WScript.Shell
    $links = @(Get-ChildItem "$env:APPDATA/Microsoft/Windows/Start Menu/Programs" -Filter '*.lnk' -Recurse | ForEach-Object {
        $s = $shell.CreateShortcut($_.FullName)
        if ($s.Arguments -like "*$prefix*" -or $s.TargetPath -like "$prefix*") {
            [pscustomobject]@{ path=$_.FullName; target=$s.TargetPath; arguments=$s.Arguments }
        }
    })
    $links | ConvertTo-Json -Depth 5 | Set-Content "prototype-results/$outName.json"
    return $links
}
try {
    $files = @(Get-ChildItem build/*Windows-arm64.exe)
    if ($files.Count -ne 1) { throw 'Expected one ARM64 installer' }
    $script:installer = $files[0].FullName
    $hash = (Get-FileHash $script:installer -Algorithm SHA256).Hash
    if ($hash -ne '8C796301FEDC821A0B6D94A672C307D23914600CBF49656D86EA7CF6B3CD2ED8') { throw 'Installer checksum mismatch' }
    Write-Output "Installer SHA256: $hash"
    $rejected = Join-Path $env:RUNNER_TEMP 'Miniforge ARM64 Rejected'
    $reject = Start-Process $script:installer -NoNewWindow -ArgumentList "/InstallationType=JustMe /RegisterPython=0 /AddToPath=0 /S /D=$rejected" -Wait -PassThru
    if ($reject.ExitCode -ne 2 -or (Test-Path "$rejected/python.exe")) { throw 'Expected existing Miniforge rejection of paths containing spaces' }
    $script:sentinel = Join-Path $env:RUNNER_TEMP 'unrelated-prototype-sentinel.txt'
    'preserve me' | Set-Content $script:sentinel
    $prefix = Join-Path $env:RUNNER_TEMP 'MiniforgeARM64Acceptance'
    Install-Prototype $prefix
    $conda = "$prefix/Scripts/conda.exe"
    $mamba = "$prefix/Library/bin/mamba.exe"
    $info = & $conda info --json | ConvertFrom-Json
    Require-Success 'Conda info'
    if ($info.platform -ne 'win-arm64') { throw 'Incorrect Conda platform' }
    & $conda list --explicit | Set-Content prototype-results/acceptance-explicit.txt
    Require-Success 'Conda inventory'
    $links = @(Save-Shortcuts $prefix 'shortcuts-installed')
    if ($links.Count -lt 1) { throw 'No installed shortcut targets this prefix' }
    if (-not ($links | Where-Object { $_.arguments -like '*activate.bat*' })) { throw 'Prompt shortcut does not invoke activation' }
    $prompt = @($links | Where-Object { $_.arguments -like '*activate.bat*' })[0]
    $probePath = Join-Path $env:RUNNER_TEMP 'shortcut-probe.json'
    # Run the shortcut's stored activation command, changing /K to /C only so the probe exits.
    $probeArgs = ($prompt.arguments -replace '(?i)^/K\s+', '/D /C call ') + ' && python -c "import json,os,platform; print(json.dumps(dict(prefix=os.environ.get(''CONDA_PREFIX''),machine=platform.machine())))" > "' + $probePath + '"'
    $probeProcess = Start-Process $prompt.target -ArgumentList $probeArgs -NoNewWindow -Wait -PassThru
    if ($probeProcess.ExitCode -ne 0 -or -not (Test-Path $probePath)) { throw 'Shortcut activation command failed' }
    $probe = Get-Content $probePath -Raw | ConvertFrom-Json
    if ($probe.prefix -ne $prefix -or $probe.machine.ToLower() -ne 'arm64') { throw 'Shortcut activated incorrect environment' }
    Copy-Item $probePath prototype-results/shortcut-runtime.json

    $child = Join-Path $env:RUNNER_TEMP 'MiniforgeARM64Child'
    & $conda create -y -p $child --override-channels -c conda-forge python=3.14 zlib
    Require-Success 'Conda create'
    & $mamba install -y -p $child --override-channels -c conda-forge six
    Require-Success 'Mamba install'
    & "$child/python.exe" -c "import platform,six,zlib; assert platform.machine().lower()=='arm64'; s=b'installer acceptance'*100; assert zlib.decompress(zlib.compress(s))==s; print(six.__version__)"
    Require-Success 'Native child execution'
    $cmdTest = Join-Path $env:RUNNER_TEMP 'prototype-activation.cmd'
    @"
@echo off
call "$prefix\condabin\conda_hook.bat"
if errorlevel 1 exit /b 1
call conda activate "$child"
if errorlevel 1 exit /b 1
if /I not "%CONDA_PREFIX%"=="$child" exit /b 2
python -c "import platform; assert platform.machine().lower()=='arm64'"
if errorlevel 1 exit /b 1
call conda deactivate
if errorlevel 1 exit /b 1
"@ | Set-Content $cmdTest
    & cmd.exe /d /c $cmdTest
    Require-Success 'CMD activation'
    $psTest = Join-Path $env:RUNNER_TEMP 'prototype-activation.ps1'
    @"
`$ErrorActionPreference = 'Stop'
(& '$conda' shell.powershell hook) | Out-String | Invoke-Expression
conda activate '$child'
if (`$env:CONDA_PREFIX -ne '$child') { throw 'Incorrect PowerShell prefix' }
python -c "import platform; assert platform.machine().lower()=='arm64'"
if (`$LASTEXITCODE) { exit `$LASTEXITCODE }
conda deactivate
"@ | Set-Content $psTest
    & pwsh -NoProfile -File $psTest
    Require-Success 'PowerShell activation'
    & $mamba update -y -p $child --override-channels -c conda-forge zlib
    Require-Success 'Mamba update'
    & $mamba remove -y -p $child six
    Require-Success 'Mamba remove'
    & "$child/python.exe" -c "import importlib.util; assert importlib.util.find_spec('six') is None"
    Require-Success 'Removal verification'
    & $conda env remove -y -p $child
    Require-Success 'Conda environment removal'
    Uninstall-Prototype $prefix
    $remaining = @(Save-Shortcuts $prefix 'shortcuts-after-uninstall')
    if ($remaining.Count) { throw 'Uninstaller left a shortcut targeting the removed prefix' }
    $offline = Join-Path $env:RUNNER_TEMP 'MiniforgeARM64Offline'
    $probeUrl = 'https://conda.anaconda.org/conda-forge/noarch/'
    Invoke-WebRequest $probeUrl -Method Head -TimeoutSec 20 | Out-Null
    $rule = 'MiniforgePrototypeOffline-' + [guid]::NewGuid().ToString()
    try {
        New-NetFirewallRule -Name $rule -DisplayName $rule -Direction Outbound -Action Block -Profile Any | Out-Null
        $blocked = $false
        try { Invoke-WebRequest $probeUrl -Method Head -TimeoutSec 10 | Out-Null } catch { $blocked = $true }
        if (-not $blocked) { throw 'Offline isolation failed: package channel still reachable' }
        Install-Prototype $offline
        & "$offline/Scripts/conda.exe" list --json | Set-Content prototype-results/offline-packages.json
        Require-Success 'Offline inventory'
        $packages = Get-Content prototype-results/offline-packages.json -Raw | ConvertFrom-Json
        foreach ($name in @('python','conda','mamba','pip','miniforge_console_shortcut')) {
            if ($name -notin $packages.name) { throw "Offline base missing $name" }
        }
        & "$offline/Library/bin/mamba.exe" --version
        Require-Success 'Offline Mamba'
    } finally { Remove-NetFirewallRule -Name $rule -ErrorAction SilentlyContinue }
    Invoke-WebRequest $probeUrl -Method Head -TimeoutSec 20 | Out-Null
    Uninstall-Prototype $offline
    'PASS: native install, shortcut activation, CMD/PowerShell activation, Conda/Mamba package operations, verified network-blocked offline installation, uninstall.' | Set-Content prototype-results/acceptance-result.txt
} finally { Stop-Transcript }
