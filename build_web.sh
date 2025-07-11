#!/bin/bash

# Build the Flutter web app
flutter build web

# Replace environment variable placeholders in the built HTML file
# This script should be run after flutter build web

# Get environment variables (you can set these or they'll be empty)
SUPABASE_URL=${SUPABASE_URL:-""}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY:-""}

# Replace placeholders in the built HTML file
sed -i '' "s/%SUPABASE_URL%/$SUPABASE_URL/g" build/web/index.html
sed -i '' "s/%SUPABASE_ANON_KEY%/$SUPABASE_ANON_KEY/g" build/web/index.html

echo "Web build completed with environment variables injected." 