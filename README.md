# Codex Prompt Coach

Codex CLI에서 작성 중인 영어·한국어 혼합 프롬프트를 교정하고, 기존 Vim에서 제안을 참고해 직접 수정하는 Windows용 도구입니다. 교정용 모델은 **gpt-6-luna**, 추론 강도는 **medium**입니다. 실제 코딩 작업의 모델은 변경하지 않습니다.

## 설치

Windows와 PowerShell 7, 로그인된 Codex CLI, Vim, Git이 필요합니다. 이 프로젝트 폴더에서 실행합니다.

```powershell
pwsh -NoProfile -File .\scripts\install.ps1
```

`%USERPROFILE%\.codex-prompt-coach`에 파일을 설치합니다. Git for Windows에 포함된 Vim도 자동으로 찾습니다. Vim을 찾지 못하면 경로를 지정합니다.

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -VimPath 'C:\path\vim.exe'
```

설치 시 지정한 Vim 경로는 자동 실행 설정에도 저장됩니다. 수동 활성화에서도 `enable.ps1 -VimPath 'C:\path\vim.exe'`로 경로를 지정할 수 있습니다.

설치하면 PowerShell 프로필에 `codex` 실행 함수를 등록합니다. 기존 프로필 내용은 유지하고, 처음 수정할 때 `.codex-prompt-coach.bak` 백업을 만듭니다. 재설치해도 등록 블록이 중복되지 않습니다.

## 사용

설치 후 **새 PowerShell 터미널**에서 다음 명령을 실행합니다. 교정기가 자동으로 활성화되고 Codex 종료 후 원래 편집기 설정이 복원됩니다.

```powershell
codex
```

1. Codex 입력창에 프롬프트를 작성합니다.
2. `Ctrl+G`를 누르면 영어 교정안을 생성하고 Vim을 엽니다.
3. 왼쪽 원문을 직접 수정합니다. 오른쪽은 읽기 전용 제안과 한국어 학습 설명입니다.
4. `Ctrl+W`, `L` 또는 `H`로 좌우 창을 이동합니다.
5. `:wqa`로 저장하고 종료하면 수정한 원문이 Codex 입력창으로 돌아옵니다.
6. 내용을 확인한 뒤 Enter를 눌러 실제 작업을 실행합니다.

AI 제안을 원문에 자동 적용하지 않습니다. 저장하지 않고 종료하려면 `:qa!`를 사용합니다. 이미 저장한 내용은 `:qa!`로 되돌아가지 않습니다.

## 세션 설정과 해제

프로필에서 `codex-function.ps1`을 불러와 `codex` 함수를 등록합니다. 함수는 원래 인수를 실제 `codex.exe`에 전달하고, 실행 중에만 교정기 환경변수를 적용합니다. Codex가 종료되면 원래 값을 복원합니다. 이 기능은 프로필을 읽는 PowerShell에서 동작하며 `pwsh -NoProfile`이나 다른 셸에서는 자동 적용되지 않습니다.

- `VISUAL`: 교정용 CMD 래퍼로 지정합니다.
- `GIT_EDITOR`: 기존 값이 있으면 유지합니다. 없으면 활성화 전에 `git var GIT_EDITOR`로 확인한 편집기를 지정합니다. 따라서 Codex 안에서 실행한 Git도 기존 편집기를 사용합니다.
- `CODEX_PROMPT_COACH_VIM`: 래퍼가 실행할 Vim 경로입니다. **Codex 자체의 환경변수가 아니라 이 도구가 사용하는 변수**입니다.

Codex의 하위 프로그램에도 환경변수가 전달됩니다. Git은 `GIT_EDITOR`로 기존 편집기를 사용하고, `VISUAL`을 사용하는 다른 하위 프로그램은 교정기를 호출할 수 있습니다. `enable.ps1`을 직접 실행하면 이전처럼 해당 세션 전체를 수동 활성화할 수 있습니다. 수동 활성화 해제는 다음과 같습니다.

```powershell
& "$env:USERPROFILE\.codex-prompt-coach\enable.ps1" -Disable
```

자동 실행을 해제하려면 다음 명령으로 프로필의 등록 블록을 제거하고 새 PowerShell을 엽니다. 설치 파일은 유지됩니다.

```powershell
pwsh -NoProfile -File "$env:USERPROFILE\.codex-prompt-coach\install.ps1" -Uninstall
```

도구를 완전히 제거하려면 자동 실행을 해제한 뒤 `%USERPROFILE%\.codex-prompt-coach` 폴더를 삭제합니다.

## 교정 호출의 동작

요청을 UTF-8 표준 입력으로 전달하고, 임시 폴더에 최종 답변을 저장합니다. 초안은 JSON 문자열로 전달해 텍스트 데이터로 취급하도록 지시합니다.

| 옵션 | 역할 |
|---|---|
| `--model gpt-6-luna`, `model_reasoning_effort="medium"` | 교정 모델과 추론 강도를 고정합니다. |
| `--ephemeral` | 교정 세션의 대화 기록을 지속적으로 저장하지 않습니다. |
| `--sandbox read-only` | 모델이 실행하는 명령의 파일 쓰기를 제한합니다. |
| `--skip-git-repo-check` | Git 저장소가 아닌 임시 폴더에서도 실행합니다. |
| `--output-last-message` | 최종 교정 답변을 별도 파일에 저장합니다. |
| `--ignore-user-config` | 사용자 Codex 설정을 읽지 않습니다. 기존 로그인은 사용합니다. |

교정 호출에서만 셸 도구·플러그인·훅·앱·다중 에이전트·코드 실행 호스트를 비활성화하고 웹 검색을 끕니다. 평소 코딩용 Codex의 도구와 설정은 변경하지 않습니다. 읽기 전용 샌드박스는 명령 실행을 끄는 옵션과는 별개입니다.

Vim은 `--clean`으로 사용자 플러그인 없이 실행하며, 모델라인과 스왑 파일을 사용하지 않습니다. 편집기를 종료하면 교정용 임시 폴더를 정리합니다.

## 오류 해결

- **교정 실패·모델 사용 불가·빈 결과:** 경고 후 원문만 Vim으로 엽니다. 다른 모델로 자동 전환하지 않습니다. `codex login status`로 로그인을 확인합니다.
- **빈 초안:** 모델을 호출하지 않고 Vim을 엽니다.
- **Vim 경로 오류:** `enable.ps1 -VimPath 'C:\path\vim.exe'`로 활성화합니다.
- **`Ctrl+G`가 기존 편집기를 여는 경우:** 설치 후 새 PowerShell을 열었는지, `Get-Command codex`가 `Function`인지 확인합니다. `codex.exe`로 직접 실행하면 자동 활성화를 거치지 않습니다.
- **잘못된 원문 경로·편집기 실행 실패:** 오류를 반환하며 교정기는 원문을 덮어쓰지 않습니다.

## 검증

```powershell
pwsh -NoProfile -File .\tests\smoke.ps1
```

자동 검증 결과와 실제 모델·Vim 검증 결과는 `docs/project_description.md`에 기록합니다. Windows Terminal의 최종 확인 순서는 다음과 같습니다.

실제 모델과 Vim을 함께 검증하려면 `pwsh -NoProfile -File .\tests\live.ps1`을 실행합니다. 이 검증은 실제 `gpt-6-luna medium` 호출 한 번을 수행합니다.

1. 새 PowerShell에서 `codex`를 실행합니다.
2. `Please analyze this code and 성능 저하의 원인을 찾아줘.`를 입력하고 `Ctrl+G`를 누릅니다.
3. 원문·영어 제안·한국어 설명이 표시되는지 확인합니다.
4. 오른쪽이 읽기 전용인지 확인하고 왼쪽을 수정한 뒤 `:wqa`로 종료합니다.
5. 수정한 원문만 입력창에 돌아오고, Enter 전까지 코딩 작업이 실행되지 않는지 확인합니다.

비동기 교정, 수정 강조, 학습 기록, Vim 플러그인, WSL은 이번 구현에 포함하지 않습니다.
