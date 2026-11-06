#if HEADROOM_COPILOT_CLI
import Foundation

/// The Copilot CLI bridge source, installed to `~/.copilot/headroom/bridge.sh` (1.1 §4.9). Copilot CLI runs it from
/// the user hooks in `~/.copilot/hooks/headroom.json` (`CopilotBridgeHooks`) as `bridge.sh hook <event>`, with the
/// hook's JSON payload on stdin, and it writes `headroom/sessions/<sessionId>.hook.json`:
///
///     {"v":1,"ts":1790250200,"event":"notification","session_id":"<uuid>","cwd":"/Users/me/app",
///      "notification_type":"permission_prompt","pids":[[12345,"copilot"]]}
///
/// It follows the terminal bridge's rules (spec §2.4, §2.5): it runs under macOS `/bin/bash` 3.2 with only bash
/// builtins plus `cat`, `ps`, `date`, `mkdir`, `mv`, `rm` and `find`; prints nothing and always exits 0; reads stdin
/// once; writes atomically; never creates the `headroom` folder (only Connect does); and does nothing once Headroom
/// is uninstalled. String values are matched with a regex that keeps them JSON-escaped, so they can be re-embedded
/// verbatim. Only the session id, the folder, the event name and the notification type are extracted: prompt
/// text, tool arguments and tool results are never stored.
public enum CopilotBridgeScript {
    /// Bumped whenever what "Connect Copilot CLI" installs changes, so older installs read as `.outdated` and get
    /// repaired. Separate from the terminal bridge's `BridgeScript.version`.
    public static let version = 2

    /// The header line prefix: the script's second line is `# headroom-copilot-bridge v<version>`.
    static let headerPrefix = "# headroom-copilot-bridge v"

    public static let contents: String = #"""
#!/bin/bash
\#(headerPrefix)\#(version)
# Headroom's Copilot CLI bridge. "Connect Copilot CLI" installs it; "Disconnect" removes it.
# Usage: bridge.sh hook <event>, with Copilot CLI's hook payload on stdin.
# It writes only into the sessions folder next to it and never stores prompt text.

# Print nothing: Copilot CLI reads some hooks' output (a postToolUse hook can replace a tool's result).
exec >/dev/null 2>/dev/null
# A closed stdin would let `$(cat)` read its own pipe and hang: read /dev/null instead. Closed
# descriptors are found by duplicating them, never through /dev/fd (see the terminal bridge).
true 4<&0 || exec </dev/null

# Process bytes, not characters.
LC_ALL=C

# The folder this script lives in, ~/.copilot/headroom (or the same folder under $COPILOT_HOME):
# the hooks run it by its absolute path. Run any other way, it does nothing, so it never writes
# into whatever folder it was started in.
case $0 in
    /?*/*) dir=${0%/*} ;;
    *) exit 0 ;;
esac
sessions="$dir/sessions"

# Read stdin exactly once; never wait on a terminal.
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

# REPLY = the first string value of key $1 in the payload, still escaped.
json_string() {
    local re="\"$1\"$sp:$sp$string_re"
    REPLY=
    if [[ $body =~ $re ]]; then REPLY=${BASH_REMATCH[1]}; fi
}

# REPLY = the value of the first of the keys given that has one. Copilot CLI's own payloads are
# camelCase; its VS Code-compatible ones are snake_case.
json_string_any() {
    local key
    for key; do
        json_string "$key"
        [ -n "$REPLY" ] && return
    done
}

# REPLY = the session id when it is a safe file name, else empty (no path traversal).
session_id() {
    json_string_any sessionId session_id
    case $REPLY in
        . | .. | *[!A-Za-z0-9._-]*) REPLY= ;;
    esac
    [ "${#REPLY}" -le 128 ] || REPLY=
}

# REPLY = the notification type when it is a plain word (permission_prompt, agent_idle), else empty.
notification_type() {
    json_string_any notification_type notificationType
    case $REPLY in *[!A-Za-z0-9_]*) REPLY= ;; esac
    [ "${#REPLY}" -le 64 ] || REPLY=
}

# REPLY = the event: the hook's argument (Headroom's hooks file names it, since Copilot CLI's
# camelCase payloads don't), else the payload's hook_event_name; empty for events Headroom
# doesn't track. An argument Headroom doesn't know is never replaced by the payload's name.
event_name() {
    REPLY=
    case $1 in
        sessionStart | userPromptSubmitted | postToolUse | notification | agentStop | errorOccurred | sessionEnd)
            REPLY=$1
            return
            ;;
        ?*) return ;;
    esac
    json_string hook_event_name
    case $REPLY in
        SessionStart | sessionStart) REPLY=sessionStart ;;
        UserPromptSubmit | userPromptSubmitted) REPLY=userPromptSubmitted ;;
        PostToolUse | postToolUse) REPLY=postToolUse ;;
        Notification | notification) REPLY=notification ;;
        Stop | agentStop) REPLY=agentStop ;;
        ErrorOccurred | errorOccurred) REPLY=errorOccurred ;;
        SessionEnd | sessionEnd) REPLY=sessionEnd ;;
        *) REPLY= ;;
    esac
}

# REPLY = this script's ancestors as JSON, [[pid,"name"],...], nearest first: its parent (Copilot
# CLI's process, which the hook command hands over to this script) and up to 5 more, stopping at
# launchd or after the first one named `copilot`. Headroom tells which one is Copilot CLI by its
# log, logs/process-<epochMs>-<pid>.log. Names keep only plain characters, so they need no JSON
# escaping.
ancestors() {
    local pid=$PPID n=0 out ppid name list=
    while [ "$n" -lt 6 ]; do
        case $pid in '' | *[!0-9]* | 0 | 1) break ;; esac
        out=$(ps -o ppid=,comm= -p "$pid")
        set -f
        set -- $out
        set +f
        [ $# -ge 2 ] || break
        ppid=$1
        shift
        name="$*"
        name=${name##*/}
        name=${name//[!A-Za-z0-9._+-]/_}
        list="${list:+$list,}[$pid,\"${name:0:64}\"]"
        [ "$name" = copilot ] && break
        pid=$ppid
        n=$((n + 1))
    done
    REPLY="[$list]"
}

