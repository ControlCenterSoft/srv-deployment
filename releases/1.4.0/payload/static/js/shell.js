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

    function visibleItems() {
        return Array.from(menu.querySelectorAll(".nav-item")).filter((item) => !item.hidden && !item.classList.contains("search-hidden"));
    }

    function activate(item) {
        if (!item || item.hidden) return;
        for (const link of menu.querySelectorAll(".nav-item")) link.classList.remove("active");
        item.classList.add("active");
    }

    if (menu) {
        menu.addEventListener("click", (event) => {
            const item = event.target.closest(".nav-item");
            if (item) activate(item);
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
        for (const item of menu.querySelectorAll(".nav-item")) {
            const haystack = `${item.textContent || ""} ${item.dataset.search || ""}`.toLocaleLowerCase("ru-RU");
            item.classList.toggle("search-hidden", Boolean(query) && !haystack.includes(query));
        }
    }

    searchInput.addEventListener("input", applySearch);
    searchInput.addEventListener("keydown", (event) => {
        if (event.key === "Escape") {
            searchInput.value = "";
            applySearch();
            searchInput.blur();
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

    refreshButton.addEventListener("click", () => {
        try {
            frame.contentWindow.location.reload();
        } catch (_) {
            frame.src = frame.src;
        }
    });

    logoutButton.addEventListener("click", async () => {
        const response = await fetch("/api/v1/auth/logout", {
            method: "POST",
            headers: {"X-CSRF-Token": csrfToken},
        });
        if (response.ok) window.location.replace("/login");
    });

    loadIdentity();
    checkBackend();
    window.setInterval(checkBackend, 10000);
})();
