package dns

import (
	"fmt"
	"net/netip"
	"strings"
)

const (
	maxResolverNameservers   = 6
	maxResolverSearchDomains = 6
)

type ResolverChangeRequest struct {
	Nameservers   []string `json:"nameservers"`
	SearchDomains []string `json:"search_domains"`
}

type ResolverDesiredState struct {
	Nameservers   []string `json:"nameservers"`
	SearchDomains []string `json:"search_domains"`
	Options       []string `json:"options"`
}

type ResolverChangePlan struct {
	Schema          int                  `json:"schema"`
	NoOp            bool                 `json:"no_op"`
	ApplySupported  bool                 `json:"apply_supported"`
	SourceKind      string               `json:"source_kind"`
	SourceMode      string               `json:"source_mode"`
	SourceManager   string               `json:"source_manager"`
	SourceAmbiguous bool                 `json:"source_ambiguous"`
	Desired         ResolverDesiredState `json:"desired"`
	Actual          ResolverDesiredState `json:"actual"`
	Rollback        ResolverDesiredState `json:"rollback"`
	Preconditions   []string             `json:"preconditions"`
	Warnings        []string             `json:"warnings"`
}

func PreviewResolverChange(in ResolverChangeRequest, actual ResolverState) (ResolverChangePlan, error) {
	nameservers, err := normalizeNameservers(in.Nameservers)
	if err != nil {
		return ResolverChangePlan{}, err
	}
	searchDomains, err := normalizeSearchDomains(in.SearchDomains)
	if err != nil {
		return ResolverChangePlan{}, err
	}

	current := ResolverDesiredState{
		Nameservers:   append([]string(nil), actual.Nameservers...),
		SearchDomains: append([]string(nil), actual.SearchDomains...),
		Options:       append([]string(nil), actual.Options...),
	}
	desired := ResolverDesiredState{
		Nameservers:   nameservers,
		SearchDomains: searchDomains,
		Options:       append([]string(nil), actual.Options...),
	}

	return ResolverChangePlan{
		Schema:          1,
		NoOp:            resolverDesiredEqual(current, desired),
		ApplySupported:  false,
		SourceKind:      actual.SourceKind,
		SourceMode:      actual.SourceMode,
		SourceManager:   actual.SourceManager,
		SourceAmbiguous: actual.SourceAmbiguous,
		Desired:         desired,
		Actual:          current,
		Rollback:        current,
		Preconditions: []string{
			"resolver_inventory_available",
			"resolver_source_unchanged",
			"backup_current_resolver_state",
			"verify_resolution_before_commit",
			"rollback_on_verify_failure",
		},
		Warnings: resolverSourceWarnings(actual),
	}, nil
}

func normalizeNameservers(values []string) ([]string, error) {
	if len(values) == 0 {
		return nil, fmt.Errorf("at least one nameserver is required")
	}
	if len(values) > maxResolverNameservers {
		return nil, fmt.Errorf("at most %d nameservers are supported", maxResolverNameservers)
	}
	out := make([]string, 0, len(values))
	for _, raw := range values {
		value := strings.TrimSpace(raw)
		addr, err := netip.ParseAddr(value)
		if err != nil || addr.Zone() != "" {
			return nil, fmt.Errorf("invalid nameserver address")
		}
		if addr.IsUnspecified() || addr.IsMulticast() {
			return nil, fmt.Errorf("nameserver address must be unicast")
		}
		out = appendUnique(out, addr.String())
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("at least one nameserver is required")
	}
	return out, nil
}

func normalizeSearchDomains(values []string) ([]string, error) {
	if len(values) > maxResolverSearchDomains {
		return nil, fmt.Errorf("at most %d search domains are supported", maxResolverSearchDomains)
	}
	out := make([]string, 0, len(values))
	for _, raw := range values {
		value, err := normalizeSearchDomain(raw)
		if err != nil {
			return nil, err
		}
		out = appendUnique(out, value)
	}
	return out, nil
}

func normalizeSearchDomain(raw string) (string, error) {
	value := strings.ToLower(strings.TrimSpace(raw))
	value = strings.TrimSuffix(value, ".")
	if value == "" || len(value) > 253 || strings.ContainsAny(value, "\r\n\t /\\") {
		return "", fmt.Errorf("invalid search domain")
	}
	labels := strings.Split(value, ".")
	for _, label := range labels {
		if label == "" || len(label) > 63 || label[0] == '-' || label[len(label)-1] == '-' {
			return "", fmt.Errorf("invalid search domain")
		}
		for _, r := range label {
			if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' {
				continue
			}
			return "", fmt.Errorf("invalid search domain")
		}
	}
	return value, nil
}

func resolverDesiredEqual(a, b ResolverDesiredState) bool {
	aSearch, err := normalizeSearchDomains(a.SearchDomains)
	if err != nil {
		return false
	}
	bSearch, err := normalizeSearchDomains(b.SearchDomains)
	if err != nil {
		return false
	}
	return stringSlicesEqual(a.Nameservers, b.Nameservers) && stringSlicesEqual(aSearch, bSearch) && stringSlicesEqual(a.Options, b.Options)
}

func stringSlicesEqual(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
