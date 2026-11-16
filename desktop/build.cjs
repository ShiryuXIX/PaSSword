const path = require("node:path");
const esbuild = require("esbuild");

esbuild.build({
  entryPoints: [path.join(__dirname, "ui", "app.js")],
  bundle: true,
  format: "esm",
  platform: "browser",
  target: "chrome130",
  outfile: path.join(__dirname, "generated", "app.bundle.js"),
  legalComments: "external",
  sourcemap: false,
}).catch((error) => {
  console.error("No se pudo preparar el código local de PaSSword.", error);
  process.exitCode = 1;
});
