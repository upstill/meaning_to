#!/bin/bash

# Download and install Flutter
curl -o flutter.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.tar.xz
tar xf flutter.tar.xz
export PATH="$PATH:$(pwd)/flutter/bin"

# Verify Flutter installation
flutter doctor

# Get dependencies and build
flutter pub get
flutter build web

# Replace environment variables in index.html
sed -i "s/%SUPABASE_URL%/$SUPABASE_URL/g" build/web/index.html
sed -i "s/%SUPABASE_ANON_KEY%/$SUPABASE_ANON_KEY/g" build/web/index.html 