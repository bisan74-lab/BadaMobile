import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/remote_config/app_gate_config.dart';

/// 강제 업데이트 화면. `AppGateConfig.forceUpgrade`가 true일 때 [AppShell]
/// 대신 이 화면이 뜨고, 뒤로가기로도 앱 본 화면에 들어갈 수 없다(`home:`
/// 자리를 통째로 대체하므로 되돌아갈 라우트 자체가 없다).
class ForceUpgradeScreen extends StatelessWidget {
  const ForceUpgradeScreen({super.key, required this.config});

  final AppGateConfig config;

  Future<void> _openStore(BuildContext context) async {
    final uri = Uri.tryParse(config.storeUrl);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('스토어 페이지를 열 수 없습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.system_update_alt,
                  size: 72,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  '업데이트가 필요합니다',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  config.message,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () => _openStore(context),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Text('업데이트하기'),
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
