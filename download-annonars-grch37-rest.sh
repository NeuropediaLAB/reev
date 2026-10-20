#!/usr/bin/env bash
set -uo pipefail
# Download ALL remaining annonars grch37 packages (builder 0.39.0) and symlink them.
# Progress-safe: aria2c resume, skips complete files, symlinks at end per package.
LOG="/home/arkantu/workspace/reev/download-annonars-grch37-rest.log"
exec >> "$LOG" 2>&1

BASE_URL="https://ceph-s3-public.cubi.bihealth.org/varfish-public"
S3_BASE="$BASE_URL/full/annonars"
TARGET_BASE="/mnt/reev-data/volumes/reev-static/data/download/annonars"
GRCH37="/mnt/reev-data/volumes/reev-static/data/annonars/grch37"

echo "=== Start $(date) ==="

# genes package discovered by listing (name contains 'genes-' and '+0.39.0')
GENES_PKG=""
GENES_PKG=$(curl -s --max-time 60 "$BASE_URL?prefix=full%2Fannonars%2Fgenes-&max-keys=100" \
  | python3 -c "
import sys, xml.etree.ElementTree as ET
NS='{http://s3.amazonaws.com/doc/2006-03-01/}'
root=ET.fromstring(sys.stdin.read())
names=set()
for k in root.findall(NS+'Contents'):
    key=k.find(NS+'Key').text
    p=key[len('full/annonars/'):].split('/')[0]
    if p.endswith('+0.39.0'):
        names.add(p)
for n in sorted(names): print(n)
" | tail -1)
if [ -n "$GENES_PKG" ]; then
  echo "Detected genes package (name in var GENES_PKG)"
fi

# Ordered small->big: package|symlinkname
ORDER=(
  "regions-grch37-20240711+0.39.0|regions"
  "gnomad-sv-genomes-grch37-2.1.1+0.39.0|gnomad-sv-genomes"
  "alphamissense-grch37-1+0.39.0|alphamissense"
  "functional-grch37-105.20201022+0.39.0|functional"
  "gnomad-mtdna-grch37-3.1+0.39.0|gnomad-mtdna"
  "gnomad-sv-exomes-grch37-0.3.1+0.39.0|gnomad-sv-exomes"
  "helixmtdb-grch37-20200327+0.39.0|helixmtdb"
  "cons-grch37-20161007+0.39.0|cons"
  "dbsnp-grch37-b151+0.39.0|dbsnp"
)
if [ -n "$GENES_PKG" ]; then ORDER+=( "$GENES_PKG|genes" ); fi
ORDER+=(
  "gnomad-exomes-grch37-2.1.1+0.39.0|gnomad_exomes"
  "gnomad-genomes-grch37-2.1.1+0.39.0|gnomad_genomes"
  "cadd-grch37-1.6+0.39.0|cadd"
)

_list_files() {
  local pkg="$1" encoded_prefix
  encoded_prefix=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1],safe=''))" "full/annonars/${pkg}/")
  python3 - "$pkg" <<'PYEOF'
import sys, urllib.request, urllib.parse, xml.etree.ElementTree as ET
pkg = sys.argv[1]
NS = '{http://s3.amazonaws.com/doc/2006-03-01/}'
BASE = 'https://ceph-s3-public.cubi.bihealth.org/varfish-public'
prefix = 'full/annonars/%s/' % pkg
keys, marker = [], None
while True:
    url = BASE + '?prefix=' + urllib.parse.quote(prefix, safe='') + '&max-keys=1000'
    if marker:
        url += '&marker=' + urllib.parse.quote(marker, safe='')
    tree = ET.parse(urllib.request.urlopen(url, timeout=60))
    cs = tree.getroot().findall(NS + 'Contents')
    if not cs:
        break
    keys += [c.find(NS + 'Key').text for c in cs]
    if tree.getroot().find(NS + 'IsTruncated').text != 'true':
        break
    marker = keys[-1]
for k in keys:
    if not k.endswith('/'):
        print(k[len(prefix):])
PYEOF
}

for ENTRY in "${ORDER[@]}"; do
  PKG="${ENTRY%%|*}"; SYMNAME="${ENTRY##*|}"
  TARGET="$TARGET_BASE/$PKG"
  if [ -L "$GRCH37/$SYMNAME" ] && [ -e "$GRCH37/$SYMNAME/rocksdb" ]; then
    echo "SKIP $PKG (symlink $SYMNAME already complete)"
    continue
  fi
  echo ""
  echo "=== $(date '+%H:%M:%S') Downloading $PKG -> $SYMNAME ==="
  aria_input="/tmp/aria_input_${PKG}.txt"
  rm -f "$aria_input"
  while IFS= read -r relpath; do
    destdir="$TARGET/$(dirname "$relpath")"
    filename=$(basename "$relpath")
    mkdir -p "$destdir"
    if [ -f "$TARGET/$relpath" ] && [ ! -f "$TARGET/$relpath.aria2" ]; then
      echo "  SKIP (exists): $relpath"
      continue
    fi
    echo "$S3_BASE/$PKG/$relpath" >> "$aria_input"
    echo "  dir=$destdir" >> "$aria_input"
    echo "  out=$filename" >> "$aria_input"
  done < <(_list_files "$PKG")
  if [ ! -s "$aria_input" ]; then
    echo "  All files already downloaded."
  else
    echo "  $(grep -c '^https' "$aria_input") files, aria2c 12 parallel..."
    aria2c --input-file="$aria_input" --max-concurrent-downloads=12 --split=1 \
      --max-connection-per-server=1 --check-certificate=false \
      --file-allocation=trunc --continue=true --auto-file-renaming=false \
      --summary-interval=0 --console-log-level=warn || echo "  aria2c exit $?"
  fi
  if [ -n "$(find "$TARGET" -name '*.aria2')" ]; then
    echo "  !! $PKG INCOMPLETE (leftover .aria2 control files)"
    continue
  fi
  ln -sfn "../../download/annonars/$PKG" "$GRCH37/$SYMNAME"
  if [ "$SYMNAME" = "genes" ]; then
    rm -f "$GRCH37/$SYMNAME"
    ln -sfn "../download/annonars/$PKG" "$GRCH37/../genes"
  fi
  echo "  LINK $SYMNAME -> $PKG"
  echo "=== $(date '+%H:%M:%S') Done $PKG ==="
done

echo ""
echo "=== Restarting annonars $(date) ==="
cd /home/arkantu/workspace/reev
docker compose restart annonars
sleep 20
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' reev-annonars)
echo "db-info:"
curl -s --max-time 10 "http://$IP:8080/annos/db-info?genome_release=grch37" || true
echo ""
echo "=== All done $(date) ==="
