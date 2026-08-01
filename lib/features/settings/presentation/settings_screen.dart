import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/ad_placeholder.dart';
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
      // 우측 탭 레일(물때날씨/Windy/설정 칩)과 겹치지 않게 본문 폭을 줄여
      // 좌측 기준으로 배치한다 — 오른쪽 여백 위에 레일이 뜬다. 레일은
      // 화면 끝 6px + 칩 46px = 52px를 차지하므로 56px면 4px 간격을 두고
      // 최대한 넓게 쓴다(64px는 틈이 너무 넓다는 사용자 피드백).
      // 맨 아래에는 물때&날씨 화면과 동일한 광고 자리를 고정해 둔다.
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(right: 56),
              children: const [
                _TemplateSection(),
                Divider(height: 1),
                _AccuracySection(),
                Divider(height: 1),
                _InfoSection(),
              ],
            ),
          ),
          const SafeArea(
            top: false,
            child: Padding(
              // 물때&날씨 화면의 하단 광고 자리와 같은 좌우/아래 여백.
              padding: EdgeInsets.fromLTRB(12, 8, 10, 8),
              child: AdPlaceholder(slot: AdSlot.settings),
            ),
          ),
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
        if (backdrop) ...[
          _label(context, '배경 사진'),
          // 물때&날씨 전체화면 배경 사진 선택(자체 생성 이미지 5종, 썸네일).
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: backgroundImageChoices.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final choice = backgroundImageChoices[i];
                final selected =
                    ref.watch(backgroundImageProvider) == choice.asset;
                return GestureDetector(
                  onTap: () => ref
                      .read(backgroundImageProvider.notifier)
                      .select(choice.asset),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 72,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? scheme.primary
                                : scheme.outlineVariant,
                            width: selected ? 2.5 : 1,
                          ),
                        ),
                        child: Image.asset(
                          choice.asset,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              ColoredBox(color: scheme.surfaceContainerLow),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        choice.label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: selected ? FontWeight.bold : null,
                          color: selected ? scheme.primary : null,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
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

/// 바다윈디가 왜 정확한 데이터를 보여주는지 설명하는 섹션(사용자 요구).
/// 데이터 출처(공식 기관)와 검증 방법을 간결한 항목으로 나열한다.
class _AccuracySection extends StatelessWidget {
  const _AccuracySection();

  static const _items = <(IconData, String, String)>[
    (
      Icons.waves,
      '물때·조위: 국립해양조사원(KHOA) 공식 데이터',
      '전국 조위관측소의 실측·예측 조위를 10분 간격으로 받아 만조·간조를 '
          '계산합니다. 전용 관측소가 없는 항구는 인접 관측소 2~3곳을 거리 '
          '가중치로 보간하고, 지형에 따른 시간차·조위차를 지점별로 보정합니다.',
    ),
    (
      Icons.fact_check_outlined,
      '전국 항구 물때 데이터',
      '국가어항·지방어항을 포함한 국내 모든 항구의 물때 데이터를 담아, '
          '어디서든 가까운 항구의 만조·간조를 확인할 수 있습니다.',
    ),
    (
      Icons.wb_sunny_outlined,
      '날씨: 기상청 + 글로벌 수치예보',
      '가까운 기간은 기상청 단기예보(공식)를 우선 쓰고, 그 이후 기간은 '
          'ECMWF 등 글로벌 수치예보 모델(Open-Meteo)로 최대 2주까지 '
          '이어 보여줍니다.',
    ),
    (
      Icons.air,
      '바람 지도: 최신 예보를 1시간 안에 반영',
      '유럽중기예보센터(ECMWF)가 하루 4회 새 예보를 공개하는 즉시 서버가 '
          '받아 지도에 반영합니다. 태풍 등 급변하는 상황도 최신 실행 기준으로 '
          '표시됩니다.',
    ),
    (
      Icons.phishing,
      '낚시지수: 해양수산부 공공데이터',
      '감성돔·농어·돌돔·벵에돔·우럭·참돔 여섯 어종의 지수는 해양수산부 '
          '공공데이터 API를 그대로 씁니다. 가장 가까운 관측 포인트를 골라 '
          '보여줍니다.',
    ),
    (
      Icons.calculate_outlined,
      '쭈꾸미·갑오징어·문어는 "추정"입니다',
      '이 세 어종은 공공데이터에 지수가 없어, 그날 조류 세기(조위 변화폭)와 '
          '바람·파고·계절로 앱이 직접 계산합니다. 관측값이 아니므로 화면에 '
          '"추정" 표시를 달아 구분하며, 참고용으로만 봐 주세요.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      leading: const Icon(Icons.verified_outlined),
      title: const Text('데이터 출처와 정확도'),
      subtitle: const Text('바다윈디의 물때·날씨가 정확한 이유'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        for (final (icon, title, body) in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
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
      query: 'subject=${Uri.encodeComponent('[바다윈디] 문의')}',
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
