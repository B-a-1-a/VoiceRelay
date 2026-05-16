# PRD — Universal Voice (working title)

**Privacy-first AI dictation that turns your iPhone into the AI box for any nearby Mac.**

| | |
|---|---|
| Status | Draft v0.1 — hackathon scope |
| Platforms (MVP) | iPhone (iOS 26+) + macOS helper (macOS 26+) |
| Platforms (stretch) | iPad / Mac Catalyst / Windows helper / BLE dongle |
| Target user | Developers first, knowledge workers next |
| Core differentiator | 100% on-device AI, cross-device, no cloud audio ever |

---

## 1. TL;DR

A user presses the Action Button on their iPhone, speaks naturally, and clean, formatted text appears typed into whatever app is focused on their nearby Mac — Cursor, Slack, Notion, the terminal, anything. Audio never leaves the iPhone. Transcription runs on Apple's `SpeechAnalyzer` (iOS 26) and cleanup runs on Apple's on-device `Foundation Models` LLM. The Mac runs a tiny signed helper app that receives the cleaned text over the local network and types it via accessibility APIs.

**The demo moment:** the presenter holds up the iPhone, presses the Action Button, says *"hey, can you push the latest changes to the staging branch and ping me when CI is green, thanks"* with normal hesitations and filler, and the Mac on stage types a clean, properly punctuated message into Slack a beat later — with the Mac's Wi-Fi off, only same-LAN, and Activity Monitor showing zero network traffic to anything but the iPhone.

---

## 2. Why this, why now

**Wispr Flow** ($80M+ raised, valued at ~$700M) is the category leader and is fundamentally cloud-based — audio goes to OpenAI and Meta servers. They've taken Reddit-level heat for it. **SuperWhisper** is on-device but Mac-only. No tool offers genuine cross-device, on-device-only dictation.

iOS 26 made this newly buildable: `SpeechAnalyzer` is faster than Whisper Large V3 Turbo on Apple silicon, and the `FoundationModels` framework exposes a 3B-parameter on-device LLM with structured output and tool calling. Both are free, both run on the Neural Engine, both ship on every iPhone 15 Pro and newer. The iPhone has become a credible "AI box" you can carry to any Mac.

---

## 3. Target user

**Primary (hackathon demo audience):** developers who already pay for dictation tools or are curious about voice-coding. They use Cursor, VS Code, terminal, Slack. They will install a signed helper on their Mac without complaint. They care about privacy more than the median user. They have an iPhone 15 Pro or newer (Action Button + Apple Intelligence eligibility line up neatly here).

**Secondary (post-MVP):** knowledge workers writing email, docs, and messages all day. Same setup, different use cases (longer prose, fewer code blocks).

**Out of scope for now:** locked-down corporate environments where users can't install a helper; non-Apple-phone owners; the BIOS/kiosk/smart-TV crowd who'd need the dongle path.

---

## 4. Goals and non-goals

**Goals**
- Sub-2-second end-to-end latency from "stop speaking" to "text appears on Mac" for a 1-sentence utterance
- Zero audio data leaves the iPhone, ever — provable from network inspection
- One-tap activation from anywhere on the iPhone (Action Button, locked screen, Control Center)
- Universal text injection into any focused macOS text field
- Works fully offline once paired (no internet required on either device)
- Cleanup quality at least comparable to Wispr Flow on dev-flavored speech (code identifiers, Slack-isms, profanity, fillers)

