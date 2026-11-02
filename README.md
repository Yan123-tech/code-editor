<div align="center">

<img src="Resources/AppIcon.png" alt="Code Editor Icon" width="128" height="128" style="border-radius: 28px; box-shadow: 0 10px 30px rgba(0,0,0,0.25);" />

# Code Editor

### Lightweight, Native macOS Code Editor Built with Swift & SwiftUI

<a href="https://github.com/Yan123-tech/code-editor">
  <img src="https://readme-typing-svg.demolab.com?font=Fira+Code&weight=600&size=15&duration=3000&pause=1000&color=0EA5E9&center=true&vCenter=true&width=550&lines=Native+Swift+6+%26+SwiftUI+Architecture;Embedded+POSIX+PTY+Terminal+with+Truecolor;LSP+Diagnostics+%26+Smart+Completions;Multi-Provider+AI+Assistance+(OpenAI%2C+Ollama);Blisteringly+Fast+Apple+Silicon+Performance" alt="Typing SVG" />
</a>

<p align="center">
  <a href="https://github.com/Yan123-tech/code-editor/actions/workflows/ci.yml">
    <img src="https://github.com/Yan123-tech/code-editor/actions/workflows/ci.yml/badge.svg" alt="CI/CD Status" />
  </a>
  <a href="https://swift.org">
    <img src="https://img.shields.io/badge/Swift-6.4-FA7343?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.4" />
  </a>
  <a href="https://apple.com/macos">
    <img src="https://img.shields.io/badge/macOS-14.0%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 14+" />
  </a>
  <a href="https://apple.com">
    <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Intel-0284C7?style=flat-square&logo=apple" alt="Apple Silicon" />
  </a>
  <a href="https://github.com/Yan123-tech/code-editor/actions">
    <img src="https://img.shields.io/badge/Tests-156%20passed-10B981?style=flat-square&logo=xcode&logoColor=white" alt="156 Tests Passed" />
  </a>
  <a href="https://github.com/Yan123-tech/code-editor/actions">
    <img src="https://img.shields.io/badge/Runner-M--Series%20ARM64-6366F1?style=flat-square&logo=githubactions&logoColor=white" alt="Self-Hosted Runner" />
  </a>
  <a href="https://gemini.google.com">
    <img src="https://img.shields.io/badge/Built%20with-Gemini%20AI-4285F4?style=flat-square&logo=googlegemini&logoColor=white" alt="Built with Gemini AI" />
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-F59E0B?style=flat-square" alt="MIT License" />
  </a>
</p>

<p align="center">
  <a href="https://skillicons.dev">
    <img src="https://skillicons.dev/icons?i=swift,apple,bash,git,go,py" alt="Tech Stack" />
  </a>
</p>

*A clean, blisteringly fast developer environment powered by native Apple frameworks, Language Server Protocol (LSP), POSIX PTY terminal emulation, and multi-provider AI completions.*

<br/>

<p align="center">
  <img src="Resources/app-screenshot.png" alt="Code Editor Interface with Go LSP Diagnostics" width="100%" style="border-radius: 12px; box-shadow: 0 16px 40px rgba(0,0,0,0.35); border: 1px solid rgba(255,255,255,0.1);" />
</p>

</div>

---

## <img src="Resources/icons/zap.svg" width="20" height="20" align="absmiddle" /> Highlights

