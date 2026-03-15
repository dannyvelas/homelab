# MVP Backlog

## MVP Scope

The MVP delivers a fully working `stc setup` that provisions a set of Debian hosts
end-to-end from a single command. It includes every command `stc setup` depends on, plus
`--preflight` on all commands.

**In scope:** `inventory generate`, `ansible bootstrap-host`, `ansible setup-host`,
`ssh add`, `setup`, `--preflight` on all of the above.

**Out of scope (post-MVP):** `ansible setup-vm`, `terraform apply`, `wg add`, `status`,
`teardown`.

---

## Notes for all tasks

**YAML library:** Use `github.com/goccy/go-yaml` for all YAML parsing and marshaling.
`gopkg.in/yaml.v3` was archived in 2024 and should not be used.

**Go templates:** All commands that generate text files or formatted output (inventory YAML, SSH config blocks, diagnostic table) must use `text/template` from the Go standard library. This makes the output format easy to read and modify — you can open the template and immediately see what the generated file will look like.

**Script tests:** Command-level behavior must be covered by txtar script tests using the `github.com/rogpeppe/go-internal/testscript` package. These tests compile the `stc` binary, run it inside a temporary directory populated with the files defined in the test, and assert on stdout, stderr, exit code, and generated file contents. Test files live in `testdata/scripts/`. Each `.txtar` file covers one scenario. The format is:

```
# Description of the test
exec stc <command> [flags]
stdout 'expected pattern'
exists .generated/some/file

-- stc.yml --
<file contents>
```

Verbs: `exec` (expect exit 0), `! exec` (expect non-zero), `stdout`, `stderr`, `exists`,
`grep <pattern> <file>`, `env KEY=VALUE`.

**Unit tests:** Logic that does not involve running the binary (parsing, rendering, resolving) must be covered by standard Go unit tests (`*_test.go` files).

**Separation of business logic and CLI wiring:** All business logic must live in `internal/` and be callable without going through the CLI layer. Command handlers in `cmd/stc/` should be thin wires that parse flags, call into `internal/`, and print results. This is the single most important architectural rule in the project — it is what allows `stc setup` to reuse the logic of `inventory generate`, `ansible bootstrap-host`, and so on without duplication, and it is what makes the codebase testable at the unit level. Every task that implements a command is expected to follow this structure. If a later task requires refactoring earlier code to better satisfy this principle, that refactoring is expected and costed into the later task's estimate.

---

## Milestone 1 — Foundation

The project builds and `stc.yml` parses correctly.

---

### Task 1 — Initialize Go project with Cobra CLI framework

**Story points:** 2

**Description**

