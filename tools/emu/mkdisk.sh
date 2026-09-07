#!/bin/sh
# mkdisk.sh - build a bootable ELF-DOS disk1.ide for Run/02
#
# Usage: tools/emu/mkdisk.sh <output-dir> [extra files as SRC=/dest/path ...]
#
# Produces <output-dir>/disk1.ide: 32MB, one FAT16 partition at LBA 2048,
# ELF-DOS's MBR + kernel installed via sys/elfdos-sys, /bin populated from
# the sibling ELF-DOS repo, plus whatever else is named on the command
# line. Run it with:  cd <output-dir> && /opt/elfc/run02 -B -nv -nd
# (or drive it non-interactively with tools/emu/drive.py).
set -e
OUT="${1:?usage: mkdisk.sh <output-dir> [SRC=/dest ...]}"; shift
HERE=$(cd "$(dirname "$0")" && pwd)
EDOS="${ELFDOS_DIR:-$HERE/../../../ELF-DOS}"
mkdir -p "$OUT"; cd "$OUT"

dd if=/dev/zero of=disk1.ide bs=1M count=32 status=none
sfdisk -q disk1.ide >/dev/null <<'PT'
label: dos
unit: sectors
start=2048, size=63488, type=6, bootable
PT
dd if=/dev/zero of=part.img bs=512 count=63488 status=none
mkfs.fat -F 16 -n ELFDOS -s 4 part.img >/dev/null
dd if=part.img of=disk1.ide bs=512 seek=2048 conv=notrunc status=none
rm -f part.img

yes y | "$EDOS/sys/elfdos-sys" -m "$EDOS/mbr.bin" -k "$EDOS/kernel-full.bin" disk1.ide >/dev/null

set -- $(for f in "$EDOS"/bin/*; do echo "$f=/bin/$(basename "$f")"; done) "$@"
python3 "$HERE/fatput.py" disk1.ide 2048 "$@"
echo "built $OUT/disk1.ide"
