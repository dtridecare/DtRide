import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'plans_screen.dart';
import 'driver_home_screen.dart';

const _docs = ['license', 'rc', 'aadhaar', 'selfie'];

/// Status-driven KYC: fresh → wizard form; submitted → review tracker;
/// rejected → admin notes + resubmit form; approved → plans CTA.
class KycScreen extends StatefulWidget {
  const KycScreen({super.key});
  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  int _step = 0;
  String _category = 'Mini';
  final _upi = TextEditingController();
  final _plate = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final Set<String> _uploads = {};
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
        // Show the form for fresh or rejected applications, status otherwise.
        _showForm = !submitted || kyc.kycStatus == 'rejected';
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _pickAndUpload(String doc) async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (img == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final bytes = await img.readAsBytes();
      await _kycSvc.uploadDoc(bytes, '$doc-${DateTime.now().millisecondsSinceEpoch}.jpg');
      setState(() => _uploads.add(doc));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_plate.text.trim().isEmpty || _upi.text.trim().isEmpty) {
      setState(() => _error = 'Number plate and UPI ID are required.');
      return;
    }
    if (_uploads.isEmpty) {
      setState(() => _error = 'Upload at least one document photo first.');
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
      );
      await _reload();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Driver onboarding')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final status = _kyc?.kycStatus ?? 'pending';
    if (!_showForm && status == 'approved') return _approvedView();
    if (!_showForm && _submitted) return _pendingView();
    return _formView(rejectedNote: status == 'rejected' ? _kyc?.notes : null);
  }

  Widget _approvedView() => Scaffold(
    appBar: AppBar(title: const Text('Driver onboarding')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const DtBanner(
        kind: BannerKind.success,
        title: 'KYC approved — welcome aboard!',
        subtitle: 'Buy a subscription plan to start accepting rides.'),
      const SizedBox(height: 16),
      DtPrimaryButton(
        label: 'View plans',
        accent: true,
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
    appBar: AppBar(title: const Text('Driver onboarding'), actions: [
      IconButton(icon: const Icon(Icons.refresh), onPressed: _reload),
    ]),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const DtBanner(
        kind: BannerKind.info,
        title: 'Application under review',
        subtitle: 'Approval usually takes under a day. Pull to check — use refresh above.'),
      if (_error != null) ...[
        const SizedBox(height: 8),
        DtBanner(kind: BannerKind.error, title: _error!),
      ],
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _trackRow(true, 'Submitted', 'Vehicle + documents received'),
            _trackRow(true, 'Under review', 'Our team is verifying your documents'),
            _trackRow(false, 'Decision', 'Approved or rejected with notes'),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => setState(() => _showForm = true),
        child: const Text('Edit & resubmit application'),
      ),
    ]),
  );

  Widget _trackRow(bool done, String title, String subtitle) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      CircleAvatar(
        radius: 14,
        backgroundColor: done ? AppColors.success : Colors.grey.shade300,
        child: Icon(done ? Icons.check : Icons.hourglass_empty,
            size: 14, color: done ? Colors.white : Colors.grey.shade600),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      ),
    ]),
  );

  Widget _formView({String? rejectedNote}) => Scaffold(
    appBar: AppBar(title: Text(rejectedNote != null ? 'Resubmit KYC' : 'Driver onboarding')),
    body: Column(children: [
      if (rejectedNote != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: DtBanner(
            kind: BannerKind.error,
            title: 'Previous application rejected',
            subtitle: rejectedNote),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: DtBanner(kind: BannerKind.error, title: _error!),
        ),
      if (_submitted)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Expanded(
              child: TextButton(
                onPressed: _reload,
                child: const Text('Back to status'),
              ),
            ),
          ]),
        ),
      Expanded(
        child: Stepper(
          currentStep: _step,
          onStepTapped: (i) => setState(() => _step = i),
          onStepContinue: () {
            if (_step < 2) {
              setState(() => _step++);
            } else {
              _submit();
            }
          },
          onStepCancel: () {
            if (_step > 0) setState(() => _step--);
          },
          controlsBuilder: (context, details) => Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(children: [
              Expanded(
                child: DtPrimaryButton(
                  label: _step == 2 ? 'Submit KYC' : 'Continue',
                  busy: _busy,
                  onPressed: details.onStepContinue,
                ),
              ),
              if (_step > 0) ...[
                const SizedBox(width: 8),
                TextButton(onPressed: details.onStepCancel, child: const Text('Back')),
              ],
            ]),
          ),
          steps: [
            Step(
              title: const Text('Vehicle'),
              isActive: _step >= 0,
              content: Column(children: [
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  items: [for (final c in VehicleCategory.all) DropdownMenuItem(value: c.id, child: Text(c.label))],
                  onChanged: (v) => setState(() => _category = v ?? 'Mini'),
                  decoration: const InputDecoration(labelText: 'Vehicle category', prefixIcon: Icon(Icons.directions_car)),
                ),
                const SizedBox(height: 8),
                TextField(controller: _plate,
                  decoration: const InputDecoration(labelText: 'Number plate *', prefixIcon: Icon(Icons.confirmation_number_outlined))),
                const SizedBox(height: 8),
                TextField(controller: _make, decoration: const InputDecoration(labelText: 'Make')),
                const SizedBox(height: 8),
                TextField(controller: _model, decoration: const InputDecoration(labelText: 'Model')),
              ]),
            ),
            Step(
              title: const Text('Documents & payout'),
              isActive: _step >= 1,
              content: Column(children: [
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    for (final d in _docs)
                      FilterChip(
                        label: Text(d),
                        selected: _uploads.contains(d),
                        avatar: _uploads.contains(d)
                            ? const Icon(Icons.check_circle, size: 18)
                            : const Icon(Icons.upload_file_outlined, size: 18),
                        onSelected: (_) => _busy ? null : _pickAndUpload(d),
                      ),
                  ],
                ),
                Text('${_uploads.length} of ${_docs.length} uploaded',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 8),
                TextField(controller: _upi,
                  decoration: const InputDecoration(
                    labelText: 'Your UPI ID *', hintText: 'name@upi',
                    prefixIcon: Icon(Icons.payments_outlined))),
                const Text('Riders pay directly to this UPI.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
            ),
            const Step(
              title: Text('Review'),
              content: Text(
                'Submit to send your application for review. Approval usually takes under a day — '
                'you can then buy a subscription plan and go online.'),
            ),
          ],
        ),
      ),
    ]),
  );
}
