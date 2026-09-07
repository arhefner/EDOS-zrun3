#!/usr/bin/env python3
"""Minimal FAT16 injector: write host files into a FAT16 partition inside a
raw disk image, creating directories as needed. Short (8.3) names only."""
import sys, os, struct

SEC = 512

class Fat16:
    def __init__(self, path, part_lba):
        self.f = open(path, 'r+b')
        self.base = part_lba * SEC
        b = self.rd(0, SEC)
        self.bps       = struct.unpack_from('<H', b, 11)[0]
        self.spc       = b[13]
        self.rsvd      = struct.unpack_from('<H', b, 14)[0]
        self.nfats     = b[16]
        self.rootents  = struct.unpack_from('<H', b, 17)[0]
        self.spf       = struct.unpack_from('<H', b, 22)[0]
        tot16          = struct.unpack_from('<H', b, 19)[0]
        tot32          = struct.unpack_from('<I', b, 32)[0]
        self.total     = tot16 or tot32
        assert self.bps == SEC, self.bps
        self.fat0      = self.rsvd
        self.rootsec   = self.rsvd + self.nfats * self.spf
        self.rootsecs  = (self.rootents * 32 + SEC - 1) // SEC
        self.data0     = self.rootsec + self.rootsecs
        self.nclusters = (self.total - self.data0) // self.spc

    def rd(self, sec, n):
        self.f.seek(self.base + sec * SEC); return self.f.read(n)
    def wr(self, sec, data):
        self.f.seek(self.base + sec * SEC); self.f.write(data)

    # --- FAT ---
    def fat_get(self, c):
        b = self.rd(self.fat0 + (c * 2) // SEC, SEC)
        return struct.unpack_from('<H', b, (c * 2) % SEC)[0]
    def fat_set(self, c, v):
        for i in range(self.nfats):
            s = self.fat0 + i * self.spf + (c * 2) // SEC
            b = bytearray(self.rd(s, SEC))
            struct.pack_into('<H', b, (c * 2) % SEC, v)
            self.wr(s, bytes(b))
    def alloc(self, n):
        out = []
        c = 2
        while len(out) < n:
            if c >= self.nclusters + 2: raise RuntimeError('disk full')
            if self.fat_get(c) == 0 and c not in out: out.append(c)
            c += 1
        for i, cl in enumerate(out):
            self.fat_set(cl, 0xFFFF if i == len(out) - 1 else out[i + 1])
        return out

    def clus_sec(self, c): return self.data0 + (c - 2) * self.spc

    def write_chain(self, data):
        if not data: return 0
        csz = self.spc * SEC
        n = (len(data) + csz - 1) // csz
        chain = self.alloc(n)
        for i, c in enumerate(chain):
            chunk = data[i * csz:(i + 1) * csz].ljust(csz, b'\0')
            self.wr(self.clus_sec(c), chunk)
        return chain[0]

    # --- directories ---
    def read_dir(self, clus):
        """Return (list_of_32byte_entries, writer(idx, entry))."""
        if clus == 0:
            secs = list(range(self.rootsec, self.rootsec + self.rootsecs))
        else:
            secs = []
            c = clus
            while 2 <= c < 0xFFF8:
                secs += list(range(self.clus_sec(c), self.clus_sec(c) + self.spc))
                c = self.fat_get(c)
        buf = b''.join(self.rd(s, SEC) for s in secs)
        return buf, secs

    def dir_write(self, secs, idx, entry):
        s = secs[(idx * 32) // SEC]
        off = (idx * 32) % SEC
        b = bytearray(self.rd(s, SEC))
        b[off:off + 32] = entry
        self.wr(s, bytes(b))

    def find(self, clus, name83):
        buf, secs = self.read_dir(clus)
        for i in range(len(buf) // 32):
            e = buf[i * 32:i * 32 + 32]
            if e[0] in (0x00, 0xE5): continue
            if e[11] & 0x0F == 0x0F: continue
            if e[0:11] == name83: return e, i, secs
        return None, None, secs

    def free_slot(self, clus):
        buf, secs = self.read_dir(clus)
        for i in range(len(buf) // 32):
            if buf[i * 32] in (0x00, 0xE5): return i, secs
        raise RuntimeError('directory full (no expansion implemented)')

    def mkentry(self, clus, name83, attr, first, size, ntres=0):
        i, secs = self.free_slot(clus)
        e = bytearray(32)
        e[0:11] = name83
        e[11] = attr
        e[12] = ntres                            # NTRes lowercase hints
        struct.pack_into('<H', e, 22, 0x6000)   # time
        struct.pack_into('<H', e, 24, 0x5A21)   # date 2025-01-01
        struct.pack_into('<H', e, 26, first)
        struct.pack_into('<I', e, 28, size)
        self.dir_write(secs, i, bytes(e))
        return bytes(e)

    def mkdir(self, parent, name83, ntres=0):
        e, i, secs = self.find(parent, name83)
        if e: return struct.unpack_from('<H', e, 26)[0]
        c = self.alloc(1)[0]
        self.wr(self.clus_sec(c), b'\0' * (self.spc * SEC))
        dot  = bytearray(32); dot[0:11]  = b'.          '; dot[11] = 0x10
        struct.pack_into('<H', dot, 26, c)
        ddot = bytearray(32); ddot[0:11] = b'..         '; ddot[11] = 0x10
        struct.pack_into('<H', ddot, 26, parent)
        blk = bytes(dot) + bytes(ddot)
        self.wr(self.clus_sec(c), blk.ljust(self.spc * SEC, b'\0'))
        self.mkentry(parent, name83, 0x10, c, 0, ntres)
        return c

def n83(name):
    if '.' in name:
        b, x = name.rsplit('.', 1)
    else:
        b, x = name, ''
    nt = 0
    if b and b == b.lower() and b != b.upper(): nt |= 0x08
    if x and x == x.lower() and x != x.upper(): nt |= 0x10
    return (b[:8].upper().ljust(8) + x[:3].upper().ljust(3)).encode('ascii'), nt

def main():
    img, lba = sys.argv[1], int(sys.argv[2])
    fs = Fat16(img, lba)
    sys.stderr.write("FAT16: spc=%d rsvd=%d nfats=%d spf=%d rootents=%d data0=%d nclus=%d\n"
                     % (fs.spc, fs.rsvd, fs.nfats, fs.spf, fs.rootents, fs.data0, fs.nclusters))
    for spec in sys.argv[3:]:
        src, dst = spec.split('=', 1)
        parts = [p for p in dst.split('/') if p]
        clus = 0
        for d in parts[:-1]:
            nm, nt = n83(d)
            clus = fs.mkdir(clus, nm, nt)
        data = open(src, 'rb').read()
        nm, nt = n83(parts[-1])
        # replace an existing file of the same name: free its chain and
        # mark the entry deleted, so the new one is the only match
        old, idx, secs = fs.find(clus, nm)
        if old is not None:
            c = struct.unpack_from('<H', old, 26)[0]
            while 2 <= c < 0xFFF8:
                nxt = fs.fat_get(c); fs.fat_set(c, 0); c = nxt
            e = bytearray(old); e[0] = 0xE5
            fs.dir_write(secs, idx, bytes(e))
        first = fs.write_chain(data)
        fs.mkentry(clus, nm, 0x20, first, len(data), nt)
        print("  %-28s -> %s (%d bytes)" % (src, dst, len(data)))
    fs.f.close()

main()
