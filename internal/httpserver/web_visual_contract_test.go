package httpserver

import (
	"math"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

var calmColorTokenRE = regexp.MustCompile(`--([a-z0-9-]+):\s*(#[0-9a-fA-F]{6})\s*;`)

func calmColorTokens(t *testing.T, css string) map[string]string {
	t.Helper()
	out := map[string]string{}
	for _, match := range calmColorTokenRE.FindAllStringSubmatch(css, -1) {
		out[match[1]] = strings.ToLower(match[2])
	}
	return out
}

func calmChannel(t *testing.T, hex string, offset int) float64 {
	t.Helper()
	value, err := strconv.ParseUint(hex[offset:offset+2], 16, 8)
	if err != nil {
		t.Fatalf("parse color %q: %v", hex, err)
	}
	channel := float64(value) / 255
	if channel <= 0.04045 {
		return channel / 12.92
	}
	return math.Pow((channel+0.055)/1.055, 2.4)
}

func calmLuminance(t *testing.T, hex string) float64 {
	t.Helper()
	if len(hex) != 7 || hex[0] != '#' {
		t.Fatalf("expected #rrggbb color, got %q", hex)
	}
	r := calmChannel(t, hex, 1)
	g := calmChannel(t, hex, 3)
	b := calmChannel(t, hex, 5)
	return 0.2126*r + 0.7152*g + 0.0722*b
}

func calmContrast(t *testing.T, foreground, background string) float64 {
	t.Helper()
	first := calmLuminance(t, foreground)
	second := calmLuminance(t, background)
	if first < second {
		first, second = second, first
	}
	return (first + 0.05) / (second + 0.05)
}

func TestCalmInfrastructureColorContrastContract(t *testing.T) {
	css := readWebAsset(t, "web/styles.css")
	tokens := calmColorTokens(t, css)

	for _, name := range []string{
		"cc-canvas", "cc-surface", "cc-text", "cc-text-muted", "cc-focus",
		"cc-danger", "cc-primary", "cc-on-primary",
	} {
		if tokens[name] == "" {
			t.Fatalf("Calm Infrastructure color token %q is missing", name)
		}
	}

	checks := []struct {
		name       string
		foreground string
		background string
		minimum    float64
	}{
		{"body text", "cc-text", "cc-canvas", 4.5},
		{"muted panel text", "cc-text-muted", "cc-surface", 4.5},
		{"focus indicator", "cc-focus", "cc-canvas", 3.0},
		{"error text", "cc-danger", "cc-surface", 4.5},
		{"primary action", "cc-on-primary", "cc-primary", 4.5},
	}

	for _, check := range checks {
		ratio := calmContrast(t, tokens[check.foreground], tokens[check.background])
		if ratio < check.minimum {
			t.Fatalf("%s contrast %.2f is below %.2f", check.name, ratio, check.minimum)
		}
	}
}

func TestCalmInfrastructureVisualRegressionSignature(t *testing.T) {
	css := readWebAsset(t, "web/styles.css")
	tokens := calmColorTokens(t, css)
	got := strings.Join([]string{
		tokens["cc-canvas"], tokens["cc-sidebar"], tokens["cc-surface"], tokens["cc-surface-inset"],
		tokens["cc-border"], tokens["cc-border-strong"], tokens["cc-text"], tokens["cc-text-secondary"],
		tokens["cc-text-muted"], tokens["cc-focus"], tokens["cc-danger"], tokens["cc-primary"], tokens["cc-on-primary"],
	}, "|")
	const want = "#0f1115|#151820|#171b22|#11141a|#2a303a|#3a4350|#f4f6f8|#cbd3dd|#8f9aaa|#7dd3fc|#ffb4ab|#eef2f7|#11141a"
	if got != want {
		t.Fatalf("Calm Infrastructure visual token signature changed:\n got %s\nwant %s", got, want)
	}
}

func TestCalmInfrastructureFocusMotionAndLayoutContract(t *testing.T) {
	css := readWebAsset(t, "web/styles.css")
	for _, required := range []string{
		"outline: 2px solid var(--cc-focus);",
		"outline-offset: 3px;",
		"@media (prefers-reduced-motion: reduce)",
		"transition: none !important;",
		"animation: none !important;",
		"@media (prefers-contrast: more)",
		".content { padding: 36px; max-width: 1100px; width: 100%; min-width: 0; }",
		".compact-list li { min-width: 0; overflow-wrap: anywhere; }",
		"@media (max-width: 960px) and (min-width: 721px)",
		".facts { grid-template-columns: repeat(2, minmax(0, 1fr)); }",
		".nav-item.active { box-shadow: inset 3px 0 0 var(--cc-focus); }",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("Calm Infrastructure interaction/layout contract is missing %q", required)
		}
	}
	if strings.Contains(css, "transform:") {
		t.Fatal("micro-interactions must not use transforms that can create distracting motion or visual instability")
	}
}

func TestCalmInfrastructureCSSPerformanceBudget(t *testing.T) {
	css := readWebAsset(t, "web/styles.css")
	if len(css) > 12*1024 {
		t.Fatalf("Admin Web CSS exceeds the 12 KiB visual-system budget: %d bytes", len(css))
	}
	for _, forbidden := range []string{"@import", "url(http://", "url(https://"} {
		if strings.Contains(strings.ToLower(css), forbidden) {
			t.Fatalf("Admin Web CSS must stay self-contained; found %q", forbidden)
		}
	}
	for _, shared := range []string{
		".card, .auth-card, .warning {",
		".facts div, .setup-panel, .agent-setup {",
		".nav-item, .primary, .text-button, input, select {",
	} {
		if !strings.Contains(css, shared) {
			t.Fatalf("shared visual component contract is missing %q", shared)
		}
	}
}
