let storageLoadGeneration = 0;

function formatStorageBytes(value) {
  const bytes = Number(value);
  if (!Number.isFinite(bytes) || bytes < 0) return "—";
  if (bytes === 0) return "0 B";
  const units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
  const exponent = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  const amount = bytes / (1024 ** exponent);
  const digits = exponent === 0 || amount >= 100 ? 0 : amount >= 10 ? 1 : 2;
  return `${amount.toFixed(digits)} ${units[exponent]}`;
}

function storageSupportLabel(value) {
  return value === true ? "да" : value === false ? "нет" : "—";
}

function renderStorageManagement(container, management = {}) {
  const note = document.createElement("p");
  note.className = "muted";
  note.textContent = `Core capabilities: inventory ${storageSupportLabel(management.inventory_supported)} · partitions ${storageSupportLabel(management.partitions_supported)} · filesystems ${storageSupportLabel(management.filesystems_supported)} · mounts ${storageSupportLabel(management.mounts_supported)} · preview ${storageSupportLabel(management.preview_supported)} · preflight ${storageSupportLabel(management.preflight_supported)} · apply ${storageSupportLabel(management.apply_supported)}.`;
  container.appendChild(note);

  if (management.reason) {
    const reason = document.createElement("p");
    reason.className = "muted";
    reason.textContent = `Ограничение Core: ${management.reason}.`;
    container.appendChild(reason);
  }
}

function renderStorageDevices(container, data) {
  container.textContent = "";
  container.hidden = false;

  const heading = document.createElement("h3");
  heading.textContent = "Накопители";
  container.appendChild(heading);

  const devices = Array.isArray(data.devices) ? data.devices : [];
  const summary = document.createElement("p");
  summary.role = "status";
  summary.setAttribute("aria-live", "polite");
  summary.textContent = devices.length ? `Обнаружено устройств: ${devices.length}.` : "Блочные устройства не обнаружены.";
  container.appendChild(summary);

  if (devices.length) {
    const list = document.createElement("ul");
    list.className = "compact-list";
    for (const device of devices) {
      const item = document.createElement("li");
      const identity = device.device_path || device.name || "—";
      const access = device.read_only ? "read-only" : "read-write";
      const removable = device.removable ? "removable" : "fixed";
      const logical = device.logical_block_size ? ` · logical block ${formatStorageBytes(device.logical_block_size)}` : "";
      const physical = device.physical_block_size ? ` · physical block ${formatStorageBytes(device.physical_block_size)}` : "";
      item.textContent = `${identity} · ${formatStorageBytes(device.size_bytes)} · ${access} · ${removable}${logical}${physical}`;
      list.appendChild(item);
    }
    container.appendChild(list);
  }

  const warnings = Array.isArray(data.warnings) ? data.warnings : [];
  if (warnings.length) {
    const warningHeading = document.createElement("h4");
    warningHeading.textContent = "Предупреждения инвентаря";
    container.appendChild(warningHeading);

    const warningList = document.createElement("ul");
    warningList.className = "compact-list";
    for (const warning of warnings) {
      const item = document.createElement("li");
      item.textContent = `${warning.device || "—"} · ${warning.code || "inventory_warning"}`;
      warningList.appendChild(item);
    }
    container.appendChild(warningList);
  }

  renderStorageManagement(container, data.management || {});
}

async function loadStorageDevices() {
  storageLoadGeneration += 1;
  const generation = storageLoadGeneration;
  const container = document.querySelector("#storage-devices");
  if (!container) return;

  container.textContent = "";
  container.hidden = false;

  const status = document.createElement("p");
  status.className = "muted";
  status.role = "status";
  status.setAttribute("aria-live", "polite");
  status.textContent = "Загрузка инвентаря накопителей…";
  container.appendChild(status);

  try {
    const data = await api("/api/v1/storage/devices");
    if (generation !== storageLoadGeneration) return;
    renderStorageDevices(container, data);
  } catch (error) {
    if (generation !== storageLoadGeneration) return;
    container.textContent = "";
    const message = document.createElement("p");
    message.className = "error";
    message.role = "alert";
    message.textContent = `Не удалось загрузить инвентарь накопителей: ${error.message}`;
    container.appendChild(message);
  }
}

document.querySelectorAll(".nav-item").forEach((button) => {
  button.addEventListener("click", () => {
    storageLoadGeneration += 1;
    const container = document.querySelector("#storage-devices");
    if (!container) return;
    container.textContent = "";
    container.hidden = true;
    if (button.dataset.page === "system") loadStorageDevices();
  });
});
