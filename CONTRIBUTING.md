# Contributing to get-DOprerequisites

Thank you for your interest in contributing to this project! Your help is greatly appreciated.

---

## Ways to Contribute

### Report a Bug

If you find a bug, please [open a GitHub Issue](../../issues/new?template=bug_report.md) and include:

- Your Windows version and build number
- Your Intune configuration details (DO policies applied, etc.)
- The full output string produced by the script
- Any error messages

### Suggest a Feature or Enhancement

If you have an idea for a new check or improvement, [open a GitHub Issue](../../issues/new?template=feature_request.md) describing:

- The problem you want to solve
- Your proposed solution
- Any alternatives you have considered

### Submit a Pull Request

Contributions via pull requests are welcome. Please follow the process below.

---

## Before You Contribute

- **Search existing issues** before opening a new one to avoid duplicates.
- For significant changes (new checks, behavioral changes, breaking output format changes), **open an issue first** to discuss the approach before investing time in a PR.

---

## Pull Request Process

1. **Fork** the repository to your own GitHub account.
2. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes** following the code style guidelines below.
4. **Test** your changes on a real Windows endpoint or a representative test environment.
5. **Open a Pull Request** against the `main` branch with a clear description of the changes.

---

## Code Style Guidelines

- Follow the existing PowerShell conventions used in `get-DOprerequisites.ps1`.
- Add inline comments for any complex or non-obvious logic.
- Use descriptive variable names.
- Do not introduce external module dependencies — the script must run with built-in PowerShell cmdlets only.
- If possible, run [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) on your changes and resolve any warnings:
  ```powershell
  Install-Module -Name PSScriptAnalyzer -Scope CurrentUser
  Invoke-ScriptAnalyzer -Path .\get-DOprerequisites.ps1
  ```
- **Do not change the output token format** for existing checks without discussing it first — downstream remediation scripts may depend on the exact token strings.

---

## Legal — Microsoft Contributor License Agreement (CLA)

If you are contributing on behalf of yourself or your employer, you may be required to sign a **Contributor License Agreement (CLA)** before your pull request can be merged.

Please visit [https://cla.opensource.microsoft.com](https://cla.opensource.microsoft.com) to sign the CLA. The CLA bot will comment on your pull request to guide you through this process if needed.

---

## Code of Conduct

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). By participating, you are expected to uphold this code. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for details.
