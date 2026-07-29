import subprocess
import os


def run_wgs(r1, r2, reference, output):
    os.makedirs(output, exist_ok=True)

    commands = []

    commands.append([
        "fastp",
        "-i", r1,
        "-I", r2,
        "-o", os.path.join(output, "clean_R1.fastq.gz"),
        "-O", os.path.join(output, "clean_R2.fastq.gz")
    ])

    return {
        "status": "prepared",
        "message": "WGS pipeline initialized",
        "commands": commands
    }
