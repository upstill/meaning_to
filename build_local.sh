#!/bin/bash

echo "Building Flutter app locally for deployment..."

# Build the Flutter web app
flutter build web

echo "Build completed! Files are in build/web/"
echo "You can now deploy to Vercel - it will use the pre-built files." 