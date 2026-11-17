# YouTube "Live Class" Player — Prototype & Handoff

A throwaway Flutter (Android) prototype that proves we can play a **YouTube video inside our app so that it looks like our own live class**:

- None of YouTube's own UI shows (title bar, channel avatar, logo, link button, "More videos", pause/play, end-screen suggestions).
- The user has no way to reach the YouTube URL from inside the app.
- The user can't pause. The class just plays.
- Joining "late" starts the video at a given offset.
- A yoga-themed breathing animation covers the few seconds while the player warms up.
- Network problems are explained clearly ("Internet connection lost", "Weak internet connection") and the class recovers by itself.

## Screenshots

<table>
  <tr>
    <td align="center" width="33%"><img src="docs/screenshots/1-home.jpg" width="240" alt="Home screen with four Join buttons" /><br/><sub><b>Home</b>: join on time or late</sub></td>
    <td align="center" width="33%"><img src="docs/screenshots/2-loader.jpg" width="240" alt="Breathing loader while the class starts" /><br/><sub><b>Loader</b>: guided breathing while the player warms up</sub></td>
    <td align="center" width="33%"><img src="docs/screenshots/3-playing.jpg" width="240" alt="Video playing with no YouTube UI" /><br/><sub><b>Class</b>: video with no YouTube UI</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/4-message.jpg" width="240" alt="Typing a message to the instructor" /><br/><sub><b>Message</b>: privacy banner stays above the keyboard</sub></td>
    <td align="center"><img src="docs/screenshots/5-offline.jpg" width="240" alt="Internet connection lost message" /><br/><sub><b>Offline</b>: "Internet connection lost"</sub></td>
    <td align="center"><img src="docs/screenshots/6-weak.jpg" width="240" alt="Weak internet connection message" /><br/><sub><b>Weak connection</b>: online but still stalled</sub></td>
  </tr>
  <tr>
    <td align="center" colspan="3"><img src="docs/screenshots/7-fullscreen.jpg" width="720" alt="Fullscreen landscape playback" /><br/><sub><b>Fullscreen</b>: landscape, immersive, still no YouTube UI</sub></td>
  </tr>
</table>

*Captured on a Nothing A024 (Android 17). Status bar cropped out.*

---

Everything lives in **one file, `lib/main.dart`**, so it's easy to lift into the real product. This document explains *what* we did, *why* each piece exists, and *what to keep in mind when porting it*.

