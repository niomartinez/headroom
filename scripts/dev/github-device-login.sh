#!/bin/bash
# Gate G1 (1.1 spec §4.8), dev only and never bundled: signs in to Headroom's GitHub App with the device flow
# (§4.3), then asks GET /user and both billing usage endpoints (§4.4) the way CopilotKit does, and refreshes once.
#
#   scripts/dev/github-device-login.sh <client-id>        e.g. Iv23liEA5ZycifEXDZCT (public, not a secret)
#
# Prints only: status codes, the X-Accepted-GitHub-Permissions header, item counts and the distinct
# (product, sku, unitType) triples, plus the one-time user code to type on GitHub. Tokens and the device code live
# only in shell variables and reach curl on stdin (never argv, URLs or files); quantities are never printed.
# Needs bash, curl and plutil (macOS).
set -uo pipefail

client_id="${1:-}"
if [[ ! "$client_id" =~ ^[A-Za-z0-9.]+$ ]]; then
    echo "usage: $0 <github-app-client-id>" >&2
    exit 2
fi

user_agent="Headroom-dev-login (macOS)"
api_version="2026-03-10"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# json <key path>: a value from the JSON on stdin ("" when missing). Arrays print their count.
json() { plutil -extract "$1" raw -o - - 2>/dev/null || true; }

# oauth <path> <form body>: POSTs the body from stdin to github.com, prints the JSON answer.
oauth() {
    printf '%s' "$2" | curl -s -X POST -H 'Accept: application/json' -H "User-Agent: $user_agent" \
        -H 'Content-Type: application/x-www-form-urlencoded' --data-binary @- "https://github.com$1"
}

# api <url> <headers file> <body file>: GETs the REST API with the token from stdin, prints the status code.
api() {
    printf 'header = "Authorization: Bearer %s"\n' "$token" | curl -s -K - -D "$2" -o "$3" -w '%{http_code}' \
        -H 'Accept: application/vnd.github+json' -H "X-GitHub-Api-Version: $api_version" \
        -H "User-Agent: $user_agent" "$1"
}

# 1. Device code.
answer=$(oauth /login/device/code "client_id=$client_id")
device_code=$(printf '%s' "$answer" | json device_code)
if [ -z "$device_code" ]; then
    echo "POST /login/device/code -> error '$(printf '%s' "$answer" | json error)'"
    exit 1
fi
interval=$(printf '%s' "$answer" | json interval)
expires_in=$(printf '%s' "$answer" | json expires_in)
interval=${interval:-5}
echo "POST /login/device/code -> ok (interval ${interval} s, expires_in ${expires_in:-?} s)"
echo "Enter code $(printf '%s' "$answer" | json user_code) at $(printf '%s' "$answer" | json verification_uri)"

# 2. Poll for the token: +5 s on each slow_down, give up at expires_in.
grant="urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"
deadline=$(($(date +%s) + ${expires_in:-900}))
token=""
refresh=""
pending=0
while [ "$(date +%s)" -lt "$deadline" ]; do
    sleep "$interval"
    answer=$(oauth /login/oauth/access_token "client_id=$client_id&device_code=$device_code&grant_type=$grant")
    error=$(printf '%s' "$answer" | json error)
    case "$error" in
        authorization_pending) pending=$((pending + 1)) ;;
        slow_down) interval=$((interval + 5)); echo "slow_down -> interval ${interval} s" ;;
        "")
            token=$(printf '%s' "$answer" | json access_token)
            refresh=$(printf '%s' "$answer" | json refresh_token)
            echo "POST /login/oauth/access_token -> authorized after $pending pending answers" \
                "(token_type $(printf '%s' "$answer" | json token_type), expires_in $(printf '%s' "$answer" | json expires_in)," \
                "refresh_token_expires_in $(printf '%s' "$answer" | json refresh_token_expires_in)," \
                "scope '$(printf '%s' "$answer" | json scope)', refresh token $([ -n "$refresh" ] && echo present || echo absent))"
            break ;;
        *) echo "POST /login/oauth/access_token -> error '$error'"; exit 1 ;;
    esac
done
answer=""
device_code=""
[ -n "$token" ] || { echo "the code expired"; exit 1; }

# 3. The login, kept in a variable.
code=$(api https://api.github.com/user "$work/h" "$work/b")
login=$(json login <"$work/b")
echo "GET /user -> $code (type $(json type <"$work/b"))"
[[ "$login" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "no usable login"; exit 1; }

# 4. Both usage endpoints, for this UTC month and without a month.
year=$(date -u +%Y)
month=$(date -u +%-m)
for endpoint in ai_credit premium_request; do
    for query in "?year=$year&month=$month" ""; do
        code=$(api "https://api.github.com/users/$login/settings/billing/$endpoint/usage$query" "$work/h" "$work/b")
        permissions=$(grep -i '^x-accepted-github-permissions:' "$work/h" | cut -d: -f2- | tr -d '\r' | xargs)
        count=$(json usageItems <"$work/b")
        triples=""
        for ((i = 0; i < ${count:-0}; i++)); do
            triples+="($(json "usageItems.$i.product" <"$work/b"), $(json "usageItems.$i.sku" <"$work/b"),"
            triples+=" $(json "usageItems.$i.unitType" <"$work/b"))"$'\n'
        done
        echo "GET $endpoint/usage${query:+ (UTC year/month)} -> $code," \
            "X-Accepted-GitHub-Permissions: ${permissions:-none}, items: ${count:-none}"
        [ -n "$triples" ] && printf '%s' "$triples" | sort -u | sed 's/^/    /'
        rm -f "$work/h" "$work/b"
    done
done

# 5. Refresh without a client secret (§4.3): both tokens should rotate.
if [ -n "$refresh" ]; then
    answer=$(printf 'client_id=%s&grant_type=refresh_token&refresh_token=%s' "$client_id" "$refresh" |
        curl -s -X POST -H 'Accept: application/json' -H "User-Agent: $user_agent" \
            -H 'Content-Type: application/x-www-form-urlencoded' --data-binary @- \
            https://github.com/login/oauth/access_token)
    new_access=$(printf '%s' "$answer" | json access_token)
    new_refresh=$(printf '%s' "$answer" | json refresh_token)
    echo "POST /login/oauth/access_token (refresh) -> error '$(printf '%s' "$answer" | json error)'," \
        "new access token $([ -n "$new_access" ] && [ "$new_access" != "$token" ] && echo yes || echo no)," \
        "refresh token rotated $([ -n "$new_refresh" ] && [ "$new_refresh" != "$refresh" ] && echo yes || echo no)"
fi
answer=""
token=""
refresh=""
new_access=""
new_refresh=""
echo "Done. The grant stays until revoked at https://github.com/settings/apps/authorizations"