Create a new Go project for the `stc` CLI. Use the [Cobra](https://github.com/spf13/cobra) library for the CLI framework — it handles subcommands, flags, and `--help` generation automatically.

**Project structure:**
```
cmd/stc/           # CLI entrypoint: main.go, root command, subcommands
internal/          # Business logic (no CLI concerns)
testdata/scripts/  # txtar script tests
Makefile
go.mod
```

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

**Makefile targets:** `all` (default, runs `build`), `build` (compiles to `./stc`), `clean` (removes `./stc`).

**Testscript setup:** Wire up `github.com/rogpeppe/go-internal/testscript` so that txtar files placed in `testdata/scripts/` are run as part of `go test ./...`. All future command tasks depend on this infrastructure.

**Required Tests**

*Txtar test — `testdata/scripts/version.txtar`:*
```
# version subcommand prints version string
exec stc version
stdout 'stc v0.1.0'

-- stc.yml --
hosts: {}
```

**Definition of Done**
- `make` produces `./stc`
- `./stc --help` lists subcommands
- `./stc version` prints `stc v0.1.0`
- `go test ./...` passes (including the testscript runner)
- A runtime error does not print the usage block

---

### Task 2 — Define Config structs and stc.yml parser

**Story points:** 2

**Description**

Define the Go structs that represent `stc.yml` and implement a function to parse it.

**Schema:** `hosts` is a `map[string]Host` where each key is the host's name (e.g. `"host-01"`). `vms` inside each host is a `map[string]VM` where each key is the VM's name. Names are not repeated inside the object — they are the map key.

**Structs** (suggested location: `internal/models/`):

```go
type Config struct {
	Hosts map[string]Host `yaml:"hosts"`
}

type Host struct {
	IP                   string        `yaml:"ip"`
	SSH                  SSHConfig     `yaml:"ssh"`
	AutoUpdateRebootTime string        `yaml:"auto_update_reboot_time"`
	WireguardEndpoint    bool          `yaml:"wireguard_endpoint"`
	Incus                IncusConfig   `yaml:"incus"`
	VMs                  map[string]VM `yaml:"vms"`
}

type VM struct {
	IP                   string    `yaml:"ip"`
	SSH                  SSHConfig `yaml:"ssh"`
	AutoUpdateRebootTime string    `yaml:"auto_update_reboot_time"`
}

type SSHConfig struct {
	User           string `yaml:"user"`
	Port           int    `yaml:"port"`
	PrivateKeyPath string `yaml:"private_key_path"`
	PublicKeyPath  string `yaml:"public_key_path"`
}

type IncusConfig struct {
	StoragePoolName   string `yaml:"storage_pool_name"`
	StoragePoolDriver string `yaml:"storage_pool_driver"`
}
```

**Parser function:** `LoadConfig(path string) (*Config, error)` using `github.com/goccy/go-yaml`.

**Required Tests**

*Unit test — `TestLoadConfig_ValidTwoHostConfig`:*

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

Expected: `config.Hosts["host-01"].IP == "192.168.1.10"`, `config.Hosts["host-01"].SSH.User == "admin"`, `config.Hosts["host-01"].VMs["host-01-vm-01"].IP == "10.0.100.10"`, `config.Hosts["host-02"].WireguardEndpoint == false`, no error.

*Unit test — `TestLoadConfig_MissingFile`:*
- Input: path that does not exist
- Expected: non-nil error, error message contains the path

*Unit test — `TestLoadConfig_InvalidYAML`:*
- Input: `hosts: [invalid: {`
- Expected: non-nil error

**Definition of Done**
- All three unit tests pass
- `LoadConfig` returns a correctly populated `*Config` for the valid input above

---

## Milestone 2 — `stc inventory generate`

The first fully working end-to-end command.

---

### Task 3 — Implement Ansible inventory YAML generator

**Story points:** 2

**Description**

Implement the internal logic that takes a parsed `Config` and renders the Ansible inventory YAML string. This is pure business logic with no CLI concerns and no file I/O. Use `text/template` to render the output so the structure is immediately legible from reading the template source.

The output structure must be:
```yaml
all:
  children:
    hosts:
      hosts:
        <host-name>:
          ansible_host: <host-ip>
        ...
    vms:
      hosts:
        <vm-name>:
          ansible_host: <vm-ip>
          ansible_ssh_common_args: '-o ProxyJump=<parent-ssh-user>@<parent-ip>'
          parent_host: <parent-name>
        ...
```

Host and VM names must appear in sorted order for deterministic output (Go maps iterate randomly). The `ProxyJump` value is `<parent.SSH.User>@<parent.IP>`.

**Required Tests**

*Unit test — `TestGenerateInventory_TwoHostsTwoVMs`:*

Input:
```go
Config{Hosts: map[string]Host{
	"host-01": {IP: "192.168.1.10", SSH: SSHConfig{User: "admin"}, VMs: map[string]VM{
		"host-01-vm-01": {IP: "10.0.100.10"},
	}},
	"host-02": {IP: "192.168.1.11", SSH: SSHConfig{User: "admin"}, VMs: map[string]VM{
		"host-02-vm-01": {IP: "10.0.100.20"},
	}},
}}
```

Expected output contains (in order):
- `host-01:` with `ansible_host: 192.168.1.10`
- `host-02:` with `ansible_host: 192.168.1.11`
- `host-01-vm-01:` with `ansible_host: 10.0.100.10`, `ansible_ssh_common_args: '-o ProxyJump=admin@192.168.1.10'`, and `parent_host: host-01`
- `host-02-vm-01:` with `ansible_host: 10.0.100.20`, `ansible_ssh_common_args: '-o ProxyJump=admin@192.168.1.11'`, and `parent_host: host-02`

*Unit test — `TestGenerateInventory_SortedOutput`:*
- Input: config with hosts `"zebra"` and `"alpha"`
- Expected: `"alpha"` appears before `"zebra"` in the output

**Definition of Done**
- Both unit tests pass
- Generated output matches the required structure exactly

---

### Task 4 — Implement `stc inventory generate` command

**Story points:** 2

**Description**

Wire up the `inventory generate` subcommand. This is also the first command that requires `stc.yml`, so config loading should be introduced here: before dispatching to any subcommand that needs config, load `stc.yml` from the current working directory. If loading fails, print a user-friendly error (`error: could not load stc.yml: <reason>`) and exit 1. The `version` subcommand must continue to work without `stc.yml`.

This command does NOT accept `--host` flags — it always generates inventory for all hosts and VMs in `stc.yml`. `--preflight` support will be added in a later milestone.

**Required config values:**
- Per top-level host: `hosts.<name>.ip`
- Per VM: `hosts.<name>.vms.<vm-name>.ip` and `hosts.<name>.ssh.user` (needed for ProxyJump)

**Behavior:**
- No `stc.yml` → print `error: could not load stc.yml: <reason>`, exit 1
- Empty `hosts` map → print `error: no hosts defined in stc.yml`, exit 1
- Any required field is empty → print a user-friendly error indicating which fields are missing, exit 1
- All fields present → write `.generated/ansible/inventory/hosts.yml` with `0644` permissions (creating parent directories as needed), print a success message, exit 0

**Required Tests**

*Txtar test — `testdata/scripts/inventory-generate.txtar`:*
```
# Happy path: inventory generate writes the correct file
exec stc inventory generate
stdout 'Inventory written'
exists .generated/ansible/inventory/hosts.yml
grep 'ansible_host: 192.168.1.10' .generated/ansible/inventory/hosts.yml
grep 'ansible_host: 10.0.100.10' .generated/ansible/inventory/hosts.yml
grep 'ProxyJump=admin@192.168.1.10' .generated/ansible/inventory/hosts.yml
grep 'parent_host: host-01' .generated/ansible/inventory/hosts.yml

-- stc.yml --
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
```

*Txtar test — `testdata/scripts/missing-stc-yml.txtar`:*
```
# Missing stc.yml produces a friendly error and exits 1
! exec stc inventory generate
stderr 'stc.yml'
```
(No `-- stc.yml --` section.)

*Txtar test — `testdata/scripts/version-no-stc-yml.txtar`:*
```
# version works without stc.yml
exec stc version
stdout 'stc v0.1.0'
```
(No `-- stc.yml --` section.)

*Txtar test — `testdata/scripts/runtime-error-no-usage.txtar`:*
```
# Runtime errors do not print the usage block
! exec stc inventory generate
! stdout 'Usage:'
stderr '.'
```
(No `-- stc.yml --` section.)

*Txtar test — `testdata/scripts/inventory-generate-zero-hosts.txtar`:*
```
# Zero hosts: exits 1 with friendly error
! exec stc inventory generate
stderr 'no hosts'

-- stc.yml --
hosts: {}
```

*Txtar test — `testdata/scripts/inventory-generate-missing-ip.txtar`:*
```
# Missing ip: exits 1 with error indicating the missing field
! exec stc inventory generate
stderr 'ip'

-- stc.yml --
hosts:
  host-01:
    ip: ""
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

**Definition of Done**
- `./stc inventory generate` produces the correct inventory file for a valid config
- `./stc inventory generate` with no `stc.yml` prints an error and exits 1
- `./stc version` still works without `stc.yml`
- All txtar tests pass
- `go test ./...` passes

---

## Milestone 3 — Ansible commands

Shared infrastructure and both `ansible` subcommands, without `--preflight` (added in Milestone 5).

---

### Task 5 — Shared infrastructure for ansible commands

**Story points:** 3

**Description**

Before implementing the individual ansible commands, build the shared logic they both depend on.

**Host/VM resolution:** Given the list of `--host` argument values and the parsed config, resolve them into a concrete list of targets. If no `--host` arguments are given, default to all top-level hosts (VMs are not included in the default). Return an error listing all names that could not be found. VM names are globally unique across `stc.yml` — a name can match either a top-level host or a VM in any host's `vms` map.

**Secret collection:** For each secret value, first look it up in the environment using a `STC_<UPPERCASE_KEY>` naming convention (e.g. `admin_email` → `STC_ADMIN_EMAIL`). If not set in the environment, prompt the user interactively via stdin. Trim whitespace from prompted values. Return an error if a prompted value is empty after trimming.

**ansible-playbook executor:** Given a resolved list of targets, write non-sensitive vars for each target to `.generated/ansible/inventory/host_vars/<name>/vars.yml` using `github.com/goccy/go-yaml`. If there are sensitive vars, write them to a temporary file (using `os.CreateTemp`). Clean up the temporary file when the executor returns, even if ansible fails. Build and run an `ansible-playbook` invocation that uses `.generated/ansible/inventory/hosts.yml` as the inventory, passes `--limit <comma-joined names>` to restrict execution to the targets, and passes `-e @<tmpfile>` if a sensitive vars file was created. Stream stdout and stderr from the subprocess to the terminal.

**Required Tests**

*Unit test — host resolution defaults to all top-level hosts when no CLI hosts are given:*
- Config: two top-level hosts (`"host-01"`, `"host-02"`), each with one VM
- Input: empty CLI host list
- Expected: result is `["host-01", "host-02"]` (VMs not included)

*Unit test — host resolution respects the CLI hosts argument:*
- Config: two hosts with VMs
- Input: `["host-01"]`
- Expected: result is `["host-01"]`

*Unit test — host resolution finds a VM by name:*
- Config: `host-01` containing VM `host-01-vm-01` with `IP: "10.0.100.10"`; `host-01` has `IP: "192.168.1.10"`, `SSH.User: "admin"`
- Input: `["host-01-vm-01"]`
- Expected: resolved target has name `"host-01-vm-01"`, IP `"10.0.100.10"`, and carries parent info (`"host-01"`, `"192.168.1.10"`, `"admin"`)

*Unit test — host resolution returns an error listing all unknown names:*
- Input names include `"nonexistent"` and `"also-missing"` alongside a valid name
- Expected: error message contains both `"nonexistent"` and `"also-missing"`

*Unit test — secret collection reads from the environment when the env var is set:*
- Env: `STC_ADMIN_EMAIL=test@example.com`
- Input reader: empty (must not be read)
- Expected: resolved value is `"test@example.com"`, no error

*Unit test — secret collection prompts when the env var is absent:*
- No env var set
- Input reader: `strings.NewReader("test@example.com\n")`
- Expected: resolved value is `"test@example.com"`, no error

*Unit test — secret collection returns an error on empty prompted input:*
- No env var set
- Input reader: `strings.NewReader("\n")`
- Expected: non-nil error

*Unit test — ansible-playbook args include `--limit` and the extra vars file when provided:*
- Input: playbook `"bootstrap-host"`, targets `["host-01", "host-02"]`, extra vars file `"/tmp/stc-vars-123.yml"`
- Expected: args contain `--limit`, `"host-01,host-02"`, `-e`, `"@/tmp/stc-vars-123.yml"`

*Unit test — ansible-playbook args omit `-e` when no extra vars file is given:*
- Input: same but no extra vars file
- Expected: `-e` is absent from args

**Definition of Done**
- All nine unit tests pass

---

### Task 6 — Implement `stc ansible bootstrap-host`

**Story points:** 3

**Description**

Wire up the `ansible bootstrap-host` command. It runs `ansible/playbooks/bootstrap-host.yml` against a set of hosts after collecting config and secrets. `--preflight` support will be added in Milestone 5.

**Flags:** 0 or more `--host <h>` (defaults to all top-level hosts).

**Config fields required per host:**

| CONFIG NAME | Description |
|---|---|
| `hosts.<name>.ip` | Host LAN IP |
| `hosts.<name>.ssh.user` | SSH username |
| `hosts.<name>.ssh.port` | SSH port |
| `hosts.<name>.ssh.public_key_path` | Path to public key file |
| `hosts.<name>.auto_update_reboot_time` | HH:MM reboot time |

**Secrets** (env var → prompt; never from stc.yml):

| Env var | Ansible var name | Description |
|---|---|---|
| `STC_ADMIN_EMAIL` | `admin_email` | Email for admin notifications |
| `STC_ADMIN_PASSWORD` | `admin_password` | Admin account password |

**`host_vars/<name>/vars.yml` must contain** (non-sensitive only):
- `ansible_host`: host IP
- `ansible_port`: SSH port
- `ansible_user`: determined at runtime (attempt configured SSH user; fall back to `"root"`)
- `ssh_port`: SSH port (used by the playbook to configure sshd)
- `ssh_public_key`: full file contents of `ssh.public_key_path`
- `auto_update_reboot_time`: from stc.yml

Secrets go in the temp vars file, not in `host_vars`.

**Behavior:**
- Any required per-host field missing → print a user-friendly error listing the missing fields, exit 1
- Unknown `--host` value → print error listing the unknown names, exit 1
- All fields present → collect secrets (env → prompt), write `host_vars`, run playbook

**Required Tests**

*Txtar test — `testdata/scripts/bootstrap-host-unknown-host.txtar`:*
```
# Unknown --host value exits 1 with a clear error
! exec stc ansible bootstrap-host --host nonexistent
stderr 'nonexistent'

-- stc.yml --
hosts:
  host-01:
    ip: 192.168.1.10
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

**Definition of Done**
- `stc ansible bootstrap-host --host nonexistent` exits 1 with an error mentioning the unknown name
- `go test ./...` passes

Note: a full end-to-end happy path test (actually running ansible) is out of scope for automated testing. Manual verification is expected.

---

### Task 7 — Implement `stc ansible setup-host`

**Story points:** 2

**Description**

Wire up the `ansible setup-host` command. It is structurally identical to `bootstrap-host` (same flags, same flow) but uses a different playbook, fewer per-host config fields, and different secrets. `--preflight` support will be added in Milestone 5.

**Refactoring note:** Before writing new code, review the implementation from Task 6. The two commands share significant logic (host resolution, secret collection, host_vars writing, playbook execution). Any logic that is duplicated rather than shared is a defect in structure, not just style. The implementor is expected to refactor as needed to eliminate duplication — this is costed into the estimate. The goal is a single shared path through `internal/` that both commands call with different parameters, not two parallel implementations.

**Flags:** 0 or more `--host <h>` (defaults to all top-level hosts).

**Config fields required per host:**

| CONFIG NAME | Description |
|---|---|
| `hosts.<name>.ip` | Host LAN IP |
| `hosts.<name>.ssh.user` | SSH username |
| `hosts.<name>.ssh.port` | SSH port |

**Secrets:**

| Env var | Ansible var name | Description |
|---|---|---|
| `STC_SMTP_USER` | `smtp_user` | SMTP username for Postfix relay |
| `STC_SMTP_PASSWORD` | `smtp_password` | SMTP password |

**`host_vars/<name>/vars.yml` must contain:**
- `ansible_host`, `ansible_port`, `ansible_user` (same as `bootstrap-host`)

Secrets go in the temp vars file. Playbook: `ansible/playbooks/setup-host.yml`.

**Required Tests**

*Txtar test — `testdata/scripts/setup-host-unknown-host.txtar`:*
```
# Unknown --host value exits 1 with a clear error
! exec stc ansible setup-host --host nonexistent
stderr 'nonexistent'

-- stc.yml --
hosts:
  host-01:
    ip: 192.168.1.10
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

**Definition of Done**
- `stc ansible setup-host --host nonexistent` exits 1 with an error mentioning the unknown name
- `go test ./...` passes

---

## Milestone 4 — `stc ssh add`

---

### Task 8 — Implement SSH config block renderer

**Story points:** 2

**Description**

Implement the internal logic for rendering SSH `Host` blocks and appending them to `~/.ssh/config`. Use `text/template` to render each block so the output format is immediately legible from reading the template source.

Top-level host block:
```
Host <name>
  HostName <ip>
  User <ssh.user>
  IdentityFile <ssh.public_key_path>
  Port <ssh.port>
```

VM block (same plus):
```
  ProxyJump <parent.ssh.user>@<parent.ip>
```

**Implementation behavior:**
- Open `~/.ssh/config` with create-if-absent semantics and `0600` permissions
- Parse the existing file to check whether a `Host <name>` alias already exists — use `github.com/kevinburke/ssh_config` for parsing
- If the alias already exists: skip it, print `<name>: already present in ~/.ssh/config, skipping`
- If not: append the rendered block to the end of the file
- Process all targets; do not stop on a skip

**Required Tests**

*Txtar test — `testdata/scripts/ssh-add-host.txtar`:*
```
# ssh add appends a Host block for a top-level host
exec stc ssh add --host host-01
stdout 'Added "host-01"'
grep 'Host host-01' $HOME/.ssh/config
grep 'HostName 192.168.1.10' $HOME/.ssh/config
grep 'User admin' $HOME/.ssh/config
grep 'Port 22' $HOME/.ssh/config
! grep 'ProxyJump' $HOME/.ssh/config

-- stc.yml --
hosts:
  host-01:
    ip: 192.168.1.10
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

*Txtar test — `testdata/scripts/ssh-add-idempotent.txtar`:*
```
# Running ssh add twice for the same host: second run skips gracefully
exec stc ssh add --host host-01
stdout 'Added'

exec stc ssh add --host host-01
stdout 'skipping'

-- stc.yml --
hosts:
  host-01:
    ip: 192.168.1.10
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

*Txtar test — `testdata/scripts/ssh-add-vm.txtar`:*
```
# ssh add for a VM includes a ProxyJump directive
exec stc ssh add --host host-01-vm-01
stdout 'Added "host-01-vm-01"'
grep 'Host host-01-vm-01' $HOME/.ssh/config
grep 'HostName 10.0.100.10' $HOME/.ssh/config
grep 'ProxyJump admin@192.168.1.10' $HOME/.ssh/config

-- stc.yml --
hosts:
  host-01:
    ip: 192.168.1.10
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
    vms:
      host-01-vm-01:
        ip: 10.0.100.10
        ssh:
          user: admin
          port: 22
          private_key_path: ~/.ssh/id_ed25519
          public_key_path: ~/.ssh/id_ed25519.pub
        auto_update_reboot_time: "05:00"
```

**Definition of Done**
- All three txtar tests pass
- `go test ./...` passes

---

### Task 9 — Implement `stc ssh add` command

**Story points:** 1

**Description**

Wire up the `ssh add` command using the SSH config writer from Task 8 and the host resolver from Task 5. `--preflight` support will be added in Milestone 5.

**Flags:** 0 or more `--host <h>` (defaults to all top-level hosts; VMs not included in default).

**Required config fields per top-level host:** `hosts.<name>.ip`, `hosts.<name>.ssh.user`, `hosts.<name>.ssh.public_key_path`, `hosts.<name>.ssh.port`. For a VM, the same four fields from the VM's own config plus the parent host's `ip` and `ssh.user` for ProxyJump.

**Behavior:**
- Any required field missing → print a user-friendly error, exit 1
- Unknown `--host` → print error listing the unknown names, exit 1
- All fields present → write entries (skipping any already present), exit 0

No secret variables. No interactive prompting.

**Required Tests**

*Txtar test — `testdata/scripts/ssh-add-unknown-host.txtar`:*
```
# Unknown --host value exits 1 with a clear error
! exec stc ssh add --host nonexistent
stderr 'nonexistent'

-- stc.yml --
hosts:
  host-01:
    ip: 192.168.1.10
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

**Definition of Done**
- All txtar tests pass (including the three from Task 8)
- `go test ./...` passes

---

## Milestone 5 — `--preflight` support

All commands gain a `--preflight` flag that prints a diagnostic table showing the status of each required config value instead of executing the command.

---

### Task 10 — Add `--preflight` to `stc inventory generate`

**Story points:** 2

**Description**

Add a `--preflight` boolean flag as a persistent flag on the root command so it is available to every subcommand, then wire it into `inventory generate`.

When `--preflight` is passed, the command must print a two-column ASCII table to stdout showing the status of each required config value, then exit 0 without writing any files. When `--preflight` is NOT passed and any required field is missing, the command should now print this same table (instead of a plain error message) and exit 1.

**Refactoring note:** Adding preflight requires separating two concerns that may be tangled in the Task 4 implementation: (1) collecting and validating the required config values, and (2) acting on them (writing the file). The implementor is expected to refactor the `inventory generate` implementation as needed so that validation produces a data structure that can be both rendered as a table (preflight path) and used to drive file generation (normal path). This refactoring is costed into the estimate.

The table format (column widths auto-size to the widest entry in each column including headers):
```
---------------------------------------------------
| CONFIG NAME                         | STATUS    |
---------------------------------------------------
| hosts.host-01.ip                    | loaded    |
| hosts.host-01.vms.host-01-vm-01.ip  | loaded    |
| hosts.host-01.ssh.user              | loaded    |
| hosts.host-02.ip                    | not found |
---------------------------------------------------
```

Requirements:
- Use `text/template` to render the table
- Column widths auto-size — no truncation, no excess whitespace
- Two possible status values for `inventory generate`: `loaded` (field present and non-empty) or `not found`
- Header: `CONFIG NAME` | `STATUS`; bordered with `-`; columns separated by ` | ` with one space padding each side

**Required Tests**

*Txtar test — `testdata/scripts/inventory-generate-preflight.txtar`:*
```
# --preflight prints diagnostic table, exits 0, writes no files
exec stc inventory generate --preflight
stdout 'CONFIG NAME'
stdout 'STATUS'
stdout 'loaded'
! exists .generated/ansible/inventory/hosts.yml

-- stc.yml --
hosts:
  host-01:
    ip: 192.168.1.10
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

*Txtar test — `testdata/scripts/inventory-generate-missing-ip-table.txtar`:*
```
# Missing ip: prints diagnostic table with 'not found' and exits 1 without writing file
! exec stc inventory generate
stdout 'not found'
! exists .generated/ansible/inventory/hosts.yml

-- stc.yml --
hosts:
  host-01:
    ip: ""
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

*Unit tests for the table renderer:*
- Input: one row `("hosts.host-01.ip", "loaded")` → assert exact output string matches expected table with correct borders and padding
- Input: two rows where the second field name is longer → assert column widths adapt to the wider entry with no truncation

**Definition of Done**
- Both txtar tests pass
- Table column widths adapt dynamically
- `--preflight` is accepted by all subcommands without an "unknown flag" error
- `go test ./...` passes

---

### Task 11 — Add `--preflight` to `stc ansible bootstrap-host` and `stc ansible setup-host`

**Story points:** 2

**Description**

Wire `--preflight` into the two ansible commands using the same table format introduced in Task 10. These commands add a third possible status value: `will prompt`, used for secret fields that are not set in the environment (meaning the user will be prompted at runtime).

**Refactoring note:** Same structural separation applies as in Task 10 — config collection/validation must be decoupled from execution so the same validation result can drive both the diagnostic table and the playbook run. The implementor should also ensure the table-rendering logic from Task 10 is genuinely shared, not duplicated. Refactoring Tasks 6 and 7 as needed is expected and costed into the estimate.

**For `bootstrap-host`**, the table covers:
- Per host: `hosts.<name>.ip`, `hosts.<name>.ssh.user`, `hosts.<name>.ssh.port`, `hosts.<name>.ssh.public_key_path`, `hosts.<name>.auto_update_reboot_time`
- Global secrets (one row each, regardless of host count): `STC_ADMIN_EMAIL`, `STC_ADMIN_PASSWORD` — status is `loaded` if the env var is set and non-empty, `will prompt` otherwise

**For `setup-host`**, the table covers:
- Per host: `hosts.<name>.ip`, `hosts.<name>.ssh.user`, `hosts.<name>.ssh.port`
- Global secrets: `STC_SMTP_USER`, `STC_SMTP_PASSWORD`

When `--preflight` is NOT passed and any per-host field is missing, print the same diagnostic table and exit 1. Secrets are never "missing" — they will always be `loaded` or `will prompt`.

**Required Tests**

*Txtar test — `testdata/scripts/bootstrap-host-preflight.txtar`:*
```
# --preflight prints diagnostic table with all required fields and exits 0
exec stc ansible bootstrap-host --preflight
stdout 'CONFIG NAME'
stdout 'hosts.host-01.ip'
stdout 'hosts.host-01.ssh.user'
stdout 'hosts.host-01.ssh.port'
stdout 'hosts.host-01.ssh.public_key_path'
stdout 'hosts.host-01.auto_update_reboot_time'
stdout 'STC_ADMIN_EMAIL'
stdout 'STC_ADMIN_PASSWORD'
stdout 'will prompt'
! exists .generated/ansible/inventory/host_vars/host-01/vars.yml

-- stc.yml --
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
    vms: {}
```

*Txtar test — `testdata/scripts/bootstrap-host-preflight-env-loaded.txtar`:*
```
# When STC_ADMIN_EMAIL is set in the environment, its row shows as loaded
env STC_ADMIN_EMAIL=admin@example.com
exec stc ansible bootstrap-host --preflight
stdout 'STC_ADMIN_EMAIL'
stdout 'loaded'

-- stc.yml --
hosts:
  host-01:
    ip: 192.168.1.10
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

*Txtar test — `testdata/scripts/setup-host-preflight.txtar`:*
```
# --preflight for setup-host shows the correct fields (not bootstrap-host fields)
exec stc ansible setup-host --preflight
stdout 'hosts.host-01.ip'
stdout 'hosts.host-01.ssh.user'
stdout 'hosts.host-01.ssh.port'
stdout 'STC_SMTP_USER'
stdout 'STC_SMTP_PASSWORD'
! stdout 'auto_update_reboot_time'
! stdout 'STC_ADMIN_EMAIL'

-- stc.yml --
hosts:
  host-01:
    ip: 192.168.1.10
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

**Definition of Done**
- All three txtar tests pass
- `go test ./...` passes

---

### Task 12 — Add `--preflight` to `stc ssh add`

**Story points:** 1

**Description**

Wire `--preflight` into the `ssh add` command. There are no secret fields for this command, so all rows show either `loaded` or `not found`. When `--preflight` is passed, print the diagnostic table and exit 0 without touching `~/.ssh/config`. When `--preflight` is NOT passed and any required field is missing, print the diagnostic table and exit 1.

**Refactoring note:** Same structural separation as Tasks 10 and 11. By this point the pattern should be well-established — if `ssh add`'s implementation from Tasks 8 and 9 doesn't fit the pattern cleanly, refactor it. The implementor should also verify the table-rendering path is genuinely shared across all three preflight implementations (inventory, ansible commands, ssh add) and consolidate if it isn't.

**Required config fields per top-level host:** `hosts.<name>.ip`, `hosts.<name>.ssh.user`, `hosts.<name>.ssh.public_key_path`, `hosts.<name>.ssh.port`. For a VM, the same four fields from the VM's own config plus `hosts.<parent-name>.ip` and `hosts.<parent-name>.ssh.user`.

**Required Tests**

*Txtar test — `testdata/scripts/ssh-add-preflight.txtar`:*
```
# --preflight prints required fields and exits without modifying ~/.ssh/config
exec stc ssh add --preflight
stdout 'CONFIG NAME'
stdout 'hosts.host-01.ip'
stdout 'hosts.host-01.ssh.user'
stdout 'hosts.host-01.ssh.public_key_path'
stdout 'hosts.host-01.ssh.port'
! exists $HOME/.ssh/config

-- stc.yml --
hosts:
  host-01:
    ip: 192.168.1.10
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

*Txtar test — `testdata/scripts/ssh-add-missing-field.txtar`:*
```
# Missing public_key_path: diagnostic table shown, exits 1
! exec stc ssh add
stdout 'not found'
stdout 'ssh.public_key_path'

-- stc.yml --
hosts:
  host-01:
    ip: 192.168.1.10
    ssh:
      user: admin
      port: 22
      private_key_path: ~/.ssh/id_ed25519
      public_key_path: ""
    auto_update_reboot_time: "05:00"
    wireguard_endpoint: false
    incus:
      storage_pool_name: default
      storage_pool_driver: dir
    vms: {}
```

**Definition of Done**
- Both txtar tests pass
- `go test ./...` passes

---

## Milestone 6 — `stc setup`

---

### Task 13 — Implement `stc setup` command with merged preflight

**Story points:** 3

**Description**

Wire up the `setup` command, which orchestrates full provisioning end-to-end. This is the primary command most users run.

**Refactoring note:** `setup` must call into `internal/` directly — it must not shell out to `stc inventory generate`, `stc ansible setup-host`, etc. as subprocesses, and it must not duplicate their logic. If the business logic from earlier tasks isn't cleanly callable from `internal/` at this point, refactor it until it is. This refactoring is costed into the estimate and is considered part of the definition of done — the merged preflight in particular is only achievable if each sub-operation can return its diagnostics as a value rather than printing them as a side effect.

**Flags:** 0 or more `--host <h>` (defaults to all top-level hosts), optional `--preflight`.

**Execution order:**
1. `inventory generate`
2. `ansible setup-host`
3. `ansible bootstrap-host`
4. `ssh add`

**Preflight behavior:** When `--preflight` is passed, collect diagnostics from all four sub-operations and merge them into a **single** table. Deduplicate rows that appear in multiple sub-operations (e.g. `hosts.host-01.ip` is required by multiple commands — show it once). Print the merged table and exit 0. Write no files and launch no subprocesses.

**Upfront secret collection:** When NOT in preflight mode, collect ALL secrets before starting execution — prompt for `STC_SMTP_USER`, `STC_SMTP_PASSWORD`, `STC_ADMIN_EMAIL`, and `STC_ADMIN_PASSWORD` at the start. The user should not be interrupted once the playbooks are running.

**Required Tests**

*Txtar test — `testdata/scripts/setup-preflight-merged-table.txtar`:*
```
# setup --preflight shows one merged table covering all four commands
exec stc setup --preflight
stdout 'CONFIG NAME'

# inventory generate fields
stdout 'hosts.host-01.ip'

# bootstrap-host-only fields
stdout 'hosts.host-01.ssh.public_key_path'
stdout 'hosts.host-01.auto_update_reboot_time'
stdout 'STC_ADMIN_EMAIL'
stdout 'STC_ADMIN_PASSWORD'

# setup-host secrets
stdout 'STC_SMTP_USER'
stdout 'STC_SMTP_PASSWORD'

# ssh add fields
stdout 'hosts.host-01.ssh.user'

# No files written
! exists .generated/ansible/inventory/hosts.yml
! exists $HOME/.ssh/config

-- stc.yml --
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
    vms: {}
```

*Txtar test — `testdata/scripts/setup-preflight-no-duplicate-rows.txtar`:*
```
# Fields shared between multiple subcommands appear only once in the merged table
exec stc setup --preflight
stdout 'hosts.host-01.ip'

-- stc.yml --
hosts:
  host-01:
    ip: 192.168.1.10
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

*Txtar test — `testdata/scripts/setup-missing-field-exits-before-execution.txtar`:*
```
# A missing required field causes setup to exit before generating any files
! exec stc setup
stdout 'not found'
! exists .generated/ansible/inventory/hosts.yml

-- stc.yml --
hosts:
  host-01:
    ip: ""
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

**Definition of Done**
- All three txtar tests pass
- `./stc setup --preflight` shows a single merged table (not four separate tables)
- No prompts appear mid-execution when running `./stc setup`
- `go test ./...` passes
