from flask import Flask, jsonify, request
from flask_cors import CORS
import os

app = Flask(__name__)
CORS(app)

UPLOAD_DIR = "uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

@app.route('/status')
def status():
    return jsonify({
        'service':'running',
        'version':'1.0.0'
    })

@app.route('/upload', methods=['POST'])
def upload():
    saved=[]
    for f in request.files.values():
        path=os.path.join(UPLOAD_DIR, f.filename)
        f.save(path)
        saved.append(path)
    return jsonify({'status':'success','files':saved})

@app.route('/run', methods=['POST'])
def run():
    data=request.json or {}
    return jsonify({
        'status':'queued',
        'module':data.get('module','unknown')
    })

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8765)
