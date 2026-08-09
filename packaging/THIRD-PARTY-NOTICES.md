# Third-party software notices

T3 Code's own source code is licensed under the MIT License. The native Linux
package also contains Electron, Chromium, and production npm dependencies that
remain under their respective upstream licenses.

The package installs these license resources:

- `LICENSE` or `copyright.upstream`: the T3 Code MIT License;
- `LICENSE.electron.txt`: the Electron license;
- `LICENSES.chromium.html`: Chromium and Chromium third-party notices;
- `THIRD-PARTY-LICENSES.json`: the package names, versions, declared licenses,
  and metadata reported by `pnpm licenses list --prod --json` for the desktop
  and server production dependency graphs; and
- license files retained with npm dependencies under
  `/usr/lib/t3code/resources/app.asar` and
  `/usr/lib/t3code/resources/app.asar.unpacked`.

The exact dependency versions used to form a package are locked by the
`pnpm-lock.yaml` in the corresponding T3 Code source commit. The source commit
and archive digest are pinned by this packaging project's build configuration.

These notices do not replace, modify, or summarize the applicable license
terms. Consult the listed files for those terms and attribution requirements.
