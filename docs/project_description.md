# Lilt

## 영어 프롬프트 교정 도구 구현 보고서

**작성일:** 2026-10-08  
**개발 단계:** MVP 구현·설치 완료  
**환경:** Windows 네이티브 / PowerShell 7 / Codex CLI / 기존 Vim  
**교정 모델:** `gpt-6-luna`, 추론 강도 `medium`  
**구현 언어:** PowerShell + CMD  
**WSL 사용:** 제외

## 1. 목표와 실행 흐름

Codex CLI에서 작성한 영어·한국어 혼합 프롬프트를 자연스러운 영어로 교정한다. 사용자는 제안을 참고해 원문을 직접 수정하며, 저장한 원문만 Codex 입력창으로 돌려받는다. AI가 원문을 자동으로 덮어쓰거나 초안에 적힌 코딩 작업을 실행하지 않는다.

원래 의미와 기술적 요구사항, 경로, 명령, 코드, 식별자, 숫자를 보존하고 수정이 필요한 영어만 고친다. 개별 수정사항을 개수 제한 없이 모두 나열하며, 각 항목에서 무엇을 왜 수정했는지 한국어로 간결하게 설명한다.

```text
새 PowerShell 터미널에서 codex 실행
    → 프로필의 codex 함수가 enable.ps1을 자동 실행
    → 프롬프트 작성 중 Ctrl+G
    → VISUAL의 lilt.cmd
    → PowerShell 교정 스크립트
    → 백그라운드 codex exec: gpt-6-luna medium 시작
    → 즉시 Vim 좌우 분할: 왼쪽 원문 / 오른쪽 읽기 전용 Coaching... 표시
    → 응답 완료 시 오른쪽 제안만 자동 갱신
    → 원문 직접 수정 후 :wqa
    → Codex 입력창 복귀
    → 사용자가 Enter로 실제 작업 실행
```

Codex 실행 파일과 소스는 수정하지 않는다. PowerShell 프로필에 등록한 함수로 `codex` 실행을 감싸 교정기를 자동 활성화하고, 종료 후 환경변수를 복원한다. Neovim 대신 기존 Vim을 사용한다.

## 2. 파일과 설치

```text
프로젝트/
  src/
    bin/
      lilt.cmd
      lilt.ps1
      coach.ps1
      suggestion.vim
    prompts/
      editing-feedback-prompt.txt
    enable.ps1
    codex-function.ps1
  scripts/
    install.ps1
  README.md
  tests/
    smoke.ps1
    live.ps1
```

저장소에서는 설치 대상 코드를 `src/`, 설치 진입 스크립트를 `scripts/`에 둔다. `scripts/install.ps1`은 의존성을 확인하고 `src/`의 파일을 `%USERPROFILE%\.lilt`에 설치한 뒤 PowerShell 프로필에 등록 블록을 추가한다. 설치 후 복사된 `install.ps1`은 설치 파일 옆에서 실행되어 재설치와 제거를 지원한다. 재설치 시 프로필 블록을 갱신하고, 기존 프로필은 최초 수정 시 백업한다. `-Uninstall`은 등록 블록만 제거한다. 다른 설치 경로는 `-InstallPath`, 다른 프로필은 `-ProfilePath`로 지정할 수 있다.

현재 PC에는 다음 버전으로 설치하고 검증했다.

| 구성 | 확인 결과 |
|---|---|
| PowerShell | 7.6.6 |
| Codex CLI | 0.161.0, 기존 ChatGPT 로그인 사용 |
| Vim | Git for Windows에 포함된 9.2 |
| 설치 위치 | `C:\Users\smg99\.lilt` |

## 3. 세션 활성화와 Git 편집기

```powershell
codex
```

`enable.ps1`은 현재 PowerShell 프로세스의 환경변수만 변경한다.

| 변수 | 처리 |
|---|---|
| `VISUAL` | 공백 경로를 지원하도록 따옴표로 감싼 CMD 래퍼 경로를 지정한다. |
| `GIT_EDITOR` | 기존 값이 있으면 유지한다. 없으면 `VISUAL` 변경 전에 `git var GIT_EDITOR`로 확인한 편집기를 지정한다. |
| `LILT_VIM` | 교정 스크립트가 사용할 실제 Vim 경로를 지정한다. 이 도구 자체의 변수이며 Codex가 직접 읽는 변수는 아니다. |

현재 PC의 기존 Git 편집기는 `C:/Program Files/Git/usr/bin/vim.exe`다. Codex가 실행한 Git도 이 편집기를 사용한다. 다른 터미널에는 변경이 전달되지 않는다. 같은 세션에서 `VISUAL`을 사용하는 Git 이외의 프로그램은 교정기를 호출할 수 있다.

반복 활성화 시 최초 환경변수 값을 보존한다. 다음 명령은 그 값을 복원하며, 원래 없었던 변수는 제거한다.

