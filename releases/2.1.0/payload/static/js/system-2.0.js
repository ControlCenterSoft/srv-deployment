(() => {
    "use strict";

    const rows = document.getElementById("backupRows");
    const selectAll = document.getElementById("backupSelectAll");
    const deleteSelected = document.getElementById("backupDeleteSelected");
    const selectionCount = document.getElementById("backupSelectionCount");
    if (!rows || !selectAll || !deleteSelected || !selectionCount) return;

    const selected = new Set();
    let csrfToken = "";

    function toast(message, kind = "info") {
        window.ControlCenterUI?.toast?.(message, kind);
    }

    function backupIdFromRow(row) {
        const link = row.querySelector('a[href*="/api/v1/system/backups/"][href$="/download"]');
        if (!link) return "";
        const match = String(link.getAttribute("href") || "").match(/\/api\/v1\/system\/backups\/([^/]+)\/download$/);
        return match ? decodeURIComponent(match[1]) : "";
    }

    function syncToolbar() {
        const boxes = Array.from(rows.querySelectorAll("input.cc-backup-select"));
        const checked = boxes.filter((box) => box.checked);
        selectionCount.textContent = `Выбрано: ${selected.size}`;
        deleteSelected.disabled = selected.size === 0;
        selectAll.disabled = boxes.length === 0;
        selectAll.checked = boxes.length > 0 && checked.length === boxes.length;
        selectAll.indeterminate = checked.length > 0 && checked.length < boxes.length;
    }

    function enhanceRows() {
        const liveIds = new Set();
        for (const row of rows.querySelectorAll("tr")) {
            const existing = row.querySelector("input.cc-backup-select");
            const backupId = backupIdFromRow(row);
            if (!backupId) continue;
            liveIds.add(backupId);
            if (existing) {
                existing.checked = selected.has(backupId);
                continue;
            }
            const cell = document.createElement("td");
            cell.setAttribute("data-cc-label", "Выбор");
            const checkbox = document.createElement("input");
            checkbox.type = "checkbox";
            checkbox.className = "cc-backup-select";
            checkbox.value = backupId;
            checkbox.checked = selected.has(backupId);
            checkbox.setAttribute("aria-label", `Выбрать резервную копию ${backupId}`);
            checkbox.addEventListener("change", () => {
                if (checkbox.checked) selected.add(backupId);
                else selected.delete(backupId);
                syncToolbar();
            });
            cell.appendChild(checkbox);
            row.insertBefore(cell, row.firstChild);
        }
        for (const id of Array.from(selected)) {
            if (!liveIds.has(id)) selected.delete(id);
        }
        syncToolbar();
        window.ControlCenterUI?.enhanceTables?.(document);
    }

    async function ensureCsrf() {
        if (csrfToken) return csrfToken;
        const response = await fetch("/api/v1/auth/status", {cache: "no-store", credentials: "same-origin"});
        if (response.status === 401) {
            window.top.location.replace("/login");
            throw new Error("Требуется вход в систему");
        }
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const payload = await response.json();
        csrfToken = payload?.data?.csrf_token || "";
        if (!csrfToken) throw new Error("CSRF token is unavailable");
        return csrfToken;
    }

    selectAll.addEventListener("change", () => {
        for (const checkbox of rows.querySelectorAll("input.cc-backup-select")) {
            checkbox.checked = selectAll.checked;
            if (selectAll.checked) selected.add(checkbox.value);
            else selected.delete(checkbox.value);
        }
        syncToolbar();
    });

    deleteSelected.addEventListener("click", async () => {
        if (!selected.size) return;
        const ids = Array.from(selected);
        const approved = window.ControlCenterUI?.confirm
            ? await window.ControlCenterUI.confirm(
                `Удалить выбранные резервные копии (${ids.length})? Это действие нельзя отменить.`,
                {
                    title: "Массовое удаление резервных копий",
                    confirmLabel: "Удалить выбранные",
                    danger: true,
                    requireText: "DELETE",
                },
            )
            : window.confirm(`Удалить выбранные резервные копии (${ids.length})?`);
        if (!approved) return;

        deleteSelected.disabled = true;
        deleteSelected.setAttribute("aria-busy", "true");
        try {
            const token = await ensureCsrf();
            const response = await fetch("/api/v1/system/backups/delete-many", {
                method: "POST",
                credentials: "same-origin",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": token,
                },
                body: JSON.stringify({backup_ids: ids}),
            });
            let payload = null;
            try { payload = await response.json(); } catch (_) {}
            if (!response.ok) throw new Error(payload?.detail || payload?.error || `HTTP ${response.status}`);
            selected.clear();
            selectAll.checked = false;
            selectAll.indeterminate = false;
            toast(`Удаление ${ids.length} резервных копий поставлено в очередь.`, "success");
            syncToolbar();
        } catch (error) {
            toast(error.message || "Не удалось удалить выбранные резервные копии.", "error");
        } finally {
            deleteSelected.removeAttribute("aria-busy");
            syncToolbar();
        }
    });

    const observer = new MutationObserver(enhanceRows);
    observer.observe(rows, {childList: true, subtree: true});
    enhanceRows();
})();
