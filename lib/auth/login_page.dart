import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../theme/app_colors.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({required this.firebaseReady, super.key});

  final bool firebaseReady;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isRegistering = false;
  bool _isPasswordVisible = false;
  bool _isBusy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submitEmailForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_requireFirebase()) return;

    await _runAuthAction(() async {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      if (_isRegistering) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    });
  }

  Future<void> _signInWithGoogle() async {
    if (!_requireFirebase()) return;

    await _runAuthAction(() async {
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw FirebaseAuthException(
          code: 'missing-google-id-token',
          message: 'Google did not return an ID token. Check Firebase setup.',
        );
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await FirebaseAuth.instance.signInWithCredential(credential);
    });
  }

  Future<void> _sendPasswordReset() async {
    if (!_requireFirebase()) return;
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showMessage('Enter your email address first.');
      return;
    }

    await _runAuthAction(() async {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showMessage('Password reset email sent. Check your inbox.');
    });
  }

  bool _requireFirebase() {
    if (widget.firebaseReady) return true;
    _showMessage(
      'Firebase is not connected yet. The sign-in screen is ready, but account login needs Firebase setup.',
    );
    return false;
  }

  Future<void> _runAuthAction(Future<void> Function() action) async {
    setState(() => _isBusy = true);
    try {
      await action();
    } on FirebaseAuthException catch (error) {
      _showMessage(_firebaseErrorMessage(error));
    } on GoogleSignInException catch (error) {
      if (error.code != GoogleSignInExceptionCode.canceled) {
        _showMessage(
          error.description ?? 'Google sign-in could not be completed.',
        );
      }
    } catch (error) {
      _showMessage('Something went wrong. Please try again.');
      debugPrint('Authentication error: $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String _firebaseErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'That email address does not look valid.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'weak-password':
        return 'Choose a stronger password with at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a bit and try again.';
      case 'network-request-failed':
        return 'Could not connect. Check your internet and try again.';
      case 'missing-google-id-token':
        return 'Google sign-in needs its Firebase configuration.';
      default:
        return error.message ?? 'Sign-in failed. Please try again.';
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.sizeOf(context).height < 860;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(22, isSmall ? 10 : 32, 22, 16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _BrandHeader(compact: isSmall),
                            SizedBox(height: isSmall ? 14 : 34),
                            _buildFormCard(context, compact: isSmall),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: const Text(
                    'Securely sign in with your email or Google account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF8A94A5),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormCard(BuildContext context, {required bool compact}) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        22,
        compact ? 16 : 24,
        22,
        compact ? 16 : 22,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE9EDF2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C172A46),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isRegistering ? 'Create your account' : 'Welcome back',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              _isRegistering
                  ? 'A few details and you’re ready to go.'
                  : 'Sign in to your CBPAK account to continue.',
              style: const TextStyle(
                color: Color(0xFF788397),
                fontSize: 14,
                height: 1.45,
              ),
            ),
            if (!widget.firebaseReady) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7EA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFE4B5)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFFAF6D12),
                      size: 19,
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Firebase still needs to be connected before sign-in can work.',
                        style: TextStyle(
                          color: Color(0xFF805716),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: compact ? 16 : 24),
            const _FieldLabel('Email address'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailController,
              enabled: !_isBusy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                hintText: 'you@example.com',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return 'Enter your email address.';
                if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                  return 'Enter a valid email address.';
                }
                return null;
              },
            ),
            const SizedBox(height: 18),
            const _FieldLabel('Password'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _passwordController,
              enabled: !_isBusy,
              obscureText: !_isPasswordVisible,
              textInputAction: _isRegistering
                  ? TextInputAction.next
                  : TextInputAction.done,
              autofillHints: _isRegistering
                  ? const [AutofillHints.newPassword]
                  : const [AutofillHints.password],
              onFieldSubmitted: (_) {
                if (!_isRegistering) _submitEmailForm();
              },
              decoration: InputDecoration(
                hintText: 'Enter your password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _isPasswordVisible
                      ? 'Hide password'
                      : 'Show password',
                  onPressed: _isBusy
                      ? null
                      : () => setState(
                          () => _isPasswordVisible = !_isPasswordVisible,
                        ),
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              validator: (value) {
                final password = value ?? '';
                if (password.isEmpty) return 'Enter your password.';
                if (_isRegistering && password.length < 6) {
                  return 'Use at least 6 characters.';
                }
                return null;
              },
            ),
            if (_isRegistering) ...[
              const SizedBox(height: 18),
              const _FieldLabel('Confirm password'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _confirmPasswordController,
                enabled: !_isBusy,
                obscureText: !_isPasswordVisible,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  hintText: 'Enter your password again',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
                validator: (value) {
                  if (value != _passwordController.text) {
                    return 'Passwords do not match.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submitEmailForm(),
              ),
            ],
            if (!_isRegistering) ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isBusy ? null : _sendPasswordReset,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    foregroundColor: AppColors.blue,
                  ),
                  child: const Text('Forgot password?'),
                ),
              ),
            ] else ...[
              const SizedBox(height: 14),
            ],
            const SizedBox(height: 6),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _isBusy ? null : _submitEmailForm,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: _isBusy
                    ? const SizedBox(
                        width: 21,
                        height: 21,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_isRegistering ? 'Create account' : 'Sign in'),
              ),
            ),
            const SizedBox(height: 19),
            const _OrDivider(),
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _isBusy ? null : _signInWithGoogle,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.navy,
                  side: const BorderSide(color: Color(0xFFE1E6ED)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: const _GoogleMark(),
                label: const Text('Continue with Google'),
              ),
            ),
            const SizedBox(height: 19),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _isRegistering
                      ? 'Already have an account? '
                      : 'New to CBPAK? ',
                  style: const TextStyle(
                    color: Color(0xFF788397),
                    fontSize: 13,
                  ),
                ),
                TextButton(
                  onPressed: _isBusy
                      ? null
                      : () => setState(() {
                          _isRegistering = !_isRegistering;
                          _formKey.currentState?.reset();
                        }),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.blue,
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  child: Text(_isRegistering ? 'Sign in' : 'Create account'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: compact ? 68 : 78,
          height: compact ? 68 : 78,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.navy, Color(0xFF29496F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22294D79),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.route_rounded, color: Colors.white, size: 35),
              Positioned(
                right: 14,
                top: 14,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.orange,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        const Text(
          'CBPAK',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 19,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.4,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'Your journey, made simpler.',
          style: TextStyle(color: Color(0xFF8792A3), fontSize: 13),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.navy,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: Color(0xFFE8EBF0), height: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 13),
          child: Text(
            'OR',
            style: TextStyle(
              color: Color(0xFF9AA3B2),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(child: Divider(color: Color(0xFFE8EBF0), height: 1)),
      ],
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 21,
      height: 21,
      child: Center(
        child: Text(
          'G',
          style: TextStyle(
            color: Color(0xFF4285F4),
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
