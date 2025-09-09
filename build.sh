#!/bin/bash
echo "Starting build process..."
rm -rf web
mkdir -p web
echo "Copying files..."
cp *.html *.js *.json *.png web/
cp -r assets canvaskit icons web/
echo "Build completed at $(date)" > web/build_id.txt
echo "Files in web directory:"
ls -la web/
echo "Build process finished."
