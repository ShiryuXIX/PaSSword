function setDesktopAppVersion(html, version) {
  const displayVersion = formatDesktopAppVersion(version);
  return html.replace(
    /<span class="version-label" id="version-label">[\s\S]*?<\/span>/,
    `<span class="version-label" id="version-label">PaSSword ${displayVersion}</span>`,
  );
}

function formatDesktopAppVersion(version) {
  const match = /^(\d+)\.(\d+)\.\d+(?:[-+][0-9A-Za-z.-]+)?$/.exec(version);
  if (!match) {
    throw new TypeError("La versión de PaSSword debe tener el formato semántico major.minor.patch.");
  }
  return `${match[1]}.${match[2]}`;
}

module.exports = { formatDesktopAppVersion, setDesktopAppVersion };
