import os
import shlex
import shutil
import subprocess
from pathlib import Path


def run_process(command, log):
    log.append('$ ' + ' '.join(map(str, command)))
    process = subprocess.run(command, capture_output=True, text=True)
    if process.stdout:
        log.append(process.stdout)
    if process.stderr:
        log.append(process.stderr)
    if process.returncode != 0:
        raise RuntimeError(f"Command failed ({process.returncode}): {' '.join(map(str, command))}")
    return process


def run_native_pipe(left_command, right_command, log):
    log.append('$ ' + ' '.join(map(str, left_command)) + ' | ' + ' '.join(map(str, right_command)))
    left = subprocess.Popen(left_command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    right = subprocess.Popen(right_command, stdin=left.stdout, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    left.stdout.close()
    right_stdout, right_stderr = right.communicate()
    left_stderr = left.stderr.read()
    left_code = left.wait()
    if left_stderr:
        log.append(left_stderr.decode(errors='replace'))
    if right_stdout:
        log.append(right_stdout.decode(errors='replace'))
    if right_stderr:
        log.append(right_stderr.decode(errors='replace'))
    if left_code != 0 or right.returncode != 0:
        raise RuntimeError(f"Pipeline failed: {left_code} | {right.returncode}")


def get_wsl_executable():
    return shutil.which('wsl.exe') or shutil.which('wsl')


def get_wsl_distro():
    env_value = str(os.environ.get('BIOSEQ_WSL_DISTRO') or '').strip()
    if env_value:
        return env_value
    if os.name == 'nt':
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\TMMBioSeq') as key:
                value, _ = winreg.QueryValueEx(key, 'WslDistro')
                if str(value).strip():
                    return str(value).strip()
        except (OSError, ImportError):
            pass
    return 'Ubuntu'


def wsl_prefix():
    executable = get_wsl_executable()
    if not executable:
        return []
    return [executable, '-d', get_wsl_distro(), '-u', 'root', '--']


def wsl_tools_available(tools):
    prefix = wsl_prefix()
    if not prefix:
        return False
    script = ' && '.join(f'command -v {shlex.quote(tool)} >/dev/null 2>&1' for tool in tools)
    process = subprocess.run(prefix + ['bash', '-lc', script], capture_output=True, text=True)
    return process.returncode == 0


def to_wsl_path(path):
    prefix = wsl_prefix()
    if not prefix:
        raise RuntimeError('WSL is not available.')
    process = subprocess.run(
        prefix + ['wslpath', '-a', str(Path(path).resolve())],
        capture_output=True,
        text=True
    )
    if process.returncode != 0 or not process.stdout.strip():
        raise RuntimeError(f'Unable to convert Windows path for WSL: {path}\n{process.stderr}')
    return process.stdout.strip()


def run_wsl_command(command, log):
    run_process(wsl_prefix() + command, log)


def run_wsl_pipe(left_command, right_command, log):
    script = ' '.join(shlex.quote(str(item)) for item in left_command)
    script += ' | '
    script += ' '.join(shlex.quote(str(item)) for item in right_command)
    run_process(wsl_prefix() + ['bash', '-lc', script], log)


def detect_tool_backend():
    required = ['fastp', 'bwa', 'samtools']
    native_missing = [tool for tool in required if shutil.which(tool) is None]
    if not native_missing:
        return 'native', []
    if wsl_tools_available(required):
        return 'wsl', []
    return None, native_missing


def ensure_reference_indexes(reference, log, backend):
    reference = str(reference)
    bwa_index_markers = [reference + suffix for suffix in ['.bwt', '.0123']]
    tool_reference = to_wsl_path(reference) if backend == 'wsl' else reference

    if not any(os.path.exists(marker) for marker in bwa_index_markers):
        log.append('BWA index not found; building it once for the default reference genome.')
        if backend == 'wsl':
            run_wsl_command(['bwa', 'index', tool_reference], log)
        else:
            run_process(['bwa', 'index', tool_reference], log)
    else:
        log.append('Reusing existing BWA reference index.')

    fasta_index = reference + '.fai'
    if not os.path.exists(fasta_index):
        log.append('FASTA index not found; building samtools faidx index.')
        if backend == 'wsl':
            run_wsl_command(['samtools', 'faidx', tool_reference], log)
        else:
            run_process(['samtools', 'faidx', tool_reference], log)
    else:
        log.append('Reusing existing samtools FASTA index.')


def run_wgs(r1, r2, reference, output):
    inputs = {'R1': r1, 'R2': r2, 'reference': reference}
    missing_files = [name for name, path in inputs.items() if not path or not os.path.isfile(path)]
    if missing_files:
        return {'status': 'failed', 'log': 'Missing input files: ' + ', '.join(missing_files)}

    backend, native_missing = detect_tool_backend()
    if not backend:
        return {
            'status': 'failed',
            'log': (
                'Missing WGS tools: ' + ', '.join(native_missing) + '. '
                'Run the current BioSeq integrated launcher to install or repair the supported WSL toolchain.'
            ),
            'missing_tools': native_missing
        }

    output_dir = Path(output)
    output_dir.mkdir(parents=True, exist_ok=True)
    clean_r1 = output_dir / 'clean_R1.fastq.gz'
    clean_r2 = output_dir / 'clean_R2.fastq.gz'
    bam = output_dir / 'aligned.sorted.bam'
    log = [f'Using reference genome: {reference}', f'WGS tool backend: {backend}']

    if backend == 'wsl':
        tool_r1 = to_wsl_path(r1)
        tool_r2 = to_wsl_path(r2)
        tool_reference = to_wsl_path(reference)
        tool_clean_r1 = to_wsl_path(clean_r1)
        tool_clean_r2 = to_wsl_path(clean_r2)
        tool_bam = to_wsl_path(bam)
        tool_fastp_html = to_wsl_path(output_dir / 'fastp_report.html')
        tool_fastp_json = to_wsl_path(output_dir / 'fastp_report.json')
    else:
        tool_r1 = r1
        tool_r2 = r2
        tool_reference = reference
        tool_clean_r1 = str(clean_r1)
        tool_clean_r2 = str(clean_r2)
        tool_bam = str(bam)
        tool_fastp_html = str(output_dir / 'fastp_report.html')
        tool_fastp_json = str(output_dir / 'fastp_report.json')

    try:
        ensure_reference_indexes(reference, log, backend)

        fastp_command = [
            'fastp', '-i', tool_r1, '-I', tool_r2,
            '-o', tool_clean_r1, '-O', tool_clean_r2,
            '--html', tool_fastp_html,
            '--json', tool_fastp_json
        ]
        if backend == 'wsl':
            run_wsl_command(fastp_command, log)
        else:
            run_process(fastp_command, log)

        bwa_command = ['bwa', 'mem', tool_reference, tool_clean_r1, tool_clean_r2]
        samtools_sort = ['samtools', 'sort', '-o', tool_bam, '-']
        if backend == 'wsl':
            run_wsl_pipe(bwa_command, samtools_sort, log)
            run_wsl_command(['samtools', 'index', tool_bam], log)
            run_wsl_command(['samtools', 'flagstat', tool_bam], log)
        else:
            run_native_pipe(bwa_command, samtools_sort, log)
            run_process(['samtools', 'index', tool_bam], log)
            run_process(['samtools', 'flagstat', tool_bam], log)

        bcftools_available = shutil.which('bcftools') is not None if backend == 'native' else wsl_tools_available(['bcftools'])
        if bcftools_available:
            vcf = output_dir / 'variants.vcf.gz'
            tool_vcf = to_wsl_path(vcf) if backend == 'wsl' else str(vcf)
            mpileup = ['bcftools', 'mpileup', '-Ou', '-f', tool_reference, tool_bam]
            call = ['bcftools', 'call', '-mv', '-Oz', '-o', tool_vcf]
            if backend == 'wsl':
                run_wsl_pipe(mpileup, call, log)
                run_wsl_command(['bcftools', 'index', '-t', tool_vcf], log)
            else:
                run_native_pipe(mpileup, call, log)
                run_process(['bcftools', 'index', '-t', tool_vcf], log)
        else:
            log.append('bcftools not found; variant calling was skipped.')

        (output_dir / 'pipeline.log').write_text('\n'.join(log), encoding='utf-8')
        return {
            'status': 'success',
            'message': 'WGS pipeline completed.',
            'log': '\n'.join(log),
            'output': str(output_dir),
            'reference': reference,
            'tool_backend': backend
        }
    except Exception as exc:
        log.append(str(exc))
        (output_dir / 'pipeline.log').write_text('\n'.join(log), encoding='utf-8')
        return {
            'status': 'failed',
            'log': '\n'.join(log),
            'output': str(output_dir),
            'reference': reference,
            'tool_backend': backend
        }
