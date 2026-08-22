package dns

import (
	"fmt"
	"io"
	"net/netip"
	"os"
	"strings"
)

const maxResolverBytes int64 = 64 << 10

const (
	etcResolvConfPath = "/etc/resolv.conf"
	resolvedConfPath  = "/run/systemd/resolve/resolv.conf"
)

type ResolverState struct {
	Schema              int      `json:"schema"`
	Managed             bool     `json:"managed"`
	ApplySupported      bool     `json:"apply_supported"`
	Source              string   `json:"source"`
	SourceKind          string   `json:"source_kind"`
	EtcResolvConfTarget string   `json:"etc_resolv_conf_target,omitempty"`
	StubDetected        bool     `json:"stub_detected"`
	Nameservers         []string `json:"nameservers"`
	SearchDomains       []string `json:"search_domains"`
	Options             []string `json:"options"`
}

type resolverFile struct {
	Nameservers   []string
	SearchDomains []string
	Options       []string
}

func Inventory() (ResolverState, error) {
	return inventoryFromPaths(etcResolvConfPath, resolvedConfPath)
}

func inventoryFromPaths(etcPath, resolvedPath string) (ResolverState, error) {
	etcState, err := readResolverFile(etcPath)
	if err != nil {
		return ResolverState{}, fmt.Errorf("read resolver state: %w", err)
	}
	if len(etcState.Nameservers) == 0 {
		return ResolverState{}, fmt.Errorf("resolver state has no nameservers")
	}

	stubDetected := containsLoopback(etcState.Nameservers)
	selected := etcState
	source := etcPath
	sourceKind := "resolv_conf"
	if stubDetected {
		if resolvedState, resolvedErr := readResolverFile(resolvedPath); resolvedErr == nil && len(resolvedState.Nameservers) > 0 {
			selected = resolvedState
			source = resolvedPath
			sourceKind = "systemd_resolved"
		}
	}

	target := ""
	if link, linkErr := os.Readlink(etcPath); linkErr == nil {
		target = link
	}

	return ResolverState{
		Schema:              1,
		Managed:             false,
		ApplySupported:      false,
		Source:              source,
		SourceKind:          sourceKind,
		EtcResolvConfTarget: target,
		StubDetected:        stubDetected,
		Nameservers:         append([]string(nil), selected.Nameservers...),
		SearchDomains:       append([]string(nil), selected.SearchDomains...),
		Options:             append([]string(nil), selected.Options...),
	}, nil
}

func readResolverFile(path string) (resolverFile, error) {
	f, err := os.Open(path)
	if err != nil {
		return resolverFile{}, err
	}
	defer f.Close()

	data, err := io.ReadAll(io.LimitReader(f, maxResolverBytes+1))
	if err != nil {
		return resolverFile{}, err
	}
	if int64(len(data)) > maxResolverBytes {
		return resolverFile{}, fmt.Errorf("resolver file exceeds %d bytes", maxResolverBytes)
	}
	return parseResolverContent(string(data))
}

func parseResolverContent(content string) (resolverFile, error) {
	state := resolverFile{}
	for _, rawLine := range strings.Split(content, "\n") {
		line := strings.TrimSpace(stripResolverComment(rawLine))
		if line == "" {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		switch strings.ToLower(fields[0]) {
		case "nameserver":
			addr, err := netip.ParseAddr(fields[1])
			if err != nil {
				return resolverFile{}, fmt.Errorf("invalid nameserver address")
			}
			state.Nameservers = appendUnique(state.Nameservers, addr.String())
		case "search":
			state.SearchDomains = boundedTokens(fields[1:], 32, 253)
		case "domain":
			state.SearchDomains = boundedTokens(fields[1:2], 1, 253)
		case "options":
			for _, option := range boundedTokens(fields[1:], 32, 128) {
				state.Options = appendUnique(state.Options, option)
			}
		}
	}
	return state, nil
}

func stripResolverComment(line string) string {
	cut := len(line)
	for _, marker := range []string{"#", ";"} {
		if i := strings.Index(line, marker); i >= 0 && i < cut {
			cut = i
		}
	}
	return line[:cut]
}

func boundedTokens(values []string, maxItems, maxLen int) []string {
	out := make([]string, 0, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" || len(value) > maxLen || strings.ContainsAny(value, "\r\n\t") {
			continue
		}
		out = appendUnique(out, value)
		if len(out) == maxItems {
			break
		}
	}
	return out
}

func appendUnique(values []string, value string) []string {
	for _, existing := range values {
		if existing == value {
			return values
		}
	}
	return append(values, value)
}

func containsLoopback(values []string) bool {
	for _, value := range values {
		addr, err := netip.ParseAddr(value)
		if err == nil && addr.IsLoopback() {
			return true
		}
	}
	return false
}
