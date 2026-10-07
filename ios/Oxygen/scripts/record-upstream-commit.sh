#!/bin/sh
set -eu

root=$(git rev-parse --show-toplevel)
commit=$(git -C "$root" merge-base HEAD upstream/HEAD)
target="$root/ios/Oxygen/Sources/App/BuildConstants.swift"

cat > "$target" <<SWIFT
enum BuildConstants {
    static let upstreamKitCommit = "$commit"
}
SWIFT

echo "wrote $target (upstream $commit)"
