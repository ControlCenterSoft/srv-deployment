import json
import os
import tempfile
from pathlib import Path
from urllib.parse import urlparse

from flask import abort, request
import main
import release_107
import release_108
import release_108_build2

app = main.app
app.config['MAX_CONTENT_LENGTH'] = 64 * 1024


def atomic_write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f'.{path.name}.', suffix='.tmp', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as fh:
            json.dump(data, fh, ensure_ascii=False, indent=2)
            fh.write('\n')
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp_name, path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
        raise


main._write_json = atomic_write_json
release_107.register(app, main)
release_108.register(app, main)
release_108_build2.register(app, main)


@app.before_request
def protect_state_changing_requests():
    if request.method not in {'POST', 'PUT', 'PATCH', 'DELETE'}:
        return None
    origin = request.headers.get('Origin')
    if not origin:
        return None
    parsed = urlparse(origin)
    if parsed.scheme not in {'http', 'https'} or parsed.netloc != request.host:
        abort(403)
    return None


@app.after_request
def add_security_headers(response):
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['Referrer-Policy'] = 'no-referrer'
    response.headers['Permissions-Policy'] = 'camera=(), microphone=(), geolocation=()'
    response.headers['Cross-Origin-Opener-Policy'] = 'same-origin'
    response.headers['Content-Security-Policy'] = (
        "default-src 'self'; "
        "script-src 'self'; "
        "style-src 'self'; "
        "img-src 'self' data:; "
        "connect-src 'self'; "
        "object-src 'none'; "
        "base-uri 'none'; "
        "form-action 'self'; "
        "frame-ancestors 'none'"
    )
    if request.path.startswith('/static/'):
        response.headers['Cache-Control'] = 'public, max-age=3600'
    else:
        response.headers['Cache-Control'] = 'no-store'
    return response
