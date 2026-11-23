---
title: Compared with npm link and yalc
description: When dryfit is the right tool, and when something simpler will do.
---

There are three common ways to try a library change in an app before releasing it, and each trades
something for its speed.

**`npm link`** (and `pnpm link`, `yarn link`) replaces the package in the app's `node_modules` with a
symlink to your library folder. Changes appear instantly, with no build or install. But the app now
resolves the library's own dependencies from the library's folder, so frameworks that must exist once,
such as Angular or React, are loaded twice. Bundlers follow symlinks differently, and nothing in the app's
manifest or lockfile records the link, so it is easy to forget it is there.

**[yalc](https://github.com/wclr/yalc)** copies a packed library into a `.yalc` folder and points the app's
`package.json` at it with a `file:` dependency. That avoids duplicate frameworks and works with every
package manager. Your manifest and lockfile change, and `yalc remove` puts the manifest back. Because the
version does not change between pushes, caches that key on versions may keep the old build.

**Copying the build output** into the app's `node_modules` is fast and needs no tool, but the next install
silently undoes it, and peer dependencies are never checked.

**dryfit** installs a newly versioned package from a registry, the same way the release will be
installed. It is slower than a symlink, by however long your build and an install take, and it runs a
background service. In return:

|                                 | dryfit                              | npm link      | yalc                        | Copying the build |
| ------------------------------- | ------------------------------------ | ------------- | --------------------------- | ----------------- |
| Installed like a release        | Yes, from a registry                 | No, a symlink | Close, a `file:` dependency | No                |
| One copy of shared frameworks   | Yes                                  | No            | Yes                         | Yes               |
| A new version for every change  | Yes                                  | No            | No                          | No                |
| Framework caches cleared        | Yes                                  | No            | No                          | No                |
| Puts the app back exactly       | Manifest and lockfile, byte for byte | By hand       | Manifest                    | Reinstall by hand |
| Keeps dev builds out of commits | Git hook                             | No            | `yalc check`                | No                |
| Several apps at once            | Linked apps and groups               | One by one    | `yalc push`                 | By hand           |

Use `npm link` for a quick look at a library with no framework peer dependencies. Use dryfit when the
change has to behave in the app exactly as the release will, or when several apps need it at once.
