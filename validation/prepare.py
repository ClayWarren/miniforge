"""Provide unpublished prerequisites without changing the integration scripts."""
from pathlib import Path
import hashlib
import subprocess
import sys

root = Path.cwd()
channel = root / 'local-channel'
pkg = channel / 'win-arm64/conda-26.7.2-py314hc6eccd4_1.conda'
assert hashlib.sha256(pkg.read_bytes()).hexdigest() == '3d039566740eb1c89987100a03d9b06e4ac4c1a562f12700516d5af1d59d47ec'
subprocess.run([sys.executable, '-m', 'conda_index', str(channel)], check=True)
(root / 'validation/condarc').write_text(
    'custom_multichannels:\n  validation:\n    - ' + channel.as_uri() + '\n    - conda-forge\n'
)
recipe = root / 'Miniforge3/construct.yaml'
recipe.write_text(recipe.read_text() + '\nchannels_remap:\n  - src: ' + channel.as_uri() + '\n    dest: https://conda.anaconda.org/conda-forge\n')
