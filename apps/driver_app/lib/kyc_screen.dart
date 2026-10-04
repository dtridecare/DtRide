import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'plans_screen.dart';
import 'driver_home_screen.dart';

/// Pack KYC: doc rows with status tags, per-doc detail capture,
/// pending timeline, per-item rejected reasons, then plans.
class KycDoc {
  final String key;
  final String title;
  final IconData icon;
  final bool needsDetail;
  const KycDoc(this.key, this.title, this.icon, {this.needsDetail = false});
}

const _docs = [
  KycDoc('licence', 'Driving licence', Icons.badge_outlined, needsDetail: true),
  KycDoc('rc', 'Vehicle RC', Icons.description_outlined),
  KycDoc('insurance', 'Vehicle insurance', Icons.verified_user_outlined),
  KycDoc('id', 'ID proof (Aadhaar)', Icons.badge_outlined),
  KycDoc('selfie', 'Profile selfie', Icons.camera_alt_outlined),
];

class KycScreen extends StatefulWidget {
  final String? initialCategory;
  const KycScreen({super.key, this.initialCategory});
  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  String _category = 'Mini';
  final _upi = TextEditingController();
  final _plate = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final Set<String> _uploads = {};
  String? _licenceNo;
  String? _licenceExpiry;
  String? _error;
  bool _busy = false;
  bool _loading = true;
  bool _showForm = true;
  DriverKyc? _kyc;
  bool _submitted = false;

