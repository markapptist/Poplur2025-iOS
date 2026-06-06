#!/bin/bash

# Setup script for screenshot automation
# Run this once to set up Fastlane Snapshot

set -e

echo "📸 Setting up Fastlane Screenshot Automation for Poplur2025"
echo ""

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew not found. Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Check if Fastlane is installed
if ! command -v fastlane &> /dev/null; then
    echo "📦 Installing Fastlane..."
    brew install fastlane
else
    echo "✅ Fastlane already installed"
fi

# Create fastlane directory if it doesn't exist
mkdir -p fastlane

# Initialize snapshot (this creates SnapshotHelper files)
echo "🔧 Initializing Snapshot..."
fastlane snapshot init

# Create screenshots output directory
mkdir -p fastlane/screenshots

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Open Xcode and ensure you have a UI Test target"
echo "2. Add SnapshotUITests.swift to your UI test target"
echo "3. Add ScreenshotConfiguration.swift to your main app target"
echo "4. Run: fastlane screenshots"
echo ""
echo "For more info, see SCREENSHOTS.md"
