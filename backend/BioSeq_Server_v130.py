from flask import Flask, jsonify, request, send_file, send_from_directory
from flask_cors import CORS
from pathlib import Path
from werkzeug.utils import secure_filename
import hashlib
import json
import shutil
import zipfile

from file_scanner import scan_project
from r_runner import run_r_script
from wgs_runner import detect_tool_backend, run_wgs, wsl_tools_available

BASE_DIR = Path(__file__).resolve().parent
PROJECT_DIR = BASE_DIR.parent
UPLOAD_DIR = PROJECT_DIR / "uploads"
RESULT_DIR = PROJECT_DIR / "BioSeq_results"
R_SCRIPT_DIR = PROJECT_DIR / "R_scripts" / "RNAseq"
REFERENCE_DIR = PROJECT_DIR / "reference_genomes"
DEFAULT_REFERENCE = REFERENCE_DIR / "ToxoDB-68_TgondiiGT1_Genome.fasta"
REFERENCE_METADATA = REFERENCE_DIR / "reference_metadata.json"
EXPECTED_REFERENCE_SHA256 = "2d80433d0f2b5f605e79c11e263e15545bdb47e8dcbeb5f6b43c1843d1c27f40"
EXPECTED_REFERENCE_SIZE = 65205230
ENGINE_VERSION = "1.3.0"
ENGINE_BUILD = "20260730-force1"

UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
RESULT_DIR.mkdir(parents=True, exist_ok=True)
REFERENCE_DIR.mkdir(parents=True, exist_ok=True)

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 2 * 1024 * 1024 * 1024
CORS(app)


def resolve_input(value, default=UPLOAD_DIR):
    if not value:
        return Path(default)
    path = Path(value)
    if path.is_absolute():
        return path
    candidate = PROJECT_DIR / path
    return candidate if candidate.exists() else path


def unique_upload_path(filename):
    safe_name = secure_filename(Path(filename).name) or "uploaded_file"
    candidate = UPLOAD_DIR / safe_name
    stem, suffix = candidate.stem, candidate.suffix
    index = 1
    while candidate.exists():
        candidate = UPLOAD_DIR / f"{stem}_{index}{suffix}"
        index += 1
    return candidate


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def default_reference_status():
    installed = DEFAULT_REFERENCE.is_file()
    metadata = {}
    if REFERENCE_METADATA.is_file():
        try:
            metadata = json.loads(REFERENCE_METADATA.read_text(encoding='utf-8'))
        except (OSError, json.JSONDecodeError):
            metadata = {}
    return {
        'installed': installed,
        'filename': DEFAULT_REFERENCE.name,
        'path': str(DEFAULT_REFERENCE) if installed else '',
        'size_bytes': DEFAULT_REFERENCE.stat().st_size if installed else 0,
        'sha256': metadata.get('sha256', ''),
        'expected_sha256': EXPECTED_REFERENCE_SHA256,
        'expected_size_bytes': EXPECTED_REFERENCE_SIZE,
        'organism': 'Toxoplasma gondii GT1',
        'release': 'ToxoDB-68'
    }


def wgs_environment_status():
    backend, missing_tools = detect_tool_backend()
    if backend == 'native':
        bcftools_available = shutil.which('bcftools') is not None
    elif backend == 'wsl':
        bcftools_available = wsl_tools_available(['bcftools'])
    else:
        bcftools_available = False
    return {
        'ready': bool(backend),
        'backend': backend or 'unavailable',
        'missing_tools': missing_tools,
        'bcftools_available': bcftools_available
    }


def clear_reference_indexes(reference):
    reference = Path(reference)
    suffixes = ['.amb', '.ann', '.bwt', '.pac', '.sa', '.0123', '.fai', '.gzi', '.dict']
    for suffix in suffixes:
        candidate = Path(str(reference) + suffix)
        if candidate.exists():
            candidate.unlink()


@app.get('/status')
def status():
    return jsonify({
        'service': 'running',
        'version': ENGINE_VERSION,
        'build': ENGINE_BUILD,
        'default_reference': default_reference_status()
    })


@app.get('/environment')
def environment():
    return jsonify({
        'status': 'success',
        'engine_version': ENGINE_VERSION,
        'engine_build': ENGINE_BUILD,
        'wgs': wgs_environment_status(),
        'default_reference': default_reference_status()
    })


@app.get('/reference/status')
def reference_status():
    return jsonify({'status': 'success', **default_reference_status()})


