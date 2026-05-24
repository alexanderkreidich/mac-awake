# Mac Awake

Mac Awake is a small macOS menu bar app that keeps your Mac awake with the lid closed for a fixed short timer: 5, 30, or 60 minutes.

![Mac Awake menu bar menu](docs/assets/mac-awake-menu.png)

## Use

1. Open Mac Awake.
2. Choose `5 minutes`, `30 minutes`, or `60 minutes` from the menu bar.
3. Click the active duration again to cancel early.
4. Quit Mac Awake to restore normal sleep behavior before exit.

## Installation

No signed release is available yet.

For a local development install:

```sh
git clone https://github.com/alexanderkreidich/mac-awake.git
cd mac-awake
./scripts/install.sh
```

This builds Mac Awake, installs the development helper, configures the app to open at login for your user account, and opens the app. It requires Xcode and an administrator password.

## Safety

Keeping a closed Mac awake can trap heat and drain battery. Use Mac Awake only when the Mac has ventilation and enough power.

If normal sleep is not restored, run:

```sh
sudo pmset -a disablesleep 0
```
