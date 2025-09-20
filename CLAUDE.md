# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Quicktest is a Neovim plugin that enables contextual test execution with real-time feedback. It supports multiple testing frameworks through an adapter system and provides both split window and popup interfaces for viewing test results.

## Development Commands

### Testing
- `make test` - Run the test suite using Plenary
- Tests are located in `tests/` directory
- Test configuration: `tests/minimal_init.lua`

### Code Formatting
- `stylua --check --glob '**/*.lua' -- lua` - Check Lua code formatting
- `stylua --glob '**/*.lua' -- lua` - Auto-format Lua code
- CI runs stylua checks on all pull requests

## Architecture

### Core Structure
- `lua/quicktest.lua` - Main module entry point with setup and public API
- `lua/quicktest/module.lua` - Core functionality, adapter management, and test execution
- `lua/quicktest/ui.lua` - Window management (split/popup) and display logic
- `plugin/quicktest.lua` - Vim plugin initialization and command definitions

### Adapter System
The plugin uses a modular adapter architecture in `lua/quicktest/adapters/`:
- Each adapter (`golang/`, `vitest/`, `playwright/`, etc.) implements the `QuicktestAdapter` interface
- Adapters define test parameter building for different run types (line, file, dir, all)
- Each adapter has `build_*_run_params` functions and a `run` function that executes tests
- Adapters can use TreeSitter queries for parsing test structures (see `query.lua` files)

### Key Components
- `lua/quicktest/fs_utils.lua` - File system utilities for finding test files and directories
- `lua/quicktest/ts.lua` - TreeSitter integration for parsing test code
- `lua/quicktest/colored_printer.lua` - ANSI color support for test output
- `lua/quicktest/notify.lua` - Notification system

### Test Execution Flow
1. User triggers test run (line/file/dir/all)
2. Module determines appropriate adapter based on buffer and configuration
3. Adapter builds run parameters using TreeSitter parsing or file analysis
4. Test command executes via Plenary Job with real-time output streaming
5. Results display in split window or popup with live scrolling and ANSI colors

### Adapter Development
When creating new adapters:
- Implement the `QuicktestAdapter` interface in `lua/quicktest/adapters/[name]/init.lua`
- Use TreeSitter queries in `query.lua` files for test parsing when applicable
- Follow existing patterns in `golang/` or `vitest/` adapters
- Test adapter functionality with example projects in `tests/support/`

## Commands and API

### Vim Commands
- `:QuicktestRunLine [mode] [adapter] [...args]` - Run test at cursor
- `:QuicktestRunFile [mode] [adapter] [...args]` - Run all tests in file
- `:QuicktestRunDir [mode] [adapter] [...args]` - Run tests in directory
- `:QuicktestRunAll [mode] [adapter] [...args]` - Run all tests in project

### Lua API
- `require('quicktest').run_line(mode)` - Run test at cursor position
- `require('quicktest').run_file(mode)` - Run file tests
- `require('quicktest').run_dir(mode)` - Run directory tests
- `require('quicktest').run_all(mode)` - Run all project tests
- `require('quicktest').run_previous(mode)` - Rerun last test
- `require('quicktest').toggle_win(mode)` - Toggle test window
- `require('quicktest').cancel_current_run()` - Cancel running test

Modes: `'split'`, `'popup'`, or omit for auto-detection.