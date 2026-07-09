import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/config_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _apiKeyController;
  late TextEditingController _tokenController;
  late TextEditingController _clientIdController;

  @override
  void initState() {
    super.initState();
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    _apiKeyController = TextEditingController(text: configProvider.tokens.apiKey);
    _tokenController = TextEditingController(text: configProvider.tokens.accessToken);
    _clientIdController = TextEditingController(text: configProvider.tokens.serverClientId);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _tokenController.dispose();
    _clientIdController.dispose();
    super.dispose();
  }

  Future<void> _launchConsoleUrl() async {
    final uri = Uri.parse('https://console.cloud.google.com/apis/library/drive.googleapis.com?organizationId=0&project=video-stream-501418');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch $uri';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot open link: $e')),
        );
      }
    }
  }

  void _saveConfig() async {
    FocusScope.of(context).unfocus();
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    
    await configProvider.saveConfig(
      _apiKeyController.text,
      _tokenController.text,
      _clientIdController.text,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration saved!')),
      );
    }
  }

  void _testConnection() async {
    FocusScope.of(context).unfocus();
    // Save first
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    await configProvider.saveConfig(
      _apiKeyController.text,
      _tokenController.text,
      _clientIdController.text,
    );

    final success = await configProvider.testConnection();
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection successful! Root folders loaded.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: ${configProvider.errorMessage}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _clearConfig() async {
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    await configProvider.clearConfig();
    _apiKeyController.clear();
    _tokenController.clear();
    _clientIdController.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration cleared.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final configProvider = Provider.of<ConfigProvider>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('API Credentials'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.orange, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            'Configuration Guide',
                            style: theme.textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '1. Open Google Cloud Console to enable Google Drive API for your project.\n'
                        '2. Generate an API Key (Credential Type: User Data) to play publicly shared files.\n'
                        '3. Retrieve an OAuth2 Access Token to view and browse private files.',
                        style: TextStyle(height: 1.5, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _launchConsoleUrl,
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Open GCP Drive API Console'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Google Login Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.account_circle, color: Colors.orange, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            'Google Drive Account',
                            style: theme.textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      configProvider.isGoogleSignedIn
                          ? Row(
                              children: [
                                if (configProvider.firebaseUser?.photoURL != null)
                                  CircleAvatar(
                                    backgroundImage: NetworkImage(configProvider.firebaseUser!.photoURL!),
                                    radius: 24,
                                  )
                                else
                                  const CircleAvatar(
                                    backgroundColor: Colors.orange,
                                    radius: 24,
                                    child: Icon(Icons.person, color: Colors.white),
                                  ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        configProvider.firebaseUser?.displayName ?? 'Connected User',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        configProvider.firebaseUser?.email ?? '',
                                        style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                                 IconButton(
                                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                                  tooltip: 'Sign Out',
                                  onPressed: () async {
                                    await configProvider.signOutGoogle();
                                    if (!mounted) return;
                                    _tokenController.clear();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Signed out successfully')),
                                    );
                                  },
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Sign in with your Google account to automatically connect your Google Drive and list all video folders.',
                                  style: TextStyle(fontSize: 13, height: 1.4),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: configProvider.isLoading
                                      ? null
                                      : () async {
                                          final success = await configProvider.signInWithGoogle();
                                          if (!mounted) return;
                                          if (success) {
                                            _tokenController.text = configProvider.tokens.accessToken;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Connected: ${configProvider.googleAccount?.email}'),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          } else if (configProvider.errorMessage.isNotEmpty) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(configProvider.errorMessage),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
                                        },
                                  icon: const Icon(Icons.login, size: 20),
                                  label: const Text('Sign In with Google'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Inputs Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Credentials Setup',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _apiKeyController,
                        decoration: const InputDecoration(
                          labelText: 'API Key (Public files & VLC streaming)',
                          hintText: 'Enter your GCP API Key',
                          prefixIcon: Icon(Icons.key, color: Colors.orange),
                        ),
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _clientIdController,
                        maxLines: 2,
                        minLines: 1,
                        decoration: const InputDecoration(
                          labelText: 'Google OAuth Client ID (for Android Login)',
                          hintText: 'Enter Web Client ID from GCP Console',
                          prefixIcon: Icon(Icons.badge, color: Colors.orange),
                        ),
                        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _tokenController,
                        maxLines: 3,
                        minLines: 1,
                        decoration: const InputDecoration(
                          labelText: 'OAuth2 Access Token (Private files)',
                          hintText: 'Paste OAuth2 Bearer Access Token here',
                          prefixIcon: Icon(Icons.vpn_key_outlined, color: Colors.orange),
                        ),
                        style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Connection Status Card
              if (configProvider.connectionStatus != ConnectionStatus.idle)
                Card(
                  color: _getStatusColor(configProvider.connectionStatus).withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: _getStatusColor(configProvider.connectionStatus),
                      width: 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _getStatusIcon(configProvider.connectionStatus),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getStatusText(configProvider.connectionStatus),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _getStatusColor(configProvider.connectionStatus),
                                ),
                              ),
                              if (configProvider.connectionStatus == ConnectionStatus.failed &&
                                  configProvider.errorMessage.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  configProvider.errorMessage,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ]
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              // Actions Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _clearConfig,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.redAccent),
                        foregroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Clear All'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: configProvider.isLoading ? null : _testConnection,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: configProvider.connectionStatus == ConnectionStatus.testing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Save & Test Connection', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _saveConfig,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Save Settings Only'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.testing:
        return Colors.orange;
      case ConnectionStatus.connected:
        return Colors.green;
      case ConnectionStatus.failed:
        return Colors.red;
      case ConnectionStatus.idle:
        return Colors.grey;
    }
  }

  Widget _getStatusIcon(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.testing:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
        );
      case ConnectionStatus.connected:
        return const Icon(Icons.check_circle, color: Colors.green, size: 24);
      case ConnectionStatus.failed:
        return const Icon(Icons.error, color: Colors.red, size: 24);
      case ConnectionStatus.idle:
        return const Icon(Icons.help_outline, color: Colors.grey, size: 24);
    }
  }

  String _getStatusText(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.testing:
        return 'Testing connection to Google Drive API...';
      case ConnectionStatus.connected:
        return 'Successfully connected to Google Drive API!';
      case ConnectionStatus.failed:
        return 'Connection Failed';
      case ConnectionStatus.idle:
        return '';
    }
  }
}