  KycService get _kycSvc => KycService(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) _category = widget.initialCategory!;
    _reload();
  }

  Future<void> _reload() async {
    setState(() { _loading = true; _error = null; });
    try {
      final kyc = await _kycSvc.getKyc();
      final submitted = await _kycSvc.hasSubmission();
      if (!mounted) return;
      setState(() {
        _kyc = kyc;
        _submitted = submitted;
        _category = kyc.vehicleCategory;
        if (_upi.text.isEmpty) _upi.text = kyc.upiId ?? '';
        _showForm = !submitted || kyc.kycStatus == 'rejected';
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  int get _payoutDone => (_upi.text.trim().isNotEmpty && _plate.text.trim().isNotEmpty) ? 1 : 0;
  int get _doneCount => _uploads.length + _payoutDone;
  static const int _totalCount = 6;

  Future<void> _pickAndUpload(String name) async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (img == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _kycSvc.uploadDoc(await img.readAsBytes(),
          '$name-${DateTime.now().millisecondsSinceEpoch}.jpg');
      setState(() => _uploads.add(name.split('-').first));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    const required = {'licence', 'rc', 'insurance', 'id', 'selfie'};
    if (!required.every(_uploads.contains)) {
      setState(() => _error = 'Upload all 5 document photos first.');
      return;
    }
    if (_plate.text.trim().isEmpty || _upi.text.trim().isEmpty) {
      setState(() => _error = 'Number plate and UPI ID are required.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await _kycSvc.submit(
        category: _category,
        upiId: _upi.text.trim(),
        plate: _plate.text.trim(),
        make: _make.text.trim().isEmpty ? null : _make.text.trim(),
        model: _model.text.trim().isEmpty ? null : _model.text.trim(),
        licenceNo: _licenceNo,
        licenceExpiry: _licenceExpiry,
      );
      await _reload();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  /// Split admin notes like "licence: blurry photo" per document.
  Map<String, String> _reasons() {
    final out = <String, String>{};
    final note = _kyc?.notes;
    if (note == null) return out;
    for (final line in note.split('\n')) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim().toLowerCase();
      const keys = ['licence', 'rc', 'insurance', 'id', 'selfie', 'payout'];
      final match = keys.where((k) => key.contains(k));
      if (match.isNotEmpty) out[match.first] = line.substring(idx + 1).trim();
    }
    if (out.isEmpty) out['general'] = note;
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Documents')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final status = _kyc?.kycStatus ?? 'pending';
    if (!_showForm && status == 'approved') return _approvedView();
    if (!_showForm && _submitted) return _pendingView();
    return _formView();
  }

  Widget _approvedView() => Scaffold(
    appBar: AppBar(title: const Text('Documents')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const DtBanner(
        kind: BannerKind.success,
        title: 'KYC approved',
        subtitle: 'Choose a plan to start receiving rides.'),
      const SizedBox(height: 16),
      DtPrimaryButton(
        label: 'View plans',
        onPressed: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PlansScreen())),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DriverHomeScreen())),
        child: const Text('Later — go to home'),
      ),
    ]),
  );

  Widget _pendingView() => Scaffold(
    appBar: AppBar(title: const Text('Documents'), actions: [
      IconButton(icon: const Icon(Icons.refresh), onPressed: _reload),
    ]),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Center(
        child: Container(
          height: 96, width: 96,
          decoration: const BoxDecoration(color: Color(0xFFFEF3C7), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: const Icon(Icons.hourglass_empty, size: 44, color: Color(0xFF92400E)),
        ),
      ),
      const SizedBox(height: 20),
      const Text('Under review', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
      const Text(
        'Our admin team is checking your documents. This usually takes up to 24 hours. We will notify you once it is done.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.muted, fontSize: 14)),
      const SizedBox(height: 24),
      _trackRow(true, 'Submitted', 'Today'),
      _trackRow(null, 'Admin review', 'In progress'),
      _trackRow(false, 'Approved', 'You can go online'),
      const SizedBox(height: 24),
      OutlinedButton(
        onPressed: () => setState(() => _showForm = true),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: const Text('Edit submission'),
      ),
      OutlinedButton(
        onPressed: () {},
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: const Text('Contact support'),
      ),
    ]),
  );

  Widget _trackRow(bool? done, String title, String subtitle) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      CircleAvatar(
        radius: 12,
        backgroundColor: done == true
            ? AppColors.success : done == null ? AppColors.accent : Colors.grey.shade300,
        child: done == true
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : const SizedBox.shrink(),
      ),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ]),
    ]),
  );

  Widget _formView() {
    final rejected = _kyc?.kycStatus == 'rejected';
    final reasons = rejected ? _reasons() : <String, String>{};
    final progress = _doneCount / _totalCount;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text(''),
      ),
      body: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 8), children: [
            if (rejected) ...[
              const Text('Action needed',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
              const Text('The admin team could not approve everything. Fix the items below and submit again.',
                  style: TextStyle(color: AppColors.muted, fontSize: 14)),
              const SizedBox(height: 12),
              for (final e in reasons.entries)
                if (e.key != 'general')
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      border: Border.all(color: const Color(0xFFFECACA)),
                      borderRadius: BorderRadius.circular(14)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_titleOf(e.key),
                          style: const TextStyle(
                              fontWeight: FontWeight.w500, color: Color(0xFF991B1B))),
                      Text(e.value,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF7F1D1D))),
                    ]),
                  ),
              if (reasons.containsKey('general'))
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    border: Border.all(color: const Color(0xFFFECACA)),
                    borderRadius: BorderRadius.circular(14)),
                  child: Text(reasons['general']!,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF7F1D1D))),
                ),
            ] else ...[
              Text('$_doneCount of $_totalCount added',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                    value: progress, minHeight: 4,
                    backgroundColor: AppColors.surface, color: AppColors.accent),
              ),
              const SizedBox(height: 14),
              const Text('Upload documents',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
            ],
            const SizedBox(height: 8),
            for (final d in _docs) _docRow(d, reasons[d.key]),
            _payoutRow(reasons['payout']),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _category,
              items: [for (final c in VehicleCategory.all) DropdownMenuItem(value: c.id, child: Text(c.label))],
              onChanged: (v) => setState(() => _category = v ?? 'Mini'),
              decoration: const InputDecoration(labelText: 'Vehicle category'),
            ),
            const SizedBox(height: 8),
            TextField(controller: _plate,
              decoration: const InputDecoration(labelText: 'Number plate *')),
            TextField(controller: _make, decoration: const InputDecoration(labelText: 'Make')),
            TextField(controller: _model, decoration: const InputDecoration(labelText: 'Model')),
            if (_error != null) ...[
              const SizedBox(height: 8),
              DtBanner(kind: BannerKind.error, title: _error!),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: DtPrimaryButton(
            label: rejected ? 'Fix and resubmit' : 'Submit for review',
            busy: _busy,
            onPressed: _submit),
        ),
      ]),
    );
  }

  String _titleOf(String key) =>
      _docs.firstWhere((d) => d.key == key, orElse: () => const KycDoc('payout', 'Bank or UPI details', Icons.payments_outlined)).title;

  Widget _docRow(KycDoc d, String? reason) {
    final done = _uploads.contains(d.key);
    return GestureDetector(
      onTap: _busy ? null : () => d.needsDetail ? _openLicence() : _pickAndUpload(d.key),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              height: 40, width: 40,
              decoration: BoxDecoration(
                  color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
              child: Icon(d.icon),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(d.title, style: const TextStyle(fontWeight: FontWeight.w500))),
            _tag(done ? 'Uploaded' : 'Upload', done),
          ]),
          if (reason != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(reason,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B))),
            ),
        ]),
      ),
    );
  }

  Widget _payoutRow(String? reason) {
    final done = _upi.text.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Row(children: [
          Container(
            height: 40, width: 40,
            decoration: BoxDecoration(
                color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.payments_outlined),
          ),
          const SizedBox(width: 12),
          const Expanded(
              child: Text('Bank or UPI details', style: TextStyle(fontWeight: FontWeight.w500))),
          _tag(done ? 'Added' : 'Add', done),
        ]),
        const SizedBox(height: 8),
        TextField(controller: _upi,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'UPI ID (riders pay here) *')),
        if (reason != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(reason,
                style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B))),
          ),
      ]),
    );
  }

  Widget _tag(String text, bool done) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: done ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
      borderRadius: BorderRadius.circular(999)),
    child: Text(text,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w500,
            color: done ? const Color(0xFF166534) : const Color(0xFF92400E))),
  );

  Future<void> _openLicence() async {
    final res = await Navigator.of(context).push<Map<String, String?>>(
      MaterialPageRoute(builder: (_) => const LicenceDetailScreen()));
    if (res == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _licenceNo = res['number'];
      _licenceExpiry = res['expiry'];
    });
    try {
      for (final key in ['licence-front', 'licence-back']) {
        final path = res[key];
        if (path == null) continue;
        // Bytes were captured on the detail screen and passed back? No —
        // detail screen uploads directly and returns markers.
      }
      // Detail screen already uploaded; just mark complete if it returned ok.
      if (res['done'] == '1') setState(() => _uploads.add('licence'));
    } finally {
      setState(() => _busy = false);
    }
  }
}

