# MVP Backlog (language-agnostic)

## MVP Scope

The MVP delivers a fully working `stc setup` that provisions a set of Debian hosts end-to-end from a single command. It includes every command `stc setup` depends on, plus `--preflight` on all commands.

**In scope:** `inventory generate`, `ansible bootstrap-host`, `ansible setup-host`, `ssh add`, `setup`, `--preflight` on all of the above.

**Out of scope (post-MVP):** `ansible setup-vm`, `terraform apply`, `wg add`, `status`, `teardown`.

---

## Notes for all tasks

**Integration tests:** Command-level behavior must be tested by invoking the compiled `stc` binary in a temporary directory populated with the necessary files and asserting on stdout, stderr, exit code, and generated file contents. The specific framework or format for writing these tests is up to the implementor — use whatever your language ecosystem provides. The requirement is the test coverage, not the mechanism.

**Unit tests:** Business logic that does not involve running the binary (parsing, rendering, resolving) must be covered by unit tests.

**Separation of business logic and CLI wiring:** All business logic must be callable without going through the CLI layer. CLI command handlers should be thin wires that parse flags, call into the business logic layer, and print results. This is the single most important architectural rule in the project — it is what allows `stc setup` to reuse the logic of `inventory generate`, `ansible bootstrap-host`, and so on without duplication, and it is what makes the codebase testable at the unit level. Every task that implements a command is expected to follow this structure. If a later task requires refactoring earlier code to better satisfy this principle, that refactoring is expected and costed into the later task's estimate.

---

## Milestone 1 — Foundation

The project builds and `stc.yml` parses correctly.

---

### Task 1 — Initialize project and CLI framework

**Story points:** 2

**Description**

Set up a new project for the `stc` CLI. Use a CLI framework appropriate for your language — something that handles subcommands, flags, and `--help` generation automatically.

**Project structure:** organize the code so that CLI wiring (command definitions, flag parsing) is clearly separated from business logic. Follow the idiomatic conventions of your language and ecosystem for this separation.

**Root command requirements:**
- Binary name: `stc`
- A `version` subcommand that prints `stc v0.1.0` to stdout and exits 0
- The root command's long description (shown by `stc --help`) must say what `stc` is and how it works at a high level — the subcommands describe themselves. Something like:
  ```
  stc is a CLI for provisioning and managing Debian servers.

  It treats stc.yml as the single source of truth for all infrastructure
  configuration, so you don't have to manually maintain Ansible inventory
  files, host_vars, or Terraform variable files. Run any subcommand with
  --preflight to preview its required config values without executing anything.
  ```
  The exact wording may vary, but the description must: (1) say what `stc` is, (2) mention `stc.yml` as the config source-of-truth, (3) mention that it abstracts both Ansible and Terraform, and (4) mention `--preflight`.

**Suppress usage on runtime errors.** Runtime errors (e.g. host not found) must not print the full usage/help text. Flag parsing errors (e.g. unknown flag) should still print usage.

**Build target:** the project must have a build command that produces a single executable named `stc`.

**Integration test setup:** set up whatever infrastructure is needed so that integration tests can invoke the `stc` binary in a temporary directory and assert on its output. All future command tasks depend on this infrastructure.

**Required Tests**

*Integration test — version subcommand:*
- Run `stc version` with an empty `stc.yml` (`hosts: {}`) present in the working directory
- Assert stdout contains `stc v0.1.0`
- Assert exit code is 0

**Definition of Done**
- The project builds and produces a `stc` executable
- `stc --help` lists subcommands
- `stc version` prints `stc v0.1.0`
- The integration test suite runs and passes
- A runtime error does not print the usage block

---

### Task 2 — Define config data model and stc.yml parser

**Story points:** 2

**Description**

Define the data model that represents `stc.yml` and implement a function to parse it from a file path.

**Schema:** `hosts` is a string-keyed map where each key is the host's name (e.g. `"host-01"`) and each value is a host object. `vms` inside each host is a string-keyed map where each key is the VM's name. Names are the map keys and are not repeated inside the object.

**Data model fields:**

`Config`:
- `hosts` — map of host name → Host

`Host`:
- `ip` (string) — LAN IP address
- `ssh` (SSHConfig)
- `auto_update_reboot_time` (string) — HH:MM reboot time for unattended updates
- `wireguard_endpoint` (boolean) — whether this host is the WireGuard VPN endpoint
- `incus` (IncusConfig)
- `vms` — map of VM name → VM

`VM`:
- `ip` (string) — IP address on the OVN overlay network
- `ssh` (SSHConfig)
- `auto_update_reboot_time` (string)

`SSHConfig`:
- `user` (string)
- `port` (integer)
- `private_key_path` (string)
- `public_key_path` (string)

`IncusConfig`:
- `storage_pool_name` (string)
- `storage_pool_driver` (string)

**Parser:** implement a `load_config(path)` function (or equivalent) that reads and parses a YAML file at the given path into the data model above.

**Required Tests**

*Unit test — valid two-host config:*

Input `stc.yml`:
```yaml
hosts:
  host-01:
    ip: 192.168.1.10
    ssh:
      user: admin
      port: 22
      private_key_path: ~/.ssh/id_ed25519
      public_key_path: ~/.ssh/id_ed25519.pub
    auto_update_reboot_time: "05:00"
    wireguard_endpoint: true
    incus:
      storage_pool_name: default
      storage_pool_driver: dir
    vms:
      host-01-vm-01:
        ip: 10.0.100.10
        ssh:
          user: admin
          port: 22
          private_key_path: ~/.ssh/id_ed25519
          public_key_path: ~/.ssh/id_ed25519.pub
        auto_update_reboot_time: "05:00"
  host-02:
    ip: 192.168.1.11
    ssh:
      user: admin
      port: 22
      private_key_path: ~/.ssh/id_ed25519
      public_key_path: ~/.ssh/id_ed25519.pub
    auto_update_reboot_time: "05:00"
    wireguard_endpoint: false
    incus:
      storage_pool_name: default
      storage_pool_driver: dir
    vms: {}
```

Expected:
- `hosts["host-01"].ip == "192.168.1.10"`
- `hosts["host-01"].ssh.user == "admin"`
- `hosts["host-01"].vms["host-01-vm-01"].ip == "10.0.100.10"`
- `hosts["host-02"].wireguard_endpoint == false`
- No error

*Unit test — missing file:*
- Input: a path that does not exist
- Expected: an error whose message contains the path

*Unit test — invalid YAML:*
- Input: `hosts: [invalid: {`
- Expected: an error

**Definition of Done**
- All three unit tests pass
- `load_config` returns a correctly populated config object for the valid input above
