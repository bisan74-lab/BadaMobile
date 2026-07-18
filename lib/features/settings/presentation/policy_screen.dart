import 'package:flutter/material.dart';

import '../app_info.dart';

/// 정책 및 이용약관 화면. 무료 정보 제공 앱으로서 데이터 정확성/이용에 대한
/// 책임을 제한하는 보호성 약관을 담는다.
///
/// 주의: 아래 문구는 일반적인 보호 목적의 초안이며 법률 자문이 아니다.
/// 실제 서비스 전에는 변호사 검토를 받는 것이 좋다.
class PolicyScreen extends StatelessWidget {
  const PolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('정책 및 이용약관')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _Section(
            title: '1. 목적',
            body:
                '본 약관은 「${AppInfo.appName}」(이하 "앱")이 제공하는 물때·조석 및 '
                '바람·해양·육상 날씨 정보 서비스(이하 "서비스")의 이용 조건과 '
                '책임 범위를 정합니다. 앱을 설치하거나 이용하면 본 약관에 동의한 것으로 봅니다.',
          ),
          _Section(
            title: '2. 정보의 성격과 한계',
            body:
                '서비스가 제공하는 물때, 조석, 바람, 파고, 날씨 등 모든 정보는 '
                '공공데이터 및 제3자 기상 정보를 가공한 참고용 자료입니다. '
                '실시간 현장 상황과 다를 수 있으며, 정확성·완전성·적시성을 보증하지 않습니다. '
                '통신 상태·외부 API 사정에 따라 합성(추정) 데이터가 표시될 수 있습니다.',
          ),
          _Section(
            title: '3. 책임의 제한',
            body:
                '이용자는 서비스 정보를 참고 자료로만 활용해야 하며, 낚시·항해·레저 등 '
                '안전과 관련된 최종 판단과 그 결과에 대한 책임은 전적으로 이용자 본인에게 있습니다. '
                '개발자는 서비스 정보의 이용 또는 이용 불능으로 발생한 어떠한 직접·간접·부수적 '
                '손해(인명·재산 피해 포함)에 대해서도 관련 법이 허용하는 최대 범위에서 책임을 지지 않습니다. '
                '기상 특보·경보 등 공식 정보는 반드시 기상청 등 공식 기관을 통해 확인하십시오.',
          ),
          _Section(
            title: '4. 서비스의 변경·중단',
            body:
                '개발자는 사전 고지 없이 서비스의 전부 또는 일부를 변경·중단하거나, '
                '무료 서비스를 유료(광고 제거 등) 버전으로 전환할 수 있습니다.',
          ),
          _Section(
            title: '5. 개인정보',
            body:
                '앱은 회원가입을 요구하지 않으며, 지역 선택·즐겨찾기·설정 값은 이용자 기기 내에만 '
                '저장됩니다. 개발자는 이러한 개인 식별 정보를 서버로 수집하지 않습니다. '
                '광고가 포함된 버전에서는 광고 제공자가 별도의 정책에 따라 정보를 수집할 수 있습니다.',
          ),
          _Section(
            title: '6. 지식재산권',
            body:
                '앱의 디자인·코드·상표에 대한 권리는 개발자에게 있으며, 원 데이터의 저작권은 '
                '각 제공 기관에 있습니다.',
          ),
          _Section(
            title: '7. 문의',
            body: '서비스 관련 문의는 ${AppInfo.contactEmail} 로 연락 주십시오.',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            body,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}
