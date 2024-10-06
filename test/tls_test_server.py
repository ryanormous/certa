#!/usr/bin/env python3

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# GLOBAL

DEFAULT_PORT = 9933


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# IMPORT

import json
import os
import socket
import ssl
from argparse import ArgumentParser
from subprocess import Popen


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# UTIL

class CertaError(RuntimeError): ...


def check_user():
    if os.geteuid() != 0:
        raise CertaError('USER NOT PRIVILEGED')


def get_args():
    parser = ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        '-r', '--root',
        action = 'store_true',
        dest = 'root',
        help = 'root certificate'
    )
    group.add_argument(
        '-s', '--sub',
        action = 'store',
        dest = 'sub',
        help = 'subordinate certificate'
    )
    parser.add_argument(
        '--host',
        action = 'store',
        dest = 'host',
        default = 'localhost'
    )
    parser.add_argument(
        '--port',
        action = 'store',
        type = int,
        dest = 'port',
        default = DEFAULT_PORT
    )
    return parser.parse_args()


def get_CA_dir():
    cert = 'certa.crt'
    dirs = (
        # FEDORA, RHEL
        '/usr/share/pki/ca-trust-source/anchors',
        # DEBIAN, UBUNTU
        '/usr/local/share/ca-certificates',
    )
    for i in dirs:
        if os.path.exists(i):
            return i
    raise CertaError(f'CA DIRECTORY NOT FOUND AT PATHS: {dirs!r}')


def get_keypair(args):
    # WORKING DIRECTORY
    cwd = os.path.dirname(os.path.abspath(__file__))

    # <certa_home>/etc
    etc = os.path.join(os.path.dirname(cwd), 'etc')

    # <certa_home>/etc/certa-root.conf
    # <certa_home>/etc/<subordinate>.conf
    ssl_conf = os.path.join(
        etc, 'certa-root.conf' if args.root else f'{args.sub}.conf'
    )
    assert os.path.exists(ssl_conf), f'REQUIRED PATH NOT FOUND: {ssl_conf!r}'

    local_ca = os.path.join(
        os.path.dirname(cwd), 'ca/priv' if args.root else f'sub/{args.sub}'
    )
    assert os.path.exists(local_ca), f'REQUIRED PATH NOT FOUND: {local_ca!r}'

    # KEY-PAIR
    if args.root:
        certfile = os.path.join(get_CA_dir(), 'certa.crt')
        # <certa_home>/ca/priv/certa-root.key.pem
        keyfile = os.path.join(local_ca, 'certa-root.key.pem')
    else:
         # <certa_home>/sub/<sub>/<sub>.crt.pem
         certfile = os.path.join(local_ca, f'{args.sub}.crt.pem')
         # <certa_home>/sub/<sub>/<sub>.key.pem
         keyfile = os.path.join(local_ca, f'{args.sub}.key.pem')
    assert os.path.exists(certfile), f'REQUIRED PATH NOT FOUND: {certfile!r}'
    assert os.path.exists(keyfile), f'REQUIRED PATH NOT FOUND: {keyfile!r}'

    return (certfile, keyfile)


def pprint(addr, data):
    js = {'address': addr}
    if not data:
        js['request'] = None
        print(json.dumps(js, indent=4))
        return False
    for line in data.decode().splitlines():
        if line:
            if ':' in line:
                js.update([line.split(':', maxsplit=1)])
            else:
                js['request'] = line
    print(json.dumps(js, indent=4))
    return True


def serve(host, port, certfile, keyfile):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile, keyfile)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        print('CERTIFICATE:', certfile)
        print('KEY:', keyfile)
        print(f'SERVICE ADDRESS: https://{host}:{port}')
        sock.bind((host, port))
        sock.listen(0)
        with context.wrap_socket(sock, server_side=True) as _sock:
            while True:
                try:
                    conn, addr = _sock.accept()
                except ssl.SSLError as e:
                    print(e)
                else:
                    with conn:
                        while True:
                            if not pprint(addr[0], conn.recv(1024)):
                                break


def main():
    # USER PRIVILEGE
    check_user()
    # ARGUMENTS
    args = get_args()
    # KEY-PAIR
    certfile, keyfile = get_keypair(args)
    # SERVE
    try:
        serve(args.host, args.port, certfile, keyfile)
    except KeyboardInterrupt:
        print()


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# MAIN

main()

