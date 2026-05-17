#!/bin/bash

# Script to find duplicate notification definitions in Swift files
# This will help locate where LoadFeedNow, ResetTabToTop, and ShowUserProfile are defined

echo "🔍 Searching for duplicate notification definitions..."
echo ""

echo "===== LoadFeedNow definitions ====="
grep -rn "static let LoadFeedNow" . --include="*.swift" 2>/dev/null

echo ""
echo "===== ResetTabToTop definitions ====="
grep -rn "static let ResetTabToTop" . --include="*.swift" 2>/dev/null

echo ""
echo "===== ShowUserProfile definitions ====="
grep -rn "static let ShowUserProfile" . --include="*.swift" 2>/dev/null

echo ""
echo "===== All Notification.Name extensions ====="
grep -rn "extension Notification.Name" . --include="*.swift" 2>/dev/null

echo ""
echo "✅ Done! Look for files OTHER than Notifications+Names.swift that define these."
