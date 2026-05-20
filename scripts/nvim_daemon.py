#!/usr/bin/env python3
"""Start nvim in a pty (non-headless) with an RPC listen socket.

Usage:
    python3 scripts/nvim_daemon.py [nvim_args...]

The daemon keeps nvim alive via pty.fork(). nvim dies when this script exits.
The chosen socket path is printed to stdout — capture it for --remote-* commands.
The path is also written to SOCKET_PATH_FILE for convenience.

The path is written *after* the socket is actually accepting connections, so
callers can use it immediately without a race.
"""

import pty
import os
import sys
import signal
import socket
import atexit
import time

SOCKET_PATH = "/tmp/nvim-server"
SOCKET_PATH_FILE = "/tmp/nvim-socket-path"
SOCKET_WAIT_TIMEOUT = 10.0
SOCKET_POLL_INTERVAL = 0.05


def _socket_in_use(path: str) -> bool:
    """Return True if a Unix socket at *path* is alive and accepting connections."""
    if not os.path.exists(path):
        return False
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(path)
        s.close()
        return True
    except (ConnectionRefusedError, FileNotFoundError):
        os.unlink(path)
        return False


def _find_socket_path() -> str:
    """Return an available socket path, trying *SOCKET_PATH*, *-1*, *-2*…"""
    if not _socket_in_use(SOCKET_PATH):
        return SOCKET_PATH
    for i in range(1, 100):
        path = f"{SOCKET_PATH}-{i}"
        if not _socket_in_use(path):
            return path
    raise RuntimeError("Could not find an available socket path")


def _wait_for_socket(path: str, timeout: float = SOCKET_WAIT_TIMEOUT) -> None:
    """Block until the Unix socket at *path* is accepting connections."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if os.path.exists(path):
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.settimeout(0.1)
                s.connect(path)
                s.close()
                return
            except (ConnectionRefusedError, FileNotFoundError, OSError):
                pass
        time.sleep(SOCKET_POLL_INTERVAL)
    raise RuntimeError(
        f"Socket {path} did not become ready within {timeout}s"
    )


# Mutable state kept so cleanup is idempotent (atexit + signals).
_socket_path = None
_nvim_pid = None


def _cleanup():
    """Kill the nvim child and remove the socket file (idempotent)."""
    global _nvim_pid, _socket_path
    pid = _nvim_pid
    sp = _socket_path
    _nvim_pid = None
    _socket_path = None
    if pid is not None:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if sp is not None and os.path.exists(sp):
        try:
            os.unlink(sp)
        except OSError:
            pass
    if os.path.exists(SOCKET_PATH_FILE):
        try:
            os.unlink(SOCKET_PATH_FILE)
        except OSError:
            pass


def _signal_handler(signum, frame):
    _cleanup()
    sys.exit(0)


def main():
    global _nvim_pid, _socket_path

    _socket_path = _find_socket_path()

    signal.signal(signal.SIGTERM, _signal_handler)
    signal.signal(signal.SIGINT, _signal_handler)
    atexit.register(_cleanup)

    argv = [
        "nvim",
        "--listen",
        _socket_path,
        "-c",
        "set columns=120 lines=40",
    ] + sys.argv[1:]

    pid, fd = pty.fork()
    if pid == 0:
        os.execvp("nvim", argv)
    else:
        _nvim_pid = pid
        _wait_for_socket(_socket_path)
        with open(SOCKET_PATH_FILE, "w") as f:
            f.write(_socket_path + "\n")
        print(_socket_path, flush=True)
        os.waitpid(pid, 0)


if __name__ == "__main__":
    main()
