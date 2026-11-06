#!/bin/bash
# Checks a built Headroom.app (or the Headroom.pkg exported for the Mac App Store) before it ships (1.1 §5.2, §8,
# §12.2 step 5). Reads only the bundle; signs, uploads and registers nothing.
#
# Usage: scripts/verify-build.sh [--group YES|NO] <Headroom.app | Headroom.pkg>
#   --group   whether this build claims the App Group (HEADROOM_APP_GROUP); default $HEADROOM_APP_GROUP, else NO.
#
# Fails unless:
#   - Contents/PlugIns holds exactly one extension, HeadroomWidgets.appex, a WidgetKit extension whose bundle id is
#     the app's plus ".widgets";
#   - app and extension carry the same CFBundleShortVersionString and CFBundleVersion, and the version is
#     project.yml's MARKETING_VERSION (when project.yml is next to this script);
#   - the signed entitlements are exactly the chosen variant's: the app has the sandbox, app-scope bookmarks and
#     user-selected read-write files, plus the App Group with --group YES, plus network.client if and only if
#     Info.plist's HeadroomGitHubClientID is set; the extension has the sandbox, plus the group with --group YES;
#     team-signed builds also carry com.apple.application-identifier and com.apple.developer.team-identifier, and
#     nothing else (no get-task-allow);
#   - HeadroomAppGroup in both Info.plists names the claimed group (empty without one);
#   - --group YES is team-signed, and each embedded provisioning profile authorizes the group (the exact id or the
#     team's wildcard) and the bundle's application identifier;
#   - both are signed with the hardened runtime and `codesign --verify --deep --strict` passes.
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

usage() {
    echo "usage: scripts/verify-build.sh [--group YES|NO] <Headroom.app | Headroom.pkg>" >&2
    exit 64
}

group="${HEADROOM_APP_GROUP:-NO}"
target=""
while [ $# -gt 0 ]; do
    case "$1" in
        --group) [ $# -ge 2 ] || usage; group="$2"; shift 2 ;;
        -*) usage ;;
        *) [ -z "$target" ] || usage; target="$1"; shift ;;
    esac
done
[ -n "$target" ] || usage
case "$group" in YES|NO) ;; *) usage ;; esac

repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d -t headroom-verify)"
trap 'rm -rf "$work"' EXIT

# A .pkg is expanded first: the app inside is what App Review gets.
case "$target" in
    *.pkg)
        pkgutil --expand-full "$target" "$work/pkg" >/dev/null
        app="$(find "$work/pkg" -type d -name 'Headroom.app' -prune | head -n 1)"
        [ -n "$app" ] || { echo "verify-build: no Headroom.app inside $target" >&2; exit 1; }
        ;;
    *) app="$target" ;;
esac
[ -d "$app" ] || { echo "verify-build: $app isn't a bundle" >&2; exit 1; }

# Everything the checks need, as JSON files for the Python part below.
dump_bundle() { # bundle name
    local bundle="$1" name="$2"
    plutil -convert json -o "$work/$name-info.json" "$bundle/Contents/Info.plist"
    if codesign -d --entitlements - --xml "$bundle" >"$work/$name-entitlements.plist" 2>/dev/null \
        && [ -s "$work/$name-entitlements.plist" ]; then
        plutil -convert json -o "$work/$name-entitlements.json" "$work/$name-entitlements.plist"
    else
        echo '{}' >"$work/$name-entitlements.json"
    fi
    codesign -dv --verbose=2 "$bundle" >"$work/$name-codesign.txt" 2>&1 || true
    if [ -f "$bundle/Contents/embedded.provisionprofile" ]; then
        security cms -D -i "$bundle/Contents/embedded.provisionprofile" >"$work/$name-profile.plist" 2>/dev/null
        # A profile holds <date> and <data> values that JSON can't represent, so convert only its Entitlements.
        plutil -extract Entitlements json -o "$work/$name-profile-entitlements.json" "$work/$name-profile.plist"
        printf '{"Entitlements":%s}' "$(cat "$work/$name-profile-entitlements.json")" >"$work/$name-profile.json"
    fi
}

appex_count="$(find "$app/Contents/PlugIns" -maxdepth 1 -name '*.appex' 2>/dev/null | wc -l | tr -d ' ')"
appex="$app/Contents/PlugIns/HeadroomWidgets.appex"
failures=()
[ "$appex_count" = 1 ] && [ -d "$appex" ] \
    || failures+=("Contents/PlugIns must hold exactly HeadroomWidgets.appex (found $appex_count extension(s))")

dump_bundle "$app" app
[ -d "$appex" ] && dump_bundle "$appex" appex

if ! codesign --verify --deep --strict "$app" 2>"$work/verify.txt"; then
    failures+=("codesign --verify --deep --strict failed: $(tr '\n' ' ' <"$work/verify.txt")")
fi

marketing="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\{0,1\}\([0-9][0-9.]*\)"\{0,1\}[[:space:]]*$/\1/p' \
    "$repo/project.yml" 2>/dev/null | head -n 1 || true)"

# Keep the heredoc outside command substitution: macOS Bash 3.2 misparses quotes in this Python body there.
/usr/bin/python3 - "$work" "$group" "$marketing" >"$work/python-failures.txt" <<'PY'
import json, os, re, sys

work, group, marketing = sys.argv[1], sys.argv[2] == "YES", sys.argv[3]
failures = []

def load(name):
    path = os.path.join(work, name)
    return json.load(open(path)) if os.path.exists(path) else None