# REPLY = the folder this session's record names, still escaped, or empty. Notification payloads
# carry no cwd, and the folder is the session's name in Headroom: it must not go blank.
recorded_cwd() {
    local file="$sessions/$1.hook.json" old= re="\"cwd\"$sp:$sp$string_re"
    REPLY=
    [ -f "$file" ] || return
    IFS= read -r -d '' old <"$file"
    if [[ $old =~ $re ]]; then REPLY=${BASH_REMATCH[1]}; fi
}

# REPLY = the current time in epoch seconds.
now() {
    REPLY=$(date +%s)
    case $REPLY in '' | *[!0-9]*) REPLY=0 ;; esac
}

# Creates the sessions folder (private) unless it exists. Never creates this script's own folder:
# only "Connect Copilot CLI" does, so a run still in flight after "Disconnect" can't bring it back.
ensure_dirs() {
    [ -d "$sessions" ] && return 0
    [ -d "$dir" ] || return 1
    mkdir -m 700 "$sessions" || [ -d "$sessions" ]
}

# Atomically replaces file $1 with $2: temp file in the same directory, then mv -f. A run stopped
# mid-write (Copilot CLI's timeout) removes its temp file.
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

# Whether Headroom is still installed. Deleting the app leaves the hooks in place, and then nothing
# reads what this writes. It is installed while any of these exists: the app "Connect Copilot CLI"
# ran from (its absolute path in app-path, one trailing newline allowed), a copy in /Applications,
# or the App Store version's container. An install that recorded no app always counts as installed.
headroom_installed() {
    local file="$dir/app-path" app=
    [ -e "$file" ] || return 0
    if [ -f "$file" ]; then
        IFS= read -r -d '' app <"$file"
        app=${app%$'\n'}
        case $app in /*) [ -e "$app" ] && return 0 ;; esac
    fi
    [ -e "\#(BridgeScript.applicationsCopyPath)" ] || [ -e "$HOME/\#(BridgeScript.containerPath)" ]
}

hook() {
    local event sid cwd kind pids ts
    [ -n "$body" ] || return
    # Once Headroom is uninstalled nothing is written, and nothing deleted.
    headroom_installed || return
    event_name "$1"
    event=$REPLY
    [ -n "$event" ] || return
    session_id
    sid=$REPLY
    [ -n "$sid" ] || return

    case $event in
        sessionEnd)
            json_string reason
            if [ "$REPLY" = complete ]; then
                # Desktop sessions end immediately after agentStop, often between Headroom polls.
                # Keep successful completion so the next poll can observe working -> idle.
                event=sessionCompleted
            else
                rm -f "$sessions/$sid.hook.json" "$sessions/.$sid.hook.json."*.tmp
                return
            fi
            ;;
        sessionStart)
            [ -d "$sessions" ] && find "$sessions" -mindepth 1 -maxdepth 1 -type f -mmin +10080 -delete
            # Temp files of runs killed before they finished (an hour is far longer than any run).
            [ -d "$dir" ] && find "$dir" -mindepth 1 -maxdepth 2 -type f -name '.*.tmp' -mmin +60 -delete
            ;;
    esac

    json_string cwd
    [ -n "$REPLY" ] || recorded_cwd "$sid"
    cwd=$REPLY
    kind=
    if [ "$event" = notification ]; then
        notification_type
        kind=$REPLY
    fi
    ancestors
    pids=$REPLY
    now
    ts=$REPLY
    ensure_dirs || return
    write_atomic "$sessions/$sid.hook.json" "{\"v\":1,\"ts\":$ts,\"event\":\"$event\",\"session_id\":\"$sid\",\"cwd\":\"$cwd\",\"notification_type\":\"$kind\",\"pids\":$pids}"
}

case $1 in
    hook) hook "${2-}" ;;
esac
exit 0

"""#

    /// The `N` of a `# headroom-copilot-bridge vN` line near the top of `script`, or nil.
    public static func headerVersion(in script: String) -> Int? {
        for line in script.split(separator: "\n", maxSplits: 5, omittingEmptySubsequences: false).prefix(5) {
            guard line.hasPrefix(headerPrefix) else { continue }
            let digits = line.dropFirst(headerPrefix.count)
            guard !digits.isEmpty, digits.count <= 9, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else {
                return nil
            }
            return Int(digits)
        }
        return nil
    }
}
#endif
