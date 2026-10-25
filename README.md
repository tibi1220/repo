# tibi1220's Repo

APT repo for jailbreak tweaks by tibi1220, served at **https://tibi1220.github.io/repo/**.

This repo holds no packages. On every build, GitHub Actions:

1. reads `tweaks.json`
2. downloads the `.deb` assets of every published release in each listed repo
3. copies each repo's `depiction/` folder to `depictions/<package id>/`
4. generates `Packages*` and `Release`, and signs them (`Release.gpg`, `InRelease`)
5. deploys the result to GitHub Pages

Builds run on push to `main`, on a `new-release` repository dispatch, nightly, and manually.

## Layout

| Path | Purpose |
|---|---|
| `tweaks.json` | Tweak repos to include |
| `config/release-header` | Fixed fields of the `Release` file |
| `config/signing-key` | Fingerprint of the repo signing key |
| `static/` | Copied as-is to the site root (landing page, icon, public key) |
| `scripts/build.sh` | Builds the site into `_site/` |

## Adding a tweak

Add it to `tweaks.json`:

```json
{
  "tweaks": [
    { "repo": "tibi1220/mytweak" }
  ]
}
```

The tweak repo is expected to have:

- a `control` file at the root with `Package: com.tibi1220.<name>`
- releases with `.deb` assets for each scheme: `iphoneos-arm` (rootful), `iphoneos-arm64` (rootless), `iphoneos-arm64e` (roothide)
- optionally, a `depiction/` folder (`depiction.json`, `index.html`, `icon.png`, …), published at
  `https://tibi1220.github.io/repo/depictions/com.tibi1220.<name>/`

Asset filenames don't matter; debs are renamed to `<package>_<version>_<arch>.deb`.
Drafts and prereleases are skipped.

To trigger a rebuild right after releasing, the tweak repo's workflow can run:

```sh
gh api repos/tibi1220/repo/dispatches -f event_type=new-release
```

with a fine-grained token that has *Contents: read and write* on `tibi1220/repo`.

## Secrets

| Secret | Purpose |
|---|---|
| `GPG_PRIVATE_KEY` | ASCII-armored secret key matching `config/signing-key` |
| `TWEAKS_READ_TOKEN` | Optional; only needed if a tweak repo is private |

## Building locally

```sh
brew install dpkg jq xz zstd gnupg gh
scripts/build.sh
python3 -m http.server -d _site
```

The `Release` file is left unsigned when the signing key isn't in your keyring.
