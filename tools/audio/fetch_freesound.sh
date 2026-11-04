#!/bin/bash
# Downloads Freesound HQ previews (only if the page says Creative Commons 0) into <outdir>/<id>/.
# Run from the folder that will hold raw/, e.g. a scratch folder outside the project.
# usage: fetch.sh <outdir> <page-url>...
out=$1; shift
for url in "$@"; do
  id=$(echo "$url" | grep -o 'sounds/[0-9]*' | cut -d/ -f2)
  html=$(curl -sL -A "Mozilla/5.0" "$url")
  lic=$(echo "$html" | grep -o 'full license text" href="[^"]*"[^>]*>[^<]*' | sed 's/.*>//' | head -1)
  prev=$(echo "$html" | grep -o 'https://cdn.freesound.org/previews/[^"]*-hq.mp3' | head -1)
  title=$(echo "$html" | grep -o '<title>[^<]*' | sed 's/<title>//')
  echo "$id | $lic | $title"
  if [ "$lic" = "Creative Commons 0" ] && [ -n "$prev" ]; then
    mkdir -p "$out/$id"; curl -sL -A "Mozilla/5.0" "$prev" -o "$out/$id/$id.mp3"
  fi
  sleep 3
done
