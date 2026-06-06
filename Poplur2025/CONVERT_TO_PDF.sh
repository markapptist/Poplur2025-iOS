#!/bin/bash

# ============================================================================
# PDF Generation Script for Android Documentation
# ============================================================================
# This script converts the markdown documentation files to professional PDFs
# with table of contents, proper formatting, and embedded images.
#
# Requirements:
#   - pandoc (install: brew install pandoc)
#   - xelatex (install: brew install --cask mactex-no-gui)
#
# Usage:
#   ./CONVERT_TO_PDF.sh
#
# Output:
#   - HomeView_Tabs_Specification.pdf
#   - Cube_3D_Navigation_Specification.pdf
#   - PDF_Creation_Guide.pdf
#   - Android_Documentation_README.pdf
# ============================================================================

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Android Documentation PDF Generator${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if pandoc is installed
if ! command -v pandoc &> /dev/null; then
    echo -e "${RED}ERROR: pandoc is not installed${NC}"
    echo "Install with: brew install pandoc"
    exit 1
fi

# Check if xelatex is installed
if ! command -v xelatex &> /dev/null; then
    echo -e "${RED}ERROR: xelatex is not installed${NC}"
    echo "Install with: brew install --cask mactex-no-gui"
    exit 1
fi

echo -e "${GREEN}✓ All dependencies found${NC}"
echo ""

# Function to convert a markdown file to PDF
convert_to_pdf() {
    local input_file=$1
    local output_file=$2
    local title=$3
    
    echo -e "${BLUE}Converting: ${input_file}${NC}"
    echo -e "  → ${output_file}"
    
    pandoc "$input_file" \
        -o "$output_file" \
        --pdf-engine=xelatex \
        --toc \
        --toc-depth=3 \
        --number-sections \
        --variable=geometry:margin=1in \
        --variable=fontsize:11pt \
        --variable=mainfont:"SF Pro Text" \
        --variable=monofont:"SF Mono" \
        --variable=documentclass:article \
        --variable=papersize:letter \
        --variable=colorlinks:true \
        --variable=linkcolor:blue \
        --variable=urlcolor:blue \
        --metadata title="$title" \
        --metadata date="$(date '+%B %d, %Y')" \
        --highlight-style=tango
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Created: ${output_file}${NC}"
    else
        echo -e "${RED}✗ Failed: ${output_file}${NC}"
    fi
    echo ""
}

# Convert each document
convert_to_pdf \
    "ANDROID_DOCS_HomeView_Tabs.md" \
    "HomeView_Tabs_Specification.pdf" \
    "Home View Tab System Specification - For Android Recreation"

convert_to_pdf \
    "ANDROID_DOCS_Cube_Specification.md" \
    "Cube_3D_Navigation_Specification.pdf" \
    "3D Cube Navigation Specification - Geometry, Materials, and Animations"

convert_to_pdf \
    "ANDROID_DOCS_PDF_CREATION_GUIDE.md" \
    "PDF_Creation_Guide.pdf" \
    "Android Documentation - PDF Creation Guide"

convert_to_pdf \
    "ANDROID_DOCS_README.md" \
    "Android_Documentation_README.pdf" \
    "Android Documentation Package - Complete Recreation Guide"

# Create a combined PDF (optional)
echo -e "${BLUE}Creating combined PDF...${NC}"

# Check if pdftk is available for combining
if command -v pdftk &> /dev/null; then
    pdftk \
        Android_Documentation_README.pdf \
        HomeView_Tabs_Specification.pdf \
        Cube_3D_Navigation_Specification.pdf \
        PDF_Creation_Guide.pdf \
        cat output Complete_Android_Documentation.pdf
    
    echo -e "${GREEN}✓ Created: Complete_Android_Documentation.pdf${NC}"
else
    echo -e "${RED}Note: pdftk not found, skipping combined PDF${NC}"
    echo "Install with: brew install pdftk-java"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}PDF Generation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Generated PDFs:"
echo "  1. HomeView_Tabs_Specification.pdf"
echo "  2. Cube_3D_Navigation_Specification.pdf"
echo "  3. PDF_Creation_Guide.pdf"
echo "  4. Android_Documentation_README.pdf"

if command -v pdftk &> /dev/null; then
    echo "  5. Complete_Android_Documentation.pdf (combined)"
fi

echo ""
echo "Next steps:"
echo "  1. Open the PDFs and verify formatting"
echo "  2. Add screenshots using the PDF_Creation_Guide"
echo "  3. Share with the Android team"
echo ""
echo -e "${BLUE}Tip: To add images to the markdown before conversion,${NC}"
echo -e "${BLUE}use: ![Description](path/to/image.png)${NC}"
echo ""
