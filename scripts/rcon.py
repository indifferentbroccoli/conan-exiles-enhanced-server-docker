#!/usr/bin/env python3
"""Minimal Source RCON client used by the mod watchdog."""

import socket
import struct
import sys

SERVERDATA_AUTH = 3
SERVERDATA_EXECCOMMAND = 2
SERVERDATA_AUTH_RESPONSE = 2
RCON_TIMEOUT = 10


def _recvall(sock, n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise ConnectionError("Connection closed by server")
        data += chunk
    return data


def _send_packet(sock, req_id, pkt_type, body):
    body_bytes = body.encode("utf-8") + b"\x00\x00"
    size = 4 + 4 + len(body_bytes)
    packet = struct.pack("<iii", size, req_id, pkt_type) + body_bytes
    sock.sendall(packet)


def _recv_packet(sock):
    raw_size = _recvall(sock, 4)
    size = struct.unpack("<i", raw_size)[0]
    data = _recvall(sock, size)
    req_id = struct.unpack("<i", data[0:4])[0]
    pkt_type = struct.unpack("<i", data[4:8])[0]
    body = data[8:-2].decode("utf-8", errors="replace")
    return req_id, pkt_type, body


def rcon_exec(host, port, password, command):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(RCON_TIMEOUT)
        s.connect((host, int(port)))

        # Authenticate
        _send_packet(s, 1, SERVERDATA_AUTH, password)
        while True:
            req_id, pkt_type, _ = _recv_packet(s)
            if pkt_type == SERVERDATA_AUTH_RESPONSE:
                if req_id == -1:
                    raise PermissionError("RCON authentication failed: wrong password")
                break

        # Execute command
        _send_packet(s, 2, SERVERDATA_EXECCOMMAND, command)
        _, _, body = _recv_packet(s)
        return body


if __name__ == "__main__":
    if len(sys.argv) < 5:
        sys.stderr.write(
            f"Usage: {sys.argv[0]} <host> <port> <password> <command>\n"
        )
        sys.exit(1)

    host_arg = sys.argv[1]
    port_arg = sys.argv[2]
    password_arg = sys.argv[3]
    command_arg = " ".join(sys.argv[4:])

    try:
        result = rcon_exec(host_arg, port_arg, password_arg, command_arg)
        if result:
            print(result)
    except Exception as e:
        sys.stderr.write(f"RCON error: {e}\n")
        sys.exit(1)
