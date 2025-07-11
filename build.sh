#!/bin/bash

# Exit on any error
set -e

echo "Starting Flutter build process..."
echo "Current directory: $(pwd)"
echo "Listing files:"
ls -la

# Download and install Flutter (using a more recent version)
echo "Downloading Flutter..."
curl -L -o flutter.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.28.5-stable.tar.xz

echo "Extracting Flutter..."
tar xf flutter.tar.xz

echo "Setting up PATH..."
export PATH="$PATH:$(pwd)/flutter/bin"

echo "Flutter version:"
flutter --version

echo "Running flutter doctor..."
flutter doctor --verbose

echo "Getting dependencies..."
flutter pub get

echo "Building web app..."
flutter build web --release

echo "Replacing environment variables..."
if [ -n "$SUPABASE_URL" ]; then
    sed -i "s/%SUPABASE_URL%/$SUPABASE_URL/g" build/web/index.html
    echo "Replaced SUPABASE_URL"
else
    echo "Warning: SUPABASE_URL not set"
fi

if [ -n "$SUPABASE_ANON_KEY" ]; then
    sed -i "s/%SUPABASE_ANON_KEY%/$SUPABASE_ANON_KEY/g" build/web/index.html
    echo "Replaced SUPABASE_ANON_KEY"
else
    echo "Warning: SUPABASE_ANON_KEY not set"
fi

echo "Build completed successfully!"
echo "Build output directory contents:"
ls -la build/web/ 