# foo_scrobble (macOS)

foobar2000 component for scrobbling to [Last.fm](https://www.last.fm/) on **macOS**.

> Based on [gix/foo_scrobble](https://github.com/gix/foo_scrobble) (Windows), modernized and ported to macOS mainly by AI. Currently no plans to support other platforms.

## Features

- Uses the [Scrobbling 2.0 API](https://www.last.fm/api/scrobbling). You authorize the component with last.fm instead of entering your login credentials into foobar2000.
- Supports "Now Playing" notifications.
- Handles intermittent network outages or reconnects well.
- Manages the scrobble cache automatically. No need to manually submit the cache.
- Allows custom tags for scrobbled details (via titleformat scripts).

## Prerequisites

- macOS 11 (Big Sur) or newer
- foobar2000 for macOS 2.0+
- Xcode Command Line Tools (`xcode-select --install`)
- `p7zip` (for SDK setup: `brew install p7zip`)

## Building

```bash
# 1. Download foobar2000 SDK
./setup.sh
# If you need a proxy: ./setup.sh http://127.0.0.1:7890

# 2. Set up Last.fm API credentials
cp src/foo_scrobble/Keys.local.h.template src/foo_scrobble/Keys.local.h
# Edit Keys.local.h with your API key and secret from https://www.last.fm/api/account/create

# 3. Build
make -j
```

The built component is at `build/foo_scrobble.component`.

## Installation

Copy `build/foo_scrobble.component` to foobar2000's user components directory:

```bash
cp -R build/foo_scrobble.component ~/Library/foobar2000-v2/user-components/foo_scrobble
```

Or use foobar2000's UI: Settings → Components → Add → select `build/foo_scrobble.component`.

## Differences from the Windows version

This is a clean-room port adapted for macOS. Several Windows-specific features were **not** ported:

| Feature | Windows | macOS |
|---------|---------|-------|
| Preferences UI | WTL dialog (rich, with dark mode) | Basic AppKit panel |
| Title format mapping editor | Full editor in preferences | Not yet implemented (edit config directly) |
| "Scrobble tracks" menu command | Yes | Not yet implemented |
| HTTP client | cpprestsdk (Microsoft) | NSURLSession (native) |
| Async framework | PPL (concurrency::task) | NSURLSession completion handlers |
| MD5 signing | foobar2000 `hasher_md5` service | CommonCrypto `CC_MD5` |
| Config storage | `cfg_var_legacy` (binary) | `cfg_var_modern` (per-key) |
| Scrobble cache | `cfg_var_legacy` (binary) | JSON file in profile dir |
| Offline test server | LastfmApiStub (C# WPF) | Not included |

## License

Code licensed under the [MIT License](LICENSE.txt), same as the original Windows version.
