#!/usr/bin/env bash
# Build a Cinder compiler as standalone binary

set -euo pipefail

prepare() {
    mkdir -p dist build
}

rbake_install() {
    if ! command -v rbake &> /dev/null; then
        echo "Installing rbake..."
        git clone https://github.com/z3nnix/rbake.git
        cd rbake
        sudo make install
        cd ..
        rm -rf rbake
    else
        echo "rbake already installed"
    fi
}

env() {
    cp -r lib main.rb build/
    cd build
    rbake main.rb -o ../dist/cinder
    cd ..
}

clean() {
    rm -rf build
}

prepare
rbake_install
env
clean