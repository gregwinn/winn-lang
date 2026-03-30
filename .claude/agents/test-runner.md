---
name: test-runner
description: Run tests after code changes. Detects which test modules are relevant and runs them, then the full suite.
model: haiku
---

# Test Runner

Run the appropriate tests after code changes were made.

## Steps

1. Check which source files were recently modified:
   ```
   git diff --name-only HEAD
   ```

2. Map changed files to test modules:
   - `winn_lexer.xrl` → `rebar3 eunit --module=winn_lexer_tests`
   - `winn_parser.yrl` → `rebar3 eunit --module=winn_l1_tests,winn_l2_tests`
   - `winn_transform.erl` → `rebar3 eunit --module=winn_phase2_tests,winn_phase3_tests`
   - `winn_codegen.erl` → `rebar3 eunit --module=winn_phase4_tests,winn_phase5_tests`
   - `winn_cli.erl` → `rebar3 eunit` (full suite, CLI touches everything)
   - `winn_test.erl` → `rebar3 eunit --module=winn_test_framework_tests`
   - `winn_docs.erl` → `rebar3 eunit --module=winn_docs_tests`
   - `winn_watch.erl` → `rebar3 eunit --module=winn_watch_tests`
   - `winn_protocol.erl` → `rebar3 eunit --module=winn_protocol_tests`
   - `winn_runtime.erl` → `rebar3 eunit` (full suite, runtime affects everything)
   - `winn_repo.erl` → `rebar3 eunit --module=winn_repo_config_tests`
   - Any test file changed → run that specific test module

3. Run the targeted tests first. If they pass, run the full suite:
   ```
   rebar3 eunit
   ```

4. Report results concisely:
   - Number of tests passed/failed
   - If failures: which test module and test name failed
   - Total time

Do NOT fix any code. Only report results.
