package network

import (
	"errors"
	"net/netip"
	"sort"
	"strings"
)

type AddressChangeRequest struct {
	Interface string `json:"interface"`
	CIDR      string `json:"cidr"`
}

type AddressChangePlan struct {
	Schema               int      `json:"schema"`
	Interface            string   `json:"interface"`
	DesiredCIDR          string   `json:"desired_cidr"`
	ActualAddresses      []string `json:"actual_addresses"`
	RollbackAddresses    []string `json:"rollback_addresses"`
	Validation           string   `json:"validation"`
	Risk                 string   `json:"risk"`
	Warnings             []string `json:"warnings"`
	NoOp                 bool     `json:"no_op"`
	ApplySupported       bool     `json:"apply_supported"`
	RequiresRecoveryPath bool     `json:"requires_recovery_path"`
}

func PreviewAddressChange(req AddressChangeRequest, interfaces []Interface) (AddressChangePlan, error) {
	name := strings.TrimSpace(req.Interface)
	if name == "" {
		return AddressChangePlan{}, errors.New("interface is required")
	}
	prefix, err := netip.ParsePrefix(strings.TrimSpace(req.CIDR))
	if err != nil {
		return AddressChangePlan{}, errors.New("cidr must be a valid IPv4 or IPv6 prefix")
	}
	addr := prefix.Addr()
	if addr.IsUnspecified() || addr.IsMulticast() {
		return AddressChangePlan{}, errors.New("unspecified or multicast addresses cannot be assigned")
	}

	var current *Interface
	for i := range interfaces {
		if interfaces[i].Name == name {
			current = &interfaces[i]
			break
		}
	}
	if current == nil {
		return AddressChangePlan{}, errors.New("interface not found")
	}
	for _, flag := range current.Flags {
		if flag == "loopback" {
			return AddressChangePlan{}, errors.New("loopback interface cannot be changed by this operation")
		}
	}

	actual := append([]string(nil), current.Addresses...)
	sort.Strings(actual)
	desired := prefix.String()
	noOp := false
	for _, existing := range actual {
		if existing == desired {
			noOp = true
			break
		}
	}

	warnings := []string{"Preview only: no host network settings are changed."}
	if containsFlag(current.Flags, "up") {
		warnings = append(warnings, "Interface is UP; an apply operation must preserve the management path and verify connectivity before commit.")
	}
	if len(actual) == 0 {
		warnings = append(warnings, "Interface currently has no addresses; rollback restores the empty address set.")
	}
	return AddressChangePlan{
		Schema:               1,
		Interface:            name,
		DesiredCIDR:          desired,
		ActualAddresses:      actual,
		RollbackAddresses:    append([]string(nil), actual...),
		Validation:           "passed",
		Risk:                 "network_connectivity",
		Warnings:             warnings,
		NoOp:                 noOp,
		ApplySupported:       false,
		RequiresRecoveryPath: true,
	}, nil
}

func containsFlag(flags []string, want string) bool {
	for _, flag := range flags {
		if flag == want {
			return true
		}
	}
	return false
}
