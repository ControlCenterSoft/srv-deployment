#!/usr/bin/env python3
import argparse
import json

import database


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('status')
    sub.add_parser('get-web-port')
    p = sub.add_parser('set-web-port')
    p.add_argument('port', type=int)
    args = parser.parse_args()

    if args.command == 'status':
        print(json.dumps(database.health(), ensure_ascii=False, default=str))
        return
    if args.command == 'get-web-port':
        print(int(database.get_setting('web.port', 8080)))
        return
    if args.command == 'set-web-port':
        if args.port < 1024 or args.port > 65535:
            raise SystemExit('web port must be 1024..65535')
        database.set_setting('web.port', args.port)
        database.set_setting('web.port.requested', None)
        print(args.port)
        return


if __name__ == '__main__':
    main()