APP_KEYS = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.bookmarks.app-scope": True,
    "com.apple.security.files.user-selected.read-write": True,
}
GROUPS_KEY = "com.apple.security.application-groups"

def team_of(codesign_text):
    match = re.search(r"^TeamIdentifier=(\S+)$", codesign_text, re.M)
    return None if not match or match.group(1) == "not set" else match.group(1)

app_info = load("app-info.json") or {}
client_id = str(app_info.get("HeadroomGitHubClientID", "")).strip()

bundles = [("app", "Headroom.app")]
if load("appex-info.json") is not None:
    bundles.append(("appex", "HeadroomWidgets.appex"))

teams = {}
for name, label in bundles:
    info = load(f"{name}-info.json")
    entitlements = load(f"{name}-entitlements.json") or {}
    codesign = open(os.path.join(work, f"{name}-codesign.txt")).read()
    team = team_of(codesign)
    teams[name] = team
    bundle_id = info.get("CFBundleIdentifier", "")
    group_id = f"{team}.com.niomartinez.headroom" if team else None

    expected = dict(APP_KEYS) if name == "app" else {"com.apple.security.app-sandbox": True}
    if name == "app" and client_id:
        expected["com.apple.security.network.client"] = True
    if group:
        if not team:
            failures.append(f"{label}: --group YES needs a team-signed build (a group claimed without a Team ID is rejected)")
        else:
            expected[GROUPS_KEY] = [group_id]
    if team:
        expected["com.apple.application-identifier"] = f"{team}.{bundle_id}"
        expected["com.apple.developer.team-identifier"] = team
    if entitlements != expected:
        extra = sorted(set(entitlements) - set(expected))
        missing = sorted(set(expected) - set(entitlements))
        wrong = sorted(k for k in set(expected) & set(entitlements) if expected[k] != entitlements[k])
        failures.append(f"{label}: entitlements differ from the {'group' if group else 'NoGroup'}"
                        f"{'' if client_id or name != 'app' else ', offline'} variant"
                        f" (extra {extra}, missing {missing}, different {wrong})")

    named = str(info.get("HeadroomAppGroup", ""))
    if named != (group_id if group and team else ""):
        failures.append(f"{label}: Info.plist HeadroomAppGroup is {named!r}, expected {(group_id if group else '')!r}")

    if "runtime" not in (re.search(r"flags=\S*\(([^)]*)\)", codesign) or [None, ""])[1]:
        failures.append(f"{label}: not signed with the hardened runtime")

    profile = load(f"{name}-profile.json")
    if team:
        if profile is None:
            failures.append(f"{label}: team-signed but has no embedded.provisionprofile")
        else:
            allowed = profile.get("Entitlements", {})
            if group:
                authorized = allowed.get(GROUPS_KEY, [])
                # On macOS a group prefixed with the team ID needs no profile entry (Mac App Store profiles don't
                # list it); only group.* identifiers must be authorized by the profile.
                team_prefixed = group_id.startswith(f"{team}.")
                if not team_prefixed and not any(g == group_id or (g.endswith("*") and group_id.startswith(g[:-1])) for g in authorized):
                    failures.append(f"{label}: the embedded profile doesn't authorize {group_id} (it lists {authorized})")
            app_identifier = allowed.get("com.apple.application-identifier", "")
            wanted = f"{team}.{bundle_id}"
            if not (app_identifier == wanted or (app_identifier.endswith("*") and wanted.startswith(app_identifier[:-1]))):
                failures.append(f"{label}: the embedded profile is for {app_identifier!r}, not {wanted!r}")
    elif profile is not None:
        failures.append(f"{label}: ad-hoc signed but carries a provisioning profile")

appex_info = load("appex-info.json")
if appex_info is not None:
    if teams.get("app") != teams.get("appex"):
        failures.append(f"app and extension are signed by different teams ({teams.get('app')} vs {teams.get('appex')})")
    if appex_info.get("CFBundleIdentifier") != f"{app_info.get('CFBundleIdentifier')}.widgets":
        failures.append(f"HeadroomWidgets.appex: bundle id {appex_info.get('CFBundleIdentifier')!r} isn't the app's + .widgets")
    point = appex_info.get("NSExtension", {}).get("NSExtensionPointIdentifier")
    if point != "com.apple.widgetkit-extension":
        failures.append(f"HeadroomWidgets.appex: NSExtensionPointIdentifier is {point!r}")
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        if app_info.get(key) != appex_info.get(key):
            failures.append(f"{key} differs: app {app_info.get(key)!r}, extension {appex_info.get(key)!r}")
if marketing and app_info.get("CFBundleShortVersionString") != marketing:
    failures.append(f"CFBundleShortVersionString {app_info.get('CFBundleShortVersionString')!r} isn't project.yml's {marketing!r}")

print("\n".join(failures))
PY
python_failures="$(cat "$work/python-failures.txt")"
if [ -n "$python_failures" ]; then
    while IFS= read -r line; do failures+=("$line"); done <<<"$python_failures"
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || echo '?')"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist" 2>/dev/null || echo '?')"
if [ ${#failures[@]} -gt 0 ]; then
    echo "verify-build: $app ($version, build $build, group $group) FAILED:" >&2
    for failure in "${failures[@]}"; do echo "  - $failure" >&2; done
    exit 1
fi
network="$([ -n "$(/usr/libexec/PlistBuddy -c 'Print :HeadroomGitHubClientID' "$app/Contents/Info.plist" 2>/dev/null)" ] && echo "network.client" || echo "no network")"
echo "verify-build: $app ($version, build $build): widget extension embedded, entitlements exact (group $group, $network), versions match"
