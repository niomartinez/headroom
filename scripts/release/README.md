# Releasing Headroom to the Mac App Store

Everything that can run from the command line goes through fastlane (`fastlane/Fastfile`). A few
steps still need the App Store Connect website. Do them in this order; the full checklist is
`docs/app-store.md`.

For 1.1 and later submissions, keep automatic release after approval, Free pricing and the existing China mainland exclusion.
The generic `metadata` and `submit` lanes below select manual release; use targeted App Store
Connect updates to preserve the current release policy when replacing a pending build.

| Step | Where | What |
|---|---|---|
| 0 | Terminal | `brew install fastlane xcodegen`, and the API key below. |
| 1 | Browser | Create the app record. |
| 2 | Terminal | `fastlane mac check`, then `fastlane mac build`. |
| 3 | Terminal | `fastlane mac upload`. |
| 4 | Terminal | `fastlane mac metadata`. |
| 5 | Browser | App Privacy: **Data Not Collected**. |
| 6 | Browser (or API) | Price: **Free**, all territories. |
| 7 | Terminal | `fastlane mac submit confirm:yes`, **only after the owner confirms**. |
| 8 | Browser | Once approved, release it (releases are manual). |

Run fastlane from the repository root. The Fastfile points `DEVELOPER_DIR` at
`/Applications/Xcode.app` itself.

On a Mac whose Homebrew lives in `/usr/local` (the Intel prefix, run under Rosetta), `brew install
fastlane` builds Ruby, Rust and LLVM from source, which takes hours. Install the gem with the Ruby
Homebrew already has instead, then run fastlane from there:

```sh
export GEM_HOME="$HOME/.local/share/fastlane" PATH="$(brew --prefix ruby)/bin:$HOME/.local/share/fastlane/bin:$PATH"
gem install fastlane --no-document
fastlane lanes
```

## 0. The App Store Connect API key

App Store Connect › Users and Access › Integrations › App Store Connect API › Team Keys: create a key
with the **Admin** role and download `AuthKey_<KEY_ID>.p8` (it can be downloaded once). `fastlane mac
build` exports with automatic signing, which signs with cloud-managed distribution certificates, and
only Admin keys may use those: with an App Manager key, xcodebuild stops at the export with a cloud
signing permission error. Keep the key file private (below). Then:

```sh
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_<KEY_ID>.p8 ~/.appstoreconnect/private_keys/
cat > ~/.appstoreconnect/api_key.json <<'JSON'
{
  "key_id": "<KEY_ID>",
  "issuer_id": "<ISSUER_ID from the same page>",
  "key_filepath": "~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8",
  "in_house": false
}
JSON
chmod 600 ~/.appstoreconnect/api_key.json ~/.appstoreconnect/private_keys/*.p8
```

`ASC_KEY_JSON` overrides the location: a path to such a file, or the JSON itself (CI). `"key"` (the
`.p8` text) works in place of `"key_filepath"`. Every lane that talks to Apple stops before doing
anything when the key is missing or incomplete, and says what's wrong. The key never goes in the
repository (`fastlane/.gitignore` ignores `*.p8`, `api_key.json` and `.env`).

## 1. App record (browser)

App Store Connect › Apps › + › New App: platform **macOS**, name **Headroom**, primary language
English (U.S.), bundle ID **com.niomartinez.headroom**, SKU e.g. `headroom-mac`, full access.

- The bundle ID must be registered first (Certificates, Identifiers & Profiles › Identifiers ›
  App IDs, explicit, no capabilities). `fastlane mac build` also lets Xcode register it through the
  API key (`-allowProvisioningUpdates`) if it's missing, so building once before this step works too.
- If the name "Headroom" is taken on the store, App Store Connect says so here. Pick the fallback
  (for example "Headroom: AI Limits") and put it in `fastlane/metadata/en-US/name.txt`.

## 2. Check and build

```sh
fastlane mac check    # no Apple contact: metadata limits, screenshots, ad-hoc Release archive
fastlane mac build    # signed archive → build/export/Headroom.pkg
```

`build` runs `xcodegen generate`, archives Release with automatic signing for team `L237BMXGB6`
(`-allowProvisioningUpdates` with the API key, so Xcode creates the certificates and profiles it
needs) and exports with `fastlane/ExportOptions.plist` (method `app-store-connect`). The build
number is one more than the newest build App Store Connect has for this version; pass
`build_number:42` (or `HEADROOM_BUILD_NUMBER`) to choose it. `MARKETING_VERSION` in `project.yml`
is the version.

