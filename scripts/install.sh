#!/bin/bash

bash scripts/build.sh
su -c "mv dist/cinder /usr/bin/cinder && chmod +x /usr/bin/cinder"

