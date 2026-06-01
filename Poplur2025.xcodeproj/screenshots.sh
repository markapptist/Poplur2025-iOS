#!/bin/bash

# Quick reference for common screenshot automation tasks

# Check prerequisites
check_prerequisites() {
    # Check if Xcode is installed
    if ! command -v xcodebuild &> /dev/null; then
        echo "❌ Error: xcodebuild not found"
        echo ""
        echo "Please install Xcode Command Line Tools:"
        echo "  xcode-select --install"
        echo ""
        echo "Or set the Xcode path:"
        echo "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
        exit 1
    fi
    
    # Check Xcode version
    echo "✅ Xcode: $(xcodebuild -version | head -n 1)"
}

case "$1" in
  "setup")
    echo "📸 Setting up screenshot automation..."
    check_prerequisites
    chmod +x setup_screenshots.sh
    ./setup_screenshots.sh
    ;;
    
  "generate")
    echo "📸 Generating screenshots..."
    check_prerequisites
    fastlane screenshots
    ;;
    
  "frame")
    echo "🖼️ Generating screenshots with device frames..."
    fastlane screenshots_framed
    ;;
    
  "upload")
    echo "☁️ Uploading screenshots to App Store Connect..."
    fastlane upload_screenshots
    ;;
    
  "clean")
    echo "🧹 Cleaning screenshots..."
    rm -rf ./fastlane/screenshots/*
    echo "✅ Screenshots cleaned"
    ;;
    
  "test")
    echo "🧪 Testing screenshot generation (single device)..."
    check_prerequisites
    fastlane snapshot --devices "iPhone 15 Pro Max"
    ;;
  
  "diagnose")
    echo "🔍 Diagnosing setup..."
    echo ""
    echo "Checking Xcode:"
    if command -v xcodebuild &> /dev/null; then
        echo "  ✅ xcodebuild found"
        xcodebuild -version
        echo "  📁 Path: $(xcode-select -p)"
    else
        echo "  ❌ xcodebuild not found"
        echo "     Run: xcode-select --install"
    fi
    echo ""
    echo "Checking Fastlane:"
    if command -v fastlane &> /dev/null; then
        echo "  ✅ fastlane found"
        fastlane --version
    else
        echo "  ❌ fastlane not found"
        echo "     Run: brew install fastlane"
    fi
    echo ""
    echo "Checking project:"
    if [ -f "fastlane/Snapfile" ]; then
        echo "  ✅ Snapfile exists"
    else
        echo "  ⚠️  Snapfile not found"
        echo "     Run: ./screenshots.sh setup"
    fi
    ;;
    
  "help"|*)
    echo "📸 Poplur2025 Screenshot Automation"
    echo ""
    echo "Usage: ./screenshots.sh [command]"
    echo ""
    echo "Commands:"
    echo "  setup     - Initial setup (run once)"
    echo "  generate  - Generate all screenshots"
    echo "  frame     - Generate screenshots with device frames"
    echo "  upload    - Upload screenshots to App Store Connect"
    echo "  clean     - Delete all generated screenshots"
    echo "  test      - Test with single device"
    echo "  diagnose  - Check your setup"
    echo "  help      - Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./screenshots.sh diagnose    # Check if everything is set up"
    echo "  ./screenshots.sh setup       # First time setup"
    echo "  ./screenshots.sh generate    # Generate screenshots"
    echo "  ./screenshots.sh clean       # Clean old screenshots"
    echo ""
    echo "Troubleshooting:"
    echo "  If you see 'command not found: xcodebuild':"
    echo "    xcode-select --install"
    echo "    sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
    echo ""
    echo "For detailed documentation, see SCREENSHOTS.md"
    ;;
esac
