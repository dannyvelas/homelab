
### world-class user experience

Every feature of `stc-cli` MUST be designed with the end user as the primary stakeholder. The following rules are non-negotiable:
- **Clarity**: Command output MUST be immediately understandable without consulting docs. Error messages MUST describe what went wrong AND suggest
  a corrective action.
- **Predictability**: Command behavior MUST be consistent and unsurprising across all subcommands. Flags with the same name MUST have the same
  semantics everywhere.
- **Feedback**: Silent success is acceptable; silent failure is NOT.
- **Fail Fast**: Invalid input MUST be rejected before any side-effectful work begins, with a human-readable message indicating the offending argument and expected format.
- **Discoverability**: Every subcommand and flag MUST appear in `--help` output with a concise, accurate description. No hidden flags in production paths.

**Rationale**: Users of a CLI make decisions based on what they see in the terminal. A confusing or silent interface erodes trust and leads to operator error in production Ansible workflows — a high-consequence environment.


### dont be afraid to refactor if necessary after a task to achieve a final code state that is well-structured and minimized duplication

`stc-cli` MUST be architected so that adding a new subcommand requires touching exactly one authoritative location per concern, with zero copy-paste of scaffolding. Concretely:
- **Single Registration Point**: Each subcommand MUST be declared in one place (e.g., a command registry or a directory of self-contained command modules). Adding a subcommand MUST NOT require editing unrelated files.
- **No Logic Duplication**: Business logic, argument parsing conventions, output formatting, and error handling MUST each live in a single canonical location. Shared behavior MUST be extracted into helpers or base abstractions rather than repeated.
- **Consistent Abstraction Layers**: The codebase MUST maintain clear separation between (a) CLI argument parsing, (b) Ansible invocation / orchestration logic, and (c) output rendering. Mixing these layers in a single function or module is prohibited.
- **Pattern Enforcement**: Any pattern established for the first subcommand MUST be mechanically reusable for the tenth subcommand without modification to shared code.
- **Separation of business logic and CLI wiring:** All business logic must be callable without going through the CLI layer. CLI command handlers should be thin wires that parse flags, call into the business logic layer, and print results. This is the single most important architectural rule in the project — it is what allows commands to reuse the logic of other commands, and so on without duplication, and it is what makes the codebase testable at the unit level. Every task that implements a command is expected to follow this structure. If a later task requires refactoring earlier code to better satisfy this principle, that refactoring is expected and costed into the later task's estimate.

**Rationale**: Duplication creates silent divergence — a developer fixing behavior in one subcommand's copy of shared logic will miss the other copies, introducing bugs. Given that `stc-cli` is expected to grow to many ansible subcommands, the cost of divergence compounds with each addition.

### code quality is important

The following constraints apply to every pull request, regardless of size:

- **No Dead Code**: Unused functions, variables, or imports MUST be removed before merge.
- **Meaningful Names**: Variables, functions, and modules MUST be named for their role in the domain, not their implementation detail (e.g., `run_playbook` not `do_thing`).
- **Small, Focused Units**: Functions and modules MUST have a single, clearly statable purpose. If a docstring requires "and" to describe what a function does, it SHOULD be split.
- **Explicit Over Implicit**: Configuration, defaults, and behavior MUST be explicit and locatable. Magic values and implicit global state are prohibited.

### testing is important

- **Test Coverage for New Paths**: Every new code path introduced MUST be covered by at least one automated test (unit or integration). Untested behavior is unshippable behavior.
**Integration tests:** If your language of choosing has ergonomic support file-system based test (e.g. similar to how Go has `https://pkg.go.dev/github.com/rogpeppe/go-internal/testscript`), then command-level behavior must be covered by integration tests that compile (or run) the `stc` binary, invoke it inside a temporary directory populated with the necessary files, and assert on stdout, stderr, exit code, and generated file contents. However, if the language of your choosing doesn't have good support for this, then this requirement can be dropped. I'll let the "implementer" decide what "good" or "ergonomic" support means.

**Unit tests:** Business logic that does not involve running the binary (parsing, rendering, resolving) must be covered by unit tests.
