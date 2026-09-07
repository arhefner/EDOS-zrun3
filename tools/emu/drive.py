#!/usr/bin/env python3
"""Drive run02 under a pty: send lines, capture console output."""
import os, pty, sys, time, select, signal, termios

def run(cmds, timeout=60, idle=2.0, args=("-B","-nv","-nd")):
    pid, fd = pty.fork()
    if pid == 0:
        # run02 looks for disk1.ide in the CURRENT directory, not next to this script
        os.execv(os.environ.get("RUN02", "/opt/elfc/run02"), ["run02", *args])
    # Raw-ish pty: ICRNL would turn the CR we send into an LF, which the
    # BIOS line-input routine zrun3 uses (lib/zinputl.asm) ignores -- a
    # harness artifact, not target behaviour, since a real serial console
    # delivers CR. ECHO off too, so what we see is the program's own echo.
    try:
        a = termios.tcgetattr(fd)
        a[0] &= ~(termios.ICRNL | termios.INLCR | termios.IGNCR)
        a[3] &= ~termios.ECHO
        termios.tcsetattr(fd, termios.TCSANOW, a)
    except Exception:
        pass

    out = bytearray()
    queue = list(cmds)
    start = time.time()
    last = time.time()
    sent_all = False
    try:
        while True:
            if time.time() - start > timeout: break
            r, _, _ = select.select([fd], [], [], 0.2)
            if r:
                try: chunk = os.read(fd, 65536)
                except OSError: break
                if not chunk: break
                out += chunk
                last = time.time()
            else:
                if time.time() - last > idle:
                    if queue:
                        line = queue.pop(0)
                        os.write(fd, (line + "\r").encode())
                        last = time.time()
                    elif not sent_all:
                        sent_all = True
                        last = time.time()
                    else:
                        break
    finally:
        try: os.kill(pid, signal.SIGKILL)
        except OSError: pass
        try: os.waitpid(pid, 0)
        except OSError: pass
    return out.decode('latin-1')

if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("cmds", nargs="*")
    ap.add_argument("--timeout", type=float, default=60)
    ap.add_argument("--idle", type=float, default=2.0)
    a = ap.parse_args()
    txt = run(a.cmds, a.timeout, a.idle)
    sys.stdout.write(txt)
