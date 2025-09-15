#!/bin/bash

# Cache Issue Troubleshooting Script
# Use this when you're still seeing stale content after deployment

set -e

echo "🔧 Fixing cache issues..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Step 1: Force clear all Vercel caches
print_status "🗑️  Clearing Vercel caches..."
vercel --force 2>/dev/null || true

# Step 2: Deploy with unique build ID
TIMESTAMP=$(date +%s)
print_status "🚀 Deploying with unique build ID: $TIMESTAMP"

# Build with timestamp
flutter clean
flutter pub get
flutter build web --release

# Deploy with force and unique identifier
vercel --force --yes

# Step 3: Get deployment URL and add aggressive cache busting
DEPLOY_URL=$(vercel ls | head -2 | tail -1 | awk '{print $2}')
if [ ! -z "$DEPLOY_URL" ]; then
    CACHE_BUST_URL="${DEPLOY_URL}?v=${TIMESTAMP}&cb=$(date +%s)&nocache=1"
    print_success "🔗 Aggressive cache-busted URL: $CACHE_BUST_URL"
    
    # Open in browser with cache busting
    if command -v open &> /dev/null; then
        open "$CACHE_BUST_URL"
    fi
fi

print_success "✅ Cache issues should be resolved!"
echo "💡 If you still see old content:"
echo "   • Hard refresh your browser (Cmd+Shift+R on Mac)"
echo "   • Open in incognito/private mode"
echo "   • Clear your browser cache completely"
