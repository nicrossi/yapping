# Yapping

Push-to-talk dictation for macOS. Hold **Fn**, talk, release — cleaned-up text lands wherever your cursor is. Fully on-device.

## Stack
- Swift 6 / SwiftUI menu-bar app, macOS 26+
- STT: Apple `SpeechAnalyzer` (default) or NVIDIA Parakeet via FluidAudio
- Cleanup: Apple Foundation Models (on-device), swappable
- Project generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Develop
```sh
brew install xcodegen
make run      # gen → build → launch
make test
make open     # open generated Yapping.xcodeproj
```
`Yapping.xcodeproj` is gitignored; edit `project.yml` instead.

## Permissions
- **Accessibility** — global Fn tap + synthetic ⌘V paste
- **Microphone**

Debug builds are ad-hoc signed. macOS ties the Accessibility grant to the code signature, so after a
rebuild the Yapping entry in System Settings → Privacy & Security → Accessibility may need to be
toggled off and on again. To avoid this, sign with a stable identity: create a free personal team in
Xcode (Settings → Accounts) and set `DEVELOPMENT_TEAM` / `CODE_SIGN_IDENTITY: "Apple Development"` in `project.yml`.

## Engines
| Engine | Where | Languages | Notes |
|---|---|---|---|
| Apple Speech (`SpeechAnalyzer`) | on-device, system model | ~30 locales (EN/ES/FR/DE/IT/PT/JA/KO/ZH) | default; streams partials while you talk |
| Parakeet TDT 0.6B v3 (FluidAudio) | on-device CoreML | 25 European langs + JA | ~600 MB download on first select, into `~/Library/Application Support/FluidAudio/Models` |

## Brand
Glass-wave identity: violet `#7C5CFF` → pink `#FF5CA8` gradient squircle, white five-bar wave.
Tokens live in `Yapping/UI/Brand.swift` (colors, wordmark, glyph, playful copy).
Icon and menu bar glyphs are generated, not hand-drawn: `make icons` (see `Tools/iconsmith.swift`).

## Debugging
```sh
/usr/bin/log stream --info --predicate 'subsystem == "com.nicorossi.yapping"'
```
(`log` is a zsh builtin — use the full path.)
