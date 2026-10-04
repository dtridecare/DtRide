import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'home_screen.dart';

/// Rider identity check per pack: selfie + government ID upload,
/// pending tracker, rejected with reason. Booking unlocks on approval.
class RiderKycScreen extends StatefulWidget {
  const RiderKycScreen({super.key});
  @override
  State<RiderKycScreen> createState() => _RiderKycScreenState();
}

class _RiderKycScreenState extends State<RiderKycScreen> {
  DtProfile? _profile;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final Set<String> _uploads = {};

  KycService get _kyc => KycService(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() { _loading = true; _error = null; });
    try {
      final p = await AuthService(Supabase.instance.client).currentProfile();
      if (mounted) setState(() { _profile = p; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _upload(String kind) async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (img == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _kyc.uploadDoc(await img.readAsBytes(),
          '$kind-${DateTime.now().millisecondsSinceEpoch}.jpg');
      setState(() => _uploads.add(kind));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_uploads.contains('selfie') ||
        !(_uploads.contains('idfront') || _uploads.contains('idback'))) {
      setState(() => _error = 'Add a selfie and at least one ID photo.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await _kyc.submitRiderKyc();
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
        appBar: AppBar(title: const Text('Verify your identity')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final status = _profile?.riderKycStatus ?? 'not_submitted';
    if (status == 'approved') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RiderHomeScreen()));
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (status == 'pending') return _pendingView();
    if (status == 'rejected') return _rejectedView();
    return _uploadView();
  }

  Widget _uploadView() => Scaffold(
    appBar: AppBar(leading: const BackButton(), title: const Text('')),
    body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
      const Text('Step 1 of 1', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const Text('Verify your identity',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
      const Text('Our admin team checks your details before your first ride.',
          style: TextStyle(color: AppColors.muted, fontSize: 14)),
      const SizedBox(height: 16),
      const Text('Selfie', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 6),
      _uploadTile('selfie', Icons.camera_alt_outlined, 'Take a selfie'),
      const SizedBox(height: 12),
      const Text('Government ID', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: _uploadTile('idfront', Icons.upload_outlined, 'Front')),
        const SizedBox(width: 10),
        Expanded(child: _uploadTile('idback', Icons.upload_outlined, 'Back')),
      ]),
      if (_error != null) ...[
        const SizedBox(height: 8),
        DtBanner(kind: BannerKind.error, title: _error!),
      ],
      const SizedBox(height: 16),
      DtPrimaryButton(label: 'Submit for review', busy: _busy, onPressed: _submit),
    ]),
  );

  Widget _uploadTile(String kind, IconData icon, String label) {
    final done = _uploads.contains(kind);
    return GestureDetector(
      onTap: _busy ? null : () => _upload(kind),
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          border: Border.all(
            style: BorderStyle.solid,
            color: done ? AppColors.success : AppColors.border, width: done ? 2 : 1.5),
          borderRadius: BorderRadius.circular(14)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(done ? Icons.check_circle : icon,
              color: done ? AppColors.success : AppColors.muted),
          const SizedBox(height: 6),
          Text(done ? 'Added' : label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      ),
    );
  }

  Widget _pendingView() => Scaffold(
    appBar: AppBar(title: const Text('')),
    body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
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
        'Our admin team is checking your details. This usually takes up to 24 hours. We will notify you once it is done.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.muted, fontSize: 14)),
      const SizedBox(height: 24),
      _step(true, 'Submitted', 'Details received'),
      _step(null, 'Admin review', 'In progress'),
      _step(false, 'Approved', 'You can book rides'),
      const SizedBox(height: 24),
      OutlinedButton(
        onPressed: _reload,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: const Text('Refresh status'),
      ),
    ]),
  );

  Widget _step(bool? done, String title, String subtitle) => Padding(
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

  Widget _rejectedView() => Scaffold(
    appBar: AppBar(title: const Text('')),
    body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
      Center(
        child: Container(
          height: 96, width: 96,
          decoration: const BoxDecoration(color: Color(0xFFFEE2E2), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: const Icon(Icons.error_outline, size: 44, color: AppColors.danger),
        ),
      ),
      const SizedBox(height: 20),
      const Text('Action needed', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
      const Text('The admin team could not approve everything. Fix the items below and submit again.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 14)),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          border: Border.all(color: const Color(0xFFFECACA)),
          borderRadius: BorderRadius.circular(14)),
        child: Text(_profile?.riderKycNote ?? 'Documents need attention.',
            style: const TextStyle(color: Color(0xFF7F1D1D), fontSize: 13)),
      ),
      const SizedBox(height: 24),
      DtPrimaryButton(label: 'Fix and resubmit', onPressed: () => setState(() {
        _profile = DtProfile(
          id: _profile!.id, role: _profile!.role, phone: _profile!.phone,
          fullName: _profile!.fullName, riderKycStatus: 'not_submitted');
      })),
    ]),
  );
}
