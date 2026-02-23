# Vercel Deployment Scripts

This directory contains automated scripts to help you deploy your Flutter app to Vercel without cache issues.

## 🚀 Scripts Overview

### 1. `deploy_vercel.sh` - Full Deployment Script
**Use this for most deployments**

- Cleans Flutter build cache
- Gets fresh dependencies
- Builds in release mode
- Deploys with cache busting
- Verifies deployment
- Provides cache-busted URL

```bash
./deploy_vercel.sh
```

### 2. `quick_deploy.sh` - Fast Deployment
**Use this for quick iterations**

- Minimal steps
- Fast deployment
- Good for development testing

```bash
./quick_deploy.sh
```

### 3. `fix_cache_issues.sh` - Cache Troubleshooting
**Use this when you're still seeing old content**

- Aggressive cache clearing
- Unique build IDs
- Multiple cache-busting parameters

```bash
./fix_cache_issues.sh
```

## 🔧 Prerequisites

1. **Vercel CLI installed:**
   ```bash
   npm install -g vercel
   ```

2. **Logged into Vercel:**
   ```bash
   vercel login
   ```

3. **Project linked to Vercel:**
   ```bash
   vercel link
   ```

## 📋 Typical Workflow

### For Regular Deployments:
```bash
./deploy_vercel.sh
```

### For Quick Testing:
```bash
./quick_deploy.sh
```

### If You See Stale Content:
```bash
./fix_cache_issues.sh
```

## 🎯 Cache Busting Features

All scripts include cache busting mechanisms:

- **Timestamp-based URLs**: `?v=1234567890`
- **Build IDs**: Unique identifiers for each build
- **Force flags**: Bypasses Vercel's internal caching
- **Fresh builds**: Cleans Flutter cache before building

## 🔍 Troubleshooting

### Still seeing old content?

1. **Run the cache fix script:**
   ```bash
   ./fix_cache_issues.sh
   ```

2. **Browser cache issues:**
   - Hard refresh: `Cmd+Shift+R` (Mac) or `Ctrl+Shift+R` (Windows)
   - Open in incognito/private mode
   - Clear browser cache completely

3. **Check deployment URL:**
   - Look for the cache-busted URL in the script output
   - Use that URL instead of the regular Vercel URL

### Script fails?

1. **Check Vercel CLI:**
   ```bash
   vercel --version
   ```

2. **Check Flutter:**
   ```bash
   flutter --version
   ```

3. **Check project setup:**
   - Make sure you're in the Flutter project root
   - Ensure `pubspec.yaml` exists
   - Run `vercel link` if needed

## 📝 Tips

- **Always use these scripts** instead of manual deployment
- **Use the cache-busted URL** for testing
- **Run `./deploy_vercel.sh`** for production deployments
- **Run `./quick_deploy.sh`** for quick iterations
- **Run `./fix_cache_issues.sh`** if you see stale content

## 🆘 Getting Help

If you're still having issues:

1. Check the script output for error messages
2. Ensure all prerequisites are installed
3. Try the cache fix script
4. Clear your browser cache completely
5. Use the cache-busted URL provided by the script
