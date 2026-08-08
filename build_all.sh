#!/bin/bash
# build_all.sh — Build meaning_to for one or more target platforms.
#
# Usage:
#   ./build_all.sh                        # build all platforms
#   ./build_all.sh --web --deploy         # web only, then push to Vercel
#   ./build_all.sh --ios --android        # mobile only
#   ./build_all.sh --clean --web          # clean first, then web
#
# Flags:
#   --web       Build Flutter web (copies output to repo root for Vercel)
#   --ios       Build iOS IPA using ios/ExportOptions.plist
#   --android   Build Android APK + AAB
#   --macos     Build macOS desktop app
#   --deploy    After a successful web build, deploy to Vercel (--prod)
#   --clean     Run 'flutter clean' before building
#   --help      Show this message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Argument parsing ───────────────────────────────────────────────────────────
BUILD_WEB=false
BUILD_IOS=false
BUILD_ANDROID=false
BUILD_MACOS=false
DO_DEPLOY=false
DO_CLEAN=false
EXPLICIT_TARGETS=false

for arg in "$@"; do
  case "$arg" in
    --web)      BUILD_WEB=true;     EXPLICIT_TARGETS=true ;;
    --ios)      BUILD_IOS=true;     EXPLICIT_TARGETS=true ;;
    --android)  BUILD_ANDROID=true; EXPLICIT_TARGETS=true ;;
    --macos)    BUILD_MACOS=true;   EXPLICIT_TARGETS=true ;;
    --deploy)   DO_DEPLOY=true ;;
    --clean)    DO_CLEAN=true ;;
    --help|-h)
      sed -n '2,20p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *)
      echo "Unknown option: $arg  (use --help for usage)"
      exit 1 ;;
  esac
done

# No explicit targets → build everything
if ! $EXPLICIT_TARGETS; then
  BUILD_WEB=true
  BUILD_IOS=true
  BUILD_ANDROID=true
  BUILD_MACOS=true
fi

# ── Environment ────────────────────────────────────────────────────────────────
if [ -f .env ]; then
  echo "📋 Loading .env..."
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
else
  echo "⚠️  No .env file — using system environment variables"
fi

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "❌ SUPABASE_URL and SUPABASE_ANON_KEY must be set"
  exit 1
fi

DART_DEFINES=(
  "--dart-define=SUPABASE_URL=$SUPABASE_URL"
  "--dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY"
)
[ -n "${YOUTUBE_API_KEY:-}" ] && DART_DEFINES+=("--dart-define=YOUTUBE_API_KEY=$YOUTUBE_API_KEY")
[ -n "${OMDB_API_KEY:-}" ] && DART_DEFINES+=("--dart-define=OMDB_API_KEY=$OMDB_API_KEY")

FLUTTER_VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
BUILD_NAME=$(echo "$FLUTTER_VERSION" | cut -d'+' -f1)
BUILD_NUMBER=$(echo "$FLUTTER_VERSION" | cut -d'+' -f2)

echo ""
echo "╔══════════════════════════════════════════╗"
echo "  meaning_to  v${BUILD_NAME}+${BUILD_NUMBER}"
echo "╚══════════════════════════════════════════╝"

# ── Optional clean ─────────────────────────────────────────────────────────────
if $DO_CLEAN; then
  echo "🧹 flutter clean..."
  flutter clean
fi

# ── Result tracking ────────────────────────────────────────────────────────────
WEB_RESULT=""
IOS_RESULT=""
ANDROID_RESULT=""
MACOS_RESULT=""

