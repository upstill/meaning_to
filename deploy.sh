#!/bin/bash

echo "Building Flutter app locally..."

# Build the Flutter web app
flutter build web

# Replace environment variables in the built files
if [ -n "$SUPABASE_URL" ]; then
    sed -i '' "s/%SUPABASE_URL%/$SUPABASE_URL/g" build/web/index.html
    echo "Replaced SUPABASE_URL"
else
    echo "Warning: SUPABASE_URL not set"
fi

if [ -n "$SUPABASE_ANON_KEY" ]; then
    sed -i '' "s/%SUPABASE_ANON_KEY%/$SUPABASE_ANON_KEY/g" build/web/index.html
    echo "Replaced SUPABASE_ANON_KEY"
else
    echo "Warning: SUPABASE_ANON_KEY not set"
fi

echo "Build completed! Files are in build/web/"
echo "You can now deploy the contents of build/web/ to any static hosting service." 