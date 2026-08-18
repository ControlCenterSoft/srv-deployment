(() => {
    "use strict";

    const api = {};
    let toastRoot = null;
    let modalRoot = null;
    let tableObserver = null;

    function ensureStyles() {
        if (document.getElementById("ccUi14Styles")) return;
        const style = document.createElement("style");
        style.id = "ccUi14Styles";
        style.textContent = `
            .cc-toast-root{position:fixed;right:18px;bottom:18px;z-index:9998;display:grid;gap:9px;width:min(380px,calc(100vw - 32px));pointer-events:none}
            .cc-toast{pointer-events:auto;padding:12px 14px;border:1px solid var(--border,#1c3850);border-radius:11px;background:rgba(8,20,31,.96);box-shadow:0 18px 50px rgba(0,0,0,.32);color:var(--text,#f1f7fc);font-size:12px;line-height:1.45;animation:ccToastIn .16s ease}
            .cc-toast.success{border-color:rgba(24,216,135,.38)} .cc-toast.error{border-color:rgba(239,100,100,.42);color:#ffd1d1}.cc-toast.warning{border-color:rgba(242,174,46,.42);color:#ffe0a2}
            .cc-modal-backdrop{position:fixed;inset:0;z-index:9999;display:grid;place-items:center;padding:18px;background:rgba(1,7,12,.72);backdrop-filter:blur(5px)}
            .cc-modal{width:min(520px,100%);border:1px solid var(--border-strong,#285270);border-radius:16px;background:linear-gradient(180deg,#0e1e2e,#091522);box-shadow:0 26px 80px rgba(0,0,0,.46);color:var(--text,#f1f7fc);overflow:hidden}
            .cc-modal.danger{border-color:rgba(239,100,100,.38)}
            .cc-modal-head{padding:20px 20px 0}.cc-modal-head h2{margin:0;font-size:18px}.cc-modal-body{padding:12px 20px 20px;color:var(--muted,#91a8bc);font-size:13px;line-height:1.55;white-space:pre-wrap}
            .cc-modal-hint{display:block;margin-top:12px;color:#f0bb67;font-size:11px;line-height:1.45}
            .cc-modal-input{width:100%;min-height:43px;margin-top:14px;padding:0 12px;border:1px solid var(--border,#1c3850);border-radius:9px;background:#081522;color:var(--text,#f1f7fc);outline:none}.cc-modal-input:focus{border-color:rgba(45,156,255,.75);box-shadow:0 0 0 3px rgba(45,156,255,.11)}
            .cc-modal-actions{display:flex;justify-content:flex-end;gap:9px;padding:14px 20px 20px}.cc-modal-actions button{min-height:40px;padding:0 15px;border-radius:9px;border:1px solid var(--border,#1c3850);background:var(--surface-2,#0e1e2e);color:var(--text,#f1f7fc);font:inherit;font-weight:700;cursor:pointer}.cc-modal-actions button.primary{border-color:rgba(45,156,255,.48);background:rgba(45,156,255,.16)}.cc-modal-actions button.danger{border-color:rgba(239,100,100,.42);background:rgba(239,100,100,.12);color:#ffc4c4}.cc-modal-actions button:disabled{opacity:.45;cursor:not-allowed}.cc-modal-actions button:focus-visible{outline:2px solid #20d8e5;outline-offset:2px}
            @keyframes ccToastIn{from{transform:translateY(8px);opacity:0}to{transform:none;opacity:1}}
            @media(max-width:720px){
                table.cc-responsive-table{display:block;width:100%;border:0;background:transparent}
                table.cc-responsive-table thead{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
                table.cc-responsive-table tbody{display:grid;gap:10px;width:100%}
                table.cc-responsive-table tr{display:grid;width:100%;padding:11px 12px;border:1px solid var(--border,#1c3850);border-radius:12px;background:rgba(10,23,36,.72)}
                table.cc-responsive-table tr.cc-empty-row{display:block;text-align:center}
                table.cc-responsive-table td{display:grid;grid-template-columns:minmax(92px,.65fr) minmax(0,1.35fr);gap:12px;align-items:start;width:100%;padding:8px 0!important;border:0!important;text-align:right!important;overflow-wrap:anywhere}
                table.cc-responsive-table td::before{content:attr(data-cc-label);color:var(--muted,#91a8bc);font-size:10.5px;font-weight:650;text-align:left;text-transform:none}
                table.cc-responsive-table td[data-cc-label=""]{grid-template-columns:1fr}
                table.cc-responsive-table td[data-cc-label=""]::before{display:none}
                table.cc-responsive-table td[colspan]{display:block;text-align:center!important;color:var(--muted,#91a8bc)}
                table.cc-responsive-table td[colspan]::before{display:none}
                table.cc-responsive-table td:last-child>div,table.cc-responsive-table td:last-child{justify-content:flex-end}
            }
            @media(max-width:600px){.cc-toast-root{right:16px;bottom:16px}.cc-modal-actions{flex-direction:column-reverse}.cc-modal-actions button{width:100%;min-height:44px}}
            @media(prefers-reduced-motion:reduce){.cc-toast{animation:none}}
        `;
        document.head.appendChild(style);
    }

    function ensureToastRoot() {
        ensureStyles();
        if (!toastRoot) {
            toastRoot = document.createElement("div");
            toastRoot.className = "cc-toast-root";
            toastRoot.setAttribute("aria-live", "polite");
            toastRoot.setAttribute("aria-atomic", "false");
            document.body.appendChild(toastRoot);
        }
        return toastRoot;
    }

    api.toast = function toast(message, kind = "info", timeout = 4200) {
        const root = ensureToastRoot();
        const node = document.createElement("div");
        node.className = `cc-toast ${kind}`.trim();
        node.setAttribute("role", kind === "error" ? "alert" : "status");
        node.textContent = String(message || "");
        root.appendChild(node);
        const remove = () => node.remove();
        window.setTimeout(remove, Math.max(1200, Number(timeout || 0)));
        return remove;
    };

    function focusableElements(root) {
        return Array.from(root.querySelectorAll('button:not(:disabled),input:not(:disabled),select:not(:disabled),textarea:not(:disabled),a[href],[tabindex]:not([tabindex="-1"])'))
            .filter((node) => !node.hidden && node.getAttribute("aria-hidden") !== "true");
    }

    function modal(options = {}) {
        ensureStyles();
        return new Promise((resolve) => {
            if (modalRoot) modalRoot.remove();
            const previousFocus = document.activeElement;
            const backdrop = document.createElement("div");
            backdrop.className = "cc-modal-backdrop";
            backdrop.setAttribute("role", "presentation");

            const box = document.createElement("section");
            box.className = `cc-modal${options.danger ? " danger" : ""}`;
            box.setAttribute("role", "dialog");
            box.setAttribute("aria-modal", "true");
            box.setAttribute("aria-labelledby", "ccModalTitle");
            box.setAttribute("aria-describedby", "ccModalBody");

            const head = document.createElement("div");
            head.className = "cc-modal-head";
            const title = document.createElement("h2");
            title.id = "ccModalTitle";
            title.textContent = options.title || "Подтверждение";
            head.appendChild(title);

            const body = document.createElement("div");
            body.className = "cc-modal-body";
            body.id = "ccModalBody";
            const text = document.createElement("div");
            text.textContent = options.message || "";
            body.appendChild(text);

            let input = null;
            const expected = options.requireText == null ? "" : String(options.requireText);
            if (options.input || expected) {
                input = document.createElement("input");
                input.className = "cc-modal-input";
                input.type = "text";
                input.value = options.defaultValue || "";
                input.placeholder = options.placeholder || "";
                input.autocomplete = "off";
                input.setAttribute("aria-label", options.inputLabel || "Значение");
                body.appendChild(input);
                if (expected) {
                    const hint = document.createElement("span");
                    hint.className = "cc-modal-hint";
                    hint.textContent = `Для подтверждения введите: ${expected}`;
                    body.appendChild(hint);
                }
            }

            const actions = document.createElement("div");
            actions.className = "cc-modal-actions";
            const cancel = document.createElement("button");
            cancel.type = "button";
            cancel.textContent = options.cancelLabel || "Отмена";
            const confirm = document.createElement("button");
            confirm.type = "button";
            confirm.className = options.danger ? "danger" : "primary";
            confirm.textContent = options.confirmLabel || "Продолжить";
            if (expected) confirm.disabled = input.value.trim() !== expected;
            actions.append(cancel, confirm);

            box.append(head, body, actions);
            backdrop.appendChild(box);
            document.body.appendChild(backdrop);
            modalRoot = backdrop;

            function resultValue() {
                if (expected) return input.value.trim() === expected;
                if (options.input) return String(input.value || "").trim();
                return true;
            }

            function finish(value) {
                if (!modalRoot) return;
                modalRoot.remove();
                modalRoot = null;
                if (previousFocus && typeof previousFocus.focus === "function") previousFocus.focus();
                resolve(value);
            }

            if (input && expected) {
                input.addEventListener("input", () => {
                    confirm.disabled = input.value.trim() !== expected;
                });
            }
            cancel.addEventListener("click", () => finish(options.input ? null : false));
            confirm.addEventListener("click", () => finish(resultValue()));
            backdrop.addEventListener("click", (event) => {
                if (event.target === backdrop && options.dismissOnBackdrop !== false) finish(options.input ? null : false);
            });
            backdrop.addEventListener("keydown", (event) => {
                if (event.key === "Escape") {
                    event.preventDefault();
                    finish(options.input ? null : false);
                    return;
                }
                if (event.key === "Tab") {
                    const focusables = focusableElements(box);
                    if (!focusables.length) return;
                    const first = focusables[0];
                    const last = focusables[focusables.length - 1];
                    if (event.shiftKey && document.activeElement === first) {
                        event.preventDefault();
                        last.focus();
                    } else if (!event.shiftKey && document.activeElement === last) {
                        event.preventDefault();
                        first.focus();
                    }
                    return;
                }
                if (event.key === "Enter" && input && document.activeElement === input && !confirm.disabled) {
                    event.preventDefault();
                    finish(resultValue());
                }
            });
            window.setTimeout(() => (input || confirm).focus(), 0);
        });
    }

    function syncTableRows(table, headers) {
        for (const row of table.querySelectorAll("tbody tr")) {
            const cells = Array.from(row.children).filter((node) => node.tagName === "TD");
            row.classList.toggle("cc-empty-row", cells.length === 1 && Number(cells[0]?.colSpan || 1) > 1);
            cells.forEach((cell, index) => {
                const label = headers[index] || "";
                if (cell.getAttribute("data-cc-label") !== label) cell.setAttribute("data-cc-label", label);
            });
        }
    }

    function enhanceTable(table) {
        if (!table) return;
        const headers = Array.from(table.querySelectorAll("thead th")).map((node) => String(node.textContent || "").trim());
        if (!headers.length) return;
        table.classList.add("cc-responsive-table");
        if (table.dataset.ccResponsive !== "1") {
            table.dataset.ccResponsive = "1";
            const body = table.tBodies[0];
            if (body) {
                const observer = new MutationObserver(() => syncTableRows(table, headers));
                observer.observe(body, {childList: true, subtree: true});
            }
        }
        syncTableRows(table, headers);
    }

    api.enhanceTables = function enhanceTables(root = document) {
        ensureStyles();
        root.querySelectorAll("table").forEach(enhanceTable);
    };

    function observeTables() {
        api.enhanceTables(document);
        if (tableObserver) return;
        tableObserver = new MutationObserver((mutations) => {
            for (const mutation of mutations) {
                for (const node of mutation.addedNodes) {
                    if (!(node instanceof Element)) continue;
                    if (node.matches("table")) enhanceTable(node);
                    node.querySelectorAll?.("table").forEach(enhanceTable);
                }
            }
        });
        tableObserver.observe(document.body, {childList: true, subtree: true});
    }

    api.confirm = (message, options = {}) => modal({message, ...options});
    api.prompt = (message, options = {}) => modal({message, input: true, confirmLabel: "Сохранить", ...options});

    window.ControlCenterUI = api;
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", observeTables, {once: true});
    else observeTables();
})();