**Reading guide**
- Just want the rules? Read [§3 The core problem](#3-the-core-problem) and [§4 Techniques](#4-techniques-and-why-each-exists).
- Rebuilding this somewhere else? Follow [Appendix A: Build it step by step](#appendix-a-build-it-step-by-step). It walks through the whole thing in build order, with the code.
- Want to know what we tried and why it ended up this way? See [Appendix B: How we got here](#appendix-b-how-we-got-here-iteration-log), the iteration log with every dead end and measurement.

> ⚠️ **Policy note — read first.** Hiding YouTube's branding, controls and links breaks the
> [YouTube API Services Developer Policies](https://developers.google.com/youtube/terms/developer-policies)
> (the player's controls and attribution must not be hidden, overlaid or blocked). This prototype was built
> for **personal / internal use only**. Shipping it publicly (e.g. Play Store) risks the API key, app removal or
> account action. For a public product, the policy-safe route is to **host the videos ourselves** and play them with
> `video_player` (+ signed URLs / DRM). See [Going to production](#going-to-production).

---

## 1. What the prototype does

| Screen | Behaviour |
|---|---|
| **Home** | Blank page with four buttons: *Join class* (00:00), *Join 2:30 mins late* (02:30), *Join 5 mins late* (05:00), *Join 08:15 mins late* (08:15). |
| **Live class** | Matches the design mock: video at the top with a back button, red **LIVE** pill, fullscreen button, message box with a green send button, and the *"Only you and the instructor can see your messages"* banner, which stays above the keyboard. |
| **Loading** | A green panel with a meditating figure inside a breathing circle (*Breathe in… / Breathe out…*, ~4 s per breath). It covers the video until YouTube's own UI has gone. |
| **Network trouble** | The same loader, with a clear message (see [4.9](#49-network-problems-clear-messages-and-self-recovery)). |
| **Fullscreen** | Landscape and immersive, video only. Back or the exit button returns to portrait. |

Test video: `aqz-KE-bpKQ` (Blender's *Big Buck Bunny*, CC-BY).

---

## 2. Stack

| Thing | Version | Why |
|---|---|---|
| Flutter | 3.50 (Dart 3.14) | — |
| [`youtube_player_iframe`](https://pub.dev/packages/youtube_player_iframe) | 6.0.3 | Wraps YouTube's official IFrame Player API in a WebView. |
| [`webview_flutter`](https://pub.dev/packages/webview_flutter) | 4.14.1 | Direct dependency so we can replace the player's `NavigationDelegate` (link blocking) and create the pre-warm WebView. |
| [`connectivity_plus`](https://pub.dev/packages/connectivity_plus) | 7.3.2 | Online / offline detection for the loader message and reconnect handling. |

Android manifest: `android.permission.INTERNET` added.

We looked at [`youtube_player_flutter`](https://github.com/sarbagyastha/youtube_player_flutter), the older sibling package in the same repo. It doesn't help: it uses the same YouTube iframe underneath, so the same overlays appear and the same workarounds would be needed.

---

## 3. The core problem

The video plays inside **YouTube's iframe in a WebView**. Everything YouTube draws (title, logo, link, pause bar, "More videos", end screen) lives **inside a cross-origin iframe**, so we **cannot style, hide or remove it with CSS/JS**. The only levers we have are:

1. **Player parameters**, which turn off what YouTube allows us to turn off.
2. **Not touching the player**, so YouTube's UI isn't triggered by hover or tap.
3. **Covering the player** at the moments YouTube shows its UI anyway.
4. **Never doing the things that make YouTube show its UI** (resizing, seeking).
5. **Blocking navigation** out of the WebView.

Each technique below is one of these.

---

## 4. Techniques (and why each exists)

Each technique below was found by recording the phone screen (see [§6](#6-how-we-verified-things)), not by guessing.

### 4.1 Turn off what YouTube lets us turn off
```dart
YoutubePlayerParams(
  showControls: false,          // controls=0 — no control bar / logo bar during play
  showFullscreenButton: false,
  showVideoAnnotations: false,
  strictRelatedVideos: true,
  enableCaption: false,
  pointerEvents: PointerEvents.none, // iframe never gets touches → UI never wakes up
  mute: true,                        // see 4.6
)
```
`controls=0` alone is **not enough**. YouTube still shows its title bar at start, a "More videos" bar on pause, an overlay on resize, and suggestions at the end.

### 4.2 Block every link (URL can't leave the app)
The package by default opens logo, title and share taps with `url_launcher` (in the YouTube app or a browser). We replace its navigation delegate:
```dart
_controller.webViewController.setNavigationDelegate(
  NavigationDelegate(onNavigationRequest: (_) => NavigationDecision.prevent),
);
```

### 4.3 Overlays MUST go through `controlsBuilder` (gotcha!)
On Android and iOS, `youtube_player_iframe` renders the WebView inside an **`OverlayPortal` above the whole page**. Anything you put on top of `YoutubePlayer` in a normal `Stack` is drawn **underneath** the video and is invisible. That's why our back button, LIVE pill and cover didn't show at first.

✅ Everything drawn over the video (cover, loader, back, LIVE, fullscreen) is returned from **`YoutubePlayer(controlsBuilder: ...)`**, which the package draws above the WebView.

### 4.4 Cover the player whenever YouTube would show UI
`_PlayerControls` listens to `controller.stream` and shows an opaque cover:

| Player state | Cover |
|---|---|
| not started / cued | breathing loader |
| `buffering` (**including mid-class stalls**) | breathing loader. During a stall YouTube shows its *full* overlay (title, "More videos", logo, spinner). |
| `paused` | breathing loader (and we immediately call `playVideo()`; see 4.7) |
| `ended` | video thumbnail (hides YouTube's end-screen suggestions) |
| `playing` after a pause | stays up **1.2 s more** (`_settle`): YouTube's pause bar *fades* out after resuming |
| `playing` after buffering | stays up **5 s more** (`_afterBuffering`): YouTube keeps its overlay up ~4 s after a stall (measured: still visible at 4.0 s, gone by 4.25 s) |

How the stall was reproduced: start playback, then `adb shell svc wifi disable && adb shell svc data disable` until the player logs `buffering` (~30–60 s, once the buffer drains), re-enable both, and screen-record the recovery. In debug builds every state change is printed as `[player] state=...`.

### 4.5 Never resize the iframe → fixed-size player that is only *scaled*
**Finding:** whenever the iframe changes size (e.g. entering or leaving fullscreen), YouTube shows its title, link, logo and pause overlay for **~6–7 s**.

**Fix:** the `YoutubePlayer` is laid out **once** at a fixed landscape-sized resolution (`baseW = screen.longestSide`, 16:9) and then only **scaled** with `FittedBox` into either the inline slot or the fullscreen area. YouTube never sees a resize, so it never shows the overlay.

- The package's overlay follows the placeholder via `CompositedTransformFollower`, so it inherits our scale automatically.
- Because the controls layer inherits the scale too, we **undo** it for the controls (`FittedBox` around a `SizedBox(baseW * scale, baseH * scale)`) so buttons stay normal size.
- Fullscreen is therefore **our own** (`_setFullscreen`: orientation + immersive mode + new rect/scale), **not** the package's `enterFullScreen()`, which resizes the WebView. `autoFullScreen` and `enableFullScreenOnVerticalDrag` are off.
- The `YoutubePlayer` widget stays at the **same place in the widget tree** in both modes (only the rect and scale change), so the WebView is never recreated.

### 4.6 Hide YouTube's start-of-playback overlay (muted intro hold)
**Finding:** for **~4.2 s after playback starts**, YouTube shows an overlay even with `controls=0`: the **title bar** at the top (channel avatar + title), a **pause icon in the centre** and a **"More videos" chip at the bottom**. Measured from 8 fps recordings: pause icon and chip gone at ~+3.6 s, title gone at ~+4.2 s.

**Fix:**
1. Start the player **muted**, **4.5 s before** the requested position (`startSeconds - 4.5`, clamped at 0).
2. Keep the full cover up for **4.5 s after the first `playing` event** (`_PlayerControlsState._introHold`).
3. Then **unmute only**. Playback is now exactly at the requested time (verified: "Join 2:30 mins late" reveals at `02:30`).

❌ **Don't seek** to fix the offset after the hold. We tried: `seekTo()` makes YouTube show its title bar and pause icon **again** for ~3–4 s. Unmuting does not.

❌ **Don't try to cover only the top strip.** We tried revealing the video after 0.8 s with a branded header band over the title area. It hid the title, but the centre pause icon and "More videos" chip were visible for ~3 s. The overlay covers the whole player, so the cover has to as well.

**Why 4.5 s can't be cut much:** the hold is only ~0.3 s longer than YouTube's own overlay, and every way of starting playback (load, seek, new video) triggers that overlay. What *can* be cut is the time **before** playback starts; see 4.10.

Trade-off: when starting at 00:00 the first 4.5 s play muted behind the loader (for this video that's just the title card).

### 4.7 No pause, ever
- Taps on the video are swallowed (`AbsorbPointer`). There is no play/pause UI.
- If the player reports `paused` while the app is in the foreground (WebView hiccup, etc.), we call `playVideo()` immediately.
- `AppLifecycleListener(onResume: playVideo)`: Android pauses the WebView in the background, so we resume when the user returns.

### 4.8 Show the loader from the very first frame (no package thumbnail)
**Finding:** while the player boots, the package draws **its own thumbnail on top of everything** (including `controlsBuilder`), but only if the controller has a `key`.

**Fix:**
- Create the controller **without a key** (`YoutubePlayerController(params: ...)` instead of `.fromVideoId(...)`), then call `loadVideoById(...)` right after.
- Pass `backgroundColor: Colors.transparent` to `YoutubePlayer`. With no key, the package's boot layer is a plain box of that colour, so it's see-through and our loader shows from frame one.

### 4.9 Network problems: clear messages and self-recovery
The loader text depends on what's going on (`_PlayerControlsState._message`):

| Situation | Headline | Sub-line |
|---|---|---|
| Normal start | *Breathe in… / Breathe out…* | Settle in, class is starting |
| Device offline (`connectivity_plus` reports no network) | 📵 **Internet connection lost** | We'll continue as soon as you're back online |
| Online but the video stalled mid-class | **Weak internet connection** | Hang on, the class will resume shortly |
| Stall over, waiting out YouTube's post-stall overlay (`_afterBuffering`) | **Connection is back** | Resuming class… |

Recovery:
- **Back online after a mid-class stall:** we call `playVideo()` as a nudge; YouTube resumes from its buffer position.
- **Joined while offline:** YouTube's player script never downloaded, so nothing can resume. When the connection returns and the class has never played, `LiveClassPage._restartPlayer()` throws the controller away and builds a fresh one (`YoutubePlayer` is keyed by `ObjectKey(_controller)`). Verified: playing ~5 s after reconnect.

Note: `connectivity_plus` only knows whether there is *a network*, not whether it reaches the internet. "Wi-Fi connected but no internet" therefore shows **Weak internet connection**.

### 4.10 Faster first join: pre-warm on the home screen
**Finding** (debug build, `[player] +Nms` logs): tap → first `playing` took **2.3 s** on the first join after launch and **0.8–1.5 s** on later joins. The difference is Android starting its WebView engine and downloading YouTube's player scripts.

**Fix:** `HomePage` creates a hidden, never-displayed `WebViewController` that loads `https://www.youtube-nocookie.com/embed/<id>?controls=0` (no autoplay; navigation locked to the embed page). The engine is then warm and the scripts cached when the user taps Join. Measured first join after launch: **1.7 s** (was 2.3 s).

Total wait now: ~1–1.7 s boot + 4.5 s intro hold.

**Bigger win for the real product:** in a real live class the "minutes late" offset is known before the user taps Join (it's *now − class start*). A lobby or class-details screen could start the real player muted and hidden in the background, so the intro hold has already passed by the time the user joins. That needs the player to live above the route (one shared `YoutubePlayer`), because the package reloads the player page whenever a `YoutubePlayer` widget is created.

---

## 5. Code map (`lib/main.dart`)

| Piece | What it is |
|---|---|
| `HomePage` | The four "Join …" buttons; `starts` list = `(label, seconds)`. |
| `LiveClassPage(startSeconds:)` | Owns the controller (early muted start, 4.6), fullscreen (4.5), player restart (4.9), page layout. |
| `_PlayerControls` | Everything drawn over the video; cover logic (4.4), intro hold (4.6), no-pause (4.7), network messages and reconnect (4.9). |
| `_Cover` / `_BreathingLoader` / `_LoaderMessage` | Loader (breathing, `_half` = 2 s in / 2 s out) with the current message, or end-of-video thumbnail. |
| `_HomePageState._warmUp` | Hidden pre-warm WebView (4.10). |
| `_MessageInput`, `_PrivacyBanner`, `_LiveBadge`, `_GlassButton` | UI from the design mock. Messages are **not sent anywhere** yet (field just clears). |

Tunables:

| Constant | Value | Meaning |
|---|---|---|
| `_introHold` | 4500 ms | Muted cover after first play; must outlast YouTube's start overlay (~4.2 s). The early start uses the same value. |
| `_settle` | 1200 ms | Cover after any later resume; outlasts the pause-bar fade. |
| `_afterBuffering` | 5000 ms | Cover after recovering from a stall; outlasts YouTube's ~4 s post-stall overlay. |
| `_BreathingLoader._half` | 2000 ms | Half a breath. |

---

## 6. How we verified things

The phone was connected over USB and we used `adb` to drive the app and **record the screen**, then turned the recording into a contact sheet of frames to see exactly when YouTube's UI appears:

```bash
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: stop it rewriting /sdcard paths
adb shell screenrecord --time-limit 12 --size 630x1400 /sdcard/load.mp4 &
adb shell input tap 630 1148            # tap a button (physical px)
adb pull /sdcard/load.mp4 load.mp4
ffmpeg -i load.mp4 -vf "fps=4,crop=630:290:0:55,tile=4x12" -frames:v 1 sheet.png
```
At 4 fps, each frame is 250 ms (we used 8 fps for the intro overlay), which is how we measured the ~4.2 s start overlay and the ~6–7 s resize overlay.

Network tests: `adb shell svc wifi disable && adb shell svc data disable` to go offline, `... enable` to come back. In debug builds the app logs `[player] +<ms> state=...` and `[player] offline=...`.

Status of checks on the test device (Nothing A024, Android 17):
- ✅ Load → loader → clean video, at the right timestamp (00:00, 02:30, 05:00 checked)
- ✅ Fullscreen in and out without YouTube UI
- ✅ Tapping the video does nothing
- ✅ Mid-class buffering stall (network cut) → "Internet connection lost" → "Connection is back" → clean video
- ✅ Joining while offline → "Internet connection lost" → player restarts on reconnect, playing ~5 s later
- ✅ Pre-warm: first join tap → playing 1.7 s (was 2.3 s)
- ✅ **"Weak internet connection"** seen on device: right after the network came back, while YouTube was still stalled (online + buffering). A genuinely slow connection couldn't be simulated (no way to throttle the phone's network without root).
- ✅ No Flutter exceptions in logs
- ⚠️ **Audio returning after unmute was not checked by ear.** Please confirm.
- ⚠️ Not tested on iOS (the package behaves differently there; e.g. its navigation handling and OverlayPortal paths).
- ⚠️ Release APK was built but not installed and tried on the device.

---

## 7. Known limitations / risks

- **Policy** (see top). This is the big one.
- **Fragile by nature:** every timing (4 s title, 1.2 s fade, resize overlay) is **YouTube behaviour we observed**, not a documented contract. A YouTube player update can break it. Re-run the screen-record check after any player change.
- **Slow networks:** every stall shows the loader and adds ~5 s of cover after recovery. On a very flaky connection the user may see the loader often. (There's a tiny window, ≤ one state update ~100 ms, between YouTube drawing its stall overlay and our cover appearing.)
- **Recovery after a long outage can be slow:** in one test YouTube took ~34 s after the network returned to resume (its own retry back-off), even with our `playVideo()` nudge. A real product may want a "Reconnect" fallback that restarts the player after N seconds.
- **The URL is not truly secret:** the video ID is in the app binary and in network traffic. Fine for "no way from the UI"; not DRM.
- **Muted autoplay at 00:00** loses the first 4.5 s of the video (see 4.6).
- The design mock's `mm:ss / mm:ss` time label and red progress bar were removed on request, so there's no visible playback position (like a real live stream). Re-adding them is easy: `controller.videoStateStream` gives the position and `controller.value.metaData.duration` the length.
- The `LIVE` pill is decorative; this is a VOD.
- Release build is signed with the **debug key** (Flutter template default).

---

## 8. Porting checklist (into the real app)

1. Add `youtube_player_iframe`, `webview_flutter` and `connectivity_plus`. Make sure Android has `INTERNET`.
2. Copy `LiveClassPage` and its private widgets. Turn `videoId` / `startSeconds` into real inputs (class ID → video ID, computed "minutes late" from the class start time instead of hard-coded buttons).
3. **Keep these exactly** (each one fixes an observed leak):
   - params in 4.1
   - navigation delegate in 4.2
   - all overlays via `controlsBuilder` (4.3)
   - fixed-size scaled player and our own fullscreen (4.5)
   - muted early start + unmute-only, **no seek** (4.6)
   - keyless controller + transparent `backgroundColor` (4.8)
   - player restart when reconnecting before the first play (4.9)
4. Only **one** `YoutubePlayer` per screen. The package coordinates fullscreen across instances with static state.
5. Wire the message box to the real instructor-chat backend.
6. Move the pre-warm (4.10) to whatever screen comes before joining, or go further with a background-started player.
7. Swap colours and fonts for the product theme (`cream`, `green`, `liveRed`, …). The design mock likely uses Inter.
8. Re-verify with the screen-record method in §6 on low-end and high-end devices and slow networks.
9. Unused dependencies: `pubspec.yaml` also lists `material_ui` and `cupertino_icons`, which `lib/main.dart` doesn't import. Drop them unless the real app needs them. (`flutter analyze` reports one info that `flutter/material.dart` is deprecated in favour of `material_ui`. It doesn't affect building or running.)

## Going to production

If this becomes public-facing, replace the YouTube layer instead of hardening it:

- Host videos ourselves (or Cloudflare Stream / Mux / Bunny) and play with **`video_player`** (or `better_player` / `media_kit`).
- Don't ship URLs in the app. Fetch **short-lived signed URLs** from our backend; add **Widevine DRM** if the content matters.
- `FLAG_SECURE` to block screenshots and screen recording.
- Most of §4 then disappears. The UI (`_PlayerControls`, loader, layout, late-join via `seekTo`) carries over almost unchanged, because a native player has no overlays to hide and seeking doesn't show any UI.

---

## Run / build

```bash
flutter pub get
flutter run -d <device-id>          # debug on a connected phone
flutter build apk --release         # → build/app/outputs/flutter-apk/app-release.apk
```

---

## Appendix A: Build it step by step

This is the order to rebuild the feature in, with the code that does each part. Every step fixes something that **actually leaked** on the device; the "why" for each is in §4, and the story of how we found it is in Appendix B.

### Step 1: Project and packages
```bash
flutter create --platforms android --project-name youtube_player_app .
flutter pub add youtube_player_iframe webview_flutter connectivity_plus
```
In `android/app/src/main/AndroidManifest.xml`, inside `<manifest>`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

### Step 2: Create the controller (keyless, muted, early start, links blocked)
```dart
final controller = YoutubePlayerController(        // NOT .fromVideoId(): no key (step 8)
  params: const YoutubePlayerParams(
    showControls: false,                // controls=0
    showFullscreenButton: false,
    showVideoAnnotations: false,
    strictRelatedVideos: true,
    enableCaption: false,
    pointerEvents: PointerEvents.none,  // the iframe never gets touches
    mute: true,                         // unmuted when the intro cover lifts (step 6)
  ),
);

// Start 4.5 s early so the intro hold ends exactly at the requested time.
controller.loadVideoById(
  videoId: videoId,
  startSeconds: (startSeconds - 4.5).clamp(0, double.infinity).toDouble(),
);

// No link inside the player may open anything (logo, title, share…).
controller.webViewController.setNavigationDelegate(
  NavigationDelegate(onNavigationRequest: (_) => NavigationDecision.prevent),
);
```

### Step 3: Fixed-size player, only scaled (never resized)
Lay the player out once at a landscape-sized resolution and scale it into place. Same widget, same tree position, in both inline and fullscreen:
```dart
final size = MediaQuery.sizeOf(context);
final baseW = size.longestSide, baseH = baseW * 9 / 16;       // fixed layout size
final inlineW = size.shortestSide, inlineH = inlineW * 9 / 16;

final scale = fullscreen
    ? min(size.width / baseW, size.height / baseH)
    : inlineW / baseW;
final rect = fullscreen
    ? Rect.fromCenter(center: size.center(Offset.zero),
                      width: baseW * scale, height: baseH * scale)
    : Rect.fromLTWH(0, topPadding, inlineW, inlineH);

Positioned.fromRect(
  rect: rect,
  child: FittedBox(
    fit: BoxFit.fill,
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: baseW, height: baseH,
      child: YoutubePlayer(
        key: ObjectKey(controller),            // new controller → new player (step 9)
        controller: controller,
        autoFullScreen: false,                 // we do fullscreen ourselves
        enableFullScreenOnVerticalDrag: false,
        backgroundColor: Colors.transparent,   // step 8
        controlsBuilder: (context, _) => ..., // step 4
      ),
    ),
  ),
);
```
Fullscreen is just orientation + system UI + a new `rect`/`scale`. Never call the package's `enterFullScreen()`, because it resizes the WebView:
```dart
SystemChrome.setPreferredOrientations(fs
    ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
    : [DeviceOrientation.portraitUp]);
SystemChrome.setEnabledSystemUIMode(
    fs ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
setState(() => _fullscreen = fs);
```
Wrap the page in `PopScope(canPop: !_fullscreen, ...)` so Back leaves fullscreen first.

### Step 4: Draw everything on top through `controlsBuilder`, with the scale undone
On phones the WebView sits in an overlay **above the page**, so a normal `Stack` over `YoutubePlayer` is hidden underneath it. Return all overlays from `controlsBuilder`. That layer inherits our scale, so undo it to keep buttons at normal size:
```dart
controlsBuilder: (context, _) => FittedBox(
  fit: BoxFit.fill,
  alignment: Alignment.topLeft,
  child: SizedBox(
    width: baseW * scale, height: baseH * scale,   // real on-screen size
    child: _PlayerControls(...),                    // cover + back + LIVE + fullscreen
  ),
),
```

### Step 5: The cover state machine (`_PlayerControls`)
Listen to `controller.stream`. Cover **immediately** on anything that isn't `playing`, and uncover only after a delay that outlasts YouTube's own fade:
```dart
void _onState(PlayerState s) {
  final wasBuffering = _state == PlayerState.buffering;
  _state = s;
  if (s == PlayerState.playing) {
    if (!_everPlayed) {                                   // first start
      _everPlayed = true;
      _uncover ??= Timer(_introHold /*4.5 s*/, () { controller.unMute(); _reveal(); });
    } else {                                              // resume
      _uncover ??= Timer(wasBuffering ? _afterBuffering /*5 s*/ : _settle /*1.2 s*/, _reveal);
    }
  } else {                                                // buffering / paused / ended / …
    _uncover?.cancel(); _uncover = null; _covered = true;
    if (_everPlayed && s == PlayerState.buffering) _stalled = true;
  }
  if (s == PlayerState.paused && appIsInForeground) controller.playVideo(); // no pause
}
```
The cover itself is wrapped in `AbsorbPointer`, so taps on the video do nothing.

### Step 6: Muted intro hold
This is already in steps 2 and 5: start 4.5 s early, muted, keep the cover up for 4.5 s after the first `playing`, then `unMute()`. **Don't** seek to correct the position afterwards (see 4.6).

### Step 7: No pause, ever
- `AbsorbPointer` on the video (step 5)
- `playVideo()` whenever `paused` arrives while the app is in the foreground (step 5)
- `AppLifecycleListener(onResume: () => controller.playVideo())`: Android pauses the WebView in the background

### Step 8: Loader from the first frame
With a keyed controller (`.fromVideoId`), the package paints its own thumbnail on top of everything while booting. With **no key** and `backgroundColor: Colors.transparent` (steps 2 and 3), that boot layer is invisible and our loader shows from frame one.

### Step 9: Network messages and recovery
```dart
final net = Connectivity();
net.checkConnectivity().then(_onNet);
_netSub = net.onConnectivityChanged.listen(_onNet);

void _onNet(List<ConnectivityResult> r) {
  final offline = r.every((c) => c == ConnectivityResult.none);
  if (_offline && !offline) {
    _everPlayed
        ? controller.playVideo()           // mid-class: nudge YouTube to resume
        : widget.onReconnectBeforeStart(); // never started: rebuild the player
  }
  setState(() => _offline = offline);
}
```
The rebuild (in `LiveClassPage`):
```dart
void _restartPlayer() {
  final old = _controller;
  setState(() => _controller = _createController()); // YoutubePlayer is keyed by it
  old.close();
}
```
Loader message priority: offline → **Internet connection lost**; stalled and still buffering → **Weak internet connection**; stalled but playing again (5 s hold) → **Connection is back**; otherwise the breathing cue.

### Step 10: The breathing loader
An `AnimationController(duration: 2 s)..repeat(reverse: true)` drives:
- three circles whose sizes and opacities follow `Curves.easeInOut`
- a `self_improvement` icon in the middle
- a headline that switches between *Breathe in… / Breathe out…* on the animation direction (`AnimatedSwitcher`), unless a network headline overrides it

The whole thing is the `_Cover` while waiting. After the video ends, the cover shows the thumbnail instead.

### Step 11: Pre-warm on the screen before joining
```dart
late final WebViewController _warmUp = WebViewController()
  ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ..setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: (r) => r.url.contains('/embed/')
          ? NavigationDecision.navigate : NavigationDecision.prevent))
  ..loadRequest(Uri.parse('https://www.youtube-nocookie.com/embed/$videoId?controls=0'));
```
It's never displayed. It just starts the WebView engine and caches YouTube's scripts.

### Step 12: Page layout around the video
The page is a `Stack`:
1. A `Column`, `Offstage` in fullscreen, containing:
   - a spacer the height of the inline video
   - the message row (pill `TextField` + round green send button)
   - a `Spacer`
   - the privacy banner (bottom padding = system inset, so it sits above the keyboard)
2. The positioned video from step 3.

### Step 13: Verify on a real device
Use the screen-record → frame contact-sheet method in §6 for:
- every start path (on time and late)
- pause/resume
- fullscreen in and out
- a mid-class stall
- joining offline

If any frame shows YouTube UI, measure how long it stays and adjust the matching hold.

---

## Appendix B: How we got here (iteration log)

Each row is one round of build → test on the phone → look at what leaked. Timings come from screen recordings split into 4–8 fps frame sheets, plus `[player] +ms state=…` logs.

| # | What we tried | What we saw on the device | What we changed |
|---|---|---|---|
| 1 | Plain `youtube_player_iframe` with the video, autoplay | Plays, with full YouTube UI | Baseline |
| 2 | `controls=0` + `pointerEvents: none` + `IgnorePointer`, a thumbnail cover when not playing | Pause bar ("More videos", link, logo) still flashed | Cover on pause; tap toggled play/pause |
| 3 | Blocked the WebView `NavigationDelegate` | Logo/title/share taps could open YouTube via `url_launcher` | All navigation prevented |
| 4 | Built the design mock (back, LIVE, time, fullscreen) in a `Stack` over the player | **None of our overlays showed**; the video was on top | Found the package's `OverlayPortal`; moved everything into `controlsBuilder` (4.3) |
| 5 | Resume after pause | YouTube's pause bar fades out *after* playback resumes | 1.2 s `_settle` before uncovering |
| 6 | Package fullscreen | Leaving fullscreen showed title + link + logo + pause icon for **~6–7 s** (measured frame by frame) | Fixed-size player that is only scaled; our own fullscreen (4.5) |
| 7 | "No pause at all" request | — | Tap does nothing; auto-resume on `paused`; resume on app foreground |
| 8 | Start of playback, frame by frame | Title bar for ~4 s after `playing` | Cover for 4.5 s after the first `playing` |
| 9 | Fix the lost first 4.5 s by **seeking** back after the hold | Seek brought the title + pause icon back for another 3–4 s | ❌ Reverted |
| 10 | Start **4.5 s early, muted**, then just unmute | Clean reveal exactly at the requested time | ✅ Kept (4.6) |
| 11 | Spinner → yoga breathing loader | Package's own thumbnail covered our loader for ~2.5 s while booting | Keyless controller + transparent `backgroundColor` (4.8) |
| 12 | Time label hidden while covered | Flashed `00:00` when it reappeared | Kept mounted with `maintainState` (label later removed on request) |
| 13 | User screenshot: YouTube UI visible **while buffering** | Mid-class stall shows YouTube's full overlay + spinner | Cover on `buffering` too |
| 14 | Forced stall (Wi-Fi + data off until `buffering`, then back on) with a 4 s hold | One frame of overlay at 4.0 s, gone by 4.25 s | `_afterBuffering` = 5 s |
| 15 | Try to shorten the 4.5 s intro: reveal after 0.8 s with a **header band** over the title strip | Band hid the title, but a **centre pause icon and "More videos" chip** showed for ~3 s | ❌ Reverted; the overlay is full-player (measured: icon/chip gone +3.6 s, title +4.2 s) |
| 16 | Measure boot time (`[player] +ms` logs) | Tap → `playing`: 2.3 s first join, 0.8–1.5 s later | Hidden pre-warm WebView on Home → first join 1.7 s (4.10) |
| 17 | Join while offline, then reconnect | "Internet connection lost" showed, but after reconnect it was **stuck forever** (player script never loaded) | Rebuild the controller on reconnect if never played (4.9) |
| 18 | Mid-class stall with the new messages | Offline → "Internet connection lost"; back online but still stalled → "Weak internet connection"; → "Connection is back" → clean video | ✅ |
| 19 | UI trims on request | — | Removed the time label and red progress bar |

**Tooling used throughout:**
- `flutter run` on a USB-connected phone, plus `flutter analyze`
- `adb shell input tap/text/keyevent` to drive the app
- `adb shell screenrecord` + `ffmpeg` (`fps=4|8`, `crop`, `tile`) for frame-by-frame contact sheets
- `adb exec-out screencap` for screenshots
- `adb shell svc wifi|data disable/enable` to simulate network loss
- `debugPrint('[player] …')` logs read from the `flutter run` output
