"""Prepare an explicitly unpublished Miniforge ARM64 prototype."""
from pathlib import Path
import hashlib, shutil, subprocess, sys, urllib.request
root = Path(__file__).resolve().parents[1]
archive = root / 'constructor-3.17.1.tar.gz'
archive.write_bytes(urllib.request.urlopen('https://github.com/conda/constructor/archive/refs/tags/3.17.1.tar.gz').read())
assert hashlib.sha256(archive.read_bytes()).hexdigest() == 'be546968befef2034066535ad454f153f24bae1cb3b5cfe7d52f8ce874c021d9'
subprocess.run([sys.executable, '-m', 'pip', 'install', '--no-deps', str(archive)], check=True)
pkg = root / 'local-channel/win-arm64/conda-26.7.2-py314hc6eccd4_1.conda'
assert hashlib.sha256(pkg.read_bytes()).hexdigest() == '3d039566740eb1c89987100a03d9b06e4ac4c1a562f12700516d5af1d59d47ec'
subprocess.run([sys.executable, '-m', 'conda_index', str(root / 'local-channel')], check=True)
out = root / 'prototype-recipe'
shutil.copytree(root / 'Miniforge3', out)
s = (out / 'construct.yaml').read_text()
s = s.replace('miniforge_console_shortcut 1.*', 'miniforge_console_shortcut 3.*')
s += '\nchannels_remap:\n  - src: ' + (root / 'local-channel').as_uri() + '\n    dest: https://conda.anaconda.org/conda-forge\n'
(out / 'construct.yaml').write_text(s)
(root / 'build').mkdir(exist_ok=True)
subprocess.run([str(Path(sys.prefix) / 'Scripts/constructor.exe'), str(out), '--platform', 'win-arm64', '--conda-exe', str(Path(sys.prefix) / 'standalone_conda/conda.exe'), '--output-dir', str(root / 'build'), '--debug'], check=True)