```powershell
& "$env:USERPROFILE\.lilt\enable.ps1" -Disable
```

설치 후 새 PowerShell을 열면 `codex` 함수가 자동 등록된다. 함수가 내부적으로 `enable.ps1`을 실행하고 실제 `codex.exe`에 인수를 전달한 뒤, 종료 시 환경변수를 복원한다. 수동으로 이미 활성화한 세션은 그대로 유지한다. 하위 PowerShell에서 중첩 실행할 때는 표시 변수를 확인해 재활성화를 생략한다.

## 4. 교정 호출과 원문 보호

교정 스크립트의 필수 첫 인수는 원문 파일 경로다. 원문을 UTF-8로 읽고 교정 지침과 JSON 문자열로 인코딩한 초안을 표준 입력으로 전달한다. 지침은 JSON 이스케이프를 한 번만 해석하고 경로와 코드의 실제 문자를 그대로 보존하도록 명시한다.

의도와 목적이 분명한 부분은 문법뿐 아니라 문장 구조와 정보 순서를 다듬어 작업, 제약, 기대 결과를 명확하게 전달한다. 모호하거나 빠진 내용은 수정안에서 임의로 확정하지 않고, 별도의 `Recommendations` 섹션에서 확인할 질문이나 보충할 정보를 한국어로 제안한다. 출력은 `Suggested Prompt`, `Changes`, `Recommendations`의 세 섹션으로 구성한다.

호출마다 고유한 임시 폴더를 만들고 최종 답변 `suggestion.md`와 실행 로그를 보관한다. 편집기 종료 후 해당 폴더만 제거한다. 원문 파일은 정리 대상에 포함하지 않는다.

`coach.ps1`은 숨겨진 PowerShell 프로세스에서 교정을 수행한다. Vim은 모델 응답을 기다리지 않고 원문과 `Coaching...` 안내를 연다. `suggestion.vim`의 100ms 타이머는 완료 표시 파일을 확인하고 제안 버퍼만 갱신하므로 원문 수정과 현재 창의 포커스를 유지한다. 제안은 Ctrl+G 시점의 원문에 대한 결과이며 편집 중 재호출하지 않는다. Vim 종료 시 진행 중인 교정 프로세스와 하위 프로세스를 종료한 뒤 임시 파일을 정리한다.

| 호출 설정 | 역할 |
|---|---|
| `--model gpt-6-luna` | 교정 모델 고정 |
| `model_reasoning_effort="medium"` | 교정 추론 강도 고정 |
| `--ephemeral` | 교정 세션 기록을 지속적으로 저장하지 않음 |
| `--sandbox read-only` | 모델이 실행하는 명령의 파일 쓰기 제한 |
| `--skip-git-repo-check` | Git 저장소가 아닌 임시 폴더에서 실행 |
| `--output-last-message` | 최종 답변을 참고용 파일로 저장 |
| `--ignore-user-config` | 사용자 Codex 설정 제외, 기존 로그인 사용 |
| 셸·플러그인·훅·앱·다중 에이전트·코드 호스트 비활성화 | 교정 호출에서 관련 도구·자동화 제외 |
| 웹 검색 비활성화, 승인 정책 `never` | 교정 중 검색과 승인 대기 제외 |

위 설정은 중첩된 교정용 `codex exec` 호출에만 적용한다. 실제 코딩 작업의 모델과 도구 설정은 유지한다. `read-only` 자체가 모든 명령 실행을 금지하는 옵션은 아니므로 셸 도구도 별도로 비활성화한다.

Vim은 `--clean`으로 사용자 설정·플러그인 없이 실행한다. UTF-8을 지정하고 모델라인과 스왑 파일을 사용하지 않는다. 왼쪽 원문을 편집 가능하게 유지하고 오른쪽 제안에 `readonly nomodifiable`을 적용한다. AI 제안을 원문으로 복사하는 동작은 없다.

## 5. 실패 처리

- 교정 명령 실패, 모델 사용 불가, 결과 파일 누락·공백: 오른쪽 창에 오류를 표시하고 원문 편집을 계속할 수 있다. 다른 모델로 자동 전환하지 않는다.
- 교정 프로세스 시작 실패: 경고 후 원문만 Vim으로 연다.
- 빈 초안: AI 호출 없이 Vim을 연다.
- 원문 파일 없음, Vim 설정 오류: 오류 코드로 종료하고 원문을 덮어쓰지 않는다.
- Vim 실패: 해당 종료 코드를 CMD 래퍼까지 전달한다.
- `:qa!`: 저장하지 않은 변경을 버리고 종료한다. 이미 저장한 내용은 취소하지 않는다.

## 6. 검증 결과

### 자동 검증

```powershell
pwsh -NoProfile -File .\tests\smoke.ps1
```

가짜 Codex·편집기로 오류와 파일 전달을 재현하고 실제 Vim으로 창 설정과 저장을 확인한다. 자동 실행 관련 검증을 포함한 **18개 시나리오가 통과**했다.

