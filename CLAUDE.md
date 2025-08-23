# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Quicktest is a Neovim plugin for contextual test execution that allows running tests directly from where the cursor is located. The plugin supports multiple test frameworks across different languages through a modular adapter system.

## Core Architecture

### Main Entry Points
- `lua/quicktest.lua` - Main module that exposes the public API and configuration
- `lua/quicktest/module.lua` - Core functionality for test execution, job management, and UI orchestration
- `plugin/quicktest.lua` - Plugin initialization and command registration

### Adapter System
The plugin uses a modular adapter architecture where each language/framework has its own adapter:

- `lua/quicktest/adapters/golang/` - Go test support with treesitter integration
- `lua/quicktest/adapters/vitest/` - Vitest JavaScript/TypeScript testing
- `lua/quicktest/adapters/playwright/` - Playwright end-to-end testing
- `lua/quicktest/adapters/pytest/` - Python pytest support
- `lua/quicktest/adapters/elixir/` - Elixir ExUnit testing
- `lua/quicktest/adapters/rspec/` - Ruby RSpec testing
- `lua/quicktest/adapters/criterion/` - C Criterion testing framework
- `lua/quicktest/adapters/dart/` - Dart testing support

Each adapter follows a consistent interface with methods like:
- `build_line_run_params()` - Extract test parameters for cursor position
- `build_file_run_params()` - Extract test parameters for entire file
- `run()` - Execute the test command
- `is_enabled()` - Determine if adapter should be used for current buffer

### Key Components
- `lua/quicktest/ui.lua` - Manages split/popup windows for test output display
- `lua/quicktest/ts.lua` - Treesitter utilities for parsing test structures
- `lua/quicktest/colored_printer.lua` - ANSI color handling for test output
- `lua/quicktest/fs_utils.lua` - File system utilities
- `lua/quicktest/notify.lua` - Notification system

### Test Execution Flow
1. User invokes test command (line/file/dir/all)
2. Plugin determines appropriate adapter based on current buffer
3. Adapter extracts necessary parameters (test names, file paths, etc.)
4. Test command is executed asynchronously via plenary.job
5. Output is streamed to UI window with real-time updates and ANSI color support
6. Previous run state is persisted for re-execution

## Development Commands

### Testing
```bash
make test
```
Runs the test suite using plenary.nvim's test framework. Tests are located in `tests/` directory with minimal Neovim initialization in `tests/minimal_init.lua`.

### Code Formatting
```bash
make stylua
```
Checks Lua code formatting using stylua. Run `stylua --glob '**/*.lua' -- lua` to automatically format code.

## Development Guidelines

### Adding New Adapters
1. Create adapter directory under `lua/quicktest/adapters/`
2. Implement required interface methods in `init.lua`
3. Add treesitter queries if needed for test parsing
4. Include adapter in main configuration examples
5. Add test support files under `tests/support/`

### Key Patterns
- All adapters use plenary.job for async command execution
- Treesitter is used for intelligent test parsing where available
- UI supports both split and popup modes for test output
- Previous test runs are persisted using JSON files in vim's data directory

### Dependencies
- `plenary.nvim` - Async utilities, job control, and testing framework
- `nui.nvim` - UI components for popup windows
- Treesitter parsers for supported languages (optional but recommended)