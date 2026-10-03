import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'plans_screen.dart';

const _docs = ['license', 'rc', 'aadhaar', 'selfie'];

/// 3-step KYC wizard: 1 Vehicle → 2 Documents + UPI → 3 Review & submit.
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
  DriverKyc? _kyc;

  KycService get _kycSvc => KycService(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _kycSvc.getKyc().then((k) {
      if (mounted) {
        setState(() {
          _kyc = k;
          _category = k.vehicleCategory;
          _upi.text = k.upiId ?? '';
        });
      }
    }).catchError((_) => null);
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
    setState(() { _busy = true; _error = null; });
    try {
      await _kycSvc.submit(
        category: _category,
        upiId: _upi.text.trim(),
        plate: _plate.text.trim(),
        make: _make.text.trim().isEmpty ? null : _make.text.trim(),
        model: _model.text.trim().isEmpty ? null : _model.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PlansScreen()));
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Driver onboarding')),
    body: Column(children: [
      if (_kyc != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: DtBanner(
            kind: _kyc!.approved ? BannerKind.success : BannerKind.info,
            title: 'KYC status: ${_kyc!.kycStatus}',
            subtitle: _kyc!.notes),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: DtBanner(kind: BannerKind.error, title: _error!),
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
                  label: _step == 2 ? (_busy ? 'Submitting…' : 'Submit KYC') : 'Continue',
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
