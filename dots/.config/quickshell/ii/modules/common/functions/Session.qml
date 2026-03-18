pragma Singleton
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common

Singleton {
    id: root

    readonly property string saveSessionScript: `${Directories.config}/quickshell/ii/scripts/hyprland/save-session.sh`

    function saveSession() {
        if (Config.options.session.saveRestore) {
            sessionSaver.running = true;
        }
    }

    Process {
        id: sessionSaver
        command: ["bash", root.saveSessionScript]
        onExited: (code) => {
            if (root._pendingAction)
                root._pendingAction();
            root._pendingAction = null;
        }
    }

    property var _pendingAction: null

    function _saveAndThen(action) {
        if (Config.options.session.saveRestore) {
            _pendingAction = action;
            sessionSaver.running = true;
        } else {
            action();
        }
    }

    function closeAllWindows() {
        HyprlandData.windowList.map(w => w.pid).forEach(pid => {
            Quickshell.execDetached(["kill", pid]);
        });
    }

    function changePassword() {
        Quickshell.execDetached(["bash", "-c", `${Config.options.apps.changePassword}`]);
    }

    function lock() {
        Quickshell.execDetached(["loginctl", "lock-session"]);
    }

    function suspend() {
        Quickshell.execDetached(["bash", "-c", "systemctl suspend || loginctl suspend"]);
    }

    function logout() {
        _saveAndThen(() => {
            closeAllWindows();
            Quickshell.execDetached(["pkill", "-i", "Hyprland"]);
        });
    }

    function launchTaskManager() {
        Quickshell.execDetached(["bash", "-c", "command -v resources && resources || " + Config.options.apps.taskManager]);
    }

    function hibernate() {
        saveSession();
        Quickshell.execDetached(["bash", "-c", `systemctl hibernate || loginctl hibernate`]);
    }

    function poweroff() {
        _saveAndThen(() => {
            closeAllWindows();
            Quickshell.execDetached(["bash", "-c", `systemctl poweroff || loginctl poweroff`]);
        });
    }

    function reboot() {
        _saveAndThen(() => {
            closeAllWindows();
            Quickshell.execDetached(["bash", "-c", `reboot || loginctl reboot`]);
        });
    }

    function rebootToFirmware() {
        _saveAndThen(() => {
            closeAllWindows();
            Quickshell.execDetached(["bash", "-c", `systemctl reboot --firmware-setup || loginctl reboot --firmware-setup`]);
        });
    }
}
