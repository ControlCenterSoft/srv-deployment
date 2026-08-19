from pathlib import Path
from flask import Response, request


def register(app, main):
    static_dir = Path(app.root_path) / 'static'

    def assets_111_services():
        if request.method != 'GET':
            return None
        if request.path == '/static/app.js':
            try:
                names = ['app.js', 'release-108.js', 'release-110.js', 'release-110-fix.js', 'release-111.js', 'release-111-services.js']
                return Response('\n\n'.join((static_dir / x).read_text() for x in names), mimetype='application/javascript')
            except Exception:
                return None
        if request.path == '/static/app.css':
            try:
                names = ['app.css', 'release-108.css', 'release-110.css', 'release-111.css', 'release-111-services.css']
                return Response('\n\n'.join((static_dir / x).read_text() for x in names), mimetype='text/css')
            except Exception:
                return None
        return None

    app.before_request_funcs.setdefault(None, []).insert(0, assets_111_services)
