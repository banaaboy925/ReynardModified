# Reynard 0.9.0 — WebRTC H.264 registration fix

This package is based on the supplied `reynard-browser-0.9.0.zip` and targets
its pinned `FIREFOX_153_0_RELEASE` Gecko source.

## What the fix changes

Firefox already routes WebRTC H.264 decoding through `MediaDataCodec` before
falling back to GMP/OpenH264. On Reynard/iOS that platform path can reach
`AppleVTDecoder`. The missing codec entry occurs earlier: Firefox 153 enables
its JSEP H.264 descriptions only when its old combined H.264 support gate is
true.

The added patches therefore:

1. enable the WebRTC hardware-H.264 pref on `XP_IOS`;
2. prefer the platform encoder path on `XP_IOS`;
3. query the actual `MediaDataCodec` encoder and decoder support on iOS;
4. enable H.264 when either direction is available;
5. mark H.264 receive-only when a decoder exists but no encoder exists.

This avoids pretending that ordinary `<video>` playback automatically
registers a WebRTC codec, while still reusing the existing VideoToolbox-backed
MediaDataDecoder/MediaDataEncoder implementations rather than introducing GMP.

## Prepare the source on Windows

Extract this zip. Open PowerShell in its top-level folder and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\tools\windows\prepare-gecko-h264.ps1
```

The script downloads the exact Firefox 153 tag and applies every official
Reynard patch plus the H.264 registration patches. It does not require the
outer source archive to contain a `.git` folder, and it does not require zsh.

To discard the downloaded Firefox tree and start over:

```powershell
.\tools\windows\prepare-gecko-h264.ps1 -ResetFirefox
```

## Building

Windows can prepare and inspect the source, but it cannot build the iOS app.
The final build still requires macOS with Xcode or a macOS GitHub Actions
runner.

## Verify after installing the build

Open `verify-webrtc-h264.html` in Reynard. The required result is at least one
`video/H264` entry under `receiveH264`. `sendH264` is reported separately so a
decoder-only result is not mistaken for encoding support.
