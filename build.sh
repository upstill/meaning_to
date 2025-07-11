#!/bin/bash

echo "Building Flutter app for serverless deployment..."

# Download and install Flutter
echo "Downloading Flutter..."
curl -s https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.28.5-stable.tar.xz | tar xJ

echo "Setting up PATH..."
export PATH="$PATH:$(pwd)/flutter/bin"

echo "Getting dependencies..."
flutter pub get

echo "Building web app..."
flutter build web

echo "Build completed! Files are in build/web/"
echo "The serverless API will be deployed automatically by Vercel." 