#!/bin/bash

version="0.2"
year=$(date +%Y)
month=$(date +%m)
day=$(date +%d)

version_string="Cinder compiler v${version}-bootstrap (b${year}${month}${day})"

echo "$version_string" > version

echo ":: written: $version_string"
