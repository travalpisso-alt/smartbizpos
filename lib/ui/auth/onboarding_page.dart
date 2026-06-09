// lib/ui/auth/onboarding_page.dart
// New-tenant setup wizard (3 steps)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _pageCtrl = PageController();
  int _currentStep = 0;

  // Step 1 – Auth
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  // Step 2 – Business info
  final _bizNameCtrl = TextEditingController();
  final _workerSecretCtrl = TextEditingController();

  // Step 3 – Done
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _bizNameCtrl.dispose();
    _workerSecretCtrl.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final supabase = ref.read(supabaseProvider);

      // Sign up
      final authRes = await supabase.auth.signUp(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      if (authRes.user == null) throw Exception('Sign-up failed. Please try again.');

      // Create tenant record
      final tenantRes = await supabase.from('tenants').insert({
        'business_name': _bizNameCtrl.text.trim(),
        'owner_id': authRes.user!.id,
        'app_settings': {
          'allow_negative_stock': false,
          'default_currency': 'LKR',
          'receipt_footer': 'Thank you for shopping!',
          'worker_secret': _workerSecretCtrl.text.trim(),
        },
      }).select('tenant_id').single();

      ref.read(tenantIdProvider.notifier).state =
          tenantRes['tenant_id'] as String;

      // Save Worker auth secret locally
      await ref
          .read(syncServiceProvider)
          .storeAuthToken(_workerSecretCtrl.text.trim());

      _nextStep();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _nextStep() {
    setState(() => _currentStep++);
    _pageCtrl.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceDeep,
      body: SafeArea(
        child: Column(
          children: [
            // Step indicators
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Row(
                children: List.generate(3, (i) {
                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i <= _currentStep
                            ? AppTheme.primary
                            : AppTheme.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStep1(),
                  _buildStep2(),
                  _buildStep3(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Create Account',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Step 1 of 3 – Your login credentials',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          const SizedBox(height: 36),
          _label('Email'),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(hintText: 'you@business.com'),
          ),
          const SizedBox(height: 20),
          _label('Password'),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(hintText: 'Min 8 characters'),
          ),
          const SizedBox(height: 32),
          _primaryButton('Continue', _nextStep),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () => context.go('/login'),
              child: const Text('Already have an account? Sign in',
                  style: TextStyle(color: AppTheme.primary)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Business Details',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Step 2 of 3 – Your business info',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          const SizedBox(height: 36),
          _label('Business Name'),
          TextField(
            controller: _bizNameCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(hintText: 'e.g. Perera Trading'),
          ),
          const SizedBox(height: 20),
          _label('Cloudflare Worker Secret'),
          TextField(
            controller: _workerSecretCtrl,
            obscureText: true,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Your WORKER_AUTH_SECRET value',
              helperText: 'Set this via: wrangler secret put WORKER_AUTH_SECRET',
              helperStyle: TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_error!,
                  style: const TextStyle(
                      color: AppTheme.error, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 32),
          _primaryButton(
            _isLoading ? 'Creating Account…' : 'Create Account',
            _isLoading ? null : _createAccount,
          ),
        ],
      ),
    );
  }

  Widget _buildStep3() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline_rounded,
                color: AppTheme.success, size: 44),
          ),
          const SizedBox(height: 24),
          const Text('You\'re all set!',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Text(
            'Your SmartBiz account is ready. Start adding items and making sales.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 40),
          _primaryButton('Go to POS', () => context.go('/pos')),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      );

  Widget _primaryButton(String label, VoidCallback? onTap) => SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: onTap,
          child: _isLoading && onTap == null
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5))
              : Text(label),
        ),
      );
}
