import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _infoMessage;

  void _showMessage(String text, {bool isError = false}) {
    if (!mounted) return;
    setState(() => _infoMessage = text);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      if (_isLogin) {
        await supabase.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        _showMessage('Signed in successfully.');
      } else {
        final response = await supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          data: {'name': _nameController.text.trim()},
        );

        if (response.session == null) {
          _showMessage(
              'Account created. Please check your email and confirm your account before signing in.');
          setState(() => _isLogin = true);
        } else {
          _showMessage('Account created and signed in.');
        }
      }
    } on AuthException catch (e) {
      final raw = e.message.toLowerCase();
      if (raw.contains('email not confirmed')) {
        _showMessage(
          'Your email is not confirmed yet. Please check your inbox.',
          isError: true,
        );
      } else if (raw.contains('invalid login credentials')) {
        _showMessage('Invalid email or password.', isError: true);
      } else {
        _showMessage(e.message, isError: true);
      }
    } catch (e) {
      _showMessage('An error occurred: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _isLogin ? 'Welcome Back' : 'Create Account',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isLogin
                      ? 'Sign in to continue'
                      : 'Sign up with your email and password',
                  style: const TextStyle(color: Colors.grey),
                ),
                if (_infoMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade700),
                    ),
                    child: Text(
                      _infoMessage!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (!_isLogin)
                  TextFormField(
                    controller: _nameController,
                    style: const TextStyle(fontFamily: 'Roboto'),
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a name';
                      }
                      return null;
                    },
                  ),
                if (!_isLogin) const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  style: const TextStyle(fontFamily: 'Roboto'),
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter an email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  style: const TextStyle(fontFamily: 'Roboto'),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                if (_isLoading)
                  const CircularProgressIndicator()
                else
                  ElevatedButton(
                    onPressed: _submitForm,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: Text(_isLogin ? 'Login' : 'Create Account'),
                  ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isLogin = !_isLogin;
                      _infoMessage = null;
                    });
                  },
                  child: Text(
                    _isLogin
                        ? 'Create a new account'
                        : 'I already have an account',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }
}
