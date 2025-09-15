#!/bin/bash

# Quick Vercel Deployment Script
# For when you just need a fast deployment without all the bells and whistles

set -e

echo "⚡ Quick Vercel deployment..."

# Clean and build
flutter clean
flutter pub get
flutter build web --release

# Deploy with force flag
vercel --force --yes

echo "✅ Quick deployment complete!"
