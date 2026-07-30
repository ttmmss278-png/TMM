import os
import shlex
import shutil
import subprocess
from functools import lru_cache
from pathlib import Path

REQUIRED_WGS_TOOLS = ("fastp", "bwa", "samtools")
OPTIONAL_WGS_TOOLS = ("bcftools",)
DEFAULT_PORTABLE_WSL_ROOT = "/opt/tmm-bioseq-wgs"


def run_process(command, log, env=None):
    command = [str(item) for item in command]
    log.append("$ " + " ".join(command))
    process = subprocess.run(
        command,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=env,
    )
    if process.stdout:
        log.append(process.stdout)
    if process.stderr:
        log.append(process.stderr)
    if process.returncode != 0:
        raise RuntimeError(f"Command failed ({process.returncode}): {' '.join(command)}")
    return process


def run_native_pipe(left_command, right_command, log):
    left_command = [str(item) for item in left_command]
    right_command = [str(item) for item in right_command]
    log.append("$ " + " ".join(left_command) + " | " + " ".join(right_command))
    left = subprocess.Popen(left_command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    right = subprocess.Popen(right_command, stdin=left.stdout, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    left.stdout.close()
    right_stdout, right_stderr = right.communicate()
    left_stderr = left.stderr.read()
    left_code = left.wait()
    if left_stderr:
        log.append(left_stderr.decode("utf-8", errors="replace"))
    if right_stdout:
        log.append(right_stdout.decode("utf-8", errors="replace"))
    if right_stderr:
        log.append(right_stderr.decode("utf-8", errors="replace"))
    if left_code != 0 or right.returncode != 0:
        raise RuntimeError(f"Pipeline failed: {left_code} | {right.returncode}")


def get_wsl_executable():
    return shutil.which("wsl.exe") or shutil.which("wsl")


def _read_registry_value(name):
    if os.name != "nt":
        return ""
    try:
        import winreg

        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\TMMBioSeq") as key:
            value, _ = winreg.QueryValueEx(key, name)
            return str(value).strip()
    except (OSError, ImportError):
        return ""


def get_wsl_distro():
    return (
        str(os.environ.get("BIOSEQ_WSL_DISTRO") or "").strip()
        or _read_registry_value("WslDistro")
        or "Ubuntu"
    )


def get_portable_wsl_root():
    value = (
        str(os.environ.get("BIOSEQ_WSL_TOOL_ROOT") or "").strip()
        or _read_registry_value("WslToolRoot")
        or DEFAULT_PORTABLE_WSL_ROOT
    )
    return value.rstrip("/") or DEFAULT_PORTABLE_WSL_ROOT


def wsl_prefix():
    executable = get_wsl_executable()
    if not executable:
        return []
    return [executable, "-d", get_wsl_distro(), "-u", "root", "--"]


def portable_tool_path(tool):
    return f"{get_portable_wsl_root()}/bin/{tool}"


def _wsl_check_script(tools, portable):
    if portable:
        return " && ".join(
            f"test -x {shlex.quote(portable_tool_path(tool))}" for tool in tools
        )
    return " && ".join(
        f"command -v {shlex.quote(tool)} >/dev/null 2>&1" for tool in tools
    )


def wsl_tools_available(tools, portable=False):
    prefix = wsl_prefix()
    if not prefix:
        return False
    process = subprocess.run(
        prefix + ["bash", "-lc", _wsl_check_script(tools, portable)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=20,
    )
    return process.returncode == 0


def to_wsl_path(path):
    prefix = wsl_prefix()
    if not prefix:
        raise RuntimeError("WSL is not available.")
    process = subprocess.run(
        prefix + ["wslpath", "-a", str(Path(path).resolve())],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=20,
    )
    if process.returncode != 0 or not process.stdout.strip():
        raise RuntimeError(f"Unable to convert Windows path for WSL: {path}\n{process.stderr}")
    return process.stdout.strip()


def tool_for_backend(tool, backend):
    return portable_tool_path(tool) if backend == "portable-wsl" else tool


def run_wsl_command(command, log):
    return run_process(wsl_prefix() + [str(item) for item in command], log)


def run_wsl_pipe(left_command, right_command, log):
    script = " ".join(shlex.quote(str(item)) for item in left_command)
    script += " | "
    script += " ".join(shlex.quote(str(item)) for item in right_command)
    return run_process(wsl_prefix() + ["bash", "-lc", script], log)


def detect_tool_backend():
    required = list(REQUIRED_WGS_TOOLS)

    if wsl_tools_available(required, portable=True):
        return "portable-wsl", []

    native_missing = [tool for tool in required if shutil.which(tool) is None]
    if not native_missing:
        return "native", []

    if wsl_tools_available(required, portable=False):
        return "wsl", []

    return None, required


@lru_cache(maxsize=8)
def get_tool_versions(backend):
    if backend not in {"native", "wsl", "portable-wsl"}:
        return {}

    versions = {}
    for tool in REQUIRED_WGS_TOOLS + OPTIONAL_WGS_TOOLS:
        executable = tool_for_backend(tool, backend)
        if backend == "native" and shutil.which(executable) is None:
            continue
        if backend in {"wsl", "portable-wsl"}:
            if not wsl_tools_available([tool], portable=backend == "portable-wsl"):
                continue
            if tool == "bwa":
                command = ["bash", "-lc", f"{shlex.quote(executable)} 2>&1 | head -n 3"]
            else:
                command = ["bash", "-lc", f"{shlex.quote(executable)} --version 2>&1 | head -n 1"]
            full_command = wsl_prefix() + command
        else:
            full_command = [executable, "--version"] if tool != "bwa" else [executable]

        try:
            process = subprocess.run(
                full_command,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=15,
            )
            text = (process.stdout or process.stderr or "").strip()
            if text:
                versions[tool] = text.splitlines()[0]
        except (OSError, subprocess.SubprocessError):
            continue
    return versions


def portable_bundle_status():
    root = get_portable_wsl_root()
    installed = wsl_tools_available(REQUIRED_WGS_TOOLS, portable=True)
    return {
        "installed": installed,
        "root": root,
        "distro": get_wsl_distro(),
    }


def ensure_reference_indexes(reference, log, backend):
    reference = str(reference)
    bwa_index_markers = [reference + suffix for suffix in [".bwt", ".0123"]]
    tool_reference = to_wsl_path(reference) if backend in {"wsl", "portable-wsl"} else reference
    bwa_tool = tool_for_backend("bwa", backend)
    samtools_tool = tool_for_backend("samtools", backend)

    if not any(os.path.exists(marker) for marker in bwa_index_markers):
        log.append("BWA index not found; building it once for the default reference genome.")
        if backend in {"wsl", "portable-wsl"}:
            run_wsl_command([bwa_tool, "index", tool_reference], log)
        else:
            run_process([bwa_tool, "index", tool_reference], log)
    else:
        log.append("Reusing existing BWA reference index.")

    fasta_index = reference + ".fai"
    if not os.path.exists(fasta_index):
        log.append("FASTA index not found; building samtools faidx index.")
        if backend in {"wsl", "portable-wsl"}:
            run_wsl_command([samtools_tool, "faidx", tool_reference], log)
        else:
            run_process([samtools_tool, "faidx", tool_reference], log)
    else:
        log.append("Reusing existing samtools FASTA index.")


def run_wgs(r1, r2, reference, output):
    inputs = {"R1": r1, "R2": r2, "reference": reference}
    missing_files = [name for name, path in inputs.items() if not path or not os.path.isfile(path)]
    if missing_files:
        return {"status": "failed", "log": "Missing input files: " + ", ".join(missing_files)}

    backend, missing_tools = detect_tool_backend()
    if not backend:
        return {
            "status": "failed",
            "log": (
                "Portable WGS tools are not installed. Missing: "
                + ", ".join(missing_tools)
                + ". Download and install the TMM BioSeq portable WGS tools package."
            ),
            "missing_tools": missing_tools,
        }

    output_dir = Path(output)
    output_dir.mkdir(parents=True, exist_ok=True)
    clean_r1 = output_dir / "clean_R1.fastq.gz"
    clean_r2 = output_dir / "clean_R2.fastq.gz"
    bam = output_dir / "aligned.sorted.bam"
    log = [f"Using reference genome: {reference}", f"WGS tool backend: {backend}"]

    is_wsl = backend in {"wsl", "portable-wsl"}
    if is_wsl:
        tool_r1 = to_wsl_path(r1)
        tool_r2 = to_wsl_path(r2)
        tool_reference = to_wsl_path(reference)
        tool_clean_r1 = to_wsl_path(clean_r1)
        tool_clean_r2 = to_wsl_path(clean_r2)
        tool_bam = to_wsl_path(bam)
        tool_fastp_html = to_wsl_path(output_dir / "fastp_report.html")
        tool_fastp_json = to_wsl_path(output_dir / "fastp_report.json")
    else:
        tool_r1 = r1
        tool_r2 = r2
        tool_reference = reference
        tool_clean_r1 = str(clean_r1)
        tool_clean_r2 = str(clean_r2)
        tool_bam = str(bam)
        tool_fastp_html = str(output_dir / "fastp_report.html")
        tool_fastp_json = str(output_dir / "fastp_report.json")

    fastp_tool = tool_for_backend("fastp", backend)
    bwa_tool = tool_for_backend("bwa", backend)
    samtools_tool = tool_for_backend("samtools", backend)
    bcftools_tool = tool_for_backend("bcftools", backend)

    try:
        ensure_reference_indexes(reference, log, backend)

        fastp_command = [
            fastp_tool,
            "-i", tool_r1,
            "-I", tool_r2,
            "-o", tool_clean_r1,
            "-O", tool_clean_r2,
            "--html", tool_fastp_html,
            "--json", tool_fastp_json,
        ]
        if is_wsl:
            run_wsl_command(fastp_command, log)
        else:
            run_process(fastp_command, log)

        bwa_command = [bwa_tool, "mem", tool_reference, tool_clean_r1, tool_clean_r2]
        samtools_sort = [samtools_tool, "sort", "-o", tool_bam, "-"]
        if is_wsl:
            run_wsl_pipe(bwa_command, samtools_sort, log)
            run_wsl_command([samtools_tool, "index", tool_bam], log)
            flagstat = run_wsl_command([samtools_tool, "flagstat", tool_bam], log)
        else:
            run_native_pipe(bwa_command, samtools_sort, log)
            run_process([samtools_tool, "index", tool_bam], log)
            flagstat = run_process([samtools_tool, "flagstat", tool_bam], log)
        (output_dir / "flagstat.txt").write_text(flagstat.stdout or "", encoding="utf-8")

        if backend == "native":
            bcftools_available = shutil.which("bcftools") is not None
        else:
            bcftools_available = wsl_tools_available(
                ["bcftools"], portable=backend == "portable-wsl"
            )

        if bcftools_available:
            vcf = output_dir / "variants.vcf.gz"
            tool_vcf = to_wsl_path(vcf) if is_wsl else str(vcf)
            mpileup = [bcftools_tool, "mpileup", "-Ou", "-f", tool_reference, tool_bam]
            call = [bcftools_tool, "call", "-mv", "-Oz", "-o", tool_vcf]
            if is_wsl:
                run_wsl_pipe(mpileup, call, log)
                run_wsl_command([bcftools_tool, "index", "-t", tool_vcf], log)
            else:
                run_native_pipe(mpileup, call, log)
                run_process([bcftools_tool, "index", "-t", tool_vcf], log)
        else:
            log.append("bcftools not found; variant calling was skipped.")

        (output_dir / "pipeline.log").write_text("\n".join(log), encoding="utf-8")
        return {
            "status": "success",
            "message": "WGS pipeline completed.",
            "log": "\n".join(log),
            "output": str(output_dir),
            "reference": reference,
            "tool_backend": backend,
        }
    except Exception as exc:
        log.append(str(exc))
        (output_dir / "pipeline.log").write_text("\n".join(log), encoding="utf-8")
        return {
            "status": "failed",
            "log": "\n".join(log),
            "output": str(output_dir),
            "reference": reference,
            "tool_backend": backend,
        }
