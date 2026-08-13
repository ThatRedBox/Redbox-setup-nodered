/*
 *  Node-RED settings for Redbox
 *
 *  Lives in the userDir the systemd drop-in points Node-RED at
 *  (/opt/Redbox/nodered), so Node-RED reads it on every start without being
 *  told where it is.
 *
 *  httpAdminRoot is '/editor' because Edgeberry proxies everything under
 *  /application/ to this port with the prefix stripped: the editor is reached
 *  at http://<device>/application/editor. Anything served from here that must
 *  be an absolute URL has to read the X-Forwarded-Prefix header, or it escapes
 *  the proxy and lands on the device's catch-all.
 */
const path = require('path');

module.exports = {
    userDir: '/opt/Redbox/nodered',
    httpAdminRoot: "/editor",
    flowFile: 'flows/Redbox_flows.json',
    library: {
        user: path.join(__dirname, 'flows', 'lib')
    },
    flowFilePretty: true,

    diagnostics: {
        enabled: true,
        ui: true,
    },

    runtimeState: {
        enabled: false,
        ui: false,
    },

    logging: {
        console: {
            level: "info",
            metrics: false,
            audit: false
        }
    },

    functionExternalModules: true,
    functionTimeout: 0,

    exportGlobalContextKeys: false,

    externalModules: {},

    editorTheme: {
        theme: "redbox",
        page: {
            title: "Redbox",
            favicon: "/favicon.ico"
        },
        header: {
            title: "Editor",
            image: null,    // no logo image, just the title text
            url: "/",
        },
        palette: {},
        projects: {
            enabled: false,
            workflow: {
                mode: "manual"
            }
        },
        codeEditor: {
            lib: "monaco",
            options: {}
        },
        markdownEditor: {
            mermaid: {
                enabled: true
            }
        },
        multiplayer: {
            enabled: false
        }
    },

    // Context storage. 'persistent' survives a restart; the default does not,
    // so anything a flow must remember across a reboot has to name it.
    contextStorage: {
        default:    { module: "memory" },
        persistent: { module: "localfilesystem" }
    },

    // Serve static files from /opt/Redbox/assets - this is what makes
    // /favicon.ico above resolve.
    httpStatic: '/opt/Redbox/assets',

    // Network settings
    uiPort: process.env.PORT || 1880,
    mqttReconnectTime: 15000,
    serialReconnectTime: 15000,

    debugMaxLength: 1000,

};
