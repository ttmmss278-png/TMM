from flask import Flask, jsonify, request, send_file
from flask_cors import CORS
import os
import zipfile

from file_scanner import scan_project
from r_runner import run_r_script
from wgs_runner import run_wgs

app = Flask(__name__)
CORS(app)

UPLOAD_DIR = "uploads"
RESULT_DIR = "BioSeq_results"
os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(RESULT_DIR, exist_ok=True)


@app.route('/status')
def status():
    return jsonify({'service':'running','version':'1.0.0'})


@app.route('/upload', methods=['POST'])
def upload():
    saved = []
    for f in request.files.values():
        path = os.path.join(UPLOAD_DIR, f.filename)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        f.save(path)
        saved.append(path)
    return jsonify({'status':'success','files':saved})


@app.route('/scan', methods=['POST'])
def scan():
    data = request.json or {}
    path = data.get('path', UPLOAD_DIR)
    return jsonify({'status':'success','files':scan_project(path)})


@app.route('/run', methods=['POST'])
def run():
    data = request.json or {}
    module = data.get('module')
    path = data.get('path', UPLOAD_DIR)
    output = os.path.join(RESULT_DIR, module or 'unknown')
    os.makedirs(output, exist_ok=True)

    if module == 'wgs':
        return jsonify(run_wgs(data.get('r1'), data.get('r2'), data.get('reference'), output))

    scripts = {
        'volcano':'../R_scripts/RNAseq/volcano_web.R',
        'bubble':'../R_scripts/RNAseq/bubble_web.R',
        'heatmap':'../R_scripts/RNAseq/heatmap_web.R',
        'violin':'../R_scripts/RNAseq/violin_web.R'
    }

    if module in scripts:
        return jsonify(run_r_script(scripts[module], path, output))

    return jsonify({'status':'error','message':'unknown module'})


@app.route('/result/<module>')
def result(module):
    folder = os.path.join(RESULT_DIR, module)
    files = []
    if os.path.exists(folder):
        for root, _, names in os.walk(folder):
            for name in names:
                files.append(os.path.join(root, name).replace('\\','/'))
    return jsonify({'status':'success','files':files})


@app.route('/download/<module>')
def download(module):
    folder = os.path.join(RESULT_DIR, module)
    zip_path = os.path.join(RESULT_DIR, module + '.zip')
    with zipfile.ZipFile(zip_path, 'w') as z:
        for root, _, files in os.walk(folder):
            for file in files:
                z.write(os.path.join(root,file), file)
    return send_file(zip_path, as_attachment=True)


if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8765)
