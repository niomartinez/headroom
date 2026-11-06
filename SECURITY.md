# Security

Headroom reads local files written by Claude, Codex and Copilot. When the user connects them, it
also adds a status line and hooks to `~/.claude/settings.json`, writes Copilot session hooks, and
keeps a GitHub token in the Keychain for Copilot usage. Problems in any of these are worth
reporting.

Please report vulnerabilities privately by email to hello@niomartinez.com rather than in a public
issue. Include the Headroom version (Settings › About), your macOS version and the steps to
reproduce it.

Fixes go into the latest version on the Mac App Store.
