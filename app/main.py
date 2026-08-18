APP_VERSION = '1.0.8'
APP_BUILD = '20260819.2'

# Compatibility shim for legacy updaters (<= 1.0.6) that read APP_VERSION
# directly from app/main.py before running the installer. The actual 1.0.7
# application is kept byte-for-byte in main_base_107.py and aliased here so
# all route functions keep a single module-global state.
import os
import sys
import main_base_107 as _base

_base.APP_VERSION = APP_VERSION
_base.APP_BUILD = APP_BUILD

if __name__ == '__main__':
    _base.app.run(
        host=os.getenv('CONTROL_CENTER_HOST', '0.0.0.0'),
        port=int(os.getenv('CONTROL_CENTER_PORT', '8080')),
    )
else:
    sys.modules[__name__] = _base
