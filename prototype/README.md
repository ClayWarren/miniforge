# Windows ARM64 Miniforge prototype

This fork tests an unsigned development installer. It does not publish a release or establish official platform support.

[Construction run](https://github.com/ClayWarren/miniforge/actions/runs/34527627394) used Constructor 3.17.1, explicit `--platform win-arm64`, the checksum-pinned Conda #320 artifact, and published shortcut package 3.0. x64 build tools/conda-standalone and the x86 NSIS launcher use Windows emulation; the installed payload targets ARM64.

The installer SHA-256 is `8c796301fedc821a0b6d94a672c307d23914600cbf49656d86ea7cf6b3cd2ed8`. This branch downloads that exact artifact and runs `acceptance.ps1` on a fresh native runner. Checks cover Python/Mamba PE architecture, shortcut activation, CMD/PowerShell, package operations, blocked-network installation, and uninstall. Paths containing spaces are rejected by the existing installer policy.

The Conda package is retained from a fork build and remapped during construction; it is not yet publicly available. Official release work still needs Conda/Constructor publication, accepted Miniforge changes, x64 regression tests, R/NumPy coverage, and signing. Interactive GUI installation and cross-release upgrades are not established here.
