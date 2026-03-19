#!/bin/bash

echo "🚀 Building and deploying to Vercel..."

# Step 0: Load environment variables from .env file
if [ -f .env ]; then
  echo "📋 Loading environment variables from .env..."
  export $(cat .env | grep -v '^#' | xargs)
  echo "✅ Environment variables loaded"
else
  echo "⚠️  No .env file found, using system environment variables"
fi

# Verify critical environment variables are set
if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
  echo "❌ Error: SUPABASE_URL and SUPABASE_ANON_KEY must be set!"
  echo "   Please create a .env file or set these environment variables."
  exit 1
fi

# Step 1: Clean previous build
echo "🧹 Cleaning Flutter build cache..."
flutter clean

# Step 2: Build Flutter web app
echo "🔨 Building Flutter web app..."
echo "   Using SUPABASE_URL: ${SUPABASE_URL:0:30}..."
flutter build web --release \
  --dart-define=YOUTUBE_API_KEY=$YOUTUBE_API_KEY \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY

if [ $? -ne 0 ]; then
  echo "❌ Flutter build failed!"
  exit 1
fi

# Step 3: Copy build output to project root (Vercel serves from root)
echo "📦 Copying build output to project root..."
# Remove old Flutter web files first to avoid stale files
rm -f index.html flutter.js flutter_bootstrap.js flutter_service_worker.js main.dart.js manifest.json
rm -rf assets/ canvaskit/ icons/
# Copy fresh build (glob * skips dotdirectories, so handle them separately)
cp -rf build/web/* .
# Copy dotdirectories (e.g. .well-known for Android App Links verification)
for d in build/web/.*; do
  base=$(basename "$d")
  [ "$base" = "." ] || [ "$base" = ".." ] && continue
  [ -e "$d" ] && cp -rf "$d" .
done

# Step 4: Update build markers with current timestamp
echo "🏷️  Updating build markers..."
BUILD_TIMESTAMP=$(date +%s)
FLUTTER_VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
FLUTTER_BUILD_NAME=$(echo $FLUTTER_VERSION | cut -d'+' -f1)
FLUTTER_BUILD_NUMBER=$(echo $FLUTTER_VERSION | cut -d'+' -f2)
echo "Build completed at $(date) — version $FLUTTER_VERSION" > build_id.txt
echo "{\"app_name\":\"meaning_to\",\"version\":\"$FLUTTER_BUILD_NAME\",\"build_number\":\"$FLUTTER_BUILD_NUMBER\",\"package_name\":\"meaning_to\"}" > version.json

# Verify files were copied
if [ ! -f "index.html" ]; then
  echo "❌ Build output not found!"
  exit 1
fi

echo "✅ Build output copied successfully"
echo "📋 Build ID: $(cat build_id.txt)"
echo "📋 Version: $(cat version.json)"
ls -la index.html flutter.js manifest.json

# Step 5: Deploy to Vercel
echo "🌐 Deploying to Vercel..."
vercel --prod

echo "✅ Deployment complete!"
echo "🌍 Visit: https://meaning-to.me"
echo "💡 Hard refresh (Cmd+Shift+R / Ctrl+Shift+R) to see changes"

