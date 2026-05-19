package formula

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func polecatPRBootstrapDir(t *testing.T) string {
	t.Helper()
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	repoRoot := filepath.Clean(filepath.Join(cwd, "..", ".."))
	return filepath.Join(repoRoot, "internal", "bootstrap", "packs", "core", "formulas")
}

func loadPolecatPR(t *testing.T) *Formula {
	t.Helper()
	dir := polecatPRBootstrapDir(t)
	parser := NewParser(dir)
	parsed, err := parser.ParseFile(filepath.Join(dir, "mol-polecat-pr.toml"))
	if err != nil {
		t.Fatalf("ParseFile: %v", err)
	}
	return parsed
}

func resolvedPolecatPR(t *testing.T) *Formula {
	t.Helper()
	dir := polecatPRBootstrapDir(t)
	parser := NewParser(dir)
	parsed, err := parser.ParseFile(filepath.Join(dir, "mol-polecat-pr.toml"))
	if err != nil {
		t.Fatalf("ParseFile: %v", err)
	}
	resolved, err := parser.Resolve(parsed)
	if err != nil {
		t.Fatalf("Resolve: %v", err)
	}
	return resolved
}

func mustStepByID(t *testing.T, f *Formula, id string) *Step {
	t.Helper()
	for _, s := range f.Steps {
		if s.ID == id {
			return s
		}
	}
	t.Fatalf("step %q not found in formula %q", id, f.Formula)
	return nil
}

// TestPolecatPRFormula_StructureAndVars verifies the formula extends
// mol-polecat-base and declares the documented vars with correct defaults.
func TestPolecatPRFormula_StructureAndVars(t *testing.T) {
	parsed := loadPolecatPR(t)

	if parsed.Formula != "mol-polecat-pr" {
		t.Errorf("formula name = %q, want mol-polecat-pr", parsed.Formula)
	}
	if len(parsed.Extends) != 1 || parsed.Extends[0] != "mol-polecat-base" {
		t.Errorf("extends = %v, want [mol-polecat-base]", parsed.Extends)
	}

	wantDefaults := map[string]string{
		"upstream_remote":       "upstream",
		"upstream_org":          "gastownhall",
		"upstream_repo":         "gascity",
		"target_base":           "main",
		"origin_remote":         "origin",
		"branch_prefix_bug":     "fix",
		"branch_prefix_feature": "feat",
		"pr_template_path":      ".github/pull_request_template.md",
		"pr_private_denylist":   "financials,IMPACT,coop-manager,sypl-code,clarity,gascity-clarity",
	}
	for name, want := range wantDefaults {
		def, ok := parsed.Vars[name]
		if !ok {
			t.Errorf("vars.%s not declared", name)
			continue
		}
		if def.Default == nil {
			t.Errorf("vars.%s default = nil, want %q", name, want)
			continue
		}
		if *def.Default != want {
			t.Errorf("vars.%s default = %q, want %q", name, *def.Default, want)
		}
	}
}

// TestPolecatPRFormula_BranchOffUpstream asserts the workspace-setup step
// creates the worktree off the upstream remote, not origin.
func TestPolecatPRFormula_BranchOffUpstream(t *testing.T) {
	parsed := loadPolecatPR(t)
	step := mustStepByID(t, parsed, "workspace-setup")

	desc := step.Description
	if !strings.Contains(desc, "git fetch {{upstream_remote}}") {
		t.Errorf("workspace-setup missing 'git fetch {{upstream_remote}}'\n%s", desc)
	}
	if !strings.Contains(desc, "{{upstream_remote}}/{{target_base}}") {
		t.Errorf("workspace-setup missing worktree base '{{upstream_remote}}/{{target_base}}'\n%s", desc)
	}
	if strings.Contains(desc, "origin/{{base_branch}}") {
		t.Errorf("workspace-setup still references origin/{{base_branch}} — must branch off upstream\n%s", desc)
	}
}

