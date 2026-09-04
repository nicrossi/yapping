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

Debug builds are ad-hoc signed, so macOS may ask for Accessibility again after a rebuild.
