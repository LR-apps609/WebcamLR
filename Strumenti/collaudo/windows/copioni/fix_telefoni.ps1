# Correzioni del collaudo 20 (t06 B5): solo la pagina Telefoni, con gli alberi UI Automation prima e dopo stampati nel registro.
$env:FIX_PAGINE_VOCI = 'Telefoni'
$env:FIX_PAGINE_ALBERI = 'Telefoni'
& (Join-Path $PSScriptRoot 'fix_pagine.ps1')
