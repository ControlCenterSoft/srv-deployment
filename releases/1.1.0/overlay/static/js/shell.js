(() => {
    "use strict";

    const menu = document.getElementById("mainMenu");
    const healthText = document.getElementById("backendHealth");
    const healthDot = document.getElementById("backendHealthDot");
    const releaseVersion = document.getElementById("releaseVersion");
    const githubSync = document.getElementById("githubSync");
    const sessionUser = document.getElementById("sessionUser");
    const logoutButton = document.getElementById("logoutButton");
    let csrfToken = "";

    if (menu) {
        menu.addEventListener("click", (event) => {
            const item = event.target.closest(".nav-item");
            if (!item) return;
            for (const link of menu.querySelectorAll(".nav-item")) {
                link.classList.remove("active");
            }
            item.classList.add("active");
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
        releaseVersion.textContent = release.version ? `Релиз ${release.version}` : "Релиз —";
        githubSync.textContent = release.synced_at ? `GitHub: ${formatSyncTime(release.synced_at)}` : "GitHub: —";
        if (release.git_sha) githubSync.title = `GitHub commit: ${release.git_sha}`;
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

        for (const item of menu.querySelectorAll(".nav-item[data-module]")) {
            const moduleName = item.dataset.module;
            item.hidden = !identity.is_admin && !permissions[moduleName];
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
                healthText.textContent = "Работает";
                healthDot.classList.remove("error");
                healthDot.classList.add("ok");
                return;
            }
            throw new Error("health failed");
        } catch (_) {
            healthText.textContent = "Ошибка";
            healthDot.classList.remove("ok");
            healthDot.classList.add("error");
        }
    }

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
