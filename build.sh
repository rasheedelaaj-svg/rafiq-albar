#!/bin/sh
# wraps app.html (artifact-style body) into a standalone index.html for hosting
cd "$(dirname "$0")"
{ printf '<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0}[hidden]{display:none!important}img{max-width:100%%}</style></head><body>\n'; cat app.html; printf '\n</body></html>\n'; } > index.html
