---
'@dryfit/cli': patch
---

When an install fails because a dev build pins a package from its own workspace that dryfit does not know, dryfit now says which folder to register with `dryfit add` and how to link both.
