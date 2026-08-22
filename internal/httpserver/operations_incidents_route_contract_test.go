package httpserver

import (
	"os"
	"strings"
	"testing"
)

func TestOperationIncidentCollectionDoesNotConsumeValidDetailID(t *testing.T) {
	if !operationLookupIDRE.MatchString("incidents") {
		t.Fatal("fixture invalid: accepted operation detail ID contract no longer includes incidents")
	}

	source, err := os.ReadFile("operations_detail.go")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(source), `if id == "incidents"`) {
		t.Fatal("incident collection consumes the valid existing operation detail ID incidents; use a non-overlapping route")
	}
}