For local launch checks, use `scripts/build-app.sh Debug` and `scripts/smoke-test.sh`.
Debug has its own Headroom Dev bundle and URL identity. Install the verified Release archive
in Applications and open it from Finder, so macOS does not associate Headroom's menu-bar
permission with the agent or IDE that started it. Register only the installed copy at login.

## 3. Upload

```sh
fastlane mac upload              # upload_to_app_store with pkg:
fastlane mac upload altool:true  # or xcrun altool --upload-app with the same key
```

App Store Connect then processes the build (usually 10 to 30 minutes, email when done). It shows up
under TestFlight › macOS; install it from TestFlight and run the checks in `docs/app-store.md` §9.

## 4. Metadata and screenshots

```sh
scripts/release/refresh-marketing-assets.sh   # only when the UI or the captions changed
fastlane mac metadata
```

Uploads `fastlane/metadata` (name, subtitle, description, keywords, promotional text, release notes,
URLs, copyright, categories, review notes), `fastlane/screenshots/en-US` and the 4+ age rating
(`fastlane/rating_config.json`). It never submits. `scripts/release/check-metadata.rb` runs first
and stops on anything App Store Connect would refuse (lengths, trademarks in the name, subtitle,
keywords or promotional text, screenshot sizes, alpha channels), and on keywords that repeat a word
of the name or subtitle. The App Review contact comes from
`HEADROOM_REVIEW_FIRST_NAME`, `HEADROOM_REVIEW_LAST_NAME`, `HEADROOM_REVIEW_PHONE` and
`HEADROOM_REVIEW_EMAIL` (see `fastlane/.env.example`); without them only the notes are uploaded.

The screenshots (01–07), the marketing PNGs (`marketing/assets`), the 1.1 feature snippets
(`marketing/social/1.1/snippets`) and the website's images are rendered from made-up data by
`headroom-render` and copied into place by `refresh-marketing-assets.sh`, never from this Mac's
sessions (`render-assets.sh`, which `fastlane mac screenshots` runs, calls it).

## 5. App Privacy (browser)

App Store Connect › the app › App Privacy › Get Started: "No, we do not collect data from this app"
→ **Data Not Collected**. Privacy Policy URL: `https://headroom.niomartinez.com/privacy`. The
bundled `App/PrivacyInfo.xcprivacy` says the same. (fastlane can only set this with an Apple ID
login, not an API key.)

## 6. Price (browser)

Pricing and Availability: price **Free (0.00)**, all countries and regions. deliver no longer
sets prices; the App Store Connect API can (`appPriceSchedules`), but the website is one click.

## 7. Submit (owner's go-ahead first)

```sh
export HEADROOM_REVIEW_FIRST_NAME=… HEADROOM_REVIEW_LAST_NAME=… HEADROOM_REVIEW_PHONE=… HEADROOM_REVIEW_EMAIL=…
fastlane mac submit confirm:yes            # optionally build_number:42
```

Refuses to run without `confirm:yes` (or `HEADROOM_CONFIRM_SUBMIT=yes`) and without the review
contact. Uploads the review information again, answers export compliance (no non-exempt encryption,
matching `ITSAppUsesNonExemptEncryption = NO`), picks the processed build and submits it with
**manual release** (`automatic_release: false`).

## 8. Release (browser)

When App Review approves, App Store Connect › the version › **Release This Version**.

## Lanes

| Lane | Talks to Apple | Does |
|---|---|---|
| `check` | no | `check-metadata.rb`, `plutil -lint` on the export options, ad-hoc signed Release archive. |
| `screenshots` | no | `scripts/release/render-assets.sh`, which runs `refresh-marketing-assets.sh`. |
| `build` | yes (signing) | Archive + export `build/export/Headroom.pkg`. |
| `upload` | yes | Upload the .pkg. |
| `metadata` | yes | Listing, screenshots, rating, review notes. No submission. |
| `submit` | yes | Submit for review, manual release. Needs `confirm:yes`. |

`ruby scripts/release/check-metadata.rb --self-test` breaks a copy of the listing in sixteen ways
(too long, trademarks, keywords that repeat the name or subtitle, wrong URL, a 12+ rating, "AI coding", a
non-affiliation line that misses OpenAI or GitHub, …) and
checks that each one is caught.
