#!/usr/bin/env python3
"""Start nvim in a pty (non-headless) with an RPC listen socket.

Usage:
    python3 scripts/nvim_daemon.py [nvim_args...]

The daemon keeps nvim alive via pty.fork(). nvim dies when this script exits.
Communicate via `nvim --server /tmp/nvim-server --remote-send/--remote-expr`.
"""

import pty
import os
import sys
import signal

SOCKET_PATH = "/tmp/nvim-server"


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

    argv = [
        "nvim",
        "--listen",
        SOCKET_PATH,
        "-c",
        "set columns=120 lines=40",
    ] + sys.argv[1:]

    pid, fd = pty.fork()
    if pid == 0:
        os.execvp("nvim", argv)
    else:
        while True:
            try:
                os.waitpid(pid, 0)
                break
            except KeyboardInterrupt:
                break


if __name__ == "__main__":
    main()
