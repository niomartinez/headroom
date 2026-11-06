#!/bin/bash
# Kept for `fastlane mac screenshots` and old notes: every product image is now rendered and copied by
# refresh-marketing-assets.sh (App Store screenshots, marketing PNGs, the 1.1 feature snippets and the website's
# images), from synthetic data only.
exec "$(dirname "$0")/refresh-marketing-assets.sh" "$@"
