(() => {
    "use strict";
    const grid = document.getElementById("torrentGrid");

    function render(items) {
        grid.textContent = "";
        if (!items.length) {
            const card = document.createElement("article");
            card.className = "service-card";
            const title = document.createElement("strong");
            title.textContent = "Торрент-сервисы не установлены";
            card.appendChild(title);
            grid.appendChild(card);
            return;
        }
        for (const item of items) {
            const card = document.createElement("article");
            card.className = "service-card";
            const head = document.createElement("div");
            head.className = "service-card-title";
            const name = document.createElement("strong");
            name.textContent = item.name;
            const state = document.createElement("span");
            state.textContent = item.state || "—";
            head.append(name, state);
            const details = document.createElement("p");
            details.textContent = item.unit || "";
            card.append(head, details);
            grid.appendChild(card);
        }
    }

    async function load() {
        const response = await fetch("/api/v1/torrents", {cache: "no-store"});
        if (!response.ok) {
            grid.textContent = "";
            return;
        }
        const payload = await response.json();
        render((payload.data && payload.data.services) || []);
    }

    load();
    window.setInterval(load, 15000);
})();
