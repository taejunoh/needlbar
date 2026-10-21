# Needlbar 경쟁 앱 비교

기준일: 2026-10-07 (America/New_York)

> **날짜가 고정된 조사 스냅샷:** 이 문서는 2026-10-07 공개 자료를 바탕으로
> 작성되었으며 v0.3.9 전의 Needlbar 상태를 비교합니다. 2026-10-20 현재의
> 제품·경쟁 앱 조사나 최신 기능 목록이 아닙니다. 아래 우선순위는 당시
> 제안이며 승인된 구현 요구사항이 아닙니다.

## 결론

시스템 모니터링의 깊이에서는 Stats와 iStat Menus가 Needlbar보다 앞선다. AI 제공자 지원 폭과 quota·credit·reset 표시에서는 CodexBar가 앞선다. Needlbar의 구분점은 시스템 상태와 AI 사용량·quota를 한 메뉴바 흐름에 결합하는 점이지 어느 한 범주의 독점은 아니다. 현재 경쟁력을 키우려면 특히 Claude quota의 신뢰할 수 있고 확인 가능한 최신성이 필요하다.

아래 평가는 각 앱의 2026-10-07 기준 공식 릴리스와 문서에 한정한다. 표기된 동작은 제품 문서에 있는 기능이며 모든 Mac에서의 실시간 수집 성능을 뜻하지 않는다.

## 제품 비교

