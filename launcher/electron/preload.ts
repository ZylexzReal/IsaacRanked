import { contextBridge, ipcRenderer } from "electron";

contextBridge.exposeInMainWorld("isaacRanked", {
  play: () => ipcRenderer.invoke("launcher:play"),
  openConfigDir: () => ipcRenderer.invoke("launcher:open-config-dir"),
  onStatus: (handler: (event: unknown) => void) => {
    const listener = (_event: Electron.IpcRendererEvent, payload: unknown) => handler(payload);
    ipcRenderer.on("launcher:status", listener);
    return () => ipcRenderer.removeListener("launcher:status", listener);
  },
  onUpdate: (handler: (event: unknown) => void) => {
    const listener = (_event: Electron.IpcRendererEvent, payload: unknown) => handler(payload);
    ipcRenderer.on("launcher:update", listener);
    return () => ipcRenderer.removeListener("launcher:update", listener);
  },
});
