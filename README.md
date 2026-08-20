![Redbox banner](https://raw.githubusercontent.com/ThatRedBox/.github/refs/heads/main/brand/Redbox_banner.png)

**Redbox** turns an [Edgeberry](https://github.com/Edgeberry) device into a Node-RED box. It
installs Node-RED, registers it with Edgeberry as *the* application on the device, and brands both
the device interface and the editor. What the box does is whatever you wire up.

## Install

```bash
wget -O install.sh https://github.com/ThatRedBox/Redbox-setup-nodered/releases/latest/download/install.sh
chmod +x ./install.sh
sudo ./install.sh
```

Editor: `http://<device>/application/editor` · Dashboard: `http://<device>/application/dashboard`

A fresh install comes with a starter flow. Its **Edgeberry Platform** group is
what puts this box on the device interface - the name, the links and the health
light all come from the messages those two inject nodes send. Edit them to suit
what the box becomes; delete them and the device interface has nothing to show.

Re-run the installer to update - it takes the latest release and preserves your
flows. The starter flow is only ever written when there is none.

Uninstall with `sudo /opt/Redbox/uninstall.sh`. It removes `/opt/Redbox` **and the flows with it**,
so export anything worth keeping. Node.js, NPM, Node-RED and jq stay: they are shared with the rest
of the device.

## License & Collaboration

**Copyright© 2026 Sanne 'SpuQ' Santens**. Redbox is licensed under the
**[MIT License](LICENSE.txt)**. Trademark rules and guidlines apply.

Contributions welcome: fork from `main`, keep to the project's conventions, test your changes, and
open a pull request describing the problem it addresses.
