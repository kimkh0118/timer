// 윈도우판 연결 다리: 화면(index.html)은 맥판과 똑같이 window.webkit.messageHandlers.tm.postMessage(...)로
// 말을 걸어요. 여기서 그 말을 받아 윈도우 쪽(main.js)에 그대로 전해 줘요.
const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("webkit", {
  messageHandlers: { tm: { postMessage: msg => ipcRenderer.send("tm", msg) } },
});
contextBridge.exposeInMainWorld("__NATIVE__", true);
contextBridge.exposeInMainWorld("__WINDOWS__", true);
contextBridge.exposeInMainWorld("__VERSION__", ipcRenderer.sendSync("version"));
contextBridge.exposeInMainWorld("__winCtl", {
  close: () => ipcRenderer.send("win", "close"),
  minimize: () => ipcRenderer.send("win", "minimize"),
});

// 윈도우 전용 손질: 창 끌기 영역, 창 버튼(최소화·닫기)
window.addEventListener("DOMContentLoaded", () => {
  const css = document.createElement("style");
  css.textContent = `
    /* 빈 곳을 잡고 끌면 창이 움직여요 (버튼·입력칸·시간 숫자는 그대로 눌려요) */
    body:not(.sheet-open) { -webkit-app-region: drag; }
    button, input, select, label, summary, a, .u, .sheet, .time.edit, #time, .winbtns { -webkit-app-region: no-drag; }
    .winbtns { position: fixed; top: 8px; left: 10px; z-index: 30; display: flex; gap: 6px; }
    .winbtns button { width: 14px; height: 14px; border-radius: 50%; border: 0; padding: 0; cursor: pointer;
      font-size: 9px; line-height: 14px; color: transparent; }
    .winbtns:hover button { color: rgba(0,0,0,.55); }
    .winbtns .wclose { background: #ff5f57; } .winbtns .wmin { background: #febc2e; }
    body.compact .winbtns { display: none; }
  `;
  document.head.appendChild(css);

  const bar = document.createElement("div");
  bar.className = "winbtns";
  bar.innerHTML = '<button class="wclose" title="닫기" aria-label="닫기">✕</button><button class="wmin" title="최소화" aria-label="최소화">−</button>';
  bar.querySelector(".wclose").onclick = () => ipcRenderer.send("win", "close");
  bar.querySelector(".wmin").onclick = () => ipcRenderer.send("win", "minimize");
  document.body.appendChild(bar);

  // 설정이 열려 있을 때는 빈 곳 클릭으로 설정을 닫아야 하니 끌기를 잠깐 꺼요.
  const sheet = document.getElementById("sheet");
  if (sheet) new MutationObserver(() => document.body.classList.toggle("sheet-open", !sheet.hidden))
    .observe(sheet, { attributes: true, attributeFilter: ["hidden"] });
});
