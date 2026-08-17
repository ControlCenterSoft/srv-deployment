(() => {
    "use strict";

    const menu = document.getElementById(
        "mainMenu"
    );

    const healthText = document.getElementById(
        "backendHealth"
    );

    const healthDot = document.getElementById(
        "backendHealthDot"
    );

    const releaseVersion = document.getElementById(
        "releaseVersion"
    );

    const githubSync = document.getElementById(
        "githubSync"
    );


    if (menu) {
        menu.addEventListener(
            "click",
            (event) => {
                const item = event.target.closest(
                    ".nav-item"
                );

                if (!item) {
                    return;
                }

                for (
                    const link
                    of menu.querySelectorAll(
                        ".nav-item"
                    )
                ) {
                    link.classList.remove(
                        "active"
                    );
                }

                item.classList.add(
                    "active"
                );
            }
        );
    }


    function formatSyncTime(value) {
        if (!value) {
            return "—";
        }

        const date = new Date(value);

        if (Number.isNaN(date.getTime())) {
            return value;
        }

        return date.toLocaleString(
            "ru-RU",
            {
                day: "2-digit",
                month: "2-digit",
                year: "numeric",
                hour: "2-digit",
                minute: "2-digit",
            }
        );
    }


    function updateReleaseInfo(payload) {
        const release = (
            payload
            &&
            payload.data
            &&
            payload.data.release
        )
            ? payload.data.release
            : {};

        if (releaseVersion) {
            releaseVersion.textContent = release.version
                ? `Релиз ${release.version}`
                : "Релиз —";
        }

        if (githubSync) {
            githubSync.textContent = release.synced_at
                ? `GitHub: ${formatSyncTime(release.synced_at)}`
                : "GitHub: —";

            if (release.git_sha) {
                githubSync.title = (
                    `GitHub commit: ${release.git_sha}`
                );
            }
        }
    }


    async function checkBackend() {
        try {
            const response = await fetch(
                "/api/v1/health",
                {
                    cache: "no-store",
                }
            );

            const payload = await response.json();

            updateReleaseInfo(payload);

            if (
                response.ok
                &&
                payload.ok
            ) {
                healthText.textContent = "Работает";

                healthDot.classList.remove(
                    "error"
                );

                healthDot.classList.add(
                    "ok"
                );

                return;
            }

            throw new Error(
                "health failed"
            );

        } catch (error) {
            healthText.textContent = "Ошибка";

            healthDot.classList.remove(
                "ok"
            );

            healthDot.classList.add(
                "error"
            );
        }
    }


    checkBackend();

    window.setInterval(
        checkBackend,
        10000
    );
})();