<table>
  <tr>
    <td width="50%">
      <h3><img src="Resources/icons/terminal.svg" width="18" height="18" align="absmiddle" /> Native POSIX PTY Terminal</h3>
      Genuine pseudo-terminal (<code>posix_openpt</code>) running your default <code>$SHELL</code>. Supports 24-bit RGB truecolor, inline carriage-return overwrites (<code>\r</code>), window resizing signals (<code>TIOCSWINSZ</code>), process-group interrupts, and interactive TUIs (<code>vim</code>, <code>top</code>, <code>git log</code>).
    </td>
    <td width="50%">
      <h3><img src="Resources/icons/code.svg" width="18" height="18" align="absmiddle" /> Language Server Protocol (LSP)</h3>
      First-class LSP support for <b>Swift</b> (<code>sourcekit-lsp</code>) and <b>Go</b> (<code>gopls</code>) over a robust, non-blocking <code>DispatchSourceRead</code> JSON-RPC transport. Features fuzzy autocomplete, parameter hints, and automatic <code>gofmt</code> formatting on save.
    </td>
  </tr>
  <tr>
    <td width="50%">
      <h3><img src="Resources/icons/alert.svg" width="18" height="18" align="absmiddle" /> Live Diagnostics & Problems</h3>
      Real-time compiler diagnostic markers in the gutter, squiggly underlines beneath issue ranges, summary error/warning badges in the status bar, jump hotkeys (<code>⌘'</code> / <code>⇧⌘'</code>), and an interactive Problems popover.
    </td>
    <td width="50%">
      <h3><img src="Resources/icons/sparkles.svg" width="18" height="18" align="absmiddle" /> AI Code Assistance</h3>
      Configurable OpenAI-compatible backend supporting <b>OpenAI</b>, <b>Ollama</b>, <b>LM Studio</b>, and <b>OpenRouter</b>. Features debounced query dispatch, multi-line documentation previews, and markdown artifact cleanup.
    </td>
  </tr>
  <tr>
    <td width="50%">
      <h3><img src="Resources/icons/palette.svg" width="18" height="18" align="absmiddle" /> Liquid Glass macOS HIG Design</h3>
      Crafted exclusively for macOS using SF Pro typography, a strict 4pt grid system, Dark / Light / High-Contrast themes, a native Settings window (<code>⌘,</code>), and a bespoke Liquid Glass app icon.
    </td>
    <td width="50%">
      <h3><img src="Resources/icons/shield.svg" width="18" height="18" align="absmiddle" /> Battle-Tested Reliability</h3>
      Hardened against edge cases: swizzled <code>NSBezierPath.safeBounds</code> preventing AppKit empty path crashes, <code>SIGPIPE</code> immunity, file modification guards, and <b>156 automated test suites</b>.
    </td>
  </tr>
</table>

---

## <img src="Resources/icons/layers.svg" width="20" height="20" align="absmiddle" /> What Works Today

