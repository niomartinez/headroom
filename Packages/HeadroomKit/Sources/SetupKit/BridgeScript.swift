import Foundation

/// The bridge script source, installed to `~/.claude/headroom/bridge.sh` (spec §2.4, §2.5).
///
/// It runs under macOS `/bin/bash` 3.2 and uses only bash builtins plus `cat`, `ps`, `date`,
/// `mkdir`, `mv`, `rm` and `find`. JSON string values are matched with a regex that keeps them
/// JSON-escaped, so they can be re-embedded verbatim; prompt text is never extracted.
public enum BridgeScript {
    /// Bumped whenever what "Connect terminal" installs changes, so older installs read as
    /// `.outdated` and get repaired. 2: adds the `PostToolUse` hook. 3: never creates
    /// ~/.claude/headroom itself, removes its temp files when killed or stale, and chains the saved
    /// status line command byte for byte (`original-statusline.cmd`). 4: does nothing but chain the
    /// user's status line once Headroom is uninstalled (`app-path`, see `headroom_installed`).
    /// 5: looks for the App Store container under the release bundle ID, com.niomartinez.headroom.
    public static let version = 5

    /// Where a copy of the app counts as installed whatever `app-path` says: the Mac App Store and
    /// drag-installs put it there.
    static let applicationsCopyPath = "/Applications/Headroom.app"
    /// The App Store version's container, relative to the home folder. It remains when the app is
    /// dragged to the Trash, so it keeps the bridge working until the user removes it too.
    static let containerPath = "Library/Containers/com.niomartinez.headroom"

    /// First lines include `# headroom-bridge v<version>`.
    public static let contents: String = #"""
#!/bin/bash
# headroom-bridge v\#(version)
# Headroom's terminal bridge. "Connect terminal" installs it; "Disconnect terminal" removes it.
# Usage: bridge.sh statusline|hook, with Claude Code's JSON payload on stdin.
# It writes only under ~/.claude/headroom/ and never stores prompt text.

# Closed descriptors are found by duplicating them, never through /dev/fd: while other
# processes look up /dev/fd (parallel hooks do), macOS fails stat("/dev/fd/N") with EBADF
# for open descriptors too. `true` is a regular builtin, so a failed probe never exits.
# Our own errors are silenced; a chained status line keeps the original stderr (fd 3).
if true 4>&2; then exec 3>&2; else exec 3>/dev/null; fi
exec 2>/dev/null
# A closed stdin would let `$(cat)` read its own pipe and hang: read /dev/null instead.
true 4<&0 || exec </dev/null

# Process bytes, not characters; a chained status line gets the user's locale back.
user_lc_all=${LC_ALL-}
user_lc_all_set=${LC_ALL+1}
LC_ALL=C

dir="$HOME/.claude/headroom"
sessions="$dir/sessions"

# Read stdin exactly once, keeping trailing newlines; never wait on a terminal.
payload=
if [ ! -t 0 ]; then
    payload=$(cat; printf x)
    payload=${payload%x}
fi

# The payload without surrounding whitespace, or empty when it is not a JSON object.
body=$payload
while :; do
    case ${body:0:1} in [[:space:]]) body=${body#?} ;; *) break ;; esac
done
while :; do
    case ${body: -1} in [[:space:]]) body=${body%?} ;; *) break ;; esac
done
[ "${body:0:1}${body: -1}" = "{}" ] || body=

sp='[[:space:]]*'
# A JSON string; group 1 is its body, still JSON-escaped so it can be re-embedded verbatim.
string_re='"(([^"\\[:cntrl:]]|\\(["\\/bfnrt]|u[0-9A-Fa-f]{4}))*)"'
# "used_percentage" directly inside the object that follows a key; group 2 is the number.
percent_re=$sp':'$sp'\{([^{}]|\{[^{}]*\})*"used_percentage"'$sp':'$sp'([0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?)'
rate_limits_re='"rate_limits"'$sp':'$sp'\{'

