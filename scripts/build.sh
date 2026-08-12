#!/usr/bin/env bash
# Build a Cinder compiler by Cinder compiler

set -euo pipefail

prepare() {
    mkdir -p dist
}

build() {
    cinder build src/main.cnd -o dist/cinder.bin --emit=bin 
}

prepare
build
