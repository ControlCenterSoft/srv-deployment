(() => {
    "use strict";

    const form = document.getElementById("loginForm");
    const username = document.getElementById("loginUsername");
    const password = document.getElementById("loginPassword");
    const errorBox = document.getElementById("loginError");

    function showError(message) {
        errorBox.textContent = message;
        errorBox.hidden = false;
    }

    function clearError() {
        errorBox.textContent = "";
        errorBox.hidden = true;
    }

    async function trySso() {
        try {
            const response = await fetch("/api/v1/auth/sso", {
                method: "GET",
                credentials: "same-origin",
                cache: "no-store",
            });
            if (response.ok) {
                window.location.replace("/");
            }
        } catch (_) {
            // Interactive login remains available without a user-facing placeholder.
        }
    }

    form.addEventListener("submit", async (event) => {
        event.preventDefault();
        clearError();
        const button = form.querySelector("button[type='submit']");
        button.disabled = true;
        try {
            const response = await fetch("/api/v1/auth/login", {
                method: "POST",
                credentials: "same-origin",
                headers: {"Content-Type": "application/json"},
                body: JSON.stringify({
                    username: username.value.trim(),
                    password: password.value,
                }),
            });
            if (!response.ok) {
                if (response.status === 429) {
                    showError("Слишком много попыток входа. Повторите позже.");
                } else {
                    showError("Неверное имя пользователя или пароль.");
                }
                return;
            }
            window.location.replace("/");
        } catch (_) {
            showError("Не удалось выполнить вход.");
        } finally {
            password.value = "";
            button.disabled = false;
        }
    });

    trySso();
})();
