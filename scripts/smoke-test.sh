#!/bin/zsh
# Compila el núcleo (sin UI) y lo prueba contra la red real.
set -e
cd "$(dirname "$0")/.."
out="$(mktemp -d)/smoke"
swiftc -O \
  DomainWidget/Models.swift \
  DomainWidget/DomainLookupService.swift \
  DomainWidget/Core/*.swift \
  scripts/SmokeTest/main.swift \
  -o "$out"
"$out"