// TestPolecatPRFormula_BranchPrefixByType asserts the workspace-setup step
// picks a branch prefix based on bead type (bug → fix, feature/task → feat).
func TestPolecatPRFormula_BranchPrefixByType(t *testing.T) {
	parsed := loadPolecatPR(t)
	step := mustStepByID(t, parsed, "workspace-setup")

	desc := step.Description
	for _, ref := range []string{
		"{{branch_prefix_bug}}",
		"{{branch_prefix_feature}}",
	} {
		if !strings.Contains(desc, ref) {
			t.Errorf("workspace-setup missing %s\n%s", ref, desc)
		}
	}
	// The prompt must instruct the worker to pick by bead type.
	if !strings.Contains(strings.ToLower(desc), "bead.type") &&
		!strings.Contains(strings.ToLower(desc), "issue type") &&
		!strings.Contains(strings.ToLower(desc), "if type") {
		t.Errorf("workspace-setup does not direct branch prefix by bead type\n%s", desc)
	}
}

// TestPolecatPRFormula_SlugDerivation asserts the workspace-setup step derives
// the branch slug from the bead title with the documented rules (lowercase,
// alphanumeric + hyphens, max 40 chars).
func TestPolecatPRFormula_SlugDerivation(t *testing.T) {
	parsed := loadPolecatPR(t)
	step := mustStepByID(t, parsed, "workspace-setup")

	desc := step.Description
	// The slug rules are documented in-line so the worker knows how to derive
	// them — assert the documented constraints appear in the prompt.
	for _, marker := range []string{
		"40",        // max length
		"lowercase", // case normalization
		"alphanumeric",
		"hyphen",
	} {
		if !strings.Contains(strings.ToLower(desc), marker) {
			t.Errorf("workspace-setup slug rule missing marker %q\n%s", marker, desc)
		}
	}
}

// TestPolecatPRFormula_CollisionSuffix asserts the workspace-setup step
// handles a pre-existing branch by appending a hex suffix.
func TestPolecatPRFormula_CollisionSuffix(t *testing.T) {
	parsed := loadPolecatPR(t)
	step := mustStepByID(t, parsed, "workspace-setup")

	desc := step.Description
	if !strings.Contains(desc, "git rev-parse --verify") {
		t.Errorf("workspace-setup missing local-branch collision check 'git rev-parse --verify'\n%s", desc)
	}
	if !strings.Contains(desc, "git ls-remote --heads {{origin_remote}}") {
		t.Errorf("workspace-setup missing remote-branch collision check 'git ls-remote --heads {{origin_remote}}'\n%s", desc)
	}
	if !strings.Contains(desc, "openssl rand -hex 3") {
		t.Errorf("workspace-setup missing 6-hex-char suffix generator 'openssl rand -hex 3'\n%s", desc)
	}
}

// TestPolecatPRFormula_DenylistSanitization asserts the commit-and-push step
// sanitizes the PR body via the denylist and replaces hits with <redacted>.
func TestPolecatPRFormula_DenylistSanitization(t *testing.T) {
	parsed := loadPolecatPR(t)
	step := mustStepByID(t, parsed, "commit-and-push")

	desc := step.Description
	if !strings.Contains(desc, "{{pr_private_denylist}}") {
		t.Errorf("commit-and-push does not reference {{pr_private_denylist}}\n%s", desc)
	}
	if !strings.Contains(desc, "<redacted>") {
		t.Errorf("commit-and-push missing <redacted> placeholder\n%s", desc)
	}
	// When a denylist substring hits the TITLE, the worker must REPLACE the
	// entire title rather than emit a half-redacted title.
	low := strings.ToLower(desc)
	if !strings.Contains(low, "replace the entire title") &&
		!strings.Contains(low, "generic placeholder") {
		t.Errorf("commit-and-push does not instruct full-title replacement on denylist hit\n%s", desc)
	}
	// Per-hit WARN log instruction for mayor audit.
	if !strings.Contains(low, "warn") {
		t.Errorf("commit-and-push does not emit a WARN log on denylist hit\n%s", desc)
	}
}

