<p align="center">
  <img src="assets/lilt.svg" alt="Lilt logo" width="120" height="120">
</p>

<h1 align="center">Lilt</h1>

<p align="center">
  <strong>Write clearer English prompts. Learn as you code.</strong><br>
  An English writing coach for your Codex CLI workflow on Windows.
</p>

<p align="center">
  <a href="#why-lilt">Why Lilt</a> ·
  <a href="#what-you-get">Features</a> ·
  <a href="#using-lilt">Usage</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#how-it-works">How it works</a>
</p>

## Why Lilt

Writing a coding prompt often means thinking through a technical problem while finding the right English words. When you work in Korean and English, switching between a translator, an editor, and your coding agent can interrupt that process.

Lilt brings English practice into the prompt you are already writing. It helps you express your intent clearly and learn from small corrections while staying in your terminal. The goal is to make everyday coding a chance to improve your English, with you choosing the final wording.

## What you get

- **Clearer prompts from mixed drafts.** Translate Korean fragments and improve wording and structure so your task, purpose, constraints, and expected outcome are easy to understand.
- **Your technical intent stays intact.** The coaching instructions preserve meaning, requirements, paths, commands, code, identifiers, and numbers. Revisions use only intent clearly supported by your draft.
- **Every edit explained in Korean.** See each individual change and its reason, with a brief explanation per item.
- **Recommendations for unclear details.** A separate Korean section suggests how to clarify ambiguous goals, scope, or expected results. These suggestions are kept separate from the revised prompt for you to decide.
- **An editor you control.** Review the suggestion in a read-only Vim pane and edit your original draft yourself. Suggestions are never applied automatically.
- **A fallback when coaching fails.** If the model call fails or returns no suggestion, Lilt opens the original draft in Vim so you can continue editing.

## Using Lilt

After installation, open a new PowerShell terminal and run `codex`.

1. Write your prompt in the Codex input box, using English, Korean, or both.
2. Press **Ctrl+G** to request a suggestion and open Vim.
3. Edit the original draft on the left. The right pane shows the suggested English prompt, brief Korean explanations of every edit, and recommendations for unclear details.
4. Use **Ctrl+W, L** or **Ctrl+W, H** to move between panes.
5. Run **`:wqa`** to save and return the edited draft to Codex.
6. Review the prompt and press **Enter** when you are ready to submit it.

Use `:qa!` to discard unsaved edits and exit. Changes you have already saved are not undone. Empty drafts open directly in Vim without a model call.

## Installation

You need **Windows, PowerShell 7, an authenticated Codex CLI, Git, and Vim**. From the repository root, run:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1
```

The installer can find Vim bundled with Git for Windows. If it cannot locate Vim, provide its path:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -VimPath 'C:\path\vim.exe'
```

Lilt currently installs to `%USERPROFILE%\.lilt`. The installer adds a `codex` launcher to your PowerShell profile, preserves existing profile content, and creates a backup before first modifying an existing profile. Open a new PowerShell terminal to load the launcher. Automatic activation requires a profile-loading PowerShell session; `pwsh -NoProfile` bypasses it.

To remove the launcher from your profile, run the following command and restart PowerShell:

```powershell
pwsh -NoProfile -File "$env:USERPROFILE\.lilt\install.ps1" -Uninstall
```

You can then delete the installation folder to remove the remaining files.

## How it works

Lilt uses PowerShell and a small CMD wrapper to connect Codex's external-editor shortcut to Vim. The profile launcher sets `VISUAL` while Codex runs, preserves Git's editor through `GIT_EDITOR`, and restores the previous environment when Codex exits. Programs launched by Codex that use `VISUAL` can also invoke Lilt.

For a nonempty draft, Lilt sends UTF-8 text to a separate `codex exec` call using **`gpt-6-luna` with `medium` reasoning**. The coaching call uses an ephemeral session, ignores user configuration, and disables shell tools, plugins, hooks, apps, multi-agent execution, the code host, and web search. These settings apply to the coaching call. Your coding session keeps its model and tool settings.

The response is saved temporarily and opened beside the draft in Vim. Vim runs with a clean configuration, modelines and swap files disabled, and the suggestion pane read-only. Temporary coaching files are removed after the editor exits.

Runtime scripts and the coaching prompt live in `src/`; the installer lives in `scripts/`. There is no build step. Run the automated checks with:

```powershell
pwsh -NoProfile -File .\tests\smoke.ps1
```

The optional `tests/live.ps1` checks the installed tool with one real model call and Vim. See [the implementation report](docs/project_description.md) for detailed behavior and recorded validation results.
