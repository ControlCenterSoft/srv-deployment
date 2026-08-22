package network

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"sort"
	"strconv"
	"strings"
)

type AddressPreflightRequest struct {
	Interface                 string `json:"interface"`
	CIDR                      string `json:"cidr"`
	ExpectedSourceFingerprint string `json:"expected_source_fingerprint"`
}

type AddressPreflightCheck struct {
	Name   string `json:"name"`
	OK     bool   `json:"ok"`
	Detail string `json:"detail,omitempty"`
}

type AddressPreflightResult struct {
	Schema                int                     `json:"schema"`
	Passed                bool                    `json:"passed"`
	NoOp                  bool                    `json:"no_op"`
	ApplySupported        bool                    `json:"apply_supported"`
	SourceFingerprint     string                  `json:"source_fingerprint"`
	Interface             string                  `json:"interface"`
	DesiredCIDR           string                  `json:"desired_cidr"`
	ActualAddresses       []string                `json:"actual_addresses"`
	RollbackAddresses     []string                `json:"rollback_addresses"`
	Checks                []AddressPreflightCheck `json:"checks"`
	Blockers              []string                `json:"blockers"`
	Warnings              []string                `json:"warnings"`
	RequiredExecutorSteps []string                `json:"required_executor_steps"`
}

func PreflightAddressChange(in AddressPreflightRequest, interfaces []Interface) (AddressPreflightResult, error) {
	expectedFingerprint := strings.TrimSpace(in.ExpectedSourceFingerprint)
	if !validInterfaceFingerprint(expectedFingerprint) {
		return AddressPreflightResult{}, fmt.Errorf("valid expected source fingerprint is required")
	}

	plan, err := PreviewAddressChange(AddressChangeRequest{Interface: in.Interface, CIDR: in.CIDR}, interfaces)
	if err != nil {
		return AddressPreflightResult{}, err
	}

	fingerprint := InterfaceFingerprintForName(interfaces, plan.Interface)
	rollbackCaptured := len(plan.ActualAddresses) == len(plan.RollbackAddresses)
	if rollbackCaptured {
		for i := range plan.ActualAddresses {
			if plan.ActualAddresses[i] != plan.RollbackAddresses[i] {
				rollbackCaptured = false
				break
			}
		}
	}
	checks := []AddressPreflightCheck{
		{Name: "network_inventory_available", OK: len(interfaces) > 0},
		{Name: "interface_source_fingerprint_available", OK: fingerprint != ""},
		{Name: "interface_source_unchanged", OK: fingerprint != "" && expectedFingerprint == fingerprint},
		{Name: "desired_state_validated", OK: plan.Validation == "passed"},
		{Name: "rollback_state_captured", OK: rollbackCaptured},
		{Name: "recovery_path_required", OK: plan.RequiresRecoveryPath},
	}
	blockers := make([]string, 0, len(checks))
	for _, check := range checks {
		if !check.OK {
			blockers = append(blockers, check.Name)
		}
	}

	warnings := make([]string, 0, len(plan.Warnings)+2)
	warnings = append(warnings, "Preflight only: no host network settings are changed.")
	warnings = append(warnings, plan.Warnings...)
	warnings = append(warnings, "Interface configuration ownership is not identified by this runtime preflight; a future executor must resolve the authoritative network manager before apply.")

	return AddressPreflightResult{
		Schema:            1,
		Passed:            len(blockers) == 0,
		NoOp:              plan.NoOp,
		ApplySupported:    false,
		SourceFingerprint: fingerprint,
		Interface:         plan.Interface,
		DesiredCIDR:       plan.DesiredCIDR,
		ActualAddresses:   append([]string{}, plan.ActualAddresses...),
		RollbackAddresses: append([]string{}, plan.RollbackAddresses...),
		Checks:            checks,
		Blockers:          blockers,
		Warnings:          warnings,
		RequiredExecutorSteps: []string{
			"identify_interface_configuration_owner",
			"backup_current_interface_configuration",
			"verify_recovery_path_before_apply",
			"apply_desired_address_state",
			"verify_management_connectivity_before_commit",
			"rollback_on_verify_failure",
		},
	}, nil
}

func InterfaceFingerprintForName(interfaces []Interface, interfaceName string) string {
	name := strings.TrimSpace(interfaceName)
	for _, current := range interfaces {
		if current.Name == name {
			return InterfaceFingerprint(current)
		}
	}
	return ""
}

func InterfaceFingerprint(current Interface) string {
	name := strings.TrimSpace(current.Name)
	if name == "" || current.Index <= 0 {
		return ""
	}
	flags := append([]string(nil), current.Flags...)
	sort.Strings(flags)
	addresses := append([]string(nil), current.Addresses...)
	sort.Strings(addresses)
	canonical := strings.Join([]string{
		"schema=1",
		"name=" + name,
		"index=" + strconv.Itoa(current.Index),
		"mtu=" + strconv.Itoa(current.MTU),
		"hardware_address=" + strings.ToLower(strings.TrimSpace(current.HardwareAddress)),
		"flags=" + strings.Join(flags, ","),
		"addresses=" + strings.Join(addresses, ","),
	}, "\n")
	sum := sha256.Sum256([]byte(canonical))
	return "sha256:" + hex.EncodeToString(sum[:])
}

func validInterfaceFingerprint(value string) bool {
	if len(value) != len("sha256:")+64 || !strings.HasPrefix(value, "sha256:") {
		return false
	}
	_, err := hex.DecodeString(strings.TrimPrefix(value, "sha256:"))
	return err == nil
}
