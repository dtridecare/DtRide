import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'plans_screen.dart';

const categories = ['Bike', 'Auto', 'Mini', 'Sedan', 'SUV'];

/// Driver KYC form: vehicle details + UPI + doc uploads, then submit_kyc RPC.
class KycScreen extends StatefulWidget {
  const KycScreen({super.key});
  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  String _category = 'Mini';
  final _upi = TextEditingController();
  final _plate = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final List<String> _uploads = [];
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
      final path = await _kycSvc.uploadDoc(bytes, '$doc-${DateTime.now().millisecondsSinceEpoch}.jpg');
      setState(() => _uploads.add(path));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      await _kycSvc.submit(
        category: _category,
        upiId: _upi.text.trim(),
        plate: _plate.text.trim(),
        make: _make.text.trim().isEmpty ? null : _make.text.trim(),
        model: _model.text.trim().isEmpty ? null : _model.text.trim(),
      );
      final k = await _kycSvc.getKyc();
      if (mounted) {
        setState(() => _kyc = k);
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
    appBar: AppBar(title: const Text('Driver KYC')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      if (_kyc != null) Chip(label: Text('Status: ${_kyc!.kycStatus}')),
      DropdownButtonFormField<String>(
        initialValue: _category,
        items: [for (final c in categories) DropdownMenuItem(value: c, child: Text(c))],
        onChanged: (v) => setState(() => _category = v ?? 'Mini'),
        decoration: const InputDecoration(labelText: 'Vehicle category'),
      ),
      TextField(controller: _plate, decoration: const InputDecoration(labelText: 'Number plate *')),
      TextField(controller: _make, decoration: const InputDecoration(labelText: 'Make')),
      TextField(controller: _model, decoration: const InputDecoration(labelText: 'Model')),
      TextField(controller: _upi, decoration: const InputDecoration(labelText: 'Your UPI ID (riders pay here) *')),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        for (final d in ['license', 'rc', 'aadhaar', 'selfie'])
          ElevatedButton(onPressed: _busy ? null : () => _pickAndUpload(d), child: Text('Upload $d')),
      ]),
      Text('Uploaded: ${_uploads.length} docs'),
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      const SizedBox(height: 12),
      ElevatedButton(
        onPressed: _busy ? null : _submit,
        child: Text(_busy ? '...' : 'Submit KYC'),
      ),
    ]),
  );
}