/// Licence detail per pack: front/back photo boxes, number, expiry, tip.
class LicenceDetailScreen extends StatefulWidget {
  const LicenceDetailScreen({super.key});
  @override
  State<LicenceDetailScreen> createState() => _LicenceDetailScreenState();
}

class _LicenceDetailScreenState extends State<LicenceDetailScreen> {
  final _number = TextEditingController();
  final _expiry = TextEditingController();
  bool _front = false;
  bool _back = false;
  bool _busy = false;
  String? _error;

  KycService get _kyc => KycService(Supabase.instance.client);

  Future<void> _photo(bool front) async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (img == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _kyc.uploadDoc(await img.readAsBytes(),
          'licence-${front ? 'front' : 'back'}-${DateTime.now().millisecondsSinceEpoch}.jpg');
      setState(() {
        if (front) {
          _front = true;
        } else {
          _back = true;
        }
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(leading: const BackButton(), title: const Text('')),
    body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
      const Text('Driving licence',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _photoBox('Front photo', _front, () => _photo(true))),
        const SizedBox(width: 10),
        Expanded(child: _photoBox('Back photo', _back, () => _photo(false))),
      ]),
      const SizedBox(height: 14),
      const Text('Licence number', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 6),
      TextField(controller: _number,
        decoration: const InputDecoration(hintText: 'KA05 2019 0012345')),
      const SizedBox(height: 12),
      const Text('Expiry date', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 6),
      TextField(controller: _expiry,
        decoration: const InputDecoration(hintText: '12 / 2031')),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(12)),
        child: const Text(
          'Place the card on a flat surface. All four corners and the text must be visible.',
          style: TextStyle(fontSize: 12)),
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        DtBanner(kind: BannerKind.error, title: _error!),
      ],
      const SizedBox(height: 16),
      DtPrimaryButton(
        label: 'Save document',
        busy: _busy,
        onPressed: (_front && _back)
            ? () => Navigator.of(context).pop({
                  'done': '1',
                  'number': _number.text.trim().isEmpty ? null : _number.text.trim(),
                  'expiry': _expiry.text.trim().isEmpty ? null : _expiry.text.trim(),
                })
            : null,
      ),
    ]),
  );

  Widget _photoBox(String label, bool done, VoidCallback onTap) => GestureDetector(
    onTap: _busy ? null : onTap,
    child: Container(
      height: 96,
      decoration: BoxDecoration(
        border: Border.all(
            style: BorderStyle.solid,
            color: done ? AppColors.success : AppColors.border, width: done ? 2 : 1.5),
        borderRadius: BorderRadius.circular(14)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(done ? Icons.check_circle : Icons.camera_alt_outlined,
            color: done ? AppColors.success : AppColors.muted),
        const SizedBox(height: 6),
        Text(done ? 'Added' : label,
            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ]),
    ),
  );
}
