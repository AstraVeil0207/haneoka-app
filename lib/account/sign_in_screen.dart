/// Native Haneoka sign-in (`renderAuth` in `lit/account-workspace.ts`):
/// email and password, email-only registration, password reset and the
/// website's sign-in providers, all against the account service directly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/app_state.dart';
import '../shell/links.dart';
import 'haneoka_account.dart';

enum _Mode { signIn, signUp, forgotPassword, verifyEmail }

/// Opens sign-in; completes true once signed in.
Future<bool> openSignIn(BuildContext context) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const SignInScreen(),
      ),
    ) ??
    false;

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  var _mode = _Mode.signIn;
  var _legal = false;
  var _legalMissing = false;
  var _busy = false;
  var _hidePassword = true;
  ({bool available, bool signUp, List<String> providers})? _config;

  HaneokaAccount get _account => HaneokaAccount.instance;

  @override
  void initState() {
    super.initState();
    _account.config().then(
      (value) {
        if (mounted) setState(() => _config = value);
      },
      onError: (_) {
        if (mounted) {
          setState(
            () => _config = (
              available: true,
              signUp: true,
              providers: const <String>[],
            ),
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _t(String key, String fallback) {
    final t = AppScope.of(context).text;
    return switch (key) {
      'privacy' => t('home.dashboard.privacy', fallback),
      'terms' => t('home.dashboard.terms', fallback),
      _ => t('account.page.$key', fallback),
    };
  }

  String _errorText(Object error) {
    final code = error is AccountError ? error.code : '';
    return switch (code) {
      'INVALID_EMAIL_OR_PASSWORD' ||
      'INVALID_EMAIL' ||
      'INVALID_PASSWORD' ||
      'CREDENTIAL_ACCOUNT_NOT_FOUND' => _t(
        'invalidCredentials',
        'The email address or password is incorrect.',
      ),
      'EMAIL_NOT_VERIFIED' => _t(
        'emailNotVerified',
        'Verify your email address before signing in.',
      ),
      'too_many_requests' || 'TOO_MANY_REQUESTS' || 'rate_limit_exceeded' => _t(
        'tooManyRequests',
        'Too many attempts. Try again later.',
      ),
      'invalid_email' => _t('invalidEmail', 'Enter a valid email address.'),
      _ => _t('authFailed', 'Authentication failed.'),
    };
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(Future<void> Function() work, {String? success}) async {
    setState(() => _busy = true);
    try {
      await work();
      if (success != null && mounted) _say(success);
    } catch (error) {
      if (mounted) _say(_errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_legal) {
      setState(() => _legalMissing = true);
      return;
    }
    final email = _email.text.trim();
    if (_mode == _Mode.signUp) {
      await _run(() async {
        await _account.register(email);
        if (mounted) setState(() => _mode = _Mode.verifyEmail);
      }, success: _t('verificationSent', 'Verification email sent.'));
      return;
    }
    await _run(() async {
      await _account.signInWithEmail(email, _password.text);
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  Future<void> _provider(String provider) => _run(() async {
    try {
      await _account.signInWithProvider(provider);
    } on AccountError catch (error) {
      if (const {'cancelled', 'access_denied'}.contains(error.code)) return;
      rethrow;
    }
    if (mounted && _account.signedIn) Navigator.of(context).pop(true);
  });

  String? _validEmail(String? value) {
    final email = value?.trim() ?? '';
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) &&
            email.length <= 254
        ? null
        : _t('invalidEmail', 'Enter a valid email address.');
  }

  Widget _emailField({String? helper}) => TextFormField(
    controller: _email,
    keyboardType: TextInputType.emailAddress,
    autofillHints: const [AutofillHints.email],
    textInputAction: _mode == _Mode.signIn
        ? TextInputAction.next
        : TextInputAction.done,
    maxLength: 254,
    decoration: InputDecoration(
      labelText: _t('email', 'Email'),
      helperText: helper,
      counterText: '',
      border: const OutlineInputBorder(),
    ),
    validator: _validEmail,
  );

  Widget _heading(IconData icon, String title, [String? body]) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: theme.textTheme.headlineSmall)),
          ],
        ),
        if (body != null) ...[
          const SizedBox(height: 12),
          Text(body, style: theme.textTheme.bodyLarge),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  List<Widget> _forgotPassword() => [
    _heading(
      Symbols.key_rounded,
      _t('forgotPasswordTitle', 'Reset your password'),
      _t(
        'forgotPasswordBody',
        "Enter your email address and we'll send you a reset link.",
      ),
    ),
    _emailField(),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: _busy
          ? null
          : () {
              if (!_form.currentState!.validate()) return;
              _run(
                () => _account.requestPasswordReset(_email.text.trim()),
                success: _t('resetEmailSent', 'Reset email sent.'),
              );
            },
      child: Text(_t('sendResetLink', 'Send reset link')),
    ),
    TextButton(
      onPressed: () => setState(() => _mode = _Mode.signIn),
      child: Text(_t('backToSignIn', 'Back to sign in')),
    ),
  ];

  List<Widget> _verifyEmail() => [
    _heading(
      Symbols.mark_email_read_rounded,
      _t('verifyEmailTitle', 'Check your email'),
      _t(
        'verifyEmailBody',
        'Open the latest setup email to finish registration.',
      ),
    ),
    _emailField(),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: _busy
          ? null
          : () {
              if (!_form.currentState!.validate()) return;
              _run(
                () => _account.register(_email.text.trim()),
                success: _t('verificationSent', 'Verification email sent.'),
              );
            },
      child: Text(_t('resendVerification', 'Resend setup email')),
    ),
    TextButton(
      onPressed: () => setState(() => _mode = _Mode.signIn),
      child: Text(_t('backToSignIn', 'Back to sign in')),
    ),
  ];

  List<Widget> _signInOrUp() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final signUp = _mode == _Mode.signUp;
    final config = _config;
    final providers = config?.providers ?? const <String>[];
    return [
      _heading(
        signUp ? Symbols.person_add_rounded : Symbols.lock_person_rounded,
        signUp ? _t('signUp', 'Create account') : _t('signIn', 'Sign in'),
      ),
      if (config?.signUp ?? true) ...[
        SegmentedButton<_Mode>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: _Mode.signIn,
              icon: const Icon(Symbols.login_rounded),
              label: Text(_t('signIn', 'Sign in')),
            ),
            ButtonSegment(
              value: _Mode.signUp,
              icon: const Icon(Symbols.person_add_rounded),
              label: Text(_t('signUp', 'Create account')),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (value) => setState(() => _mode = value.single),
        ),
        const SizedBox(height: 24),
      ],
      _emailField(
        helper: signUp
            ? _t('emailOnlySignupHint', "We'll email a secure setup link.")
            : null,
      ),
      if (!signUp) ...[
        const SizedBox(height: 16),
        TextFormField(
          controller: _password,
          obscureText: _hidePassword,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          maxLength: 128,
          decoration: InputDecoration(
            labelText: _t('password', 'Password'),
            counterText: '',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _hidePassword = !_hidePassword),
              icon: Icon(
                _hidePassword
                    ? Symbols.visibility_rounded
                    : Symbols.visibility_off_rounded,
              ),
            ),
          ),
          validator: (value) => (value?.length ?? 0) >= 12
              ? null
              : _t('passwordHint', 'Use at least 12 characters.'),
        ),
      ],
      const SizedBox(height: 8),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _legal,
        isError: _legalMissing && !_legal,
        onChanged: (value) => setState(() => _legal = value ?? false),
        title: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${_t('legalAgreementPrefix', 'I agree to the')} '),
            InkWell(
              onTap: () => openLink(context, '/privacy'),
              child: Text(
                _t('privacy', 'Privacy Policy'),
                style: TextStyle(
                  color: scheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            Text(' ${_t('legalAgreementJoiner', 'and')} '),
            InkWell(
              onTap: () => openLink(context, '/terms'),
              child: Text(
                _t('terms', 'Terms of Use'),
                style: TextStyle(
                  color: scheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            Text(_t('legalAgreementSuffix', '.')),
          ],
        ),
      ),
      if (_legalMissing && !_legal)
        Text(
          _t(
            'legalAgreementRequired',
            'Accept the policies before continuing.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
        ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _busy ? null : _submit,
        icon: Icon(
          signUp ? Symbols.mark_email_read_rounded : Symbols.login_rounded,
        ),
        label: Text(
          _busy
              ? _t('working', 'Working…')
              : signUp
              ? _t('signUp', 'Create account')
              : _t('signIn', 'Sign in'),
        ),
      ),
      if (!signUp && (config?.signUp ?? true)) ...[
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => setState(() => _mode = _Mode.forgotPassword),
          child: Text(_t('forgotPassword', 'Forgot password?')),
        ),
      ],
      if (providers.isNotEmpty) ...[
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _t('orContinueWith', 'Or continue with'),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 400 ? 2 : 1;
            final width = (constraints.maxWidth - 8 * (columns - 1)) / columns;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final provider in providers)
                  SizedBox(
                    width: width,
                    child: FilledButton.tonalIcon(
                      onPressed: _busy ? null : () => _provider(provider),
                      icon: SvgPicture.asset(
                        'assets/brand/oauth/$provider.svg',
                        width: 18,
                        height: 18,
                        colorFilter: provider == 'google'
                            ? null
                            : ColorFilter.mode(
                                scheme.onSecondaryContainer,
                                BlendMode.srcIn,
                              ),
                        placeholderBuilder: (_) =>
                            const Icon(Symbols.link_rounded, size: 18),
                      ),
                      label: Text(provider),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final children = config == null
        ? [const Center(child: CircularProgressIndicator())]
        : !config.available
        ? [
            _heading(
              Symbols.cloud_off_rounded,
              _t('unavailableTitle', 'Accounts are unavailable'),
              _t(
                'unavailableBody',
                'The account service is temporarily unavailable.',
              ),
            ),
          ]
        : switch (_mode) {
            _Mode.forgotPassword => _forgotPassword(),
            _Mode.verifyEmail => _verifyEmail(),
            _ => _signInOrUp(),
          };
    return Scaffold(
      appBar: AppBar(title: Text(_t('signIn', 'Sign in'))),
      body: SafeArea(
        child: Form(
          key: _form,
          child: AutofillGroup(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [...children],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
