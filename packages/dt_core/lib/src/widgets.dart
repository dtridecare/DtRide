import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'theme.dart';

/// Pack logo (black rounded square, yellow D-route).
class DtLogo extends StatelessWidget {
  final double size;
  const DtLogo({super.key, this.size = 44});
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/branding/logo.svg',
    width: size, height: size,
    placeholderBuilder: (_) => Container(
      width: size, height: size,
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(size * 0.22)),
      alignment: Alignment.center,
      child: Text('Dt', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w900, fontSize: size * 0.4)),
    ),
  );
}

/// Shared app-grade widgets used by rider + driver apps.

class DtPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool danger;
  final bool accent;
  final bool dark;
  const DtPrimaryButton({super.key, required this.label, this.onPressed, this.busy = false, this.danger = false, this.accent = true, this.dark = false});

  @override
  Widget build(BuildContext context) {
    ButtonStyle? style;
    if (danger) {
      style = ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white);
    } else if (dark) {
      style = ElevatedButton.styleFrom(backgroundColor: AppColors.ink, foregroundColor: Colors.white);
    } else if (!accent) {
      style = ElevatedButton.styleFrom(backgroundColor: AppColors.surface, foregroundColor: AppColors.ink);
    }
    return ElevatedButton(
      onPressed: (onPressed == null || busy) ? null : onPressed,
      style: style,
      child: busy
          ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
          : Text(label),
    );
  }
}

/// Full-bleed brand splash. Shows [image] while [load] runs (min [minShow]),
/// then swaps to the gated home. Used by both apps with their own artwork.
class BrandSplash extends StatefulWidget {
  final String image;
  final Future<Widget> Function() load;
  final Duration minShow;
  const BrandSplash({super.key, required this.image, required this.load, this.minShow = const Duration(milliseconds: 2200)});

  @override
  State<BrandSplash> createState() => _BrandSplashState();
}

class _BrandSplashState extends State<BrandSplash> {
  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    final stopwatch = Stopwatch()..start();
    Widget next;
    try {
      next = await widget.load();
    } catch (_) {
      next = const Scaffold(body: Center(child: Text('Something went wrong. Restart the app.')));
    }
    final remaining = widget.minShow - stopwatch.elapsed;
    if (remaining > Duration.zero) await Future.delayed(remaining);
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => next));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SizedBox.expand(
      child: Image.asset(widget.image, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: AppColors.primaryDark,
          alignment: Alignment.center,
          child: const Text('DT Ride',
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white)),
        )),
    ),
  );
}

class DtSheetHandle extends StatelessWidget {
  const DtSheetHandle({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      height: 5, width: 44,
      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)),
    ),
  );
}

enum BannerKind { info, warn, error, success }

/// Colored notice card (credits, blocks, SOS confirmations…).
class DtBanner extends StatelessWidget {
  final BannerKind kind;
  final String title;
  final String? subtitle;
  const DtBanner({super.key, required this.kind, required this.title, this.subtitle});

  Color get _bg => switch (kind) {
    BannerKind.info => const Color(0xFFEFF6FF),
    BannerKind.warn => const Color(0xFFFFFBEB),
    BannerKind.error => const Color(0xFFFEF2F2),
    BannerKind.success => const Color(0xFFECFDF5),
  };
  Color get _fg => switch (kind) {
    BannerKind.info => const Color(0xFF1D4ED8),
    BannerKind.warn => const Color(0xFFB45309),
    BannerKind.error => const Color(0xFFB91C1C),
    BannerKind.success => const Color(0xFF047857),
  };
  IconData get _icon => switch (kind) {
    BannerKind.info => Icons.info_outline,
    BannerKind.warn => Icons.warning_amber_outlined,
    BannerKind.error => Icons.error_outline,
    BannerKind.success => Icons.check_circle_outline,
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(16)),
    child: Row(children: [
      Icon(_icon, color: _fg),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: _fg)),
        if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 13, color: _fg)),
      ])),
    ]),
  );
}

/// App-style OTP boxes with auto-advance, backspace nav and paste.
class DtOtpBoxes extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChange;
  final int length;
  const DtOtpBoxes({super.key, required this.value, required this.onChange, this.length = 6});

  @override
  State<DtOtpBoxes> createState() => _DtOtpBoxesState();
}

class _DtOtpBoxesState extends State<DtOtpBoxes> {
  final List<TextEditingController> _ctls = [];
  final List<FocusNode> _nodes = [];

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.length; i++) {
      _ctls.add(TextEditingController());
      _nodes.add(FocusNode());
    }
    _syncFromValue();
  }

  @override
  void didUpdateWidget(DtOtpBoxes old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _syncFromValue();
  }

  void _syncFromValue() {
    for (var i = 0; i < widget.length; i++) {
      final ch = i < widget.value.length ? widget.value[i] : '';
      if (_ctls[i].text != ch) _ctls[i].text = ch;
    }
  }

  @override
  void dispose() {
    for (final c in _ctls) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _emit() => widget.onChange(_ctls.map((c) => c.text).join());

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      for (var i = 0; i < widget.length; i++)
        SizedBox(
          width: 48, height: 56,
          child: TextField(
            controller: _ctls[i],
            focusNode: _nodes[i],
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 1,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(counterText: ''),
            onChanged: (v) {
              if (v.length > 1) _ctls[i].text = v.characters.last;
              if (_ctls[i].text.isNotEmpty && i < widget.length - 1) {
                _nodes[i + 1].requestFocus();
              }
              if (_ctls[i].text.isEmpty && i > 0) _nodes[i - 1].requestFocus();
              _emit();
            },
          ),
        ),
    ],
  );
}

