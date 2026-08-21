package main

import (
	"strings"
	"testing"
)

func TestVerifyReleaseV2CLIUnknownFieldIsUsageError(t *testing.T) {
	fixture := newVerifyV2CLIFixture(t)
	_, stderr, code := runVerifyV2Helper(t,
		"--manifest", fixture.manifest,
		"--signature", fixture.signature,
		"--public-key", fixture.publicKey,
		"--artifact", fixture.artifact,
		"--worker", fixture.worker,
		"--field", "unknown",
	)
	if code != 2 {
		t.Fatalf("unknown field exit code: got %d want 2; stderr=%s", code, stderr)
	}
	if !strings.Contains(stderr, "unknown verify-release field") {
		t.Fatalf("unknown field must report usage contract error, got: %s", stderr)
	}
}
