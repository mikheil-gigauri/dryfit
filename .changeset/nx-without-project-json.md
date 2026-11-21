---
"@dryfit/cli": patch
---

`dryfit add` builds an Nx library that has no `project.json` with Nx. When its `package.json` has a `build` script or `nx.targets.build`, or it has an `ng-package.json`, the library is built with `nx build` under the name Nx gives it, and its output folder is published, instead of falling back to `npm run build` and the library root.
