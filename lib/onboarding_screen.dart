import 'dart:async';
import 'dart:io';

import 'package:country_picker/country_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_controller.dart';
import 'auth_service.dart';
import 'company_id_image_service.dart';
import 'pin_input.dart';
import 'receipt_auth_layout.dart';

enum _OnboardingStep {
  welcome,
  createAccount,
  verifyEmail,
  createPin,
  createCompany,
  companyCreated,
  companyId,
  checkingCompany,
  memberLogin,
  recoverCompanyId,
  resetAdminPin,
  recoverySent,
  staffPinHelp,
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _nativeChannel = MethodChannel('saleo/native');
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _pin = TextEditingController();
  final _confirmPin = TextEditingController();
  final _companyName = TextEditingController();
  final _customCompanyId = TextEditingController();
  final _companyId = TextEditingController();
  final _loginUsername = TextEditingController();
  final _loginPin = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _recoveryEmail = TextEditingController();
  _OnboardingStep _recoveryReturn = _OnboardingStep.companyId;
  bool _recoveringId = true;
  bool _verificationChecking = false;

  _OnboardingStep _step = _OnboardingStep.welcome;
  Country _country = Country.parse('GH');
  RegistrationTicket? _registration;
  CompanyPreview? _company;
  AuthenticatedMember? _createdMember;
  Uint8List? _logoBytes;
  Timer? _verificationTimer;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _chooseCustomCompanyId = false;
  DateTime? _dateOfBirth;
  String? _error;

  AuthService get _auth => widget.controller.authService;

