import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../app_info.dart';
import 'policy_screen.dart';
import 'providers.dart';

/// 설정 화면: 두 개의 탭으로 구성.
/// - 템플릿: 앱 스킨(색/테마) 변경
/// - 정보: 개발자 문의·버전·광고 제거·약관
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('설정'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '템플릿'),
              Tab(text: '정보'),
            ],
          ),
        ),
        body: const TabBarView(children: [_TemplateTab(), _InfoTab()]),
      ),
    );
  }
}

/// 앱 스킨(시드 색) 선택 탭.
class _TemplateTab extends ConsumerWidget {
  const _TemplateTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(skinProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('앱 테마', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          '앱의 색상 스킨을 선택하세요. 선택은 저장되어 다음 실행에도 유지됩니다.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        for (final skin in appSkins)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(backgroundColor: skin.seed),
              title: Text(skin.name),
              trailing: skin.id == current.id
                  ? Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => ref.read(skinProvider.notifier).select(skin),
            ),
          ),
      ],
    );
  }
}

/// 개발자·앱 정보 탭.
class _InfoTab extends StatelessWidget {
  const _InfoTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.mail_outline),
          title: const Text('오류신고 및 사업제휴 문의'),
          subtitle: const Text(AppInfo.contactEmail),
          onTap: () => _sendMail(context),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('앱 버전'),
          subtitle: const Text(
            'v${AppInfo.appVersion} · 릴리즈 ${AppInfo.releaseDate}',
          ),
        ),
        const Divider(),
        ListTile(
          leading: Icon(
            Icons.workspace_premium_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text('광고 제거'),
          subtitle: const Text('유료 결제로 광고 없는 버전으로 업그레이드'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showRemoveAds(context),
        ),
        ListTile(
          leading: const Icon(Icons.policy_outlined),
          title: const Text('정책 및 이용약관'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const PolicyScreen())),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            '${AppInfo.appName}  v${AppInfo.appVersion}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _sendMail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppInfo.contactEmail,
      query: 'subject=${Uri.encodeComponent('[바다 윈디] 문의')}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('메일 앱을 열 수 없습니다: ${AppInfo.contactEmail}'),
        ),
      );
    }
  }

  void _showRemoveAds(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('광고 제거', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text(
              '광고 없는 버전으로 업그레이드할 수 있습니다.\n'
              '인앱 결제는 스토어 배포 후 활성화됩니다.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.workspace_premium),
                label: const Text('업그레이드 (준비 중)'),
                onPressed: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('인앱 결제는 정식 배포 후 제공될 예정입니다.')),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
