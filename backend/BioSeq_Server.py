from flask import Flask, jsonify, request, send_file, send_from_directory
from flask_cors import CORS
from pathlib import Path
from werkzeug.utils import secure_filename
import zipfile

from file_scanner import scan_project
from r_runner import run_r_script
from wgs_runner import run_wgs

BASE_DIR = Path(__file__).resolve().parent
PROJECT_DIR = BASE_DIR.parent
UPLOAD_DIR = PROJECT_DIR / "uploads"
RESULT_DIR = PROJECT_DIR / "BioSeq_results"
R_SCRIPT_DIR = PROJECT_DIR / "R_scripts" / "RNAseq"

UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
RESULT_DIR.mkdir(parents=True, exist_ok=True)

app = Flask(__name__)
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


@app.get('/status')
def status():
    return jsonify({'service': 'running', 'version': '1.1.0'})


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
        return jsonify(run_wgs(
            str(resolve_input(data.get('r1'))),
            str(resolve_input(data.get('r2'))),
            str(resolve_input(data.get('reference'))),
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