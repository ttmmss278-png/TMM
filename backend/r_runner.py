import subprocess
import os


def run_r_script(script, input_dir, output_dir):
    os.makedirs(output_dir, exist_ok=True)

    cmd = [
        "Rscript",
        script,
        input_dir,
        output_dir
    ]

    try:
        p = subprocess.run(
            cmd,
            capture_output=True,
            text=True
        )

        return {
            "status": "success" if p.returncode == 0 else "failed",
            "log": p.stdout + p.stderr,
            "output": output_dir
        }

    except Exception as e:
        return {
            "status": "failed",
            "log": str(e)
        }
