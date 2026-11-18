#!/bin/bash
# Runs the chapter / contents / index detection checks (English + Bangla). No Ollama needed.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)"
C=Sources/Pandulipi/Core
swiftc -parse-as-library -o "$OUT/selftest" Tests/StructureSelfTest.swift \
  $C/Models.swift $C/EPUBExporter.swift $C/BookStructure.swift $C/SourceDocument.swift $C/Tesseract.swift
"$OUT/selftest" "$@"
