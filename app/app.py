from flask import Flask, jsonify
import os

app = Flask(__name__)

# The main website page
@app.route('/')
def home():
    return "<h1>Hello from the Python Flask App!</h1><p>Running in a secure tenant namespace.</p>"

# Liveness probe (restarts container if it fails)
@app.route('/healthz')
def healthz():
    return jsonify({"status": "healthy"}), 200

# Readiness probe (gates the pod into the Service endpoints)
@app.route('/readyz')
def readyz():
    return jsonify({"status": "ready"}), 200

if __name__ == '__main__':
    # Run on port 5000, which is the default for Flask
    app.run(host='0.0.0.0', port=5000)