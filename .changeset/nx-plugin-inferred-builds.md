---
"@dryfit/cli": patch
---

`dryfit add` builds an Nx library whose build target comes from a plugin. When `nx.json` lists the `@nx/js/typescript`, `@nx/vite`, `@nx/rollup` or `@nx/webpack` plugin and the library has that plugin's config file, it is built with `nx` under the target name the plugin is configured to use, instead of falling back to the npm script.