// TestPolecatPRFormula_TemplateRendering asserts the commit-and-push step
// renders the upstream PR template and submits via gh pr create.
func TestPolecatPRFormula_TemplateRendering(t *testing.T) {
	parsed := loadPolecatPR(t)
	step := mustStepByID(t, parsed, "commit-and-push")

	desc := step.Description
	if !strings.Contains(desc, "{{pr_template_path}}") {
		t.Errorf("commit-and-push does not render {{pr_template_path}}\n%s", desc)
	}
	if !strings.Contains(desc, "gh pr create --draft --repo \"{{upstream_org}}/{{upstream_repo}}\"") {
		t.Errorf("commit-and-push missing 'gh pr create --draft --repo \"{{upstream_org}}/{{upstream_repo}}\"'\n%s", desc)
	}
	if !strings.Contains(desc, "--base \"{{target_base}}\"") {
		t.Errorf("commit-and-push missing --base \"{{target_base}}\" on gh pr create\n%s", desc)
	}
	if !strings.Contains(desc, "pr_url") {
		t.Errorf("commit-and-push does not record PR URL on bead metadata\n%s", desc)
	}
	// Bead closes with gc.outcome=success.
	if !strings.Contains(desc, "gc.outcome=success") {
		t.Errorf("commit-and-push does not set gc.outcome=success on close\n%s", desc)
	}
}

// TestPolecatPRFormula_PushRetry asserts the commit-and-push step pushes the
// feature branch to the origin remote with the 3-attempt rebase-retry policy.
func TestPolecatPRFormula_PushRetry(t *testing.T) {
	parsed := loadPolecatPR(t)
	step := mustStepByID(t, parsed, "commit-and-push")

	desc := step.Description
	if !strings.Contains(desc, "git push -u {{origin_remote}}") {
		t.Errorf("commit-and-push missing 'git push -u {{origin_remote}} ...'\n%s", desc)
	}
	if !strings.Contains(desc, "for attempt in 1 2 3") {
		t.Errorf("commit-and-push missing 3-attempt retry loop\n%s", desc)
	}
	if !strings.Contains(desc, "git fetch {{upstream_remote}} {{target_base}}") {
		t.Errorf("commit-and-push missing rebase fetch 'git fetch {{upstream_remote}} {{target_base}}'\n%s", desc)
	}
	if !strings.Contains(desc, "git rebase {{upstream_remote}}/{{target_base}}") {
		t.Errorf("commit-and-push missing rebase 'git rebase {{upstream_remote}}/{{target_base}}'\n%s", desc)
	}
}

// TestPolecatPRFormula_CommitsOnFeatureBranch asserts the commit-and-push step
// commits on the feature branch (not base_branch) and does NOT push to the
// upstream remote.
func TestPolecatPRFormula_CommitsOnFeatureBranch(t *testing.T) {
	parsed := loadPolecatPR(t)
	step := mustStepByID(t, parsed, "commit-and-push")

	desc := step.Description
	if strings.Contains(desc, "HEAD:{{base_branch}}") || strings.Contains(desc, "HEAD:{{target_base}}") {
		t.Errorf("commit-and-push pushes to base/target branch — must push feature branch only\n%s", desc)
	}
	if strings.Contains(desc, "git push {{upstream_remote}}") || strings.Contains(desc, "git push -u {{upstream_remote}}") {
		t.Errorf("commit-and-push pushes to upstream remote — must push to origin\n%s", desc)
	}
}

// TestPolecatPRFormula_InheritsBaseSteps asserts the resolved formula carries
// load-context, preflight-tests, implement, and self-review verbatim from
// mol-polecat-base.
func TestPolecatPRFormula_InheritsBaseSteps(t *testing.T) {
	resolved := resolvedPolecatPR(t)

	for _, id := range []string{
		"load-context",
		"preflight-tests",
		"implement",
		"self-review",
	} {
		if mustStepByID(t, resolved, id) == nil {
			t.Errorf("resolved formula missing inherited step %q", id)
		}
	}
}

// TestPolecatPRFormula_Compiles asserts the formula compiles cleanly with
// only the required var (issue) provided.
func TestPolecatPRFormula_Compiles(t *testing.T) {
	dir := polecatPRBootstrapDir(t)

	recipe, err := Compile(context.Background(), "mol-polecat-pr", []string{dir}, map[string]string{
		"issue": "gascity-test-1",
	})
	if err != nil {
		t.Fatalf("Compile: %v", err)
	}
	if recipe == nil {
		t.Fatal("Compile returned nil recipe")
	}
	if len(recipe.Steps) == 0 {
		t.Fatal("Compile produced empty recipe")
	}
}
