import os
import shutil
import subprocess
from pathlib import Path


def run_command(command, log):
    log.append('$ ' + ' '.join(map(str, command)))
    process = subprocess.run(command, capture_output=True, text=True)
    if process.stdout:
        log.append(process.stdout)
    if process.stderr:
        log.append(process.stderr)
    if process.returncode != 0:
        raise RuntimeError(f"Command failed ({process.returncode}): {' '.join(command)}")


def run_pipe(left_command, right_command, log):
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


def ensure_reference_indexes(reference, log):
    reference = str(reference)
    bwa_index_markers = [reference + suffix for suffix in ['.bwt', '.0123']]
    if not any(os.path.exists(marker) for marker in bwa_index_markers):
        log.append('BWA index not found; building it once for the default reference genome.')
        run_command(['bwa', 'index', reference], log)
    else:
        log.append('Reusing existing BWA reference index.')

    fasta_index = reference + '.fai'
    if not os.path.exists(fasta_index):
        log.append('FASTA index not found; building samtools faidx index.')
        run_command(['samtools', 'faidx', reference], log)
    else:
        log.append('Reusing existing samtools FASTA index.')


def run_wgs(r1, r2, reference, output):
    inputs = {'R1': r1, 'R2': r2, 'reference': reference}
    missing_files = [name for name, path in inputs.items() if not path or not os.path.isfile(path)]
    if missing_files:
        return {'status': 'failed', 'log': 'Missing input files: ' + ', '.join(missing_files)}

    required_tools = ['fastp', 'bwa', 'samtools']
    missing_tools = [tool for tool in required_tools if shutil.which(tool) is None]
    if missing_tools:
        return {
            'status': 'failed',
            'log': 'Missing command-line tools: ' + ', '.join(missing_tools) + '. Install them and add them to PATH.'
        }

    output_dir = Path(output)
    output_dir.mkdir(parents=True, exist_ok=True)
    clean_r1 = output_dir / 'clean_R1.fastq.gz'
    clean_r2 = output_dir / 'clean_R2.fastq.gz'
    bam = output_dir / 'aligned.sorted.bam'
    log = [f'Using reference genome: {reference}']

    try:
        ensure_reference_indexes(reference, log)

        run_command([
            'fastp', '-i', r1, '-I', r2,
            '-o', str(clean_r1), '-O', str(clean_r2),
            '--html', str(output_dir / 'fastp_report.html'),
            '--json', str(output_dir / 'fastp_report.json')
        ], log)

        run_pipe(
            ['bwa', 'mem', reference, str(clean_r1), str(clean_r2)],
            ['samtools', 'sort', '-o', str(bam), '-'],
            log
        )
        run_command(['samtools', 'index', str(bam)], log)
        run_command(['samtools', 'flagstat', str(bam)], log)

        if shutil.which('bcftools'):
            vcf = output_dir / 'variants.vcf.gz'
            run_pipe(
                ['bcftools', 'mpileup', '-Ou', '-f', reference, str(bam)],
                ['bcftools', 'call', '-mv', '-Oz', '-o', str(vcf)],
                log
            )
            run_command(['bcftools', 'index', '-t', str(vcf)], log)
        else:
            log.append('bcftools not found; variant calling was skipped.')

        (output_dir / 'pipeline.log').write_text('\n'.join(log), encoding='utf-8')
        return {
            'status': 'success',
            'message': 'WGS pipeline completed.',
            'log': '\n'.join(log),
            'output': str(output_dir),
            'reference': reference
        }
    except Exception as exc:
        log.append(str(exc))
        (output_dir / 'pipeline.log').write_text('\n'.join(log), encoding='utf-8')
        return {'status': 'failed', 'log': '\n'.join(log), 'output': str(output_dir), 'reference': reference}
