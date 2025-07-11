#!/bin/bash

echo "Building Flutter app locally..."

# Check if environment variables are set
if [ -z "$SUPABASE_URL" ]; then
    echo "Warning: SUPABASE_URL not set"
    echo "Please set SUPABASE_URL environment variable"
    exit 1
fi

if [ -z "$SUPABASE_ANON_KEY" ]; then
    echo "Warning: SUPABASE_ANON_KEY not set"
    echo "Please set SUPABASE_ANON_KEY environment variable"
    exit 1
fi

# Build the Flutter web app with environment variables
flutter build web \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

echo "Build completed! Files are in build/web/"
echo "You can now deploy the contents of build/web/ to any static hosting service." 