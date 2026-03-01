#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Compiling LiveTodo..."
swiftc main.swift -o LiveTodo \
    -target arm64-apple-macos14.0 \
    -O \
    -whole-module-optimization

echo "Creating app bundle..."
rm -rf LiveTodo.app
mkdir -p LiveTodo.app/Contents/MacOS
mkdir -p LiveTodo.app/Contents/Resources

cp LiveTodo LiveTodo.app/Contents/MacOS/
cp Info.plist LiveTodo.app/Contents/

rm -f LiveTodo

echo ""
echo "Done! LiveTodo.app created."
echo ""
echo "To launch:  open LiveTodo.app"
echo "To install: cp -r LiveTodo.app /Applications/"
