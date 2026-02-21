#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Compiling LittleTodo..."
swiftc main.swift -o LittleTodo \
    -target arm64-apple-macos14.0 \
    -O \
    -whole-module-optimization

echo "Creating app bundle..."
rm -rf LittleTodo.app
mkdir -p LittleTodo.app/Contents/MacOS
mkdir -p LittleTodo.app/Contents/Resources

cp LittleTodo LittleTodo.app/Contents/MacOS/
cp Info.plist LittleTodo.app/Contents/

rm -f LittleTodo

echo ""
echo "Done! LittleTodo.app created."
echo ""
echo "To launch:  open LittleTodo.app"
echo "To install: cp -r LittleTodo.app /Applications/"
