"""Serve the built editor with an isolated real API and worker for Playwright."""
import os
from pathlib import Path
import secrets
import signal
import subprocess
import sys
import tempfile
import time


def main():
    root = Path(__file__).resolve().parents[1]
    python = os.environ.get("NEUROTUNE_BACKEND_PYTHON")
    if python is None:
        local = root / "backend/.venv/bin/python"
        python = str(local) if local.exists() else sys.executable
    if not (root / "web/dist/index.html").exists():
        raise SystemExit("Build the editor before running acceptance: cd web && npm run build")

    processes = []

    def stop(_signal, _frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    with tempfile.TemporaryDirectory(prefix="neurotune-browser-acceptance-") as directory:
        env = os.environ | {
            "DATABASE_URL": f"sqlite:///{directory}/acceptance.sqlite",
            "AUDIO_DATA_DIR": f"{directory}/audio",
            "RAW_DATA_DIR": f"{directory}/raw",
            "EDITOR_DIST_DIR": str(root / "web/dist"),
            "CONTRACTS_PATH": str(root / "contracts/default_experiment.json"),
            "JWT_SECRET": secrets.token_urlsafe(32),
            "ENVIRONMENT": "development",
        }
        try:
            subprocess.run([python, "-m", "alembic", "upgrade", "head"],
                           cwd=root / "backend", env=env, check=True)
            processes.append(subprocess.Popen(
                [python, "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "18016"],
                cwd=root / "backend", env=env))
            processes.append(subprocess.Popen([python, "-m", "app.worker"],
                                              cwd=root / "backend", env=env))
            while all(process.poll() is None for process in processes):
                time.sleep(.2)
            raise SystemExit("The disposable acceptance API or worker stopped unexpectedly.")
        except KeyboardInterrupt:
            pass
        finally:
            for process in processes:
                if process.poll() is None:
                    process.terminate()
            for process in processes:
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    main()
