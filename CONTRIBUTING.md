# Contributing to Headroom

Bug reports, fixes and small improvements are welcome. For anything larger (a new tool, a new
panel section, a change to what Headroom reads or where it connects), open an issue first so we
can agree on the approach before you write it.

## Building and testing

`README.md` covers the requirements, building, the tests and the debugging tools. In short:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
(cd Packages/HeadroomKit && swift test)
scripts/test-app.sh
scripts/build-app.sh
```

The golden render tests (`Packages/HeadroomKit/Tests/HeadroomUITests/GoldenRenderTests.swift`)
compare pixels exactly, and text rendering differs between macOS versions. If only those fail on
your Mac and your change doesn't touch drawing, say so in the pull request rather than
re-capturing the goldens.

## Before you open a pull request

- Package and app tests pass.
- Fixtures, screenshots and renders use made-up data: no real session names, project paths,
  account names or tokens. `headroom-render` and the sample data exist for this.
- Tests stay silent and leave the real `~/.claude`, `~/.codex` and Copilot folders alone. See
  Silent QA in `AGENTS.md`.
- Privacy stays as it is: no analytics, no accounts, and no network connections except GitHub,
  and only after the user connects it for Copilot usage. A change here also changes the App Store
  privacy answers and the website's privacy page, so raise it in an issue first.
- One change per pull request, with a short description of what you checked by hand.

## Forks

The MIT license lets you build and ship your own version. Please give it your own name, icon and
bundle identifiers (`project.yml` and `Config/`): the Headroom name and icon identify the Mac App
Store app.

## License

By contributing, you agree that your contribution is licensed under the MIT License in `LICENSE`.
