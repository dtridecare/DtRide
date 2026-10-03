import 'package:flutter/material.dart';
import 'theme.dart';

/// Shared app-grade widgets used by rider + driver apps.

class DtPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool danger;
  const DtPrimaryButton({super.key, required this.label, this.onPressed, this.busy = false, this.danger = false});

  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: (onPressed == null || busy) ? null : onPressed,
    style: danger
        ? ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white)
        : null,
    child: busy
        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
        : Text(label),
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
