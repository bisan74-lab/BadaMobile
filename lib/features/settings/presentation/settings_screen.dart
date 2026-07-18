import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../app_info.dart';
import 'policy_screen.dart';
import 'providers.dart';

/// 설정 화면 — 템플릿과 정보를 한 화면에 세로로 나열한다.
/// 맨 위 "템플릿"을 펼치면 앱 테마·밝기·배경 그래픽을 고를 수 있고,
/// 그 아래로 문의·버전·광고 제거·약관 정보가 순서대로 이어진다.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: const [
          _TemplateSection(),
          Divider(height: 1),
          _InfoSection(),
        ],
      ),
    );
  }
}

/// 템플릿(테마/그래픽) — 펼치면 옵션이 나온다. 기본으로 펼쳐 둔다.
class _TemplateSection extends ConsumerWidget {
  const _TemplateSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = ref.watch(skinProvider);
    final mode = ref.watch(themeModeProvider);
    final backdrop = ref.watch(backdropEnabledProvider);
    final scheme = Theme.of(context).colorScheme;

    return ExpansionTile(
      initiallyExpanded: true,
      leading: const Icon(Icons.palette_outlined),
      title: const Text('템플릿'),
      subtitle: Text('앱 테마 · 밝기 · 배경 그래픽  (현재: ${skin.name})'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        _label(context, '앱 테마'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final s in appSkins)
              _SkinChip(
                skin: s,
                selected: s.id == skin.id,
                onTap: () => ref.read(skinProvider.notifier).select(s),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _label(context, '밝기 모드'),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              label: Text('시스템'),
              icon: Icon(Icons.brightness_auto),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              label: Text('라이트'),
              icon: Icon(Icons.light_mode),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text('다크'),
              icon: Icon(Icons.dark_mode),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (s) =>
              ref.read(themeModeProvider.notifier).select(s.first),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(Icons.image_outlined, color: scheme.primary),
          title: const Text('배경 그래픽'),
          subtitle: const Text('물때 타임라인 등에 바다 일러스트 배경 표시'),
          value: backdrop,
          onChanged: (v) => ref.read(backdropEnabledProvider.notifier).set(v),
        ),
      ],
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}

/// 앱 테마 색상 칩(원형 색 + 이름).
class _SkinChip extends StatelessWidget {
  const _SkinChip({
    required this.skin,
    required this.selected,
    required this.onTap,
  });

  final AppSkin skin;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 10, backgroundColor: skin.seed),
            const SizedBox(width: 8),
            Text(skin.name),
            if (selected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle, size: 16, color: scheme.primary),
            ],
          ],
        ),
      ),
    );
  }
}

/// 개발자·앱 정보 — 템플릿 아래에 순서대로 나열.
class _InfoSection extends StatelessWidget {
  const _InfoSection();

  @override
  Widget build(BuildContext context) {
    return Column(
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
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PolicyScreen()),
          ),
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
                    const SnackBar(
                      content: Text('인앱 결제는 정식 배포 후 제공될 예정입니다.'),
                    ),
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
