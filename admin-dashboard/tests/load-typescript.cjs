const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const ts = require("typescript");

const root = path.resolve(__dirname, "..");

function createLoader(mocks = {}, globals = {}) {
  const cache = new Map();
  function load(relative) {
    const filename = path.resolve(root, relative);
    if (cache.has(filename)) return cache.get(filename).exports;
    const module = { exports: {} };
    cache.set(filename, module);
    const code = ts.transpileModule(fs.readFileSync(filename, "utf8"), {
      compilerOptions: {
        module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
        jsx: ts.JsxEmit.ReactJSX, esModuleInterop: true,
      },
    }).outputText;
    const context = {
      module, exports: module.exports, process, console, URLSearchParams, ...globals,
      require(name) {
        if (Object.hasOwn(mocks, name)) return mocks[name];
        if (name.startsWith("@/")) {
          const stem = name.slice(2);
          const target = [stem + ".ts", stem + ".tsx", stem + "/index.ts"].find((candidate) => fs.existsSync(path.join(root, candidate)));
          if (!target) throw new Error("Module absent : " + name);
          return load(target);
        }
        return require(name);
      },
    };
    vm.runInNewContext(code, context, { filename });
    return module.exports;
  }
  return load;
}

module.exports = { createLoader, root };
