#!/bin/bash
# Renders every product image the App Store listing, the website and the social posts use, from synthetic data
# only (HeadroomSamples: nothing from this Mac's ~/.claude, ~/.codex or ~/.copilot ever reaches an image), and copies
# each one to where it's used. Re-run it after any UI change, then look at the diff before committing.
#
#   scripts/release/refresh-marketing-assets.sh [--skip-website-renders]
#
# Writes:
#   fastlane/screenshots/en-US/*.png          App Store screenshots 01–07, 2880×1800 opaque sRGB (headroom-render --store)
#   marketing/assets/pill-*@3x.png, panel-*@2x.png, app-icon-1024.png
#                                             transparent pills and panels (headroom-render --assets), the app icon
#   marketing/social/1.1/snippets/*.png       the 1.1 feature snippets at 2×, transparent (headroom-render --marketing)
#   website/public/screenshots/*.jpg          the store screenshots as JPEG, for the screenshots strip
#   website/public/screenshots/phone/*.jpg    their 4:5 phone crops (1152×1440: the panel and the pill)
#   website/public/images/snippets/*.png      the feature snippets, for the "New in 1.1" cards
#   website/public/images/hero-panel.png, og-pill.png, renders/*.png
#                                             the hero panel and keyed renders (website/scripts/hero-render and
#                                             prepare-assets.py, which needs Pillow); --skip-website-renders skips them
#
# Ends with scripts/release/check-metadata.rb, which also checks the screenshots' size and alpha.
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

website_renders=yes
case "${1:-}" in
    "") ;;
    --skip-website-renders) website_renders=no ;;
    *) echo "usage: $0 [--skip-website-renders]" >&2; exit 64 ;;
esac

cd "$(dirname "$0")/../.."
root="$(pwd)"
screenshots="$root/fastlane/screenshots/en-US"
assets="$root/marketing/assets"
snippets="$root/marketing/social/1.1/snippets"
web="$root/website/public"

# Render into a scratch folder first, so a failed render never leaves a half-updated set behind.
work="$(mktemp -d "${TMPDIR:-/tmp}/headroom-assets.XXXXXX")"
trap 'rm -rf "$work"' EXIT

(
    cd "$root/Packages/HeadroomKit"
    swift build --product headroom-render
    render="$(swift build --show-bin-path)/headroom-render"
    "$render" --store "$work/store" >/dev/null
    "$render" --assets "$work/assets" >/dev/null
    "$render" --marketing "$work/marketing" >/dev/null
    if [ "$website_renders" = yes ]; then
        "$render" "$work/review" >/dev/null
    fi
)

# App Store screenshots. Old names must not linger: deliver uploads every PNG in the folder.
mkdir -p "$screenshots"
rm -f "$screenshots"/*.png
cp "$work"/store/*.png "$screenshots/"

# Website and marketing PNGs.
mkdir -p "$assets" "$snippets" "$web/images/snippets" "$web/screenshots/phone"
rm -f "$assets"/pill-*.png "$assets"/panel-*.png "$snippets"/*.png "$web"/images/snippets/*.png
cp "$work"/assets/*.png "$assets/"
cp "$root/App/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" "$assets/app-icon-1024.png"
for file in "$work"/marketing/snippet-*@2x.png; do
    name="$(basename "$file")"          # snippet-codex@2x.png
    cp "$file" "$snippets/$name"
    short="${name#snippet-}"            # codex@2x.png
    cp "$file" "$web/images/snippets/${short%@2x.png}.png"
done

# The screenshots strip: every store screenshot as a JPEG, plus a 4:5 crop of the panel and the pill for phones,
# where a whole 2880×1800 screenshot shrinks to about 330 px (website/src/content/screenshots.ts lists them).
# The crop is 1152×1440 from the top; its left edge is at x 1426 (49.5 %), except where the layout differs.
rm -f "$web"/screenshots/*.jpg "$web"/screenshots/phone/*.jpg
for file in "$screenshots"/*.png; do
    name="$(basename "$file" .png)"
    case "$name" in
        07-*) crop_x=1716 ;;            # the widgets: the medium and large widgets and the pill, not the small one
        *) crop_x=1426 ;;
    esac
    sips -s format jpeg -s formatOptions 85 "$file" --out "$web/screenshots/$name.jpg" >/dev/null
    sips -c 1440 1152 --cropOffset 0 "$crop_x" -s format jpeg -s formatOptions 85 "$file" \
        --out "$web/screenshots/phone/$name.jpg" >/dev/null
done

# The hero panel, the social card's pill and the keyed renders (website/README.md, "Images").
if [ "$website_renders" = yes ]; then
    if python3 -c "import PIL" 2>/dev/null; then
        (
            cd "$root/website/scripts/hero-render"
            swift build --product hero-render
            "$(swift build --show-bin-path)/hero-render" "$work/hero" >/dev/null
        )
        (cd "$root/website" && python3 scripts/prepare-assets.py "$work/review" "$work/hero" >/dev/null)
    else
        echo "warning: Pillow isn't installed (python3 -m pip install Pillow), so the website's hero panel and" >&2
        echo "         renders weren't refreshed. Everything else was." >&2
    fi
fi

ruby "$root/scripts/release/check-metadata.rb" "$root"
echo "Refreshed. Check the images by eye, then 'git status' shows what changed."
