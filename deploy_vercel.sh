#!/bin/bash

# Vercel Deployment Script with Cache Busting
# This script ensures fresh deployments and avoids stale cache issues

set -e  # Exit on any error

echo "🚀 Starting Vercel deployment with cache busting..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    print_error "pubspec.yaml not found. Please run this script from the Flutter project root."
    exit 1
fi

# Check if Vercel CLI is installed
if ! command -v vercel &> /dev/null; then
    print_error "Vercel CLI is not installed. Please install it first:"
    echo "npm install -g vercel"
    exit 1
fi

# Step 1: Clean Flutter build
print_status "🧹 Cleaning Flutter build cache..."
flutter clean
if [ $? -ne 0 ]; then
    print_error "Flutter clean failed"
    exit 1
fi

# Step 2: Get fresh dependencies
print_status "📦 Getting fresh Flutter dependencies..."
flutter pub get
if [ $? -ne 0 ]; then
    print_error "Flutter pub get failed"
    exit 1
fi

# Step 3: Build Flutter web with release mode
print_status "🏗️  Building Flutter web (release mode)..."
flutter build web --release --web-renderer html
if [ $? -ne 0 ]; then
    print_error "Flutter build failed"
    exit 1
fi

# Step 4: Verify build output
if [ ! -d "build/web" ]; then
    print_error "Build output directory not found"
    exit 1
fi

print_success "Flutter build completed successfully"

# Step 5: Clean any existing Vercel cache
print_status "🗑️  Cleaning Vercel cache..."
vercel --force 2>/dev/null || true

# Step 6: Deploy with cache busting
print_status "🚀 Deploying to Vercel with cache busting..."

# Generate a unique timestamp for cache busting
TIMESTAMP=$(date +%s)
BUILD_ID="build-${TIMESTAMP}"

# Deploy with force flag to bypass cache
DEPLOY_RESULT=$(vercel --force --yes 2>&1)
DEPLOY_EXIT_CODE=$?

if [ $DEPLOY_EXIT_CODE -eq 0 ]; then
    print_success "✅ Deployment successful!"
    
    # Extract deployment URL from output
    DEPLOY_URL=$(echo "$DEPLOY_RESULT" | grep -o 'https://[^[:space:]]*' | head -1)
    if [ ! -z "$DEPLOY_URL" ]; then
        print_success "🌐 Your app is live at: $DEPLOY_URL"
        
        # Add cache busting parameter to URL
        CACHE_BUST_URL="${DEPLOY_URL}?v=${TIMESTAMP}&build=${BUILD_ID}"
        print_success "🔗 Cache-busted URL: $CACHE_BUST_URL"
        
        # Try to open in browser (works on macOS)
        if command -v open &> /dev/null; then
            print_status "🌍 Opening deployment in browser..."
            open "$CACHE_BUST_URL"
        fi
    fi
    
    # Optional: Promote to production (uncomment if you want auto-promotion)
    # print_status "📢 Promoting to production..."
    # vercel promote --yes
    
else
    print_error "❌ Deployment failed!"
    echo "$DEPLOY_RESULT"
    exit 1
fi

# Step 7: Verify deployment
print_status "🔍 Verifying deployment..."
sleep 5

# Check if the deployment is accessible
if [ ! -z "$DEPLOY_URL" ]; then
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DEPLOY_URL" || echo "000")
    
    if [ "$HTTP_STATUS" = "200" ]; then
        print_success "✅ Deployment verification successful (HTTP $HTTP_STATUS)"
    else
        print_warning "⚠️  Deployment accessible but returned HTTP $HTTP_STATUS"
    fi
fi

# Step 8: Clean up local build artifacts (optional)
read -p "🧹 Do you want to clean up local build artifacts? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Cleaning up build artifacts..."
    rm -rf build/web
    print_success "Build artifacts cleaned up"
fi

print_success "🎉 Deployment process completed!"
print_status "Next time you deploy, just run: ./deploy_vercel.sh"

echo
echo "📝 Tips for avoiding cache issues:"
echo "   • Always run this script for deployments"
echo "   • Use the cache-busted URL for testing"
echo "   • Clear browser cache if you still see old content"
echo "   • The script uses --force flag to bypass Vercel's cache"