  @override
  void dispose() {
    _verificationTimer?.cancel();
    for (final controller in [
      _username,
      _email,
      _phone,
      _password,
      _pin,
      _confirmPin,
      _companyName,
      _customCompanyId,
      _companyId,
      _loginUsername,
      _loginPin,
      _recoveryEmail,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _go(_OnboardingStep step) {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _verificationTimer?.cancel();
    setState(() {
      _step = step;
      _error = null;
    });
    if (step == _OnboardingStep.verifyEmail) {
      _verificationTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _checkVerification(silent: true),
      );
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openEmailApp() async {
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', ['mailto:']);
      } else {
        await _nativeChannel.invokeMethod<void>('openEmail', {
          'email': _registration?.email ?? _email.text,
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Open your email app or webmail and follow the verification link.',
        );
      }
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      _registration = await _auth.register(
        dateOfBirth: _dateOfBirth!,
        username: _username.text,
        email: _email.text,
        countryCode: '+${_country.phoneCode}',
        phoneNumber: _phone.text,
        password: _password.text,
      );
      if (mounted) _go(_OnboardingStep.verifyEmail);
    });
  }

  Future<void> _chooseDateOfBirth(FormFieldState<DateTime> field) async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 15, now.month, now.day),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      helpText: 'Select date of birth',
    );
    if (selected == null || !mounted) return;
    setState(() => _dateOfBirth = selected);
    field.didChange(selected);
  }

  String _dateLabel(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  Future<void> _checkVerification({bool silent = false}) async {
    final registration = _registration;
    if (registration == null ||
        _verificationChecking ||
        _step != _OnboardingStep.verifyEmail) {
      return;
    }
    _verificationChecking = true;
    try {
      final verified = await _auth.isEmailVerified(registration.id);
      if (!mounted ||
          _step != _OnboardingStep.verifyEmail ||
          _registration != registration) {
        return;
      }
      if (verified) {
        _go(_OnboardingStep.createPin);
      } else if (!silent) {
        setState(
          () => _error = 'Your email is not verified yet. Follow the link in your inbox, then try again.',
        );
      }
    } catch (_) {
      if (!silent && mounted && _step == _OnboardingStep.verifyEmail) {
        setState(
          () => _error = 'Could not check verification. Please try again.',
        );
      }
    } finally {
      _verificationChecking = false;
    }
  }

  Future<void> _savePin() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      await _auth.setRegistrationPin(_registration!.id, _pin.text);
      if (mounted) _go(_OnboardingStep.createCompany);
    });
  }

  Future<void> _pickLogo() async {
    final image = await FilePicker.pickFile(
      type: FileType.image,
      compressionQuality: 82,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() {
      _logoBytes = bytes;
      _error = null;
    });
  }

  Future<void> _createCompany() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      _createdMember = await _auth.createCompany(
        registrationId: _registration!.id,
        companyName: _companyName.text,
        country: _country.countryCode,
        requestedCompanyId: _chooseCustomCompanyId
            ? _customCompanyId.text
            : null,
        logoBytes: _logoBytes,
      );
      _company = _createdMember!.company;
      if (mounted) _go(_OnboardingStep.companyCreated);
    });
  }

  Future<void> _findCompany() async {
    if (!_formKey.currentState!.validate()) return;
    _go(_OnboardingStep.checkingCompany);
    await _run(() async {
      _company = await _auth.findCompany(_companyId.text);
      if (mounted) _go(_OnboardingStep.memberLogin);
    });
    if (_error != null && mounted) {
      final message = _error;
      _go(_OnboardingStep.companyId);
      setState(() => _error = message);
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      final member = await _auth.login(
        companyId: _company!.companyId,
        username: _loginUsername.text,
        pin: _loginPin.text,
      );
      await widget.controller.acceptAuthenticatedMember(member);
    });
  }

  void _recoverCompanyId() => _openRecovery(recoverId: true);

  void _requestAdminPinReset() => _openRecovery(recoverId: false);

  void _openRecovery({required bool recoverId}) {
    _recoveryReturn = _step;
    _recoveringId = recoverId;
    _recoveryEmail.text = _email.text.trim();
    _go(
      recoverId
          ? _OnboardingStep.recoverCompanyId
          : _OnboardingStep.resetAdminPin,
    );
  }

  Future<void> _sendRecovery() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      final email = _recoveryEmail.text.trim();
      if (_recoveringId) {
        await _auth.recoverCompanyId(email);
      } else {
        await _auth.requestAdminPinReset(email);
      }
      if (mounted) _go(_OnboardingStep.recoverySent);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      // A form key must never exist in both the outgoing and incoming page.
      // Replacing the step directly avoids AnimatedSwitcher retaining old forms.
      child: KeyedSubtree(key: ValueKey(_step), child: _buildStep(context)),
    ),
  );

  Widget _buildStep(BuildContext context) => switch (_step) {
    _OnboardingStep.welcome => _welcome(context),
    _OnboardingStep.createAccount => _createAccount(context),
    _OnboardingStep.verifyEmail => _verifyEmail(context),
    _OnboardingStep.createPin => _createPinScreen(context),
    _OnboardingStep.createCompany => _createCompanyScreen(context),
    _OnboardingStep.companyCreated => _companyCreatedScreen(context),
    _OnboardingStep.companyId => _companyIdScreen(context),
    _OnboardingStep.checkingCompany => _checkingCompany(context),
    _OnboardingStep.memberLogin => _memberLogin(context),
    _OnboardingStep.recoverCompanyId ||
    _OnboardingStep.resetAdminPin => _recoveryScreen(),
    _OnboardingStep.recoverySent => _recoveryConfirmation(),
    _OnboardingStep.staffPinHelp => _staffPinHelp(),
  };

  String get _section => switch (_step) {
    _OnboardingStep.welcome => 'WELCOME TO SALEO',
    _OnboardingStep.companyId ||
    _OnboardingStep.checkingCompany => 'SIGN IN · COMPANY',
    _OnboardingStep.memberLogin => 'SIGN IN · YOUR ACCOUNT',
    _OnboardingStep.createAccount => 'CREATE ACCOUNT · 1 OF 4',
    _OnboardingStep.verifyEmail => 'VERIFY EMAIL · 2 OF 4',
    _OnboardingStep.createPin => 'CREATE PIN · 3 OF 4',
    _OnboardingStep.createCompany => 'YOUR COMPANY · 4 OF 4',
    _OnboardingStep.companyCreated => 'READY TO BEGIN',
    _ => 'ACCOUNT RECOVERY',
  };

  Widget _page({required Widget child, bool back = true}) => ReceiptAuthLayout(
    section: _section,
    onBack: back ? _back : null,
    busy: _busy,
    child: child,
  );

  Widget _recoveryScreen() => _page(
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RoundIcon(
            _recoveringId ? Icons.badge_outlined : Icons.lock_reset_rounded,
          ),
          const SizedBox(height: 24),
          _Title(
            _recoveringId ? 'Find your company ID' : 'Reset your admin PIN',
          ),
          const SizedBox(height: 12),
          Text(
            _recoveringId
                ? 'Enter the administrator email used for your company. We will email the company ID if an account matches.'
                : 'Enter your administrator email. We will send a secure link to choose a new 4-digit PIN if an account matches.',
          ),
          const SizedBox(height: 24),
          TextFormField(
            key: const ValueKey('recovery-email'),
            controller: _recoveryEmail,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Administrator email',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
            validator: (value) =>
                RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                    .hasMatch(value?.trim() ?? '')
                ? null
                : 'Enter a valid email address',
            onFieldSubmitted: (_) => _sendRecovery(),
          ),
          _errorView(),
          const SizedBox(height: 24),
          _primaryButton(
            _recoveringId ? 'Email company ID' : 'Send reset link',
            _sendRecovery,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _go(_recoveryReturn),
            child: const Text('Back to sign in'),
          ),
          if (!_recoveringId)
            TextButton(
              onPressed: () => _go(_OnboardingStep.staffPinHelp),
              child: const Text('I am a staff member'),
            ),
        ],
      ),
    ),
  );

  Widget _recoveryConfirmation() => _page(
    back: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _RoundIcon(Icons.mark_email_read_outlined),
        const SizedBox(height: 24),
        const _Title('Check your inbox'),
        const SizedBox(height: 12),
        Text(
          _recoveringId
              ? 'If this email matches an administrator account, you will receive your company ID.'
              : 'If this email matches an administrator account, you will receive a secure PIN reset link. Follow it in your browser, then return here to sign in.',
        ),
        const SizedBox(height: 16),
        SelectableText(
          _recoveryEmail.text.trim(),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        const Text(
          'Check your spam folder too. Delivery may take a few minutes.',
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => _go(_recoveryReturn),
          child: const Text('Back to sign in'),
        ),
        TextButton(
          onPressed: () => _go(
            _recoveringId
                ? _OnboardingStep.recoverCompanyId
                : _OnboardingStep.resetAdminPin,
          ),
          child: const Text('Use another email'),
        ),
      ],
    ),
  );

  Widget _staffPinHelp() => _page(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _RoundIcon(Icons.support_agent_rounded),
        const SizedBox(height: 24),
        const _Title('Reset your staff PIN'),
        const SizedBox(height: 12),
        const Text(
          'Ask your company administrator to reset your PIN from Staff settings. For your account security, staff PINs cannot be reset using the administrator email form.',
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => _go(
            _company == null
                ? _OnboardingStep.companyId
                : _OnboardingStep.memberLogin,
          ),
          child: const Text('Back to sign in'),
        ),
      ],
    ),
  );

  void _back() {
    switch (_step) {
      case _OnboardingStep.createAccount:
      case _OnboardingStep.companyId:
        _go(_OnboardingStep.welcome);
      case _OnboardingStep.verifyEmail:
        _go(_OnboardingStep.createAccount);
      case _OnboardingStep.createPin:
        _go(_OnboardingStep.verifyEmail);
      case _OnboardingStep.createCompany:
        _go(_OnboardingStep.createPin);
      case _OnboardingStep.memberLogin:
      case _OnboardingStep.checkingCompany:
        _go(_OnboardingStep.companyId);
      case _OnboardingStep.recoverCompanyId:
      case _OnboardingStep.resetAdminPin:
      case _OnboardingStep.recoverySent:
        _go(_recoveryReturn);
      case _OnboardingStep.staffPinHelp:
        _go(
          _company == null
              ? _OnboardingStep.companyId
              : _OnboardingStep.memberLogin,
        );
      case _OnboardingStep.welcome:
      case _OnboardingStep.companyCreated:
        break;
    }
  }

  Widget _welcome(BuildContext context) => _page(
    back: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Title('Run your business.\nAll in one place.'),
        const SizedBox(height: 14),
        const Text(
          'Sales, stock, customers and receipts — everything your team needs for a better working day.',
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => _go(_OnboardingStep.companyId),
          child: const Text('Log in'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => _go(_OnboardingStep.createAccount),
          child: const Text('Create company'),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        Text(
          'Already part of a team? Have your company ID, username and 4-digit PIN ready.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  Widget _createAccount(BuildContext context) => _page(
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Title('Create your account'),
          const SizedBox(height: 24),
          FormField<DateTime>(
            initialValue: _dateOfBirth,
            validator: (value) {
              if (value == null) return 'Enter your date of birth';
              final now = DateTime.now();
              var age = now.year - value.year;
              if (now.month < value.month ||
                  (now.month == value.month && now.day < value.day)) {
                age--;
              }
              return age >= 15
                  ? null
                  : 'Company accounts are available to people aged 15 or over';
            },
            builder: (field) => InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _busy ? null : () => _chooseDateOfBirth(field),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date of birth',
                  prefixIcon: const Icon(Icons.cake_outlined),
                  errorText: field.errorText,
                  helperText: 'Minimum age is 15. If you are under 18, use Saleo with a parent, guardian or responsible adult. Your birth date is not stored.',
                ),
                child: Text(
                  _dateOfBirth == null
                      ? 'Select date'
                      : _dateLabel(_dateOfBirth!),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _username,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: _required('Enter a username'),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email address',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: (value) {
              final email = value?.trim() ?? '';
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 116,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _chooseCountry,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Code'),
                    child: Row(
                      children: [
                        Text(_country.flagEmoji),
                        const SizedBox(width: 6),
                        Text('+${_country.phoneCode}'),
                        const Spacer(),
                        const Icon(Icons.arrow_drop_down, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                  validator: (value) {
                    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                    return digits.length < 6 ? 'Enter a valid number' : null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _password,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) =>
                (value ?? '').length < 8 ? 'Use at least 8 characters' : null,
          ),
          _errorView(),
          const SizedBox(height: 20),
          _primaryButton('Continue', _register),
          const SizedBox(height: 18),
          TextButton(
            onPressed: () => _go(_OnboardingStep.companyId),
            child: const Text('Already have an account? Log in'),
          ),
        ],
      ),
    ),
  );

  void _chooseCountry() => showCountryPicker(
    context: context,
    showPhoneCode: true,
    favorite: const ['GH', 'NG', 'GB', 'US'],
    countryListTheme: const CountryListThemeData(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      bottomSheetHeight: 650,
    ),
    onSelect: (country) => setState(() => _country = country),
  );

  Widget _verifyEmail(BuildContext context) => _page(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Title('Verify your email'),
        const SizedBox(height: 28),
        const _RoundIcon(Icons.mark_email_read_outlined),
        const SizedBox(height: 24),
        const Text(
          'We sent a secure verification link to',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          _registration?.email ?? _email.text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _openEmailApp,
          child: const Text('Open email app'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () => _run(() => _auth.resendVerification(_registration!.id)),
          child: const Text('Resend email'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : () => _checkVerification(),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          child: const Text('I have verified my email'),
        ),
        _errorView(),
      ],
    ),
  );

  Widget _createPinScreen(BuildContext context) => _page(
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Title('Create your 4-digit PIN'),
          const SizedBox(height: 8),
          const Text('You will use this PIN for quick, secure sign-in.'),
          const SizedBox(height: 24),
          FourDigitPinField(
            controller: _pin,
            label: '4-digit PIN',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          FourDigitPinField(
            controller: _confirmPin,
            label: 'Confirm PIN',
            confirmingController: _pin,
            onSubmitted: _savePin,
          ),
          _errorView(),
          const SizedBox(height: 20),
          _primaryButton('Continue', _savePin),
        ],
      ),
    ),
  );

  Widget _createCompanyScreen(BuildContext context) => _page(
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Title('Create your company'),
          const SizedBox(height: 24),
          TextFormField(
            controller: _companyName,
            decoration: const InputDecoration(
              labelText: 'Company name',
              prefixIcon: Icon(Icons.business_outlined),
            ),
            validator: _required('Enter the company name'),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Choose my own Shop ID'),
            subtitle: const Text('Use a memorable format like AMA-101.'),
            value: _chooseCustomCompanyId,
            onChanged: (value) =>
                setState(() => _chooseCustomCompanyId = value),
          ),
          if (_chooseCustomCompanyId) ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _customCompanyId,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Shop ID',
                hintText: 'AAA-000',
                prefixIcon: Icon(Icons.badge_outlined),
                helperText: '3 letters, dash, 3 numbers. It must be unique.',
              ),
              validator: (value) {
                if (!_chooseCustomCompanyId) return null;
                final clean = value?.trim().toUpperCase() ?? '';
                if (!RegExp(r'^[A-Z]{3}-\d{3}$').hasMatch(clean)) {
                  return 'Use the format AAA-000';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
          ],
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _chooseCountry,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Business country',
                prefixIcon: Icon(Icons.public),
              ),
              child: Row(
                children: [
                  Text('${_country.flagEmoji}  ${_country.name}'),
                  const Spacer(),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          InkWell(
            onTap: _pickLogo,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              height: 156,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(18),
                image: _logoBytes == null
                    ? null
                    : DecorationImage(
                        image: MemoryImage(_logoBytes!),
                        fit: BoxFit.cover,
                      ),
              ),
              child: _logoBytes == null
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 44),
                        SizedBox(height: 8),
                        Text('Add company logo'),
                      ],
                    )
                  : null,
            ),
          ),
          _errorView(),
          const SizedBox(height: 22),
          _primaryButton('Create company', _createCompany),
        ],
      ),
    ),
  );

  Widget _companyCreatedScreen(BuildContext context) => _page(
    back: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle, color: Color(0xFFD5A62E), size: 54),
        const SizedBox(height: 10),
        const Text(
          'Company created',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 22),
        _CompanyIdentity(company: _company!),
        const SizedBox(height: 28),
        const Text('Your Company ID', textAlign: TextAlign.center),
        const SizedBox(height: 8),
        SelectableText(
          _company!.companyId,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Save this ID. Your team will use it to sign in.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () => _saveCompanyIdPicture(context),
          icon: const Icon(Icons.download_outlined),
          label: const Text('Save company ID as picture'),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () => _run(
            () => widget.controller.acceptAuthenticatedMember(_createdMember!),
          ),
          child: const Text('Enter dashboard'),
        ),
      ],
    ),
  );

  Future<void> _saveCompanyIdPicture(BuildContext context) async {
    final company = _company;
    if (company == null) return;
    try {
      final location = await const CompanyIdImageService().save(
        companyName: company.name,
        companyId: company.companyId,
        companyLogoBytes: _logoBytes,
      );
      if (!context.mounted || location == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Company ID picture saved to $location')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the picture: $error')),
      );
    }
  }

  Widget _companyIdScreen(BuildContext context) => _page(
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Title('Welcome back'),
          const SizedBox(height: 8),
          const Text('Enter your company ID to continue'),
          const SizedBox(height: 24),
          TextFormField(
            controller: _companyId,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Company ID',
              hintText: 'e.g. ABC-123',
              prefixIcon: Icon(Icons.business_outlined),
            ),
            validator: _required('Enter your company ID'),
            onFieldSubmitted: (_) => _findCompany(),
          ),
          _errorView(),
          const SizedBox(height: 20),
          _primaryButton('Continue', _findCompany),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _recoverCompanyId,
            child: const Text('Forgot company ID?'),
          ),
          const SizedBox(height: 18),
          TextButton(
            onPressed: () => _go(_OnboardingStep.createAccount),
            child: const Text('Create a new company'),
          ),
        ],
      ),
    ),
  );

  Widget _checkingCompany(BuildContext context) => _page(
    back: false,
    child: Column(
      children: [
        const _RoundIcon(Icons.apartment_rounded),
        const SizedBox(height: 30),
        const _Title('Checking company', center: true),
        const SizedBox(height: 26),
        const CircularProgressIndicator(),
        const SizedBox(height: 22),
        Text(
          _companyId.text.trim().toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text('Finding your company securely…'),
      ],
    ),
  );

  Widget _memberLogin(BuildContext context) => _page(
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CompanyIdentity(company: _company!),
          const SizedBox(height: 10),
          const Center(
            child: Chip(
              avatar: Icon(Icons.check_circle, size: 17),
              label: Text('Company verified'),
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _loginUsername,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: _required('Enter your username'),
          ),
          const SizedBox(height: 14),
          FourDigitPinField(
            controller: _loginPin,
            label: '4-digit PIN',
            onSubmitted: _login,
          ),
          _errorView(),
          const SizedBox(height: 20),
          _primaryButton('Sign in', _login),
          TextButton(
            onPressed: _busy ? null : _requestAdminPinReset,
            child: const Text('Forgot admin PIN?'),
          ),
          TextButton(
            onPressed: () => _go(_OnboardingStep.staffPinHelp),
            child: const Text('Receptionist forgot PIN?'),
          ),
          TextButton(
            onPressed: () => _go(_OnboardingStep.companyId),
            child: const Text('Use a different company'),
          ),
        ],
      ),
    ),
  );

  FormFieldValidator<String> _required(String message) =>
      (value) => value == null || value.trim().isEmpty ? message : null;

  Widget _primaryButton(String label, Future<void> Function() action) =>
      FilledButton(
        onPressed: _busy ? null : action,
        child: _busy
            ? SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.surface,
                ),
              )
            : Text(label),
      );

  Widget _errorView() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        );
}

class _Title extends StatelessWidget {
  const _Title(this.text, {this.center = false});
  final String text;
  final bool center;
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: center ? TextAlign.center : null,
    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 30, color: colors.onPrimaryContainer),
      ),
    );
  }
}

class _CompanyIdentity extends StatelessWidget {
  const _CompanyIdentity({required this.company});
  final CompanyPreview company;

  @override
  Widget build(BuildContext context) {
    final words = company.name.trim().split(RegExp(r'\s+'));
    final initials = words
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word[0])
        .join()
        .toUpperCase();
    final logoUrl = company.logoUrl;
    return Column(
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundImage: logoUrl == null || logoUrl.isEmpty
              ? null
              : NetworkImage(logoUrl),
          child: Text(
            initials,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
              fontSize: 20,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          company.name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}
