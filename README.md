# elementary 0

Unofficial elementary OS patches and modified packages with latest upstream


## Bug fixed
- [x] slingshot-launcher (applications-menu) [issue](https://github.com/elementary/applications-menu/issues/677) | [patch](https://github.com/fahmiirsyadk/elementary-zero/blob/main/recipes/applications-menu/patches/calculator-crash-fix.patch)

## Modified packages
- file search feature on application menu 

## Setup
1. install nix, this is required for build process [Nix](https://nixos.org/download/).
2. run `nix-shell` and you ready to go.
3. cd recipes/<packages_you_want_to_patch>
4. run build `./build.sh` and then to install (overwrite existing package) `./install.sh`
5. you can rollback using `./rollback.sh`

## Warning
This might be or likely can crash you system, but all patches already tested on VM so its safe.
