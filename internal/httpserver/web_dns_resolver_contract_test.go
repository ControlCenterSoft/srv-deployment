package httpserver

import (
	"strings"
	"testing"
)

func TestAdminWebDNSResolverWorkflowContract(t *testing.T) {
	network := readWebAsset(t, "web/network.js")

	for _, required := range []string{
		`/api/v1/dns/resolver`,
		`/api/v1/dns/resolver/preview`,
		`/api/v1/dns/resolver/preflight`,
		`Promise.allSettled`,
		`renderDNSResolverInventory`,
		`renderDNSPreview`,
		`renderDNSPreflight`,
		`currentDNSPreview = data`,
		`nameservers: currentDNSPreview.desired.nameservers`,
		`search_domains: currentDNSPreview.desired.search_domains`,
		`expected_source_fingerprint: currentDNSPreview.source_fingerprint`,
	} {
		if !strings.Contains(network, required) {
			t.Fatalf("DNS resolver Admin Web workflow is missing %q", required)
		}
	}

	if strings.Contains(network, "/api/v1/dns/resolver/apply") {
		t.Fatal("Admin Web must not invent or call a DNS apply endpoint while Core apply_supported=false")
	}
	if strings.Count(network, "innerHTML") != 1 || !strings.Contains(network, "page.innerHTML") {
		t.Fatal("API-backed DNS/network data must be rendered with DOM text nodes; only the static page template may use innerHTML")
	}
}

func TestAdminWebDNSResolverValidationAndStalePreviewContract(t *testing.T) {
	network := readWebAsset(t, "web/network.js")

	for _, required := range []string{
		`Введите минимум один DNS-сервер.`,
		`Сначала выполните свежий DNS preview.`,
		`document.querySelector(selector).addEventListener('input', resetDNSPreview)`,
		`currentDNSPreview = null`,
		`button.disabled = true`,
		`button.disabled = false`,
	} {
		if !strings.Contains(network, required) {
			t.Fatalf("DNS resolver validation/preflight safety is missing %q", required)
		}
	}
}

func TestAdminWebDNSResolverAccessibilityAndFailureStates(t *testing.T) {
	network := readWebAsset(t, "web/network.js")

	for _, required := range []string{
		`id="dns-resolver-workflow" aria-labelledby="dns-resolver-title"`,
		`id="dns-resolver-status" class="muted" role="status" aria-live="polite"`,
		`<label for="dns-nameservers">`,
		`<label for="dns-search-domains">`,
		`id="dns-resolver-error" class="error" role="alert"`,
		`id="dns-preview-result" role="status" aria-live="polite"`,
		`id="dns-preflight-result" role="status" aria-live="polite"`,
		`Загрузка состояния DNS resolver…`,
		`Не удалось загрузить DNS resolver:`,
		`DNS-серверы в authoritative Actual state не обнаружены.`,
	} {
		if !strings.Contains(network, required) {
			t.Fatalf("DNS resolver accessibility/loading/error/empty state contract is missing %q", required)
		}
	}
}

func TestAdminWebDNSResolverCoreAuthorityContract(t *testing.T) {
	network := readWebAsset(t, "web/network.js")

	for _, required := range []string{
		`Сервер остаётся источником истины для нормализации и проверки.`,
		`Apply остаётся отключённым до появления recovery-aware executor.`,
		`Apply отключён Core contract; Web выполняет только preview/preflight и не меняет resolver.`,
		`data.management?.preflight_supported`,
		`data.source_fingerprint`,
		`data.desired`,
	} {
		if !strings.Contains(network, required) {
			t.Fatalf("DNS resolver Web/Core authority boundary is missing %q", required)
		}
	}
}
