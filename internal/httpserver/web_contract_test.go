package httpserver

import (
	"strings"
	"testing"
)

func TestWebStylesHonorHiddenAttribute(t *testing.T) {
	b, err := webFS.ReadFile("web/styles.css")
	if err != nil {
		t.Fatalf("read embedded styles: %v", err)
	}
	css := string(b)
	if !strings.Contains(css, "[hidden] { display: none !important; }") {
		t.Fatal("web styles must explicitly hide elements carrying the hidden attribute")
	}
}
