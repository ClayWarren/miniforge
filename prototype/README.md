# Windows ARM64 installer prototype

This fork branch builds a development installer. It does not publish a Miniforge release or establish official platform support.

The build runs on `windows-11-arm` with x64 Constructor/NSIS/conda-standalone tools under emulation. Constructor 3.17.1 is installed from its checksum-verified release archive and receives `--platform win-arm64` explicitly. The installer payload targets ARM64; the bootstrap executable may use x64 emulation.

The only unpublished payload prerequisite is Conda 26.7.2 from the unchanged conda-forge/conda-feedstock#320 recipe. Its retained package is verified by SHA-256. Both shortcut pins are changed to the published 3.x menuinst-compatible package. Local Conda package metadata is remapped to conda-forge for installer construction; this does not make that package publicly downloadable before merge/publication.

The first test pass covers silent JustMe installation into a path with spaces, native Python, Conda's platform, mamba startup, and public-channel environment creation/execution/removal. The existing Miniforge R/NumPy suite has not been claimed as passing or replaced. Full release acceptance also requires shortcut/shell checks, offline installation, uninstall, and established-platform regression coverage.

Upstream release workflows are removed only from this isolated validation branch. The `prototype-recipe` directory is generated from the unchanged upstream construct recipe at runtime.