# REPLY = the first string value of key $1 in $2 (default: the payload), still escaped.
json_string() {
    local re="\"$1\"$sp:$sp$string_re"
    REPLY=
    if [[ ${2-$body} =~ $re ]]; then REPLY=${BASH_REMATCH[1]}; fi
}

# REPLY = "used_percentage" of the object under key $1, rounded to an integer, or empty.
percent_of() {
    local re="\"$1\"$percent_re" n int frac
    REPLY=
    [[ $body =~ $re ]] || return
    n=${BASH_REMATCH[2]}
    case $n in
        *[eE]-*) REPLY=0; return ;;
        *[eE]*) return ;;
    esac
    int=${n%%.*}
    frac=${n#"$int"}
    frac=${frac#.}
    [ "${#int}" -le 6 ] || return
    int=$((10#$int))
    case $frac in [5-9]*) int=$((int + 1)) ;; esac
    REPLY=$int
}

# REPLY = the session id when it is a safe file name, else empty (no path traversal).
session_id() {
    json_string session_id
    case $REPLY in
        . | .. | *[!A-Za-z0-9._-]*) REPLY= ;;
    esac
    [ "${#REPLY}" -le 128 ] || REPLY=
}

# REPLY = the pid of the nearest ancestor named `claude` within 6 levels, else $PPID.
claude_pid() {
    local pid=$PPID n=0 out ppid
    while [ "$n" -lt 6 ]; do
        out=$(ps -o ppid=,comm= -p "$pid")
        set -f
        set -- $out
        set +f
        [ $# -ge 2 ] || break
        ppid=$1
        shift
        out="$*"
        if [ "${out##*/}" = claude ]; then
            REPLY=$pid
            return
        fi
        case $ppid in '' | *[!0-9]* | 0 | 1) break ;; esac
        pid=$ppid
        n=$((n + 1))
    done
    REPLY=$PPID
}

# REPLY = the current time in epoch seconds.
now() {
    REPLY=$(date +%s)
    case $REPLY in '' | *[!0-9]*) REPLY=0 ;; esac
}

# Creates ~/.claude/headroom/sessions (private) unless it exists. Never creates ~/.claude/headroom:
# only "Connect terminal" does, so a run still in flight after "Disconnect terminal" can't bring it back.
ensure_dirs() {
    [ -d "$sessions" ] && return 0
    [ -d "$dir" ] || return 1
    mkdir -m 700 "$sessions" || [ -d "$sessions" ]
}

# Atomically replaces file $1 with $2: temp file in the same directory, then mv -f. Claude Code
# kills a status line run when a newer one starts; the temp file goes with it.
write_atomic() {
    local tmp="${1%/*}/.${1##*/}.$$.tmp"
    trap 'rm -f "$tmp"; exit 0' HUP INT TERM
    if printf '%s\n' "$2" >"$tmp" && mv -f "$tmp" "$1"; then
        trap - HUP INT TERM
        return 0
    fi
    rm -f "$tmp"
    trap - HUP INT TERM
    return 1
}