- **File Explorer**: Recursive directory tree with asynchronous lazy loading, file/folder creation, inline renaming, deletion, and Finder integration. System dotfiles are cleanly hidden.
- **Source Editor**: Full `NSTextView`-backed editor (via [CodeEditSourceEditor](https://github.com/CodeEditApp/CodeEditSourceEditor)) with Tree-sitter syntax highlighting, line numbers, bracket-pair highlighting, indentation-on-type, word wrap, and unified undo stack.
- **34 Supported Languages**: Swift, Go, JavaScript, TypeScript, JSX, TSX, Python, Rust, C, C++, C#, Java, Ruby, HTML, CSS, JSON, Shell, Markdown, and all `TreeSitterLanguage` grammars exposed by `CodeEditLanguages`.
- **Tabs & Buffers**: Multiple open documents, dirty state indicators, safe close alerts, and smart file-change detection on disk (Reload vs. Overwrite vs. Cancel).
- **Find & Replace**: Built-in find and replace panel (`⌘F`) with match navigation.
- **Quick Open (`⌘P`)**: Instant fuzzy file search across the entire project workspace with live matched character highlighting.
- **Integrated PTY (`^```)**: Toggleable bottom drawer terminal. Drag the divider to smoothly resize with debounced layout updates.
- **LSP Diagnostics**: Live error and warning gutter indicators, squiggly underlines, status bar counts, and jump shortcuts (`⌘'` / `⇧⌘'`).
- **AI Autocompletions**: Toggle between LSP and AI completion modes directly in Settings or via hotkeys.
- **Session Restoration**: Seamlessly restores your open workspace and active tabs on next launch.

---

## <img src="Resources/icons/keyboard.svg" width="20" height="20" align="absmiddle" /> Keyboard Shortcuts

| Shortcut | Command | Shortcut | Command |
|:---:|:---|:---:|:---|
| `⌘N` | New file | `^``` | Toggle integrated terminal |
| `⌘O` | Open project folder | `⌘'` | Jump to next diagnostic problem |
| `⇧⌘O` | Open specific files | `⇧⌘'` | Jump to previous diagnostic problem |
| `⌘F` | Find in document | `⇧⌘L` | Toggle Dark / Light theme |
| `⌘P` | Quick Open fuzzy search | `⌘,` | Open Preferences / Settings |
| `⌘S` | Save document | `⌘B` | Toggle project sidebar |
| `⌥⌘S` | Save all modified documents | `⌘W` | Close current tab |

---

## <img src="Resources/icons/play.svg" width="20" height="20" align="absmiddle" /> Getting Started

### Prerequisites
- **macOS 14.0 (Sonoma)** or later
- **Xcode 16** with the **Swift 6.4+** toolchain

### Build & Run from Source

```bash
# Clone the repository
git clone https://github.com/Yan123-tech/code-editor.git
cd code-editor

# Build debug binary
swift build

# Run the application
swift run CodeEditorApp
```

### Run Test Suite

```bash
swift test
```

### Packaging the `.app` Bundle

To package a standalone, double-clickable `Code Editor.app` with icons and embedded language bundles:

```bash
# Build release bundle into build/Code Editor.app
./Scripts/build-app.sh

# Or build debug bundle and launch immediately
./Scripts/build-app.sh --debug --open
```

| Flag | Description |
|:---|:---|
| `--debug` | Compiles the debug build configuration instead of release |
| `--open` | Automatically launches the application once packaged |
| `--install` | Copies the compiled `.app` bundle into `/Applications` |

### Code Formatting & Linting

```bash
# Format code in-place
swift-format format --in-place --recursive --configuration .swift-format Sources Tests

# Lint strictly
swift-format lint --recursive --strict --configuration .swift-format Sources Tests
```

---

## <img src="Resources/icons/workflow.svg" width="20" height="20" align="absmiddle" /> Continuous Integration

Every Pull Request and commit to `main` is validated through automated GitHub Actions workflows:

```
┌────────────────────────────────────────────────────────┐
│                   GitHub Actions CI                    │
├─────────────────────┬──────────────────┬───────────────┤
│ Format              │ Syntax           │ Build & Test  │
│ macos-latest        │ macos-latest     │ Apple Silicon │
│ (swift-format lint) │ (swiftc -parse)  │ (156 tests)   │
└─────────────────────┴──────────────────┴───────────────┘
```

- **Hosted Runners (`macos-latest`)**: Fast formatting and syntax checks.
- **Dedicated Self-Hosted Runner (`yan-macbook-runner`)**: Apple Silicon runner executing `swift build`, `swift test` (156 unit & end-to-end tests), and `./Scripts/build-app.sh --debug` bundle layout and codesigning.

---

## <img src="Resources/icons/folder.svg" width="20" height="20" align="absmiddle" /> Project Architecture

```
Code Editor/
├── Sources/
│   ├── CodeEditorCore/       # Documents, selection, file system, quick open, metrics
│   ├── CodeEditorThemes/     # Liquid Glass palettes, chrome tokens, typography
│   ├── CodeEditorTerminal/   # POSIX PTY, ANSI parser, process signals, window resize
│   ├── CodeEditorLSP/        # DispatchSourceRead transport, LSPClient, OpenAIClient
│   ├── CodeEditorUI/         # SwiftUI views, sidebar, tabs, terminal drawer, settings
│   └── CodeEditorApp/        # Application entry point, window chrome, menu bar
├── Tests/                    # 156 comprehensive unit and integration tests
├── Resources/                # 1024x1024 Liquid Glass AppIcon.png & vector icons
└── Scripts/                  # App bundle packaging and icon compilation
```

<details>
<summary><b><img src="Resources/icons/book.svg" width="16" height="16" align="absmiddle" /> Architectural Documentation</b></summary>

- [docs/IDEA.md](docs/IDEA.md) — Product philosophy and non-goals
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Module boundaries and data flow
- [docs/MEMORY.md](docs/MEMORY.md) — Critical architectural constraints & system invariants
- [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md) — Active roadmap status and test coverage
- [docs/PROCESS.md](docs/PROCESS.md) — PR lifecycle, local gates, and definition of done
- [docs/BRANCHING.md](docs/BRANCHING.md) — Git workflow and branch naming conventions
- [docs/COMMITTING.md](docs/COMMITTING.md) — Conventional Commits guidelines

</details>

---

## <img src="Resources/icons/milestone.svg" width="20" height="20" align="absmiddle" /> Roadmap

- [x] **Completion Popup** — Fuzzy-filtered LSP completion menu ([#1](https://github.com/Yan123-tech/code-editor/issues/1))
- [x] **Diagnostics & Problems Popover** — Live compiler issues and jump hotkeys ([#2](https://github.com/Yan123-tech/code-editor/issues/2), [#10](https://github.com/Yan123-tech/code-editor/pull/10))
- [x] **External Change Detection** — Safe reload prompts when disk files change ([#6](https://github.com/Yan123-tech/code-editor/issues/6))
- [x] **POSIX PTY Terminal** — Embedded terminal with truecolor & resize support ([#5](https://github.com/Yan123-tech/code-editor/issues/5), [#7](https://github.com/Yan123-tech/code-editor/pull/7))
- [x] **Native Settings Panel** — Preferences window with modular tabs ([#4](https://github.com/Yan123-tech/code-editor/issues/4), [#8](https://github.com/Yan123-tech/code-editor/pull/8))
- [x] **Go Language Support** — `gopls` integration and `gofmt` on save ([#17](https://github.com/Yan123-tech/code-editor/issues/17), [#18](https://github.com/Yan123-tech/code-editor/pull/18))
- [x] **AI Autocompletions** — Multi-provider AI streaming backend ([#21](https://github.com/Yan123-tech/code-editor/issues/21), [#22](https://github.com/Yan123-tech/code-editor/pull/22))
- [x] **Liquid Glass App Icon** — macOS HIG app icon redesign ([#30](https://github.com/Yan123-tech/code-editor/issues/30), [#31](https://github.com/Yan123-tech/code-editor/pull/31))
- [ ] **Find in Project** — Global workspace search & replace (`⇧⌘F`) ([#27](https://github.com/Yan123-tech/code-editor/issues/27))
- [ ] **Inline Ghost-Text AI** — Multi-token inline suggestions accepted with Tab ([#28](https://github.com/Yan123-tech/code-editor/issues/28))
- [ ] **Git Gutter Diff Markers** — Gutter line additions/deletions and branch status ([#29](https://github.com/Yan123-tech/code-editor/issues/29))
- [ ] **Hover & Go-to-Definition** — Quick docs and jump-to-source ([#3](https://github.com/Yan123-tech/code-editor/issues/3))

---

## <img src="Resources/icons/users.svg" width="20" height="20" align="absmiddle" /> Contributing

Contributions are welcome! Please check our [Contributing Guidelines](docs/PROCESS.md) and [Branching Strategy](docs/BRANCHING.md) before submitting a Pull Request.

1. Fork & branch off `main` (`git checkout -b feature/your-feature`)
2. Format code (`swift-format format --in-place --recursive Sources Tests`)
3. Run tests (`swift test`)
4. Commit following [Conventional Commits](https://www.conventionalcommits.org/)
5. Open a Pull Request and verify CI status

---

## <img src="Resources/icons/license.svg" width="20" height="20" align="absmiddle" /> License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

## <img src="Resources/icons/gemini.svg" width="20" height="20" align="absmiddle" /> Built with AI Agents

> [!NOTE]
> This project is built and evolved collaboratively with **autonomous AI agents** powered by **Google DeepMind's Gemini models**.
>
> From native macOS Swift & SwiftUI architecture, POSIX PTY pseudo-terminal subsystems, and Language Server Protocol implementations to self-hosted Apple Silicon CI/CD pipelines — every architectural decision and implementation detail is paired with automated AI coding assistants, prioritizing transparency and best engineering practices.

