from flask import Flask, jsonify, request
from flask_cors import CORS
import os

from file_scanner import scan_project
from r_runner import run_r_script
from wgs_runner import run_wgs

app = Flask(__name__)
CORS(app)

UPLOAD_DIR = "uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)


@app.route('/status')
def status():
    return jsonify({
        'service': 'running',
        'version': '1.0.0'
    })


@app.route('/upload', methods=['POST'])
def upload():
    saved = []
    for f in request.files.values():
        path = os.path.join(UPLOAD_DIR, f.filename)
        f.save(path)
        saved.append(path)
    return jsonify({'status':'success','files':saved})


@app.route('/scan', methods=['POST'])
def scan():
    data = request.json or {}
    path = data.get('path', UPLOAD_DIR)
    return jsonify({
        'status':'success',
        'files':scan_project(path)
    })


@app.route('/run', methods=['POST'])
def run():
    data = request.json or {}
    module = data.get('module')
    path = data.get('path', UPLOAD_DIR)
    output = os.path.join('BioSeq_results', module or 'unknown')
    os.makedirs(output, exist_ok=True)

    scripts = {
        'volcano':'../R_scripts/RNAseq/volcano_web.R',
        'bubble':'../R_scripts/RNAseq/bubble_web.R',
        'heatmap':'../R_scripts/RNAseq/heatmap_web.R',
        'violin':'../R_scripts/RNAseq/violin_web.R'
    }

    if module in scripts:
        return jsonify(run_r_script(scripts[module], path, output))

    return jsonify({'status':'error','message':'unknown module'})


@app.route('/run_wgs', methods=['POST'])
def run_wgs_api():
    data = request.json or {}
    return jsonify(run_wgs(
        data.get('r1'),
        data.get('r2'),
        data.get('reference'),
        data.get('output','BioSeq_results/WGS')
    ))


if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8765)