# ── Web ────────────────────────────────────────────────────────────────────────
if $BUILD_WEB; then
  echo ""
  echo "── 🌐  Web ──────────────────────────────────"
  # Regenerate the static help page from its single source (docs/help.md) so it
  # ships in this build; runs before the flutter build that bundles web/.
  echo "📝 Generating web/help.html from docs/help.md..."
  dart run tool/generate_help_html.dart || echo "⚠️  help generation failed (continuing)"
  if flutter build web --release "${DART_DEFINES[@]}"; then
    # Copy output to repo root (where Vercel serves from)
    rm -f index.html flutter.js flutter_bootstrap.js flutter_service_worker.js \
          main.dart.js manifest.json
    rm -rf assets/ canvaskit/ icons/
    cp -rf build/web/* .
    for d in build/web/.*; do
      base=$(basename "$d")
      [ "$base" = "." ] || [ "$base" = ".." ] && continue
      [ -e "$d" ] && cp -rf "$d" .
    done
    # Update build markers
    echo "Build completed at $(date) — version $FLUTTER_VERSION" > build_id.txt
    printf '{"app_name":"meaning_to","version":"%s","build_number":"%s","package_name":"meaning_to"}\n' \
      "$BUILD_NAME" "$BUILD_NUMBER" > version.json
    WEB_RESULT="✅  build/web/"

    if $DO_DEPLOY; then
      echo "🚀 Deploying to Vercel..."
      if vercel --prod; then
        WEB_RESULT="✅  deployed → https://meaning-to.me"
        # Commit and push web build files so Vercel's GitHub integration
        # doesn't overwrite the deployment with stale files on the next push.
        echo "📦 Committing web build files to git..."
        # Include index.html + manifest.json so the GitHub-integration redeploy
        # (triggered by this push) serves the same files as the CLI deploy —
        # otherwise stale committed copies (e.g. an old <title>) override it.
        # Static help page + its images (served at the site root) and the
        # in-app help assets (docs/help.md, web/*.png) the Flutter web app loads
        # — all must be committed so the GitHub-integration redeploy serves them.
        git add -f build_id.txt flutter_service_worker.js main.dart.js version.json .last_build_id index.html manifest.json privacy.html help.html help-extension.png rouzme_icon.png assets/docs/help.md assets/web/help-extension.png assets/web/rouzme_icon.png 2>/dev/null || true
        git diff --cached --quiet || git commit -m "Deploy web build $FLUTTER_VERSION" --no-verify
        git push
      else
        WEB_RESULT="⚠️  built OK but Vercel deploy failed"
      fi
    fi
  else
    WEB_RESULT="❌  build failed"
  fi
fi

# ── iOS ────────────────────────────────────────────────────────────────────────
if $BUILD_IOS; then
  echo ""
  echo "── 🍎  iOS (IPA) ────────────────────────────"
  if flutter build ipa --release \
       --export-options-plist=ios/ExportOptions.plist \
       "${DART_DEFINES[@]}"; then
    IPA=$(find build/ios/ipa -name "*.ipa" 2>/dev/null | head -1)
    IOS_RESULT="✅  ${IPA:-build/ios/ipa/}"
  else
    IOS_RESULT="❌  build failed"
  fi
fi

# ── Android ────────────────────────────────────────────────────────────────────
if $BUILD_ANDROID; then
  echo ""
  echo "── 🤖  Android (APK + AAB) ──────────────────"
  APK_OK=true
  AAB_OK=true

  if flutter build apk --release "${DART_DEFINES[@]}"; then
    echo "   APK → build/app/outputs/flutter-apk/app-release.apk"
  else
    APK_OK=false
  fi

  if flutter build appbundle --release "${DART_DEFINES[@]}"; then
    echo "   AAB → build/app/outputs/bundle/release/app-release.aab"
  else
    AAB_OK=false
  fi

  if $APK_OK && $AAB_OK; then
    ANDROID_RESULT="✅  APK + AAB"
  elif $APK_OK; then
    ANDROID_RESULT="⚠️  APK only (AAB failed)"
  elif $AAB_OK; then
    ANDROID_RESULT="⚠️  AAB only (APK failed)"
  else
    ANDROID_RESULT="❌  both targets failed"
  fi
fi

# ── macOS ──────────────────────────────────────────────────────────────────────
if $BUILD_MACOS; then
  echo ""
  echo "── 🖥️   macOS Desktop ───────────────────────"
  if flutter build macos --release "${DART_DEFINES[@]}"; then
    APP=$(find "build/macos/Build/Products/Release" -maxdepth 1 -name "*.app" 2>/dev/null | head -1)
    MACOS_RESULT="✅  ${APP:-build/macos/Build/Products/Release/}"
  else
    MACOS_RESULT="❌  build failed"
  fi
fi

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════╗"
echo "  Summary  v${BUILD_NAME}+${BUILD_NUMBER}  $(date '+%Y-%m-%d %H:%M')"
echo "╚══════════════════════════════════════════╝"
[ -n "$WEB_RESULT"     ] && printf "  web      %s\n" "$WEB_RESULT"
[ -n "$IOS_RESULT"     ] && printf "  ios      %s\n" "$IOS_RESULT"
[ -n "$ANDROID_RESULT" ] && printf "  android  %s\n" "$ANDROID_RESULT"
[ -n "$MACOS_RESULT"   ] && printf "  macos    %s\n" "$MACOS_RESULT"
echo ""
