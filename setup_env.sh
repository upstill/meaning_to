#!/bin/bash

echo "Setting up environment variables for local development..."

# Check if .env file exists
if [ ! -f .env ]; then
    echo "Creating .env file..."
    cat > .env << EOF
# Supabase Configuration
SUPABASE_URL=your_supabase_url_here
SUPABASE_ANON_KEY=your_supabase_anon_key_here
EOF
    echo "Created .env file. Please edit it with your actual Supabase credentials."
else
    echo ".env file already exists."
fi

echo ""
echo "To build for deployment, run:"
echo "export SUPABASE_URL='your_actual_url'"
echo "export SUPABASE_ANON_KEY='your_actual_key'"
echo "./deploy.sh"
echo ""
echo "Or for local development:"
echo "flutter run -d chrome --dart-define=SUPABASE_URL='your_actual_url' --dart-define=SUPABASE_ANON_KEY='your_actual_key'" 