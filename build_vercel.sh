#!/bin/bash

echo "Starting Vercel build process..."

# Check if build/web directory exists
if [ -d "build/web" ]; then
    echo "✅ Pre-built Flutter web files found"
    ls -la build/web/
else
    echo "❌ build/web directory not found"
    echo "Building Flutter web app..."
    
    # Download and install Flutter if needed
    if ! command -v flutter &> /dev/null; then
        echo "Installing Flutter..."
        curl -s https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.28.5-stable.tar.xz | tar xJ
        export PATH="$PATH:$(pwd)/flutter/bin"
    fi
    
    # Build the Flutter web app
    flutter pub get
    flutter build web
fi

echo "Build process completed!" 