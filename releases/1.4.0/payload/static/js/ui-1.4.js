(() => {
    "use strict";

    const api = {};
    let toastRoot = null;
    let modalRoot = null;

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
            .cc-modal-head{padding:20px 20px 0}.cc-modal-head h2{margin:0;font-size:18px}.cc-modal-body{padding:12px 20px 20px;color:var(--muted,#91a8bc);font-size:13px;line-height:1.55;white-space:pre-wrap}
            .cc-modal-input{width:100%;min-height:43px;margin-top:14px;padding:0 12px;border:1px solid var(--border,#1c3850);border-radius:9px;background:#081522;color:var(--text,#f1f7fc);outline:none}.cc-modal-input:focus{border-color:rgba(45,156,255,.75);box-shadow:0 0 0 3px rgba(45,156,255,.11)}
            .cc-modal-actions{display:flex;justify-content:flex-end;gap:9px;padding:14px 20px 20px}.cc-modal-actions button{min-height:40px;padding:0 15px;border-radius:9px;border:1px solid var(--border,#1c3850);background:var(--surface-2,#0e1e2e);color:var(--text,#f1f7fc);font:inherit;font-weight:700;cursor:pointer}.cc-modal-actions button.primary{border-color:rgba(45,156,255,.48);background:rgba(45,156,255,.16)}.cc-modal-actions button.danger{border-color:rgba(239,100,100,.42);background:rgba(239,100,100,.12);color:#ffc4c4}.cc-modal-actions button:focus-visible{outline:2px solid #20d8e5;outline-offset:2px}
            @keyframes ccToastIn{from{transform:translateY(8px);opacity:0}to{transform:none;opacity:1}}
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

    function modal(options = {}) {
        ensureStyles();
        return new Promise((resolve) => {
            if (modalRoot) modalRoot.remove();
            const previousFocus = document.activeElement;
            const backdrop = document.createElement("div");
            backdrop.className = "cc-modal-backdrop";
            backdrop.setAttribute("role", "presentation");

            const box = document.createElement("section");
            box.className = "cc-modal";
            box.setAttribute("role", "dialog");
            box.setAttribute("aria-modal", "true");
            box.setAttribute("aria-labelledby", "ccModalTitle");

            const head = document.createElement("div");
            head.className = "cc-modal-head";
            const title = document.createElement("h2");
            title.id = "ccModalTitle";
            title.textContent = options.title || "Подтверждение";
            head.appendChild(title);

            const body = document.createElement("div");
            body.className = "cc-modal-body";
            const text = document.createElement("div");
            text.textContent = options.message || "";
            body.appendChild(text);

            let input = null;
            if (options.input) {
                input = document.createElement("input");
                input.className = "cc-modal-input";
                input.type = "text";
                input.value = options.defaultValue || "";
                input.placeholder = options.placeholder || "";
                input.setAttribute("aria-label", options.inputLabel || "Значение");
                body.appendChild(input);
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
            actions.append(cancel, confirm);

            box.append(head, body, actions);
            backdrop.appendChild(box);
            document.body.appendChild(backdrop);
            modalRoot = backdrop;

            function finish(value) {
                if (!modalRoot) return;
                modalRoot.remove();
                modalRoot = null;
                if (previousFocus && typeof previousFocus.focus === "function") previousFocus.focus();
                resolve(value);
            }

            cancel.addEventListener("click", () => finish(options.input ? null : false));
            confirm.addEventListener("click", () => finish(options.input ? String(input.value || "").trim() : true));
            backdrop.addEventListener("click", (event) => {
                if (event.target === backdrop) finish(options.input ? null : false);
            });
            backdrop.addEventListener("keydown", (event) => {
                if (event.key === "Escape") {
                    event.preventDefault();
                    finish(options.input ? null : false);
                }
                if (event.key === "Enter" && input && document.activeElement === input) {
                    event.preventDefault();
                    finish(String(input.value || "").trim());
                }
            });
            window.setTimeout(() => (input || confirm).focus(), 0);
        });
    }

    api.confirm = (message, options = {}) => modal({message, ...options});
    api.prompt = (message, options = {}) => modal({message, input: true, confirmLabel: "Сохранить", ...options});

    window.ControlCenterUI = api;
})();
