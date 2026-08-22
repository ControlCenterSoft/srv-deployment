package dns

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"
)

type ResolverPreflightRequest struct {
	Nameservers               []string `json:"nameservers"`
	SearchDomains             []string `json:"search_domains"`
	ExpectedSourceFingerprint string   `json:"expected_source_fingerprint"`
}

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
	SourceMode            string                   `json:"source_mode"`
	SourceManager         string                   `json:"source_manager"`
	SourceAmbiguous       bool                     `json:"source_ambiguous"`
	SourceFingerprint     string                   `json:"source_fingerprint"`
	Desired               ResolverDesiredState     `json:"desired"`
	Actual                ResolverDesiredState     `json:"actual"`
	Rollback              ResolverDesiredState     `json:"rollback"`
	Checks                []ResolverPreflightCheck `json:"checks"`
	Blockers              []string                 `json:"blockers"`
	Warnings              []string                 `json:"warnings"`
	RequiredExecutorSteps []string                 `json:"required_executor_steps"`
}

func PreflightResolverChange(in ResolverPreflightRequest, actual ResolverState) (ResolverPreflightResult, error) {
	expectedFingerprint := strings.TrimSpace(in.ExpectedSourceFingerprint)
	if !validResolverFingerprint(expectedFingerprint) {
		return ResolverPreflightResult{}, fmt.Errorf("valid expected source fingerprint is required")
	}
	plan, err := PreviewResolverChange(ResolverChangeRequest{
		Nameservers:   in.Nameservers,
		SearchDomains: in.SearchDomains,
	}, actual)
	if err != nil {
		return ResolverPreflightResult{}, err
	}

	sourceSupported := actual.SourceKind == "resolv_conf" || actual.SourceKind == resolverSourceManagerSystemd
	fingerprint := ResolverStateFingerprint(actual)
	rollbackAvailable := len(plan.Rollback.Nameservers) > 0
	checks := []ResolverPreflightCheck{
		{Name: "resolver_inventory_available", OK: len(actual.Nameservers) > 0},
		{Name: "resolver_source_supported", OK: sourceSupported, Detail: actual.SourceKind},
		{Name: "resolver_source_fingerprint_available", OK: fingerprint != ""},
		{Name: "resolver_source_unchanged", OK: fingerprint != "" && expectedFingerprint == fingerprint},
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
		SourceMode:        actual.SourceMode,
		SourceManager:     actual.SourceManager,
		SourceAmbiguous:   actual.SourceAmbiguous,
		SourceFingerprint: fingerprint,
		Desired:           plan.Desired,
		Actual:            plan.Actual,
		Rollback:          plan.Rollback,
		Checks:            checks,
		Blockers:          blockers,
		Warnings:          resolverSourceWarnings(actual),
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
		"source_mode=" + actual.SourceMode,
		"source_manager=" + actual.SourceManager,
		"source_ambiguous=" + boolString(actual.SourceAmbiguous),
		"etc_target=" + actual.EtcResolvConfTarget,
		"stub_detected=" + boolString(actual.StubDetected),
		"nameservers=" + strings.Join(actual.Nameservers, ","),
		"search_domains=" + strings.Join(actual.SearchDomains, ","),
		"options=" + strings.Join(actual.Options, ","),
	}, "\n")
	sum := sha256.Sum256([]byte(canonical))
	return "sha256:" + hex.EncodeToString(sum[:])
}

func validResolverFingerprint(value string) bool {
	if len(value) != len("sha256:")+64 || !strings.HasPrefix(value, "sha256:") {
		return false
	}
	_, err := hex.DecodeString(strings.TrimPrefix(value, "sha256:"))
	return err == nil
}

func boolString(value bool) string {
	if value {
		return "true"
	}
	return "false"
}
