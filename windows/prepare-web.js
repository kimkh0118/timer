// 맥판 화면 파일(app/Resources)을 그대로 가져와 web/ 에 넣어요. 엔딩 크레딧 숫자도 함께 만들어요.
const fs = require("fs"), path = require("path"), { execSync } = require("child_process");
const src = path.join(__dirname, "..", "app", "Resources"), dst = path.join(__dirname, "web");
fs.rmSync(dst, { recursive: true, force: true }); fs.mkdirSync(dst);
for (const f of fs.readdirSync(src)) if (!f.endsWith(".mp3") && f !== ".DS_Store") fs.copyFileSync(path.join(src, f), path.join(dst, f));
const git = c => { try { return execSync(c, { cwd: __dirname }).toString().trim(); } catch (e) { return "0"; } };
const commits = +git("git rev-list --count HEAD"), versions = git("git tag").split("\n").filter(Boolean).length + 1;
fs.writeFileSync(path.join(dst, "credits-stats.js"), `window.CREDIT_STATS = { commits: ${commits}, versions: ${versions} };\n`);
fs.copyFileSync(path.join(__dirname, "..", "docs", "icon.png"), path.join(__dirname, "icon.png"));
console.log("web/ 준비 완료");