`src/`의 PowerShell 스크립트를 `Main` 진입점과 역할별 주석으로 정리한 뒤에도 18개 시나리오가 모두 통과했다. 프로필에서 불러오는 `codex-function.ps1`은 임시 범위에서 등록을 실행하여 `Main`을 사용자 세션에 남기지 않고, 필요한 `codex` 함수와 설정만 전역에 유지한다.

- 정상 교정 호출, 고정 모델·추론 강도·분리 옵션, UTF-8 입력과 출력, 원문 미수정, 임시 폴더 정리
- 교정 실패·빈 결과·결과 파일 누락 각각의 원문 편집 복구
- 빈 초안의 AI 호출 생략
- 사용자 편집만 유지
- 편집기 실패의 종료 코드 전달과 잘못된 원문 경로 거부
- 공백·한글·대괄호가 포함된 경로, 프로필 등록 중복 방지, 기존 내용 백업·유지, 등록 해제
- 실제 `codex --version` 인수 전달, 종료 후 환경 복원, 중첩 호출의 재활성화 생략
- 반복 활성화, 기존 `GIT_EDITOR` 보존, 설정 해제 시 원래 값 복원
- 원래 없었던 `GIT_EDITOR`의 설정과 제거, Git 편집기 유지
- 별도 프로세스 활성화가 부모 세션에 영향을 주지 않음
- 실제 Vim 좌우 분할·오른쪽 읽기 전용·왼쪽 UTF-8 저장

### 실제 모델 검증

2026-10-12 비동기 교정 변경 후 `tests/smoke.ps1`의 **19개 시나리오가 통과**했다. 대기 안내를 먼저 표시하는 흐름, 실패 시 오른쪽 오류 표시, 조기 종료 시 하위 교정 프로세스 종료와 임시 파일 정리, 실제 Vim에서 응답 자동 갱신 중 원문 수정·포커스·읽기 전용 유지 및 저장을 확인했다. `tests/live.ps1 -CoachRoot ./src`도 실제 `gpt-6-luna medium` 응답으로 자동 갱신, 기술 문자열과 한국어 설명 보존, 원문 저장을 통과했다.

```powershell
pwsh -NoProfile -File .\tests\live.ps1
```

이 검증은 실제 모델 호출 한 번을 수행한다. 실행 로그에서 `gpt-6-luna`, `medium`, `read-only`를 확인했다. 혼합 언어를 영어로 교정하고 한국어 학습 설명을 생성했으며, `src\parser.ts`, `parseTokens`, `npm test`, `const timeout = 5000;`를 보존했다. 실제 Vim에서 원문만 수정·저장하는 경로도 통과했다.

### 실제 대화형 CLI 검증

Windows 네이티브 의사 터미널에서 실제 Codex CLI와 Vim을 실행해 다음을 확인했다.

- [x] 혼합 언어 프롬프트 작성 후 `Ctrl+G`로 CMD 래퍼 호출
- [x] Codex 원문 파일 전달과 실제 AI 교정
- [x] 원문·제안 좌우 분할
- [x] 오른쪽 편집 시 `E21: Cannot make changes, 'modifiable' is off`로 차단
- [x] 왼쪽 원문 수정 후 `:wqa` 저장·종료
- [x] 수정한 원문만 Codex 입력창으로 복귀
- [x] Enter 없이 실제 코딩 작업이 실행되지 않음

실제 Windows Terminal 앱에서의 화면 확인 절차는 README에 제공한다. 위 대화형 결과는 Windows 네이티브 의사 터미널에서 확인한 결과다.

## 7. 이번 범위와 추후 기능

MVP 구현, 현재 PC 설치, 오류 복구, 세션 활성화·해제, 자동·실제 모델·대화형 CLI 검증을 완료했다.

비동기 교정을 지원한다. 수정 표현 강조, 학습 기록, 선택 문장 교정, 사용자 Vim 플러그인 연동, WSL 지원은 포함하지 않는다.

## Claude Code 지원

- `codex-function.ps1`이 `codex`와 `claude` 두 런처를 등록한다. 런처는 실행하는 동안만 `VISUAL`, `LILT_ACTIVE`, `LILT_AGENT`를 설정하고 종료 후 복원한다.
- `lilt.ps1`은 `LILT_AGENT`(기본 `codex`)로 교정 CLI를 고르고 `coach.ps1 -Agent -AgentPath`에 전달한다. 로그 파일 이름은 `agent.log`다.
- Claude 교정 호출: `claude -p --model sonnet --effort medium --no-session-persistence --tools "" --disable-slash-commands --strict-mcp-config --setting-sources ""`. 표준 출력이 제안이다.
- `smoke.ps1`에 Claude 백엔드 시나리오를 추가했고 20개 시나리오가 통과했다. 실제 Claude Code에서 Ctrl+G 동작은 아직 실기 확인하지 않았다.
