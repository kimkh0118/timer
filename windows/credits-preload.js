// 엔딩 크레딧 창: credits.html이 "닫아 줘"라고 하면 윈도우 쪽에 전해요.
const { contextBridge, ipcRenderer } = require("electron");
contextBridge.exposeInMainWorld("webkit", {
  messageHandlers: { cr: { postMessage: () => ipcRenderer.send("credits-close") } },
});
