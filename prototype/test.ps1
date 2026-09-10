$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force prototype-results | Out-Null
Start-Transcript -Path prototype-results/install-test.log
try {
  $installer = @(Get-ChildItem build/*Windows-arm64.exe)
  if ($installer.Count -ne 1) { throw "Expected one ARM64 installer" }
  Get-FileHash $installer[0] -Algorithm SHA256 | Format-List
  $prefix = Join-Path $env:RUNNER_TEMP 'Miniforge ARM64 Prototype'
  $p = Start-Process $installer[0].FullName -ArgumentList "/InstallationType=JustMe /RegisterPython=0 /AddToPath=0 /S /D=$prefix" -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "Installer exit $($p.ExitCode)" }
  & "$prefix/python.exe" -c "import platform,struct,sys; print(sys.executable,platform.machine()); assert platform.machine().lower()=='arm64'; assert struct.calcsize('P')==8"
  if ($LASTEXITCODE) { throw 'Native Python check failed' }
  $conda = "$prefix/Scripts/conda.exe"
  $info = & $conda info --json | ConvertFrom-Json
  if ($LASTEXITCODE -or $info.platform -ne 'win-arm64') { throw 'Conda platform check failed' }
  $info | ConvertTo-Json -Depth 20 | Set-Content prototype-results/conda-info.json
  & $conda list --explicit | Set-Content prototype-results/base-explicit.txt
  if ($LASTEXITCODE) { throw 'Package inventory failed' }
  & "$prefix/Library/bin/mamba.exe" --version
  if ($LASTEXITCODE) { throw 'Mamba failed' }
  $child = Join-Path $env:RUNNER_TEMP 'arm64-child'
  & $conda create -y -p $child --override-channels -c conda-forge python=3.14 zlib
  if ($LASTEXITCODE) { throw 'Conda create failed' }
  & "$child/python.exe" -c "import platform,zlib; assert platform.machine().lower()=='arm64'; s=b'arm64 test'*100; assert zlib.decompress(zlib.compress(s))==s; print('ARM64 zlib round trip passed')"
  if ($LASTEXITCODE) { throw 'Child runtime failed' }
  & $conda env remove -y -p $child
  if ($LASTEXITCODE) { throw 'Conda removal failed' }
  'PASS: silent installation into path with spaces; native Python; Conda platform; mamba; public-channel create/runtime/remove.' | Set-Content prototype-results/result.txt
} finally { Stop-Transcript }
