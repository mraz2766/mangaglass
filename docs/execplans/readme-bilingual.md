# ExecPlan: Bilingual README with English Default

## Summary

Create a bilingual README setup for MangaGlass where the repository's default `README.md` is in English and prominently links to a Chinese version. This improves first-time onboarding for international readers while preserving a native-language path for Chinese-speaking users.

## User Value

- New visitors immediately see an English README that explains what MangaGlass does and how to run it.
- Chinese-speaking users can switch to a dedicated Chinese document without losing detail.
- The repository gains a clearer onboarding path without changing product behavior or source code.

## Scope

In scope:

- Rewrite `README.md` into an English-first document.
- Add a dedicated Chinese README that can be reached from the English README.
- Add visible language-switch links between the two README files.
- Keep commands, supported sites, requirements, and project structure aligned with the current codebase.

Out of scope:

- Source code changes.
- UI localization inside the app.
- Adding unsupported commands, tests, or packaging flows.

## Constraints

- The project-level or global `PLANS.md` template was not present at `./.agent/PLANS.md` or `/Users/mraz/.codex/PLANS.md`, so this plan uses a compatible explicit structure and records that decision.
- The task must stay documentation-only before plan approval.
- All README content must be based on repository facts, existing scripts, and current source layout.

## Files To Modify

- `README.md`
- `README.zh-CN.md`
- `docs/execplans/readme-bilingual.md`

## Facts Gathered

- The project is a macOS app built with Swift Package Manager and SwiftUI.
- `Package.swift` declares Swift tools version `6.2` and platform `macOS 13`.
- The primary runnable command is `swift run MangaGlass`.
- The packaging script is `./scripts/build_dmg.sh`.
- Current assets include `assets/home.png`, `assets/logo.png`, and `assets/AppIcon.icns`.
- Current source layout includes `App`, `Models`, `Services`, `UI`, `Utils`, and `Resources`.
- Supported sites currently documented are CopyManga variants, Manhuagui, and MYCOMIC.

## Implementation Plan

### Milestone 1: Define the bilingual README structure

- Decide the language switch placement and wording for both documents.
- Keep `README.md` as the canonical English landing page.
- Use `README.zh-CN.md` as the dedicated Chinese counterpart.

### Milestone 2: Rewrite the English README

- Translate and refine the current Chinese README into concise English.
- Preserve real commands, paths, requirements, supported sites, and screenshots.
- Present usage flow, configuration notes, FAQ, and development notes in an English-first onboarding style.

### Milestone 3: Add the Chinese README with bidirectional switching

- Create `README.zh-CN.md` from the current README content, cleaned up as needed.
- Add a language toggle link near the top of both files.
- Ensure the Chinese version remains consistent with the English structure where practical.

### Milestone 4: Validate document behavior

- Check both files render sensible headings, links, code blocks, and screenshot references.
- Verify language links resolve correctly in the repository.
- Verify all commands and file paths mentioned in the README still exist.

## Verification

Observable checks:

- Opening `README.md` shows English content first and includes a visible link to `README.zh-CN.md`.
- Opening `README.zh-CN.md` shows Chinese content and includes a visible link back to `README.md`.
- Commands in the docs match real project entry points:
  - `swift build`
  - `swift run MangaGlass`
  - `./scripts/build_dmg.sh`
- Referenced files exist:
  - `assets/home.png`
  - `dist/MangaGlass.app`
  - `dist/MangaGlass.dmg`

## Risks

- The old Chinese README may contain wording that reads naturally in Chinese but needs adaptation rather than literal translation in English.
- The repository currently has no project-local planning template, so plan formatting may differ from the team's usual PLANS file while still covering the required execution details.
- Packaging artifacts under `dist/` are build outputs; the README must describe them as generated results, not committed guarantees.

## Decisions

- Decision: Use `README.md` for English and `README.zh-CN.md` for Chinese.
  Reason: This is the most common GitHub-friendly bilingual layout and ensures English is the default landing page.

- Decision: Keep the task documentation-only.
  Reason: The user requested README work, and no product behavior changes are needed.

- Decision: Use this custom ExecPlan structure.
  Reason: The required template file was unavailable in both project and global fallback locations.

## Progress

- [x] Inspect existing README, package manifest, build script, assets, and source tree.
- [x] Choose the bilingual documentation approach.
- [x] Create and save the ExecPlan.
- [x] Wait for user confirmation before editing README files.
- [x] Implement the bilingual README changes.
- [x] Validate links, commands, and referenced files.

## Surprises & Discoveries

- No `PLANS.md` template was available in the expected project or global fallback paths.
- The repository currently contains only a Chinese `README.md`, so a Chinese counterpart file will need to be created during implementation.
- The packaging script produces `dist/MangaGlass.app` and `dist/MangaGlass.dmg`, but those outputs are generated only after running the packaging step, so the README should describe them as build artifacts rather than assume they are committed.

## Outcomes & Retrospective

- `README.md` now serves as the default English landing page.
- `README.zh-CN.md` now provides the Chinese version with a direct switch back to English.
- Both files keep the same practical onboarding flow: overview, supported sites, quick start, usage, configuration, FAQ, and development notes.
- Validation was completed by checking the referenced commands and repository paths against current project files.