/// Small caps section label.
class DtSectionLabel extends StatelessWidget {
  final String text;
  const DtSectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(text.toUpperCase(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            letterSpacing: 0.8, color: Colors.grey.shade600)),
  );
}

/// Interactive star row.
class DtStars extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const DtStars({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 1; i <= 5; i++)
        IconButton(
          icon: Icon(i <= value ? Icons.star : Icons.star_border,
              color: Colors.amber.shade700, size: 34),
          onPressed: () => onChanged(i),
        ),
    ],
  );
}

void showDtMessage(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: error ? AppColors.danger : AppColors.ink,
    behavior: SnackBarBehavior.floating,
  ));
}

/// First-run permission gate: location + notifications with plain-language
/// reasons, skip allowed, settings shortcut when permanently denied.
class DtPermissionsScreen extends StatefulWidget {
  final VoidCallback onDone;
  const DtPermissionsScreen({super.key, required this.onDone});

  @override
  State<DtPermissionsScreen> createState() => _DtPermissionsScreenState();
}

class _DtPermissionsScreenState extends State<DtPermissionsScreen> {
  bool _loc = false;
  bool _notif = false;
  bool _locBlocked = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final loc = await Geolocator.checkPermission();
    final notif = await ph.Permission.notification.status;
    if (!mounted) return;
    setState(() {
      _loc = loc == LocationPermission.always || loc == LocationPermission.whileInUse;
      _locBlocked = loc == LocationPermission.deniedForever;
      _notif = notif.isGranted || notif.isLimited;
    });
  }

  Future<void> _askLocation() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.deniedForever) {
      await ph.openAppSettings();
    }
    _refresh();
  }

  Future<void> _askNotif() async {
    final s = await ph.Permission.notification.request();
    if (s.isPermanentlyDenied) await ph.openAppSettings();
    _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Permissions')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: _loc ? Colors.green.shade50 : AppColors.primary.withValues(alpha: 0.12),
            child: Icon(Icons.my_location, color: _loc ? Colors.green : AppColors.primary),
          ),
          title: const Text('Location', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('Find nearby rides and share live trip tracking.'),
          trailing: _loc
              ? const Icon(Icons.check_circle, color: Colors.green)
              : DtPrimaryButton(
                  label: _locBlocked ? 'Settings' : 'Allow',
                  onPressed: _askLocation),
        ),
      ),
      Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: _notif ? Colors.green.shade50 : AppColors.primary.withValues(alpha: 0.12),
            child: Icon(Icons.notifications_outlined, color: _notif ? Colors.green : AppColors.primary),
          ),
          title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('Ride status, offers and credit reminders.'),
          trailing: _notif
              ? const Icon(Icons.check_circle, color: Colors.green)
              : DtPrimaryButton(label: 'Allow', onPressed: _askNotif),
        ),
      ),
      const SizedBox(height: 8),
      const Text('You can change these anytime in Settings. The app works with reduced features if you skip.',
          style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 12),
      DtPrimaryButton(label: 'Continue', accent: true, onPressed: widget.onDone),
    ]),
  );
}

/// One onboarding slide.
class OnboardSlide {
  final IconData icon;
  final String title;
  final String subtitle;
  const OnboardSlide({required this.icon, required this.title, required this.subtitle});
}

/// Swipeable intro per pack: white screen, Skip, illustration slot,
/// dots, title, subtitle, yellow CTA.
class DtOnboarding extends StatefulWidget {
  final List<OnboardSlide> slides;
  final String cta;
  final VoidCallback onDone;
  final VoidCallback? onSkip;
  const DtOnboarding({super.key, required this.slides, required this.cta, required this.onDone, this.onSkip});

  @override
  State<DtOnboarding> createState() => _DtOnboardingState();
}

class _DtOnboardingState extends State<DtOnboarding> {
  final _ctl = PageController();
  int _i = 0;
  bool _last = false;

  @override
  void initState() {
    super.initState();
    _last = widget.slides.length == 1;
  }

  void _done() => widget.onDone();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: _last
                ? const SizedBox(height: 24)
                : TextButton(
                    onPressed: widget.onSkip ?? _done,
                    child: const Text('Skip', style: TextStyle(color: AppColors.muted)),
                  ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _ctl,
              itemCount: widget.slides.length,
              onPageChanged: (i) => setState(() {
                _i = i;
                _last = i == widget.slides.length - 1;
              }),
              itemBuilder: (context, i) {
                final s = widget.slides[i];
                return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    height: 180, width: 180,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Icon(s.icon, size: 84, color: AppColors.ink),
                  ),
                  const SizedBox(height: 28),
                  Text(s.title, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Text(s.subtitle, textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted, fontSize: 14)),
                ]);
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.slides.length; i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 6, width: i == _i ? 22 : 6,
                  decoration: BoxDecoration(
                    color: i == _i ? AppColors.ink : const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(3)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          DtPrimaryButton(
            label: _last ? widget.cta : 'Next',
            onPressed: () {
              if (_last) {
                _done();
              } else {
                _ctl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
              }
            },
          ),
        ]),
      ),
    ),
  );
}
