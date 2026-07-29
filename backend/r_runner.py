import subprocess
import os
import shutil


def run_r_script(script, input_path, output_dir, extra_args=None):
    os.makedirs(output_dir, exist_ok=True)
    if not os.path.exists(script):
        return {"status": "failed", "log": f"R script not found: {script}"}
    if shutil.which("Rscript") is None:
        return {"status": "failed", "log": "Rscript was not found in PATH. Please install R and add Rscript to PATH."}

    cmd = ["Rscript", script, input_path, output_dir] + list(extra_args or [])
    try:
        process = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)
        return {
            "status": "success" if process.returncode == 0 else "failed",
            "log": (process.stdout or "") + (process.stderr or ""),
            "output": output_dir,
            "command": cmd
        }
    except subprocess.TimeoutExpired:
        return {"status": "failed", "log": "R analysis exceeded the 60-minute timeout."}
    except Exception as exc:
        return {"status": "failed", "log": str(exc)}