| 항목 | Needlbar | Stats | iStat Menus | CodexBar |
|---|---|---|---|---|
| 기준 릴리스·플랫폼 | [v0.3.8 (10월 5일)](https://github.com/taejunoh/needlbar/releases/tag/v0.3.8), build 11 확인. macOS 14+, arm64. [README](../../README.md), [STATUS](../STATUS.md) | [v3.0.20 (10월 4일)](https://github.com/exelban/stats/releases/tag/v3.0.20), macOS 12+. 단일 DMG로 architecture 미단정. [README](https://github.com/exelban/stats/blob/v3.0.20/README.md) | [7.5 (9월 14일)](https://bjango.com/mac/istatmenus/versionhistory/), macOS 11+. 공식 페이지에서 architecture 미확인. [제품](https://bjango.com/mac/istatmenus/) | [v0.72.0 (10월 4일)](https://github.com/steipete/CodexBar/releases/tag/v0.72.0), macOS 14+, universal 앱. [README](https://github.com/steipete/CodexBar/blob/v0.72.0/README.md) |
| CPU · RAM · Disk · Network · Battery | CPU 하드웨어/사용률·코어별 막대; RAM 사용·가용·압축·wired·swap·압력; 시스템 볼륨 용량/I/O; 합산 네트워크 속도; 배터리 잔량·충전·health. 1초 갱신. [README](../../README.md#system-monitor-v030), [모델](../../Sources/NeedlbarCore/SystemMetrics/SystemMetricModels.swift) | CPU/GPU/RAM/Disk/Network/Battery 모니터. [README](https://github.com/exelban/stats/blob/v3.0.20/README.md) | CPU 코어/이력·앱별 상위; RAM 압력/앱별; SMART·앱별 Disk; 인터페이스·앱별 Network; 배터리와 주변기기 잔량. [제품 기능](https://bjango.com/mac/istatmenus/) | v0.72.0 문서는 AI 사용량/비용 중심, 시스템 자원 모니터링은 문서화하지 않음. [README](https://github.com/steipete/CodexBar/blob/v0.72.0/README.md) |
| GPU · 센서 · 팬 | GPU, 온도, 팬, 센서, 프로세스별 CPU/RAM 제외. [v0.3 설계](../superpowers/specs/2026-09-02-needlbar-v0.3-system-monitor-design.md#22-explicit-exclusions) | GPU·온도/전압/전력 센서 포함. 팬 제어는 legacy·비유지. [README](https://github.com/exelban/stats/blob/v3.0.20/README.md), [릴리스](https://github.com/exelban/stats/releases/tag/v3.0.20) | 지원 Mac에서 GPU 메모리/온도/주파수, 실시간 센서·팬·센서 기반 팬 제어. [제품 기능](https://bjango.com/mac/istatmenus/) | 해당 릴리스 문서에서 시스템 자원 모니터링은 문서화하지 않음. |
| AI 제공자·quota·reset | Claude Code·Codex·Cursor 사용량/추정 비용; Claude·Codex quota/reset. Cursor quota는 Spending 링크만 제공. [README](../../README.md#provider-support), [Cursor 안내](../providers/cursor.md) | AI quota 연결 문서화 안 됨. | 확인한 제품/버전 페이지에서 AI quota 연결 문서화 안 됨. | Codex·Claude·Cursor·Gemini·Copilot·OpenAI 등. 세션/주/월 quota, reset countdown, 기록된 quota burndown, credits/spend를 출처별로 표시. [v0.72 README](https://github.com/steipete/CodexBar/blob/v0.72.0/README.md) |
| Claude/Fable·최신성 | 직접 quota 실패 시 last-known/확인 시각 보존. opt-in status line은 CLI의 5시간/7일 창과 receipt만 전달하며 Fable/polling 없음. 10월 7일 Settings 관찰은 복구 확인일 뿐 무인 지속 갱신은 미검증. [Claude 안내](../providers/claude.md), [README](../../README.md#claude-code-status-line-quota-source-v035), [runtime](../STATUS.md) | AI quota 연결 문서화 안 됨. | AI quota 연결 문서화 안 됨. | 앱의 기본 Claude 선택 순서 OAuth API → CLI PTY → Web API; 사용자 설정 refresh와 stale 값 나이 표시. Keychain 정책상 수동 복구가 필요할 수 있다. 모델별 주간 창은 소스가 제공하는 경우 표시하므로 Needlbar Fable과 일대일 지원 등가로 단정하지 않는다. [Claude v0.72 문서](https://github.com/steipete/CodexBar/blob/v0.72.0/docs/claude.md) |
| 비용·credit·API billing | 로컬 토큰/가격 기준 추정은 청구액이 아니다. Claude API Billing은 Console 링크만, API 잔액 조회는 안 함. [README](../../README.md#claude-api-billing-link-and-feasibility-harness), [Analytics](../../README.md#v022-local-repository-analytics) | AI 비용/credit 기능 미확인. | AI 비용/credit 기능 미확인. | Admin API spend, balance/credits와 로컬 추정 비용을 구분. Claude Admin API spend는 조직 사용량 보고이지 선불 API 잔액이 아니다. [README](https://github.com/steipete/CodexBar/blob/v0.72.0/README.md), [Claude](https://github.com/steipete/CodexBar/blob/v0.72.0/docs/claude.md) |
| 메뉴바·제어 | 통합 2줄 메뉴바/dashboard; 표면별 모듈/제공자 순서·표시·지표 설정. [README](../../README.md#system-monitor-v030) | 개별 아이콘 또는 combined popup. [릴리스](https://github.com/exelban/stats/releases/tag/v3.0.20) | 아이템 표시, 색상, 순서 사용자화와 Combined. [제품](https://bjango.com/mac/istatmenus/) | 개별/합친 아이콘, provider switcher, 설정 가능 refresh. 새 설치 Adaptive 2–30분; 고정 1·2·5·15·30분 또는 수동. [README](https://github.com/steipete/CodexBar/blob/v0.72.0/README.md), [refresh loop](https://github.com/steipete/CodexBar/blob/v0.72.0/docs/refresh-loop.md) |
| Widgets·알림 | 중간 크기 Overview widget; opt-in Claude/Codex quota 알림. 시스템 지표는 widget/alert 미포함. macOS 14 arm64 수용 미완료. [README](../../README.md#widget-and-quota-notifications), [제한](../../README.md#known-limitations-and-documentation) | desktop widgets 기본 off; README는 `chronod` 부하 문제로 설명. [README](https://github.com/exelban/stats/blob/v3.0.20/README.md) | 시스템 지표 알림 Rules. 현행 위젯은 확인하지 못함. [Rules](https://bjango.com/help/istatmenus7/rules/), [제품](https://bjango.com/mac/istatmenus/) | 지원 provider WidgetKit widget, opt-in quota alert/reset 효과. [README](https://github.com/steipete/CodexBar/blob/v0.72.0/README.md) |
| 가격·라이선스 | 공개 arm64 릴리스; Needlbar source MIT. 문서에 제품 가격 미표기. [릴리스](https://github.com/taejunoh/needlbar/releases/tag/v0.3.8), [LICENSE](../../LICENSE) | 무료 오픈소스, MIT. [README](https://github.com/exelban/stats/blob/v3.0.20/README.md) | 상용 앱, 14일 무료 체험; 단독 라이선스 수치 가격은 확인 불가. 별도 Setapp 구독도 안내. [공식 페이지](https://bjango.com/mac/istatmenus/) | 무료 오픈소스, MIT. universal macOS 앱. [공식 사이트](https://codexbar.app/), [릴리스](https://github.com/steipete/CodexBar/releases/tag/v0.72.0) |

## 개인정보와 근거의 경계

- Needlbar는 계정·backend·hosted sync·telemetry 없이 알려진 로컬 사용 기록을 읽는다. Claude/Codex quota 요청은 각 제공자에게 직접 전송된다. 프롬프트, 응답, 소스 코드, 로컬 이력은 업로드하지 않는다고 정책에 명시한다. 단, public IP 옵션을 켜면 고정 ipify endpoint에 제한된 요청을 보낸다. [개인정보 안내](../privacy.md)
- Stats README는 telemetry/analytics가 없다고 하지만 업데이트 확인 및 public IP를 위한 자체 endpoint 요청을 설명한다. Remote/headless 모드는 사용자가 승인하면 지표를 Stats 계정으로 스트리밍한다. 따라서 Stats 전체를 “네트워크를 사용하지 않는다”고 요약하지 않는다. [v3.0.20 README](https://github.com/exelban/stats/blob/v3.0.20/README.md)
- iStat Menus는 광고·analytics·추적이 없다고 설명한다. [제품 페이지](https://bjango.com/mac/istatmenus/)
- CodexBar는 로컬 파싱을 기본으로 설명하지만, provider에 따라 브라우저 cookie·Keychain·API key·CLI 접근이 사용될 수 있다. Claude OAuth fallback은 키체인 정책상 수동 복구나 사용자 권한을 요구할 수 있다. [README](https://github.com/steipete/CodexBar/blob/v0.72.0/README.md), [Claude 문서](https://github.com/steipete/CodexBar/blob/v0.72.0/docs/claude.md)
- Needlbar 기능 설명과 코드가 존재하는 것은 공개 아카이브의 모든 UI 상태를 실기에서 재검증했다는 뜻이 아니다. 특히 Overview 위젯의 macOS 14 arm64 수용 검증과 Claude quota의 지속적인 무인 최신성은 아직 확인 범위 밖이다. [README acceptance 한계](../../README.md#native-macos-14-acceptance-maintainer-only), [10월 7일 상태](../STATUS.md)

## 우선순위 제안

아래는 비교 자료에 따른 판단이며 승인된 구현 계획은 아니다.

1. **Claude quota의 자동 복구와 최신성 증거를 먼저 강화한다.** 값의 출처와 마지막 성공 시각을 유지하고, status-line receipt와 provider fetch를 혼동하지 않도록 한다. 성공·실패·stale 전환을 실제 실행 기록으로 확인할 수 있어야 한다.
2. **좁은 메뉴바에서도 핵심 정보가 바로 읽히도록 compact hierarchy를 다듬는다.** 한눈에 볼 상태와 펼쳐 볼 설명의 경계를 명확히 해 Stats/iStat의 정보 밀도와 CodexBar의 reset 가시성에 대응한다.
3. **GPU/팬 기능 확장보다 AI 비용·quota 워크플로의 차별점을 선명하게 한다.** 로컬 추정 비용, subscription quota, reset, 제공자 billing link의 의미를 구분해 표현한다. 별도 시스템 센서 경쟁에 기능을 넓히기보다 Stats/iStat + CodexBar를 함께 쓰는 것보다 편한 통합 경험을 만든다는 방향을 검토한다.

벤치마크 결과는 수집하지 않았다. 따라서 앱 간 CPU/RAM 사용량, polling 부하, 배터리 영향에 관한 수치나 “더 가볍다”는 성능 주장은 하지 않는다.
