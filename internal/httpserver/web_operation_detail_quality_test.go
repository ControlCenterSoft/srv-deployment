package httpserver

import (
	"strings"
	"testing"
)

func TestAdminWebOperationDetailActionTargetAndResponsiveLayout(t *testing.T) {
	css := readWebAsset(t, "web/styles.css")

	for _, required := range []string{
		"#operations-list > .compact-list > li {\n  display: flex;\n  align-items: center;\n  justify-content: space-between;\n  gap: var(--cc-space-3);\n}",
		"#operations-list > .compact-list > li > span {\n  min-width: 0;\n  overflow-wrap: anywhere;\n}",
		"#operations-list .inline-action {\n  display: inline-flex;\n  align-items: center;\n  min-height: var(--cc-row-min-height);\n}",
		"#operations-list > .compact-list > li {\n    align-items: flex-start;\n    flex-direction: column;\n    gap: var(--cc-space-2);\n  }",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("operation-detail action quality contract is missing %q", required)
		}
	}

	if !strings.Contains(css, "--cc-row-min-height: 44px;") {
		t.Fatal("operation-detail action target must remain tied to the 44px row-size token")
	}
}