**Non-goals (for the hackathon)**
- Windows and Linux helpers
- A BLE/USB hardware dongle
- Voice-driven editing of already-typed text ("make this more formal") — that's a fast-follow, not MVP
- A personal dictionary UI (we'll handle vocab via the LLM cleanup prompt for now)
- Cloud sync of settings or transcripts
- Accounts, auth, payments
- Audio file transcription (drag-and-drop a meeting recording)
- Translation
- Wake words ("Hey Voice")

---

## 5. Core user flow (MVP)

1. **One-time pairing.** User launches the macOS helper. It shows a QR code containing its mDNS service name + a 32-byte pre-shared key. User opens the iPhone app, scans the QR. Done. Persists across reboots.
2. **Trigger.** User long-presses the Action Button (or taps a Control Center toggle, or the lock-screen widget). A Live Activity appears in the Dynamic Island showing a waveform and a Stop button.
3. **Speak.** Audio is captured at 16 kHz mono and streamed into `SpeechAnalyzer` with `SpeechTranscriber` + `SpeechDetector`. Partial transcripts render in the Dynamic Island in real time so the user has visual confirmation.
4. **Stop.** User releases the Action Button (or `SpeechDetector` reports 1.5s of silence, or user taps Stop).
5. **Clean.** The full transcript is passed to a `LanguageModelSession` (Foundation Models) with instructions like *"remove filler words, fix grammar and punctuation, preserve the speaker's intent and tone, do not add new information."* Output is streamed.
6. **Send.** Cleaned text streams over the encrypted LAN socket to the paired Mac helper.
7. **Type.** Helper types the text into the currently focused app via `CGEventPost`.
8. **Done.** Live Activity dismisses. Total wall-clock from "stop speaking" to "text appearing": target ≤2 seconds.

---

## 6. Scope ladder

| Tier | Feature | Notes |
|---|---|---|
| **MVP (hackathon)** | Action Button trigger | `AudioRecordingIntent` App Intent |
| | Live Activity with waveform + partial transcript | Dynamic Island |
| | On-device transcription | `SpeechAnalyzer` + `SpeechTranscriber` (en-US only) |
| | On-device cleanup | Foundation Models with fixed cleanup prompt |
| | LAN transport with mDNS discovery + QR pairing + ChaCha20-Poly1305 encryption | WebSocket over TCP |
| | macOS helper: receive + type into focused app | `CGEventPost`, menubar icon, no window |
| **V1 (post-hackathon, ~2 weeks)** | Control Center widget | Toggle |
| | Lock-screen widget | Tap to record |
| | Back Tap support | Via Shortcuts |
| | Mode picker (Auto / Email / Code / Chat) | Changes LLM cleanup prompt |
| | Per-Mac-app context awareness | Helper reports focused app bundle ID back to iPhone |
| | Personal vocabulary (free-form list, applied in LLM prompt) | Bypasses SpeechAnalyzer's missing custom-vocab feature |
| **Stretch** | Command Mode | Highlight text on Mac, hit button, say *"make this more formal"* |
| | iPad app via Mac Catalyst / "Designed for iPad" | Likely free — same codebase |
| | Mac-native version (record on Mac directly) | macOS 26 has the same APIs |
| | Windows helper | Rust or C# + `SendInput` |
| | BLE/USB HID dongle | The "universal" SKU |
| | AirPods high-quality recording mode | iOS 26 feature |
| | Apple Watch trigger | Watch records, streams to phone |

---

## 7. Functional requirements

### 7.1 iOS app

- **Minimum target:** iOS 26.0, iPhone 15 Pro / Pro Max / 16 / 16 Plus / 16 Pro / 16 Pro Max / 17 series. (Apple Intelligence + Action Button + iOS 26 APIs all line up at this cut.)
- **Entitlements:** microphone, local network (for mDNS), background audio recording (via `AudioRecordingIntent`).
- **No Bluetooth permission required** for MVP — pairing is QR + LAN, not BLE.
- **App Intents:** one primary intent — `StartDictationIntent: AudioRecordingIntent` — that can be triggered from Action Button, Shortcuts, widgets, Control Center, Spotlight.
- **Live Activity:** waveform, partial transcript, Stop button, elapsed timer.
- **Recording:** `AVAudioEngine` tap into a `PCMBuffer`, fed to `SpeechAnalyzer` configured with `SpeechTranscriber(locale: .current)` and `SpeechDetector`.
- **Endpointing:** stop on (a) user release of Action Button, (b) tap on Live Activity Stop, (c) 1.5s of silence reported by `SpeechDetector`, (d) hard cap at 60s for MVP.
- **Cleanup:** `LanguageModelSession` with developer-defined instructions. Streamed response. If session unavailable (Apple Intelligence disabled), fall back to "raw transcript with simple regex filler-word removal" and surface a one-time banner.
- **Privacy guarantee in code:** the app declares no outbound network entitlements beyond the local-network usage description. ATS configured to disallow all non-local connections.
- **Error states:** mic denied, Apple Intelligence not enabled, helper unreachable, helper rejected handshake. Each has a designed Live Activity error state with one-tap remediation.

### 7.2 macOS helper

- **Minimum target:** macOS 26 (Tahoe), Apple silicon. Universal binary is trivial; Intel is out of scope.
- **Form:** menubar-only app, no Dock icon, no window in normal operation. Settings panel accessible from the menubar.
- **Permissions:** Accessibility (for `CGEventPost`), Local Network. Onboarding walks the user through granting these.
- **Discovery:** advertises `_universalvoice._tcp.local.` via Bonjour with a TXT record containing a stable device UUID.
- **Pairing:** displays a QR code containing `{service_name, device_uuid, psk_base64}`. PSK is generated on first launch and never leaves the keychain.
- **Transport:** WebSocket Secure over TCP using the PSK to derive a session key (Noise protocol or simple AEAD with handshake nonce). Messages are JSON: `{"type": "text", "content": "..."}`, `{"type": "ping"}`, `{"type": "context_request"}`.
- **Typing:** `CGEventPost` to the HID system event tap. Throttled at a configurable CPS (default ~600 — fast but reliable in laggy Electron apps).
- **Focus reporting (V1):** on each text injection, the helper records the currently-focused app's bundle ID and (optionally) sends it back to the iPhone for context-aware formatting on the next round.
- **No-op mode:** if Accessibility permission is missing, helper falls back to copying text to clipboard and showing a notification — the user can paste manually.

### 7.3 Transport and pairing

- mDNS for discovery on the LAN.
- QR code for one-time secret exchange.
- Authenticated symmetric encryption (libsodium / CryptoKit) for every message.
- Replay protection via monotonic nonces.
- If the helper is not on the same LAN, the iPhone shows a "Mac not found" error in the Live Activity and offers to copy the transcript to the iPhone clipboard as a fallback.
- **Explicitly not in scope:** relay servers, NAT traversal, multi-device fan-out, cloud sync of pairings.

---

## 8. Architecture

```
┌─────────────────────────── iPhone (iOS 26+) ───────────────────────────┐
│                                                                        │
│   Action Button ──► AudioRecordingIntent ──► Live Activity             │
│         │                                                              │
│         ▼                                                              │
│   AVAudioEngine ──► PCMBuffer ──► SpeechAnalyzer                       │
│                                   ├── SpeechTranscriber ──► transcript │
│                                   └── SpeechDetector ──► endpointing   │
│                                                  │                     │
│                                                  ▼                     │
│                                   FoundationModels.LanguageModelSession│
│                                   (cleanup, streaming)                 │
│                                                  │                     │
│                                                  ▼                     │
│                                   Encrypted WebSocket ─────────────────┼──┐
└────────────────────────────────────────────────────────────────────────┘  │
                                                                            │
                                                LAN (Wi-Fi or peer-to-peer) │
                                                                            │
┌──────────────────── macOS helper (macOS 26+) ──────────────────────────┐  │
│                                                                        │  │
│    mDNS advertiser ◄────── Bonjour browser on iPhone ──────────────────┼──┘
│         │                                                              │
│         ▼                                                              │
│    WebSocket server ──► decrypt ──► CGEventPost ──► focused app types  │
│                                                                        │
│    Menubar UI ──► pairing QR, focus reporting toggle, logs             │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 9. Tech stack

- **iOS app:** Swift 6, SwiftUI, Xcode 26. Frameworks: `FoundationModels`, `Speech` (the new `SpeechAnalyzer` API), `AVFoundation`, `AppIntents`, `ActivityKit`, `Network`, `CryptoKit`.
- **macOS helper:** Swift 6, AppKit (menubar) + SwiftUI (settings). Frameworks: `Network` (for mDNS + WebSocket), `CryptoKit`, `ApplicationServices` / `CoreGraphics` (for `CGEventPost`), `Carbon` (for focused-app detection — `NSWorkspace` is enough).
- **Shared:** a small Swift Package (`UniversalVoiceProtocol`) defining the wire format, codecs, and crypto, used by both apps to keep them in lockstep.
- **No third-party dependencies for MVP.** Everything is in the Apple SDKs.

---

## 10. Non-functional requirements

| | Target (MVP) | Stretch |
|---|---|---|
| Latency, end of speech → first character typed | ≤ 2.0s for a 1-sentence utterance | ≤ 1.0s with streaming chunks |
| Word Error Rate, dev-speak English | ≤ 8% on a held-out test set | ≤ 5% |
| iPhone battery drain | < 5% per 30 min of active dictation | < 3% |
| Audio leaving the iPhone | Zero bytes, ever | Zero bytes, ever |
| Cold-start time (Action Button → recording active) | ≤ 400ms | ≤ 200ms |
| Helper memory footprint at idle | ≤ 50 MB | ≤ 30 MB |
| Helper CPU at idle | ≤ 0.5% | ≤ 0.1% |

---

## 11. Cross-platform — iPad and Mac

Because Foundation Models, SpeechAnalyzer, AppIntents, and ActivityKit all ship on iPadOS 26 and macOS 26, the iPhone app should build for iPad and "Designed for iPad on Mac" with minimal additional code — likely just hiding the Action Button setup hints and adapting the Live Activity (which doesn't exist on iPad/Mac) to an in-app or menu-bar surface.

**iPad version, if it falls out for free:** the iPad becomes a second AI box that can type to the same Mac. Useful for users who keep an iPad as a writing surface.

**Mac-native version:** the same Mac that runs the helper could also run the recording app, making the iPhone optional for solo-Mac users. This is a real product wedge but is **explicitly stretch** — the hackathon story is "your iPhone types into your Mac," and the iPhone is the hero.

---

## 12. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Apple Intelligence not enabled on demo iPhone | Med | High | Pre-check `SystemLanguageModel.default.availability` on app launch, surface a clear "Enable Apple Intelligence in Settings" CTA. Have a known-good demo device with it on. |
| Foundation Models cleanup adds too much latency | Med | High | Cap input length at ~50 words; use streaming output; if first token >800ms, ship raw transcript and clean asynchronously (text gets a soft revision after typing). |
| `CGEventPost` flaky in Electron apps (Slack, VS Code, Cursor) | Med | Med | Throttle CPS; test against the demo apps explicitly; clipboard-paste fallback as escape hatch. |
| Same-LAN assumption breaks at hackathon venue (guest Wi-Fi isolation) | High | High | Support peer-to-peer Wi-Fi via `NWConnection` / `MultipeerConnectivity` as a fallback. **Test this before the demo.** |
| Live Activity / `AudioRecordingIntent` background recording subtlety | Med | High | This is a documented but nuanced iOS 18+ API. Build a thin smoke-test target on day 1 before building anything else. |
| `SpeechAnalyzer` lacks custom vocab → "Kubernetes" comes out wrong | Med | Med | Acceptable for MVP. V1 fix: post-correct in the LLM cleanup prompt with the user's vocab list. |
| App Store policy concerns about background audio + system-wide injection | Low (we're not on App Store for the hackathon) | High (long-term) | Document this risk for the post-hackathon roadmap. Likely fine — Wispr Flow ships an analogous architecture. |
| Demo Wi-Fi is hostile to mDNS | Med | High | iPhone hotspot as primary demo network. The helper laptop joins the hotspot, iPhone is on the hotspot, no internet needed. |

---

## 13. Open questions

1. Do we stream cleanup output to the helper character-by-character (text appears as the user speaks), or batch on each finalized sentence? Streaming is the "wow" but is finicky. Recommend batching for MVP.
2. How does the user undo a botched dictation? Probably out of scope — they ⌘Z on the Mac as normal.
3. What's our position on profanity, racy text, etc., from a model-safety standpoint? Foundation Models will refuse some content. We need to document the cleanup prompt to be transparent and not over-correct user intent. Worth a 30-min internal call.
4. Multi-language? `SpeechTranscriber` auto-detects mid-stream, but we should explicitly decide what locales the demo supports.
5. Should the helper run as a LaunchAgent at login? Probably yes for V1, no for MVP.
6. Do we even need pairing security for the hackathon demo? Arguably no — same-LAN trust is fine for a stage. But the architecture should support it from day 1 since retrofitting crypto is painful.

---

## 14. Hackathon plan

**Day 0 (prep, before the hackathon)**
- Confirm iPhone 15 Pro+ with iOS 26 and Apple Intelligence enabled.
- Confirm M-series Mac with macOS 26 and Xcode 26.
- Walk through Apple's `FoundationModels` and `SpeechAnalyzer` sample code, end-to-end, on the target devices.
- Smoke-test `AudioRecordingIntent` triggered by Action Button.

**Day 1 — vertical slice**
- Bare-bones iOS app: button on screen, record audio, transcribe with `SpeechAnalyzer`, show transcript on screen.
- Bare-bones macOS helper: button on screen, type "hello world" into the focused app via `CGEventPost`.
- Wire them: hardcoded WebSocket localhost-only first, then over LAN.

**Day 2 — the demo**
- Replace the iOS button with the Action Button intent.
- Add Foundation Models cleanup pass.
- Add Live Activity.
- Add mDNS discovery + QR pairing.
- Polish: app icon, menubar icon, error states for the top 3 failure modes.
- Demo dry-run, twice, on the actual demo network.

**What we explicitly do NOT build during the hackathon:** Control Center widget, Back Tap, mode picker, vocabulary, Command Mode, settings UI beyond pairing, Windows/Linux helpers, account system, telemetry.

---

## 15. Success criteria

**Hackathon-level success:**
- Live demo works on the first try, end-to-end, on stage.
- Latency is visibly snappy — under 2 seconds from stop to type.
- One judge says "wait, where is the audio going?" and we get to deliver the punchline.

**Post-hackathon "we should keep building this" signal:**
- We use it ourselves daily for two weeks without falling back to typing.
- A handful of TestFlight beta users (devs) report the same.
- WER on dev-speak is competitive with Wispr Flow on a small evaluation set.

---

## Appendix A — Naming

Working title: **Universal Voice**. Candidates to consider before launch: *Murmur*, *Conduit*, *Beam*, *Voiceline*, *Echo*, *Cascade*. Avoid: anything with "Whisper" (OpenAI), "Flow" (Wispr), "Talk" (Apple).

## Appendix B — Why iOS 26 minimum, restated

- `FoundationModels` framework: iOS 26+.
- `SpeechAnalyzer` / `SpeechTranscriber`: iOS 26+.
- Required hardware overlaps cleanly: iPhone 15 Pro+ has the Action Button *and* runs Apple Intelligence *and* runs both new frameworks. The constraint stacks line up at the same SKU. There is no reason to support iOS 18 — doing so would mean shipping a worse product to a smaller audience for more work.

## Appendix C — What we'd build next, by month

- **Month 1:** Command Mode (highlight + voice edit), per-app context formatting, personal vocabulary, settings UI.
- **Month 2:** iPad + Mac-native versions, Apple Watch trigger, AirPods high-quality mode.
- **Month 3:** Windows helper (Rust + `SendInput`), then Linux.
- **Month 4+:** the BLE/USB-HID dongle — the "universal SKU" that makes the original pitch's claim of true cross-platform compatibility real.
