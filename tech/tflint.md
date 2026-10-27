# TFLint

## 1. What it is

TFLint is a **linter for Terraform**: it reads `.tf` files and reports likely mistakes that `terraform validate` does not catch, such as an unused variable, a missing version constraint, or (with the Google rule set) a machine type or a setting value that does not exist. It runs locally with no cloud account.

## 2. Why this repository uses it

`terraform validate` only checks that the files are well formed. TFLint adds rules about good practice and about the Google provider, so the modules stay tidy and typos in provider settings are found early.

## 3. Where it appears

| Path | What it does |
| --- | --- |
| `infra/.tflint.hcl` | The TFLint configuration: which rule sets to use. |
| `Makefile` | `make lint-terraform` runs `tflint --init` and then `tflint --recursive`. |
| `.github/workflows/ci.yml` | Installs TFLint (v0.65.0) and runs the same make target. |

## 4. How it works underneath

TFLint is a program with **plug-ins** (rule sets). `tflint --init` downloads the plug-ins named in the config from GitHub releases into `~/.tflint.d/plugins`. `tflint --recursive` walks every folder under the current one that holds Terraform files and checks each. A rule set is built in (`terraform`, with a `recommended` preset) and one is the Google provider's (`google`, version 0.41.0). Findings print with a rule name; the exit status is non-zero if any are found.

## 5. Walkthrough of this repository's use

`infra/.tflint.hcl`

```hcl
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "google" {
  enabled = true
  version = "0.41.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}
```

- `config { call_module_type = "local" }`: when the environment calls a module from a local folder, check inside it too.
- `plugin "terraform" { enabled = true; preset = "recommended" }`: the built-in Terraform rules (naming, unused declarations, required versions, deprecated syntax).
- `plugin "google" { version, source }`: the Google rule set, pinned to a version and fetched from the stated GitHub path.

The make target:

`Makefile`

```make
lint-terraform:
	$(TF) fmt -check -recursive -diff infra
	cd infra && tflint --init >/dev/null && tflint --recursive --config "$$PWD/.tflint.hcl"
```

- `terraform fmt -check -recursive -diff infra` first checks the layout (see `terraform.md`).
- `cd infra && tflint --init >/dev/null && tflint --recursive --config "$$PWD/.tflint.hcl"`: install plug-ins quietly, then check every folder using the one config file. `$$PWD` is the absolute path of `infra`; the doubled `$` is Make's escape.

## 6. Try it yourself

```bash
tflint --version
```
Expected: `TFLint version 0.65.0` and a line for the `terraform` ruleset.

```bash
cd infra && tflint --init && tflint --recursive --config "$PWD/.tflint.hcl"; echo "exit=$?"
```
Expected: `Installing "google" plugin...` the first time (needs network), then no findings and `exit=0`.

Make a finding: add `variable "unused" {}` to `infra/modules/service-account/variables.tf`, rerun, and read the two warnings (`variable "unused" is declared but not used` and one about the missing type); remove the line.

## 7. Mistakes people make

- **Skipping `--init`** and getting "plugin not installed".
- **Not pinning the plug-in version.** Rule changes would break builds without warning.
- **Running only in one folder.** Use `--recursive` so every module is checked.
- **Treating findings as noise.** Fix them or record why a rule is off.

## 8. Check yourself

1. What does TFLint add to `terraform validate`? *Good-practice and provider-specific rules.*
2. What does `tflint --init` do? *Downloads the plug-ins named in the config.*
3. What does `--recursive` do? *Checks every folder with Terraform files below the current one.*
4. Why pin the Google plug-in version? *So the rule set does not change under you.*
5. What does `call_module_type = "local"` mean? *Also check local modules that are called.*

## 9. Further reading

- TFLint: <https://github.com/terraform-linters/tflint>
- Configuration: <https://github.com/terraform-linters/tflint/blob/master/docs/user-guide/config.md>
- Google ruleset: <https://github.com/terraform-linters/tflint-ruleset-google>
