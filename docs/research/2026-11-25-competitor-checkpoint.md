# Needlbar 경쟁 앱 중간점검

기준일: 2026-11-25 (America/New_York)

> **날짜가 고정된 조사 스냅샷:** 각 앱의 2026-11-25 공식 자료(GitHub 저장소·릴리스, 제품 페이지,
> 공식 문서)만 읽었다. 로그인, 다운로드, 실행은 하지 않았다. 앞선 비교는
> [2026-10-07 문서](2026-10-07-competitor-comparison.md)다. 아래 제안은 당시 판단이며 승인된
> 구현 요구사항이 아니다. 연도가 표시되지 않은 릴리스 날짜는 2026년으로 가정했다.

## 결론

AI 제공자 범위에서는 CodexBar가 더 멀리 앞서 나갔다. 시스템 모니터 쪽(Stats, iStat Menus)은
AI 기능을 추가하지 않았다. 조사한 AI 사용량 앱 대부분은 Claude Code의 토큰, 키체인 항목,
브라우저 쿠키 또는 세션 키를 읽는다. Needlbar의 다음 릴리스는 인증정보를 읽지 않고 사용자가
설치한 `claude`만 실행하며 자동 실행은 opt-in이다. 이 점과 시스템 상태·AI quota의 결합, 위젯의
Fable 표시가 구분점이다. 단, 공개된 v0.3.14는 아직 키체인을 읽으므로 이 구분점은 다음 릴리스부터
실제가 된다.

## AI 사용량 메뉴바 앱

| 앱 | 최신 버전 | 제공자 | Claude quota 출처 | 플랫폼 | 라이선스 | 10월 이후 |
|---|---|---|---|---|---|---|
| [CodexBar](https://github.com/steipete/CodexBar/releases) | 0.85.0 (11월 21일) | 약 115개 | OAuth API, 다음 `claude /usage`, 다음 웹 쿠키 API ([docs/claude.md](https://github.com/steipete/CodexBar/blob/main/docs/claude.md)) | macOS 14+, Linux, CLI | MIT | 제공자 대폭 추가, 자동 확인·설치 분리(0.82), Codex 알림(0.83), Linux 수정 |
| [Claude Usage Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker/releases) | v3.4.0 (11월 13일) | Claude, Codex | 기존 Claude Code 로그인, claude.ai 로그인, 세션 키 붙여넣기 | macOS 13+ | MIT | Claude Code 소유 토큰을 갱신하던 문제 수정(v3.2, v3.3) |
| [ClaudeBar](https://github.com/tddworks/ClaudeBar/releases) | v0.5.29 (11월 20일) | 약 31개 | 확인 못 함 | macOS 15+ | Apache-2.0 | 모델·프로젝트별 요약, 세션 상태 |
| [claude-usage-bar](https://github.com/Blimp-Labs/claude-usage-bar) | v0.0.13 (11월 19일) | Claude | 자체 브라우저 로그인, 토큰을 `credentials.json`에 저장 | macOS 14+ | BSD-2-Clause | 11월 릴리스 2회 |
| [f-is-h/Usage4Claude](https://github.com/f-is-h/Usage4Claude) | 확인 못 함 | Claude, Codex | 브라우저 로그인 또는 세션 키 | macOS 13+ | MIT | 확인 못 함 |
| [cli-usage-bar](https://github.com/svenedik/cli-usage-bar) | 약 v0.2.0 | Claude Code, Codex | Claude Code의 키체인 OAuth 토큰, 로컬 기록 대체 | macOS | MIT | 확인 못 함 |
| [CC Usage Tracker](https://github.com/pedroprates/claude-code-usage) | 알파 | Claude Code | status line `rate_limits` | macOS 14+ | MIT 표기(LICENSE 파일 없음) | 확인 못 함 |

CodexBar는 파싱을 기기 안에서 하고 브라우저 쿠키는 opt-in이며, Claude Code의 키체인 항목은
명시적으로 켠 OAuth 복구에서만 읽는다고 설명한다([README](https://github.com/steipete/CodexBar)).
Fable 같은 모델별 한도는 CodexBar 문서에서만 언급을 찾았다.

## 시스템 모니터 앱

| 앱 | 최신 버전 | 10월 이후 | AI 기능 | 가격·라이선스 |
|---|---|---|---|---|
| [Stats](https://github.com/exelban/stats/releases) | v3.1.1 (11월 22일) | GPU 상위 프로세스, 배터리 기록 차트, Remote의 배터리, public IP 엔드포인트 변경 | 없음 | 무료, MIT |
| [iStat Menus](https://bjango.com/mac/istatmenus/versionhistory/) | 7.5 (9월 14일) | 새 버전 없음 | 없음 | 유료(가격 표기 확인 못 함), Setapp 포함 |

시스템 상태와 AI 한도를 함께 보이는 앱으로 [Headroom](https://github.com/masquare/headroom)(MIT,
CLI 로그인 토큰으로 사용량 엔드포인트 호출)과 [StatsMenu](https://github.com/MariuzM/mac-stats-menu)
(라이선스·출시일 확인 못 함)를 찾았다.

## Anthropic

- [Status line](https://code.claude.com/docs/en/statusline)은 Pro, Max, Ultra에서 5시간·7일
  `rate_limits`를 준다. 모델별 값은 없다. 10월 전부터 있었다.
- Claude Code 2.1.328~2.1.332(11월 19~25일)의 변경은 `/usage`와 한도 관련 수정뿐이다
  ([changelog](https://code.claude.com/docs/en/changelog)).
- 데스크톱 앱의 입력창 아래 사용량 링이 플랜 사용량을 보인다([문서](https://code.claude.com/docs/en/desktop)).
- 공식 메뉴바나 위젯은 찾지 못했다.

## 흐름

- 인증정보를 전혀 읽지 않는 앱은 드물다. status line만 쓰는 알파 앱 하나를 찾았다.
- [법률·규정 페이지](https://code.claude.com/docs/en/legal-and-compliance)의 인증정보 조항을 언급하는
  앱은 찾지 못했다.
- Claude Code의 토큰을 다른 앱이 갱신해 로그아웃시키는 문제가 실제로 보고되었다.
- 시장은 다수 제공자로 이동했다. Claude 전용 앱은 작고 새롭다.
- 모델별 한도(Fable 등)는 거의 다뤄지지 않는다.

## 제안 (승인된 요구사항 아님)

1. 다음 릴리스를 서두른다. 인증정보를 읽지 않는다는 구분점은 공개된 버전에 들어가야 의미가 있다.
2. README 첫머리에 위치를 한 줄로 밝힌다.
3. 제공자 수로 경쟁하지 않는다. Claude·Codex·Cursor의 신뢰도와 모델별 한도에 집중한다.
4. Anthropic의 공식 메뉴바·위젯 출시 여부를 다음 점검에서 다시 본다.
