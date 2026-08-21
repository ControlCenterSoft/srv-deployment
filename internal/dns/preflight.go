package dns

import (
	"crypto/sha256"
	"encoding/hex"
	"strings"
)

type ResolverPreflightCheck struct {
	Name   string `json:"name"`
	OK     bool   `json:"ok"`
	Detail string `json:"detail,omitempty"`
}

type ResolverPreflightResult struct {
	Schema                int                      `json:"schema"`
	Passed                bool                     `json:"passed"`
	NoOp                  bool                     `json:"no_op"`
	ApplySupported        bool                     `json:"apply_supported"`
	SourceKind            string                   `json:"source_kind"`
	SourceFingerprint     string                   `json:"source_fingerprint"`
	Desired               ResolverDesiredState     `json:"desired"`
	Actual                ResolverDesiredState     `json:"actual"`
	Rollback              ResolverDesiredState     `json:"rollback"`
	Checks                []ResolverPreflightCheck `json:"checks"`
	Blockers              []string                 `json:"blockers"`
	RequiredExecutorSteps []string                 `json:"required_executor_steps"`
}

func PreflightResolverChange(in ResolverChangeRequest, actual ResolverState) (ResolverPreflightResult, error) {
	plan, err := PreviewResolverChange(in, actual)
	if err != nil {
		return ResolverPreflightResult{}, err
	}

	sourceSupported := actual.SourceKind == "resolv_conf" || actual.SourceKind == "systemd_resolved"
	fingerprint := ResolverStateFingerprint(actual)
	rollbackAvailable := len(plan.Rollback.Nameservers) > 0
	checks := []ResolverPreflightCheck{
		{Name: "resolver_inventory_available", OK: len(actual.Nameservers) > 0},
		{Name: "resolver_source_supported", OK: sourceSupported, Detail: actual.SourceKind},
		{Name: "resolver_source_fingerprint_available", OK: fingerprint != ""},
		{Name: "desired_state_validated", OK: true},
		{Name: "rollback_state_available", OK: rollbackAvailable},
	}
	blockers := make([]string, 0, 2)
	for _, check := range checks {
		if !check.OK {
			blockers = append(blockers, check.Name)
		}
	}

	return ResolverPreflightResult{
		Schema:            1,
		Passed:            len(blockers) == 0,
		NoOp:              plan.NoOp,
		ApplySupported:    false,
		SourceKind:        actual.SourceKind,
		SourceFingerprint: fingerprint,
		Desired:           plan.Desired,
		Actual:            plan.Actual,
		Rollback:          plan.Rollback,
		Checks:            checks,
		Blockers:          blockers,
		RequiredExecutorSteps: []string{
			"backup_current_resolver_state",
			"apply_desired_resolver_state",
			"verify_resolution_before_commit",
			"rollback_on_verify_failure",
		},
	}, nil
}

func ResolverStateFingerprint(actual ResolverState) string {
	if actual.SourceKind == "" || actual.Source == "" || len(actual.Nameservers) == 0 {
		return ""
	}
	canonical := strings.Join([]string{
		"schema=1",
		"source_kind=" + actual.SourceKind,
		"source=" + actual.Source,
		"etc_target=" + actual.EtcResolvConfTarget,
		"stub_detected=" + boolString(actual.StubDetected),
		"nameservers=" + strings.Join(actual.Nameservers, ","),
		"search_domains=" + strings.Join(actual.SearchDomains, ","),
		"options=" + strings.Join(actual.Options, ","),
	}, "\n")
	sum := sha256.Sum256([]byte(canonical))
	return "sha256:" + hex.EncodeToString(sum[:])
}

func boolString(value bool) string {
	if value {
		return "true"
	}
	return "false"
}
