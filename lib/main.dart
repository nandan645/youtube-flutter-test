import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

const videoId = 'aqz-KE-bpKQ';

const cream = Color(0xFFF8F6F1);
const green = Color(0xFF2E6B4B);
const liveRed = Color(0xFFE53935);
const bannerBg = Color(0xFFE6F0E8);
const ink = Color(0xFF2B2B2B);

void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(seedColor: green),
    ),
    home: const HomePage(),
  ),
);

// ───────────────────────────── Home ─────────────────────────────

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // (label, start position in seconds)
    const starts = [
      ('Join class', 0),
      ('Join 2:30 mins late', 150),
      ('Join 5 mins late', 300),
      ('Join 08:15 mins late', 495),
    ];

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, seconds) in starts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                  width: 220,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: green,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LiveClassPage(startSeconds: seconds),
                      ),
                    ),
                    child: Text(label, style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Live class ───────────────────────────

class LiveClassPage extends StatefulWidget {
  const LiveClassPage({super.key, this.startSeconds = 0});

  /// Where playback begins, in seconds.
  final int startSeconds;

  @override
  State<LiveClassPage> createState() => _LiveClassPageState();
}

class _LiveClassPageState extends State<LiveClassPage> {
  late final YoutubePlayerController _controller;
  late final StreamSubscription<YoutubePlayerValue> _sub;
  final _message = TextEditingController();
  bool _fullscreen = false;

  /// YouTube shows its title bar for the first ~4s of playback. Until this
  /// intro is over the video plays muted behind the cover, then it unmutes.
  static const _introHold = Duration(milliseconds: 4500);
  Timer? _introTimer;
  bool _introDone = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    // Created without a video key on purpose: with a key the package paints
    // the video thumbnail over everything while the player boots, hiding our
    // breathing loader. The video is loaded right after instead.
    _controller = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: false,
        showFullscreenButton: false,
        showVideoAnnotations: false,
        strictRelatedVideos: true,
        enableCaption: false,
        pointerEvents: PointerEvents.none,
        mute: true, // unmuted once the intro hold is over
      ),
    );
    _controller.loadVideoById(
      videoId: videoId,
      // Start a little early: the intro hold plays muted behind the cover and
      // ends right at the requested position. (Seeking is not an option — it
      // makes YouTube show its title bar again.)
      startSeconds: (widget.startSeconds - _introHold.inMilliseconds / 1000)
          .clamp(0, double.infinity)
          .toDouble(),
    );
    _sub = _controller.stream.listen((v) {
      if (v.playerState == PlayerState.playing && _introTimer == null) {
        _introTimer = Timer(_introHold, _finishIntro);
      }
    });
    // Never let a YouTube link (logo / title / share) leave the player.
    _controller.webViewController.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (_) => NavigationDecision.prevent,
      ),
    );
  }

  void _finishIntro() {
    _controller.unMute();
    if (mounted) setState(() => _introDone = true);
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    _sub.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controller.close();
    _message.dispose();
    super.dispose();
  }

  void _setFullscreen(bool fs) {
    SystemChrome.setPreferredOrientations(
      fs
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
    SystemChrome.setEnabledSystemUIMode(
      fs ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    setState(() => _fullscreen = fs);
  }

  void _send() {
    if (_message.text.trim().isEmpty) return;
    _message.clear();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final topPad = MediaQuery.paddingOf(context).top;

    // The YouTube iframe is laid out ONCE at a fixed landscape-sized
    // resolution and only *scaled* on screen. YouTube shows its title / logo /
    // link overlay for ~7s whenever the player is resized, so never resizing
    // it means switching to fullscreen never reveals that overlay.
    final baseW = size.longestSide;
    final baseH = baseW * 9 / 16;
    final inlineW = size.shortestSide;
    final inlineH = inlineW * 9 / 16;

    final double scale;
    final Rect videoRect;
    if (_fullscreen) {
      scale = [
        size.width / baseW,
        size.height / baseH,
      ].reduce((a, b) => a < b ? a : b);
      final w = baseW * scale, h = baseH * scale;
      videoRect = Rect.fromLTWH(
        (size.width - w) / 2,
        (size.height - h) / 2,
        w,
        h,
      );
    } else {
      scale = inlineW / baseW;
      videoRect = Rect.fromLTWH(0, topPad, inlineW, inlineH);
    }

    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _setFullscreen(false);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
        ),
        child: Scaffold(
          backgroundColor: _fullscreen ? Colors.black : cream,
          body: Stack(
            children: [
              // Page content (hidden, not removed, in fullscreen).
              Positioned.fill(
                child: Offstage(
                  offstage: _fullscreen,
                  child: Column(
                    children: [
                      SizedBox(height: topPad + inlineH),
                      _ProgressBar(controller: _controller),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: _MessageInput(
                          controller: _message,
                          onSend: _send,
                        ),
                      ),
                      const Spacer(),
                      const _PrivacyBanner(),
                    ],
                  ),
                ),
              ),
              // The video. Same widget in both modes, only position/scale change.
              Positioned.fromRect(
                rect: videoRect,
                child: FittedBox(
                  fit: BoxFit.fill,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: baseW,
                    height: baseH,
                    child: YoutubePlayer(
                      controller: _controller,
                      autoFullScreen: false,
                      enableFullScreenOnVerticalDrag: false,
                      // Transparent: the package's boot layer uses this colour,
                      // and our loader underneath should show through it.
                      backgroundColor: Colors.transparent,
                      // On mobile the player lives in an overlay above the page,
                      // so everything drawn over it must come from here. It
                      // inherits the player's scale, so undo that for the
                      // controls to keep them at normal size.
                      controlsBuilder: (context, _) => FittedBox(
                        fit: BoxFit.fill,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: baseW * scale,
                          height: baseH * scale,
                          child: _PlayerControls(
                            controller: _controller,
                            isFullscreen: _fullscreen,
                            holdCover: !_introDone,
                            onBack: () => _fullscreen
                                ? _setFullscreen(false)
                                : Navigator.of(context).maybePop(),
                            onFullscreen: () => _setFullscreen(!_fullscreen),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────── Controls over the video ───────────────────────

class _PlayerControls extends StatefulWidget {
  const _PlayerControls({
    required this.controller,
    required this.isFullscreen,
    required this.onBack,
    required this.onFullscreen,
    this.holdCover = false,
  });

  final YoutubePlayerController controller;
  final bool isFullscreen;

  /// Keep the cover up regardless of player state (used for the intro).
  final bool holdCover;
  final VoidCallback onBack;
  final VoidCallback onFullscreen;

  @override
  State<_PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<_PlayerControls> {
  /// How long the cover stays after playback (re)starts — YouTube's own pause
  /// bar / title fade out during this time.
  static const _settle = Duration(milliseconds: 1200);

  late final StreamSubscription<YoutubePlayerValue> _sub;
  late final AppLifecycleListener _lifecycle;
  Timer? _uncover;
  bool _covered = true;
  PlayerState _state = PlayerState.unknown;

  @override
  void initState() {
    super.initState();
    _onState(widget.controller.value.playerState);
    _sub = widget.controller.stream.listen((v) {
      if (v.playerState != _state) _onState(v.playerState);
    });
    // Leaving the app pauses the WebView; carry on when the user comes back.
    _lifecycle = AppLifecycleListener(
      onResume: () => widget.controller.playVideo(),
    );
  }

  void _onState(PlayerState s) {
    _state = s;
    if (s == PlayerState.playing) {
      _uncover ??= Timer(_settle, () {
        if (mounted) setState(() => _covered = false);
      });
    } else if (s != PlayerState.buffering || _covered) {
      // Paused / ended / cued / not started → cover immediately.
      _uncover?.cancel();
      _uncover = null;
      _covered = true;
    }
    // There is no pause: if playback gets paused anyway (e.g. by the
    // WebView), resume it — but only while the app is in the foreground.
    if (s == PlayerState.paused &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      widget.controller.playVideo();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _uncover?.cancel();
    _sub.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fs = widget.isFullscreen;
    final pad = fs ? 24.0 : 16.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Swallows taps on the video: there is nothing to tap.
        AbsorbPointer(
          child: _covered || widget.holdCover
              ? _Cover(ended: _state == PlayerState.ended, fullscreen: fs)
              : const SizedBox.expand(),
        ),
        Positioned(
          left: pad,
          top: pad,
          child: _GlassButton(
            icon: Icons.chevron_left,
            circle: true,
            onTap: widget.onBack,
          ),
        ),
        Positioned(left: pad + 48, top: pad + 6, child: const _LiveBadge()),
        // Time label only once the video is actually showing.
        if (!(_covered || widget.holdCover))
          Positioned(
            left: pad,
            bottom: pad,
            child: StreamBuilder<YoutubeVideoState>(
              stream: widget.controller.videoStateStream,
              builder: (context, snap) => Text(
                '${_fmt(snap.data?.position ?? Duration.zero)} / '
                '${_fmt(widget.controller.value.metaData.duration)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
            ),
          ),
        Positioned(
          right: pad,
          bottom: pad - 6,
          child: _GlassButton(
            icon: fs ? Icons.fullscreen_exit : Icons.fullscreen,
            onTap: widget.onFullscreen,
          ),
        ),
      ],
    );
  }
}

String _fmt(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

class _Cover extends StatelessWidget {
  const _Cover({required this.ended, required this.fullscreen});

  final bool ended;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    // While waiting: a short guided breath instead of a spinner.
    if (!ended) return const _BreathingLoader();

    // After the video ends: just the thumbnail.
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        Image.network(
          YoutubePlayerController.getThumbnail(videoId: videoId),
          fit: fullscreen ? BoxFit.contain : BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Yoga-themed loader: a breathing circle that grows on "Breathe in" and
/// shrinks on "Breathe out", around a meditating figure. One breath is ~4s,
/// so the intro hold feels like a warm-up rather than a wait.
class _BreathingLoader extends StatefulWidget {
  const _BreathingLoader();

  @override
  State<_BreathingLoader> createState() => _BreathingLoaderState();
}

class _BreathingLoaderState extends State<_BreathingLoader>
    with SingleTickerProviderStateMixin {
  static const _half = Duration(milliseconds: 2000); // in, then out

  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: _half,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E6B4B), Color(0xFF4E8C69), Color(0xFF7FAE8C)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final d = box.biggest.shortestSide * 0.5; // breathing circle size
          return AnimatedBuilder(
            animation: _breath,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(_breath.value);
              final inhaling = _breath.status == AnimationStatus.forward;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: d,
                    height: d,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Soft outer halo.
                        _ring(d * (0.75 + 0.25 * t), 0.10 + 0.08 * t),
                        // Middle ring.
                        _ring(d * (0.60 + 0.20 * t), 0.18 + 0.10 * t),
                        // Core.
                        Container(
                          width: d * (0.46 + 0.10 * t),
                          height: d * (0.46 + 0.10 * t),
                          decoration: const BoxDecoration(
                            color: cream,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.self_improvement,
                            color: green,
                            size: d * 0.30,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: d * 0.08),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Text(
                      inhaling ? 'Breathe in…' : 'Breathe out…',
                      key: ValueKey(inhaling),
                      style: const TextStyle(
                        color: cream,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Settle in, class is starting',
                    style: TextStyle(
                      color: cream.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _ring(double size, double opacity) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: cream.withValues(alpha: opacity),
    ),
  );
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.onTap,
    this.circle = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 26),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: const BoxDecoration(
        color: liveRed,
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 3, backgroundColor: Colors.white),
          SizedBox(width: 5),
          Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Below the video ─────────────────────────

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.controller});

  final YoutubePlayerController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<YoutubeVideoState>(
      stream: controller.videoStateStream,
      builder: (context, snap) {
        final total = controller.value.metaData.duration.inMilliseconds;
        final pos = snap.data?.position.inMilliseconds ?? 0;
        final fraction = total > 0 ? (pos / total).clamp(0.0, 1.0) : 0.0;
        return LinearProgressIndicator(
          value: fraction,
          minHeight: 4,
          color: liveRed,
          backgroundColor: const Color(0xFFD9D6D0),
        );
      },
    );
  }
}

class _MessageInput extends StatelessWidget {
  const _MessageInput({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: const BorderSide(color: ink),
    );
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            style: const TextStyle(fontSize: 16, color: ink),
            decoration: InputDecoration(
              hintText: 'Enter the message',
              hintStyle: const TextStyle(fontSize: 16, color: ink),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
              border: border,
              enabledBorder: border,
              focusedBorder: border,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: green,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onSend,
            child: const SizedBox(
              width: 46,
              height: 46,
              child: Icon(Icons.send, color: Colors.white, size: 22),
            ),
          ),
        ),
      ],
    );
  }
}

class _PrivacyBanner extends StatelessWidget {
  const _PrivacyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: bannerBg,
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      child: const Row(
        children: [
          Icon(Icons.lock_outline, size: 15, color: green),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Only you and the instructor can see your messages.',
              style: TextStyle(
                fontSize: 13,
                color: green,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
