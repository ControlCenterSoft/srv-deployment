(() => {
    "use strict";

    const menu = document.getElementById("mainMenu");
    const frame = document.getElementById("moduleFrame");
    const healthText = document.getElementById("backendHealth");
    const healthDot = document.getElementById("backendHealthDot");
    const releaseVersion = document.getElementById("releaseVersion");
    const githubSync = document.getElementById("githubSync");
    const sessionUser = document.getElementById("sessionUser");
    const sessionRole = document.getElementById("sessionRole");
    const sessionAvatar = document.getElementById("sessionAvatar");
    const logoutButton = document.getElementById("logoutButton");
    const searchInput = document.getElementById("globalSearch");
    const refreshButton = document.getElementById("refreshButton");
    let csrfToken = "";
    let refreshFallbackTimer = null;

    function menuItems() {
        return Array.from(menu.querySelectorAll(".nav-item")).filter((item) => !item.hidden);
    }

    function visibleItems() {
        return menuItems().filter((item) => !item.classList.contains("search-hidden"));
    }

    function itemLabel(item) {
        const label = item && item.querySelector(".nav-label");
        return String(label ? label.textContent : item?.textContent || "Control Center").trim();
    }

    function syncDocumentTitle(item) {
        const label = itemLabel(item);
        frame.title = label ? `${label} — Control Center` : "Control Center";
        document.title = label ? `${label} — Control Center` : "Control Center";
    }

    function activate(item) {
        if (!item || item.hidden) return;
        for (const link of menuItems()) {
            link.classList.remove("active");
            link.removeAttribute("aria-current");
        }
        item.classList.add("active");
        item.setAttribute("aria-current", "page");
        syncDocumentTitle(item);
    }

    function focusRelative(current, delta) {
        const items = visibleItems();
        if (!items.length) return;
        const index = Math.max(0, items.indexOf(current));
        const target = items[(index + delta + items.length) % items.length];
        target.focus();
    }

    if (menu) {
        menu.addEventListener("click", (event) => {
            const item = event.target.closest(".nav-item");
            if (item) activate(item);
        });
        menu.addEventListener("keydown", (event) => {
            const item = event.target.closest(".nav-item");
            if (!item) return;
            if (event.key === "ArrowDown") {
                event.preventDefault();
                focusRelative(item, 1);
            } else if (event.key === "ArrowUp") {
                event.preventDefault();
                focusRelative(item, -1);
            } else if (event.key === "Home") {
                event.preventDefault();
                visibleItems()[0]?.focus();
            } else if (event.key === "End") {
                event.preventDefault();
                visibleItems().at(-1)?.focus();
            }
        });
    }

    function formatSyncTime(value) {
        if (!value) return "—";
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return value;
        return date.toLocaleString("ru-RU", {
            day: "2-digit", month: "2-digit", year: "numeric",
            hour: "2-digit", minute: "2-digit",
        });
    }

    function updateReleaseInfo(payload) {
        const release = payload && payload.data && payload.data.release ? payload.data.release : {};
        releaseVersion.textContent = release.version ? `Control Center ${release.version}` : "Control Center —";
        githubSync.textContent = release.synced_at ? `Синхронизация: ${formatSyncTime(release.synced_at)}` : "Синхронизация: —";
        githubSync.title = release.git_sha ? `GitHub commit: ${release.git_sha}` : "";
    }

    function canReadAny(identity, permissions, names) {
        if (identity.is_admin) return true;
        return names.some((name) => Boolean(permissions[name]));
    }

    function avatarFor(username) {
        const value = String(username || "A").trim();
        return value ? value.slice(0, 1).toUpperCase() : "A";
    }

    async function loadIdentity() {
        const response = await fetch("/api/v1/auth/status", {cache: "no-store"});
        if (!response.ok) {
            window.location.replace("/login");
            return;
        }
        const payload = await response.json();
        if (!payload.data || !payload.data.authenticated) {
            window.location.replace("/login");
            return;
        }
        const identity = payload.data.identity || {};
        const permissions = payload.data.permissions || {};
        csrfToken = payload.data.csrf_token || "";
        sessionUser.textContent = identity.username || "—";
        sessionRole.textContent = identity.is_admin ? "Администратор" : "Пользователь";
        sessionAvatar.textContent = avatarFor(identity.username);

        for (const item of menu.querySelectorAll(".nav-item[data-module]")) {
            item.hidden = !canReadAny(identity, permissions, [item.dataset.module]);
        }
        for (const item of menu.querySelectorAll(".nav-item[data-modules]")) {
            const names = item.dataset.modules.split(",").map((value) => value.trim()).filter(Boolean);
            item.hidden = !canReadAny(identity, permissions, names);
        }
        for (const item of menu.querySelectorAll(".nav-item[data-admin-only='true']")) {
            item.hidden = !identity.is_admin;
        }
    }

    async function checkBackend() {
        try {
            const response = await fetch("/api/v1/health", {cache: "no-store"});
            const payload = await response.json();
            updateReleaseInfo(payload);
            if (response.ok && payload.ok) {
                healthText.textContent = "Система работает";
                healthDot.classList.remove("error");
                healthDot.classList.add("ok");
                return;
            }
            throw new Error("health failed");
        } catch (_) {
            healthText.textContent = "Требует внимания";
            healthDot.classList.remove("ok");
            healthDot.classList.add("error");
        }
    }

    function applySearch() {
        const query = String(searchInput.value || "").trim().toLocaleLowerCase("ru-RU");
        for (const item of menuItems()) {
            const haystack = `${item.textContent || ""} ${item.dataset.search || ""}`.toLocaleLowerCase("ru-RU");
            item.classList.toggle("search-hidden", Boolean(query) && !haystack.includes(query));
        }
        searchInput.setAttribute("aria-label", query
            ? `Поиск по разделам. Найдено: ${visibleItems().length}`
            : "Поиск по разделам");
    }

    searchInput.addEventListener("input", applySearch);
    searchInput.addEventListener("keydown", (event) => {
        if (event.key === "Escape") {
            searchInput.value = "";
            applySearch();
            searchInput.blur();
            return;
        }
        if (event.key === "ArrowDown") {
            const first = visibleItems()[0];
            if (first) {
                event.preventDefault();
                first.focus();
            }
            return;
        }
        if (event.key === "Enter") {
            const first = visibleItems()[0];
            if (first) {
                activate(first);
                first.click();
                searchInput.value = "";
                applySearch();
                searchInput.blur();
            }
        }
    });

    window.addEventListener("keydown", (event) => {
        if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
            event.preventDefault();
            searchInput.focus();
            searchInput.select();
        }
    });

    function finishRefresh() {
        window.clearTimeout(refreshFallbackTimer);
        refreshFallbackTimer = null;
        refreshButton.disabled = false;
        refreshButton.classList.remove("is-loading");
        refreshButton.setAttribute("aria-busy", "false");
        refreshButton.title = "Обновить текущий раздел";
    }

    refreshButton.addEventListener("click", () => {
        refreshButton.disabled = true;
        refreshButton.classList.add("is-loading");
        refreshButton.setAttribute("aria-busy", "true");
        refreshButton.title = "Обновление раздела...";
        window.clearTimeout(refreshFallbackTimer);
        refreshFallbackTimer = window.setTimeout(finishRefresh, 5000);
        try {
            frame.contentWindow.location.reload();
        } catch (_) {
            frame.src = frame.src;
        }
    });

    frame.addEventListener("load", () => {
        finishRefresh();
        const active = menu.querySelector(".nav-item.active");
        if (active) syncDocumentTitle(active);
    });

    logoutButton.addEventListener("click", async () => {
        logoutButton.disabled = true;
        try {
            const response = await fetch("/api/v1/auth/logout", {
                method: "POST",
                headers: {"X-CSRF-Token": csrfToken},
            });
            if (response.ok) window.location.replace("/login");
        } finally {
            logoutButton.disabled = false;
        }
    });

    const initial = menu.querySelector(".nav-item.active");
    if (initial) activate(initial);
    loadIdentity();
    checkBackend();
    window.setInterval(checkBackend, 10000);
})();
