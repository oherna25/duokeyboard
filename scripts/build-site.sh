#!/bin/sh
# prototype/index.html is a body fragment because the Claude artifact viewer supplies the document shell.
# Without a viewport meta, phones lay the page out at 980px and real-size mode never triggers.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-"$root/_site"}
mkdir -p "$out"
{
  cat <<'HEAD'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0}[hidden]{display:none!important}</style>
</head>
<body>
HEAD
  cat "$root/prototype/index.html"
  printf '\n</body>\n</html>\n'
} > "$out/index.html"
echo "$out/index.html"
