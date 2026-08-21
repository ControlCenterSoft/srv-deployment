(() => {
  const baseEnrollmentStatusLabel = enrollmentStatusLabel;
  enrollmentStatusLabel = (node) => {
    const base = baseEnrollmentStatusLabel(node);
    const health = node.health || "unknown";
    const seen = Number.isFinite(node.last_seen_seconds_ago)
      ? ` · seen ${node.last_seen_seconds_ago}s ago`
      : "";
    const inventory = [node.hostname, node.os_name && node.os_version ? `${node.os_name} ${node.os_version}` : node.os_name, node.architecture]
      .filter(Boolean)
      .join(" · ");
    return `${base} · health ${health}${seen}${inventory ? ` · ${inventory}` : ""}`;
  };
})();
