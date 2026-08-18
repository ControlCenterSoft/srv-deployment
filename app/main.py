APP_VERSION = '1.0.9'
APP_BUILD = '20260819.3'

# Compatibility shim for legacy updaters that read APP_VERSION directly from
# app/main.py before running the installer. The application implementation is
# kept in main_base_107.py; release extensions upgrade runtime behavior.
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
