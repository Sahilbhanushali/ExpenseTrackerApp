import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/app_lock_service.dart';

/// Full-screen PIN gate shown at app launch (and on resume) when app lock
/// is enabled. Tries biometrics first if available, falls back to PIN.
class UnlockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const UnlockScreen({super.key, required this.onUnlocked});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _pinController = TextEditingController();
  String? _error;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final available = await AppLockService.instance.canUseBiometrics();
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
    if (available) _tryBiometric();
  }

  Future<void> _tryBiometric() async {
    final ok = await AppLockService.instance.authenticateWithBiometrics();
    if (ok && mounted) widget.onUnlocked();
  }

  Future<void> _submitPin() async {
    final ok = await AppLockService.instance.verifyPin(_pinController.text);
    if (ok) {
      widget.onUnlocked();
      return;
    }
    HapticFeedback.heavyImpact();
    setState(() => _error = 'Wrong PIN');
    _pinController.clear();
  }

  @override
  Widget build(BuildContext context) {
    // Stacked directly over HomeShell while locked, so it must paint an
    // opaque ground of its own.
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: p.inkSurface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_rounded,
                      size: AppIconSize.xl,
                      color: p.onInk,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Enter your PIN',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _pinController,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(letterSpacing: 8),
                    decoration: InputDecoration(
                      counterText: '',
                      errorText: _error,
                    ),
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _submitPin(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitPin,
                      child: const Text('Unlock'),
                    ),
                  ),
                  if (_biometricAvailable) ...[
                    const SizedBox(height: AppSpacing.md),
                    TextButton.icon(
                      onPressed: _tryBiometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Use biometrics'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two-step PIN creation, used from Settings when app lock is switched on.
/// Returns true on success, null/false if the user backed out.
class SetPinScreen extends StatefulWidget {
  const SetPinScreen({super.key});

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _firstPin;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submitFirst() {
    final pin = _pinController.text;
    if (pin.length < 4) {
      setState(() => _error = 'PIN must be at least 4 digits');
      return;
    }
    setState(() {
      _firstPin = pin;
      _error = null;
      _pinController.clear();
    });
  }

  Future<void> _submitConfirm() async {
    if (_confirmController.text != _firstPin) {
      setState(() {
        _error = "PINs don't match — try again";
        _firstPin = null;
        _pinController.clear();
        _confirmController.clear();
      });
      return;
    }
    await AppLockService.instance.setPin(_firstPin!);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final confirming = _firstPin != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Set up app lock')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                confirming ? 'Confirm your PIN' : 'Choose a PIN',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                key: ValueKey(confirming),
                controller: confirming ? _confirmController : _pinController,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(letterSpacing: 8),
                decoration: InputDecoration(counterText: '', errorText: _error),
                onSubmitted: (_) =>
                    confirming ? _submitConfirm() : _submitFirst(),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: confirming ? _submitConfirm : _submitFirst,
                child: Text(confirming ? 'Confirm' : 'Next'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