@app.post('/reference/install')
def install_reference():
    uploaded = request.files.get('reference')
    if not uploaded or not uploaded.filename:
        return jsonify({'status': 'error', 'message': 'No reference genome received'}), 400

    suffix = Path(uploaded.filename).suffix.lower()
    if suffix not in {'.fa', '.fasta', '.fna'}:
        return jsonify({'status': 'error', 'message': 'Reference genome must be FASTA/FA/FNA format'}), 400

    temp_path = REFERENCE_DIR / f".{DEFAULT_REFERENCE.name}.uploading"
    if temp_path.exists():
        temp_path.unlink()
    uploaded.save(temp_path)

    actual_size = temp_path.stat().st_size
    actual_sha256 = sha256_file(temp_path)
    if actual_size != EXPECTED_REFERENCE_SIZE or actual_sha256 != EXPECTED_REFERENCE_SHA256:
        temp_path.unlink(missing_ok=True)
        return jsonify({
            'status': 'error',
            'message': 'The selected file does not match the verified ToxoDB-68 Tgondii GT1 reference genome.',
            'actual_size_bytes': actual_size,
            'actual_sha256': actual_sha256,
            'expected_size_bytes': EXPECTED_REFERENCE_SIZE,
            'expected_sha256': EXPECTED_REFERENCE_SHA256
        }), 400

    clear_reference_indexes(DEFAULT_REFERENCE)
    temp_path.replace(DEFAULT_REFERENCE)
    metadata = {
        'filename': DEFAULT_REFERENCE.name,
        'sha256': actual_sha256,
        'size_bytes': actual_size,
        'sequence_records': 2063,
        'total_bases': 63945332,
        'organism': 'Toxoplasma gondii GT1',
        'release': 'ToxoDB-68'
    }
    REFERENCE_METADATA.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')
    return jsonify({'status': 'success', 'message': 'Default reference genome installed.', **default_reference_status()})


@app.post('/upload')
def upload():
    saved = []
    for _, file_list in request.files.lists():
        for uploaded in file_list:
            if not uploaded or not uploaded.filename:
                continue
            path = unique_upload_path(uploaded.filename)
            uploaded.save(path)
            saved.append(str(path))
    if not saved:
        return jsonify({'status': 'error', 'message': 'No files received'}), 400
    return jsonify({'status': 'success', 'files': saved})


@app.post('/scan')
def scan():
    data = request.get_json(silent=True) or {}
    path = resolve_input(data.get('path'))
    if not path.exists():
        return jsonify({'status': 'error', 'message': f'Path not found: {path}'}), 404
    return jsonify({'status': 'success', 'files': scan_project(str(path))})


@app.post('/run')
def run():
    data = request.get_json(silent=True) or {}
    module = str(data.get('module') or '').strip().lower()
    output = RESULT_DIR / (module or 'unknown')
    output.mkdir(parents=True, exist_ok=True)

    if module == 'wgs':
        reference_value = data.get('reference')
        reference_path = resolve_input(reference_value) if reference_value else DEFAULT_REFERENCE
        if not reference_path.is_file():
            return jsonify({
                'status': 'failed',
                'message': 'Default reference genome is not installed. Select ToxoDB-68_TgondiiGT1_Genome.fasta once in the WGS page.',
                'reference_required': True
            }), 400
        return jsonify(run_wgs(
            str(resolve_input(data.get('r1'))),
            str(resolve_input(data.get('r2'))),
            str(reference_path),
            str(output)
        ))

    scripts = {
        'volcano': R_SCRIPT_DIR / 'volcano_web.R',
        'bubble': R_SCRIPT_DIR / 'bubble_web.R',
        'heatmap': R_SCRIPT_DIR / 'heatmap_web.R',
        'violin': R_SCRIPT_DIR / 'violin_web.R'
    }
    if module not in scripts:
        return jsonify({'status': 'error', 'message': f'Unknown module: {module}'}), 400

    input_path = resolve_input(data.get('path'))
    if not input_path.exists():
        return jsonify({'status': 'error', 'message': f'Input not found: {input_path}'}), 404

    extra_args = []
    if module == 'violin':
        extra_args = [
            str(data.get('genes') or ''),
            str(data.get('title') or ''),
            str(data.get('scale') or 'none')
        ]

    return jsonify(run_r_script(str(scripts[module]), str(input_path), str(output), extra_args))


@app.get('/result/<module>')
def result(module):
    folder = RESULT_DIR / secure_filename(module)
    files = []
    if folder.exists():
        files = [path.relative_to(RESULT_DIR).as_posix() for path in folder.rglob('*') if path.is_file()]
    return jsonify({'status': 'success', 'files': files})


@app.get('/file/<path:relative_path>')
def result_file(relative_path):
    return send_from_directory(str(RESULT_DIR), relative_path, as_attachment=False)


@app.get('/download/<module>')
def download(module):
    safe_module = secure_filename(module)
    folder = RESULT_DIR / safe_module
    if not folder.exists():
        return jsonify({'status': 'error', 'message': 'Result folder not found'}), 404

    zip_path = RESULT_DIR / f'{safe_module}.zip'
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in folder.rglob('*'):
            if path.is_file():
                archive.write(path, path.relative_to(folder))
    return send_file(zip_path, as_attachment=True, download_name=zip_path.name)


if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8765, threaded=True)