# Whether Headroom is still installed. Deleting the app leaves this bridge in settings.json, and then
# nothing reads what it writes. It is installed while any of these exists: the app "Connect terminal"
# ran from (its absolute path in app-path, one trailing newline allowed), a copy in /Applications, or
# the App Store version's container. Installs from before app-path existed always count as installed.
headroom_installed() {
    local file="$dir/app-path" app=
    [ -e "$file" ] || return 0
    if [ -f "$file" ]; then
        IFS= read -r -d '' app <"$file"
        app=${app%$'\n'}
        case $app in /*) [ -e "$app" ] && return 0 ;; esac
    fi
    [ -e "\#(applicationsCopyPath)" ] || [ -e "$HOME/\#(containerPath)" ]
}

# REPLY = the status line command saved at install time, byte for byte; fails if none.
original_statusline_command() {
    local file="$dir/original-statusline.cmd" cmd=
    [ -f "$file" ] || return 1
    IFS= read -r -d '' cmd <"$file"
    case $cmd in '' | *headroom/bridge.sh*) return 1 ;; esac
    REPLY=$cmd
}

statusline() {
    local sid pid ts parts installed=1
    headroom_installed || installed=
    session_id
    sid=$REPLY
    if [ -n "$installed" ] && [ -n "$body" ] && [ -n "$sid" ] && ensure_dirs; then
        claude_pid
        pid=$REPLY
        now
        ts=$REPLY
        if [[ $body =~ $rate_limits_re ]]; then
            write_atomic "$dir/statusline-latest.json" "$body"
        fi
        write_atomic "$sessions/$sid.statusline.json" "{\"v\":1,\"ts\":$ts,\"pid\":$pid,\"payload\":$body}"
    fi

    # Chain the user's own status line: print only its output.
    if original_statusline_command; then
        if [ -n "$user_lc_all_set" ]; then LC_ALL=$user_lc_all; else unset LC_ALL; fi
        printf '%s' "$payload" | /bin/sh -c "$REPLY" 2>&3 3>&-
        return
    fi

    # Headroom's own summary only while Headroom is there.
    [ -n "$installed" ] || return
    parts=
    percent_of five_hour
    [ -n "$REPLY" ] && parts="5h $REPLY%"
    percent_of seven_day
    [ -n "$REPLY" ] && parts="${parts:+$parts · }wk $REPLY%"
    percent_of context_window
    [ -n "$REPLY" ] && parts="${parts:+$parts · }ctx $REPLY%"
    [ -n "$parts" ] && printf '%s\n' "$parts"
}

hook() {
    local event sid cwd transcript kind pid ts
    [ -n "$body" ] || return
    # Once Headroom is uninstalled nothing is written, and nothing deleted.
    headroom_installed || return
    json_string hook_event_name
    event=$REPLY
    case $event in '' | *[!A-Za-z]*) return ;; esac
    session_id
    sid=$REPLY
    [ -n "$sid" ] || return

    case $event in
        SessionEnd)
            rm -f "$sessions/$sid.hook.json" "$sessions/$sid.statusline.json" \
                "$sessions/.$sid.hook.json."*.tmp "$sessions/.$sid.statusline.json."*.tmp
            return
            ;;
        SessionStart)
            [ -d "$sessions" ] && find "$sessions" -mindepth 1 -maxdepth 1 -type f -mmin +10080 -delete
            # Temp files of runs killed before they finished (an hour is far longer than any run).
            [ -d "$dir" ] && find "$dir" -mindepth 1 -maxdepth 2 -type f -name '.*.tmp' -mmin +60 -delete
            ;;
    esac

    json_string cwd
    cwd=$REPLY
    json_string transcript_path
    transcript=$REPLY
    kind=
    if [ "$event" = Notification ]; then
        json_string notification_type
        kind=$REPLY
        # Versions without notification_type say so in the message, which is never stored.
        if [ -z "$kind" ]; then
            json_string message
            case $REPLY in *"waiting for your input"*) kind=idle_prompt ;; esac
        fi
    fi
    claude_pid
    pid=$REPLY
    now
    ts=$REPLY
    ensure_dirs || return
    write_atomic "$sessions/$sid.hook.json" "{\"v\":1,\"ts\":$ts,\"pid\":$pid,\"event\":\"$event\",\"session_id\":\"$sid\",\"cwd\":\"$cwd\",\"transcript_path\":\"$transcript\",\"notification_type\":\"$kind\"}"
}

case $1 in
    statusline) statusline ;;
    hook) hook ;;
esac
exit 0

"""#

    /// The `N` of a `# headroom-bridge vN` line near the top of `script`, or nil.
    public static func headerVersion(in script: String) -> Int? {
        let prefix = "# headroom-bridge v"
        for line in script.split(separator: "\n", maxSplits: 5, omittingEmptySubsequences: false).prefix(5) {
            guard line.hasPrefix(prefix) else { continue }
            let digits = line.dropFirst(prefix.count)
            guard !digits.isEmpty, digits.count <= 9, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else {
                return nil
            }
            return Int(digits)
        }
        return nil
    }
}
