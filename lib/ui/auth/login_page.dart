// lib/ui/auth/login_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _obscurePass = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final supabase = ref.read(supabaseProvider);
      final response = await supabase.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );

      if (response.user == null) {
        setState(() => _error = 'Invalid credentials. Please try again.');
        return;
      }

      // Load tenant ID
      final tenant = await supabase
          .from('tenants')
          .select('tenant_id')
          .eq('owner_id', response.user!.id)
          .maybeSingle();

      if (tenant == null) {
        // New user – go to onboarding
        if (mounted) context.go('/onboarding');
        return;
      }

      ref.read(tenantIdProvider.notifier).state = tenant['tenant_id'] as String;

      // Store Worker auth secret (same as env var – configured during onboarding)
      final syncService = ref.read(syncServiceProvider);
      final stored = await supabase
          .from('tenants')
          .select('app_settings')
          .eq('tenant_id', tenant['tenant_id'] as String)
          .single();
      final settings = stored['app_settings'] as Map<String, dynamic>;
      final workerSecret = settings['worker_secret'] as String?;
      if (workerSecret != null) {
        await syncService.storeAuthToken(workerSecret);
      }

      if (mounted) context.go('/pos');
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceDeep,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              // Logo / brand
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.point_of_sale_rounded,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'SmartBiz',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),
              const Text(
                'Welcome back',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in to your business account',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
              ),
              const SizedBox(height: 40),

              // Email
              const Text('Email',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'you@business.com',
                  prefixIcon: Icon(Icons.email_outlined, color: AppTheme.textMuted),
                ),
              ),
              const SizedBox(height: 20),

              // Password
              const Text('Password',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              TextField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                style: const TextStyle(color: AppTheme.textPrimary),
                onSubmitted: (_) => _signIn(),
                decoration: InputDecoration(
                  hintText: '••••••••',
                  prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.textMuted),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: AppTheme.textMuted,
                    ),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              if (_error != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                color: AppTheme.error, fontSize: 13)),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 28),

              // Sign in button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _signIn,
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Text('Sign In'),
                ),
              ),

              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: () => context.go('/onboarding'),
                  child: const Text(
                    "Don't have an account? Create one",
                    style: TextStyle(color: AppTheme.primary),
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
