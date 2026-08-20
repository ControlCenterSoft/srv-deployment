"""Final runtime build identity for Control Center 1.0.11 hotfix builds.

Loaded after all 1.0.11 extensions so older release modules cannot overwrite
APP_BUILD with the original 20260819.5 value during register().
"""

import database

VERSION = '1.0.11'
BUILD = '20260820.1'


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
        # Runtime identity must not depend on DB availability during bootstrap.
        pass
