# Flutter Run Implementation Plan

> Execute directly in the current workspace; no Git worktree.

**Goal:** Build the agreed Flutter desktop runner with embedded DevTools and Android Logcat.
**Architecture:** Flutter desktop UI manages SDK subprocesses and their lifecycle; embedded DevTools connects to the VM service of a machine-mode run session.
**Tech Stack:** Flutter/Dart, Flutter CLI, adb, desktop WebView.
**Spec:** docs/superpowers/specs/2026-11-06-flutter-run-design.md

1. Scaffold the desktop application and check SDK and desktop WebView compatibility.
2. Implement and test machine protocol, device discovery, run control, and process cleanup.
3. Implement and test Logcat streaming and filtering.
4. Embed DevTools and connect Inspector to the active session.
5. Add settings and desktop UI; run tests, static analysis, and available local integration checks.

Review failure modes: missing SDK or adb; malformed process output; disconnected device; process termination; unavailable embedded browser.
