import subprocess
from pathlib import Path

import pytest

T0 = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize("script", sorted(p.name for p in T0.glob("*.sh")))
def test_shell_syntax(script):
    subprocess.run(["bash", "-n", str(T0 / script)], check=True)
