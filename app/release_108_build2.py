from __future__ import annotations

import database

VERSION = '1.0.8'
BUILD = '20260819.2'


def register(app, main):
    main.APP_VERSION = VERSION
    main.APP_BUILD = BUILD
    try:
        lic = main._license_info()
        database.upsert_local_node(
            edition=lic.get('edition', 'Home'),
            version=VERSION,
            build=BUILD,
        )
    except Exception:
        pass
