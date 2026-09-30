/*
 * Vencord user plugin. Licensed under GPL-3.0-or-later.
 */
import { definePluginSettings } from "@api/Settings";
import definePlugin, { OptionType } from "@utils/types";
import { FluxDispatcher } from "@webpack/common";

const settings = definePluginSettings({
    applicationId: { type: OptionType.STRING, description: "Discord application ID for Capturely", default: "", restartNeeded: true },
    paused: { type: OptionType.BOOLEAN, description: "Pause publishing presence", default: false, onChange: () => { clear(); socket?.close(); } }
});
const socketId = "EnhancedPresence";
let socket: WebSocket | undefined;
let reconnect: ReturnType<typeof setTimeout> | undefined;
let running = false;
let retry = 1000;

function clear() {
    FluxDispatcher.dispatch({ type: "LOCAL_ACTIVITY_UPDATE", socketId, activity: null });
}
function connect() {
    if (!running) return;
    const ws = new WebSocket("ws://127.0.0.1:48731");
    socket = ws;
    ws.onopen = () => { retry = 1000; };
    ws.onmessage = event => {
        if (ws !== socket || !running || typeof event.data !== "string" || event.data.length > 8192) return;
        try {
            const message = JSON.parse(event.data);
            if (message?.version !== 1) return;
            if (settings.store.paused || message.type === "clear") { clear(); return; }
            if (message.type !== "activity") return;
            const a = message.activity;
            const id = settings.store.applicationId.trim();
            // A local provider is still an input boundary. Accept only bounded normalized fields.
            if (!/^\d{17,20}$/.test(id) || a?.appId !== "com.capturely.app" || a.source !== "capturely"
                || typeof a.appName !== "string" || a.appName.length > 128
                || typeof a.details !== "string" || a.details.length > 128
                || typeof a.state !== "string" || a.state.length > 128
                || !Number.isFinite(a.timestamps?.start) || a.timestamps.start <= 0) { clear(); return; }
            FluxDispatcher.dispatch({
                type: "LOCAL_ACTIVITY_UPDATE", socketId,
                activity: {
                    application_id: id, name: a.appName, details: a.details, state: a.state,
                    type: 0, flags: 1, timestamps: { start: a.timestamps.start * 1000 }
                }
            });
        } catch { clear(); }
    };
    ws.onerror = () => ws.close();
    ws.onclose = () => {
        if (ws !== socket) return;
        clear();
        socket = undefined;
        if (running) {
            reconnect = setTimeout(connect, retry);
            retry = Math.min(retry * 2, 30000);
        }
    };
}

export default definePlugin({
    name: "EnhancedPresence",
    description: "Publishes Capturely replay status from the local EnhancedPresence bridge.",
    authors: [{ name: "Italian-seasoning", id: 0n }],
    settings,
    start() { running = true; connect(); },
    stop() {
        running = false;
        clearTimeout(reconnect);
        const ws = socket;
        socket = undefined;
        ws?.close();
        clear();
    }
});
