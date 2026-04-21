# MangaGlass

[中文](./README.zh-CN.md)

MangaGlass is a local manga parsing and download tool for macOS, built with SwiftUI and Swift Package Manager.

Its core workflow is straightforward:

- paste a manga detail-page URL or chapter URL
- parse categories, volumes, and chapters
- choose a local download directory and add items to the queue
- manage downloads, retries, and logs on your machine

This project is a desktop app. It is not a general-purpose crawler framework and not a backend service.

## Supported Sites

- CopyManga family
  - `mangacopy.com`
  - `2025copy.com`
  - `2026copy.com`
- Manhuagui
  - `manhuagui.com`
- MYCOMIC
  - `mycomic.com`

Notes:

- Different sites use different page structures, anti-bot strategies, and stability levels.
- Some sites only parse reliably under specific network conditions, with cookies, or through a proxy.
- When a target site changes its layout, the parsing and download logic may need updates.

## Preview

<div align="center">
  <img src="./assets/home.png" alt="MangaGlass home screen" width="900">
</div>

## Features

- Parse manga detail pages and chapter pages
- Select categories, volumes, and chapters
- Batch download, pause, resume, cancel, and retry failed items
- Review queue state, progress, and failure reasons in the download manager
- Configure cookies and proxies
- Keep a recent history of opened entries
- Clear caches for:
  - parsed data
  - mirror cooldown state
  - current input and current parsing result
- Include basic rate-limit avoidance, partial site shutdown handling, and download protection

## Requirements

- macOS 13 or later
- Xcode Command Line Tools
- Swift 6.2 toolchain

If command line tools are not installed yet:

```bash
xcode-select --install
```

## Quick Start

### Run locally

```bash
swift build
swift run MangaGlass
```

### Build the `.app` and `.dmg`

```bash
./scripts/build_dmg.sh
```

Generated artifacts:

- `dist/MangaGlass.app`
- `dist/MangaGlass.dmg`

## How To Use

### 1. Load a manga

MangaGlass accepts:

- a full manga detail-page URL
- a full chapter-page URL
- for some sites, a simplified slug or path

Common examples:

```text
https://www.manhuagui.com/comic/19430/
https://www.2026copy.com/comic/haizeiwang
https://mycomic.com/comics/1759
https://mycomic.com/chapters/790421
```

### 2. Choose chapters

- select a category or volume first
- then choose one or more chapters
- use select all, clear, or select-all-in-current-category
- multi-selection and drag selection are supported

### 3. Start downloading

- choose a download directory
- add selected chapters to the queue
- watch progress, failures, and logs in Download Manager

## Configuration

### Cookies

Some sites or chapters require cookies to be accessed correctly. You can enter cookies directly in the app.

Typical cases where cookies help:

- the page opens in a browser, but the app cannot parse the content
- the chapter opens in a browser, but the app returns `403`, `404`, or empty content when downloading

### Proxy

The app supports proxy configuration in the UI:

- no proxy
- HTTP
- HTTPS
- SOCKS5

If your network is unstable when reaching the target site, proxy-based troubleshooting is often the first thing to try.

## Common Operations

### Clear cache

The top bar includes a `Clear Cache` action. It clears:

- the current URL in the input field
- the current cover and manga metadata
- parsed categories and chapters
- parsing-related caches
- mirror cooldown state

This is useful after anti-bot triggers, mirror issues, or temporary page-structure errors.

### Download Manager

The download manager is mainly used to:

- inspect queued, active, failed, and completed counts
- pause all downloads
- resume downloads
- cancel all downloads
- retry failed items
- clear completed items
- inspect failure reasons and current progress

## Project Structure

```text
Sources/MangaGlass/
  App/        App entry point, window setup, main state management
  Models/     Site, manga, download, proxy, and related data models
  Services/   Site parsing, download scheduling, DOM extraction
  UI/         SwiftUI views
  Utils/      Networking, JSON, session, and shared helpers
  Resources/  Bundled app resources

assets/
  AppIcon.icns
  logo.png
  home.png

scripts/
  build_dmg.sh
```

Key files:

- `Sources/MangaGlass/App/MainViewModel.swift`
- `Sources/MangaGlass/Services/CopyMangaAPI.swift`
- `Sources/MangaGlass/Services/DownloadCoordinator.swift`
- `Sources/MangaGlass/UI/ContentView.swift`

## Development

### Common commands

```bash
# debug build
swift build

# run locally
swift run MangaGlass

# package app and dmg
./scripts/build_dmg.sh
```

### Design direction

- prioritize simplicity, stability, and maintainability
- keep site-specific parsing logic inside the service layer as much as possible
- keep download logic separate from UI logic
- avoid over-polluting shared logic with one-off site-specific behavior

## FAQ

### 1. No chapters are parsed

Check the following first:

- the site may have changed its layout
- the current network may be rate-limited or blocked
- cookies may be required
- clearing the cache before retrying may help

### 2. All downloads fail or many images return 404

Common causes:

- the image resources are no longer valid
- the site or image host has entered a defensive mode
- parsed image URLs are no longer usable
- proxy quality or network stability is poor

### 3. A site works in my browser but fails in the app

This usually means:

- your browser already has cookies, but the app does not
- the site is more sensitive to headers, referer, or request frequency
- the current machine or IP is limited by the target site

### 4. Should I use the `.app` or the `.dmg`?

The build script generates both:

- `dist/MangaGlass.app`
- `dist/MangaGlass.dmg`

They come from the same build. In most cases you can use the app bundle directly or install the version inside the DMG.

## Known Boundaries

- Parsing depends on third-party site structures.
- Target sites may change, rate-limit requests, or block access at any time.
- Some chapters or image hosts are sensitive to referer, cookies, or request frequency.
- This project does not guarantee long-term compatibility with every target site.

## Usage Notice

This project is intended for local learning, research, and personal use.

Only access and download content that you are allowed to access. You are responsible for complying with the target site's rules, copyright requirements, and network restrictions.
