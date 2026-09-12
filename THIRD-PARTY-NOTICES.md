# Third-party Notices

This file identifies dependencies relevant to the distributed DeckScope plugin. It does not assign a license to DeckScope's original code or resolve the provenance of the user-supplied prototype. The project owner must review redistribution rights before publishing a release.

| Component | Version / source | Distribution role | License |
| --- | --- | --- | --- |
| Decky API | `@decky/api` 1.1.3, [loader-api](https://github.com/SteamDeckHomebrew/loader-api) | API wrapper code is bundled into `dist/index.js` | LGPL-2.1; included in [license text](licenses/decky-api-LGPL-2.1.txt) |
| Decky UI | `@decky/ui` 4.12.0, [decky-frontend-lib](https://github.com/SteamDeckHomebrew/decky-frontend-lib) | External host dependency, exposed through Decky's `DFL`; implementation not included in the plugin ZIP | LGPL-2.1 |
| React / ReactDOM | Provided by Steam/Decky | External host dependencies, not distributed as standalone React libraries in the plugin ZIP | Refer to the host distribution |
| React Icons | `react-icons` 5.7.0, [react-icons](https://github.com/react-icons/react-icons) | Tree-shaken icon rendering helpers and selected icons | MIT for the library; included [upstream notice](licenses/react-icons.txt) identifies icon-set licenses |
| Font Awesome 5 | [Font Awesome](https://fontawesome.com/), by Fonticons, Inc. | Selected icons imported from `react-icons/fa`, adapted to React/SVG through React Icons | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) for icons |

Dependency versions and integrity hashes are recorded in `pnpm-lock.yaml`. Install the lockfile with `pnpm install --frozen-lockfile`; the package contents and licenses are available in `node_modules/@decky/api`, `node_modules/@decky/ui` and `node_modules/react-icons`. The published API source package is available from [npm](https://www.npmjs.com/package/@decky/api/v/1.1.3). The build recipe and project source are in this repository. The API wrapper can be replaced with a locally modified implementation and rebuilt using `pnpm build`; no signature check or anti-modification mechanism is added by DeckScope.

The upstream React Icons notice lists many icon sets. Its inclusion preserves the upstream file unchanged; it does not mean that every listed icon set is bundled. Toolchain/build-only packages are also not installed into SteamOS by the plugin ZIP. This notice is an inventory, not a legal-compliance certification.
