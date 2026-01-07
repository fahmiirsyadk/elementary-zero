# Elementary Zero
Tool to patch several issue & extra features for elementary OS

### Background

My reason is simple: I use elementary OS as my main operating system. I love how it looks and its simplicity classic yet modern. However, nothing is perfect, and there are some issues I need to deal with. This tool helps me apply patches and fix the issues I encounter.

## Patches

### applications-menu

* **calculator-crash-fix.patch** - Fixes crash when tyring to copy/click calculator results from search. Adds clipboard copy functionality for calculator results.

* **file-search-feature.patch** - Adds file search functionality to the applications menu. Like search and you can open it directly without navigation from file manager.

* **fix-double-launch-on-enter.patch** - Fixes bug where pressing Enter after searching would launch applications twice. Prevents duplicate application launches.

## Building and Installation

You'll need the following dependencies:

* libgee-0.8-dev
* libgranite-7-dev >= 7.7.0
* libgtk-4-dev >= 4.10.0
* libjson-glib-dev
* libsoup-3.0-dev >= 3.0.0
* libswitchboard-3-dev >= 8.0.0
* meson >= 0.59.0
* valac >= 0.48.0

Run `meson` to configure the build environment and then `ninja` to build

    meson build --prefix=/usr
    cd build
    ninja

To install, use `ninja install`

    sudo ninja install

## Building .deb Package

Run `./build-deb.sh` to create a .deb package

    ./build-deb.sh

Upload the generated .deb file to GitHub releases.

## Runtime Dependencies

* git
* meson
* ninja-build
* policykit-1

## License

MIT
