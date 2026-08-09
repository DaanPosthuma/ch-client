const DISPLAY_W = 64, DISPLAY_H = 32;
const canvas = document.getElementById("display-canvas");
const ctx = canvas.getContext("2d");
const scale = canvas.width / DISPLAY_W;

let runId = null;
let playing = false;
let playTimer = null;
let pressedKeys = new Set();

// Standard CHIP-8 keypad layout (COSMAC VIP), and the common physical-keyboard mapping.
const KEYPAD_LAYOUT = [0x1, 0x2, 0x3, 0xC, 0x4, 0x5, 0x6, 0xD, 0x7, 0x8, 0x9, 0xE, 0xA, 0x0, 0xB, 0xF];
const KEY_MAP = {
    "1": 0x1, "2": 0x2, "3": 0x3, "4": 0xC,
    "q": 0x4, "w": 0x5, "e": 0x6, "r": 0xD,
    "a": 0x7, "s": 0x8, "d": 0x9, "f": 0xE,
    "z": 0xA, "x": 0x0, "c": 0xB, "v": 0xF,
};

function drawDisplay(disp) {
    ctx.fillStyle = "#000";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = "#c9d1d9";
    for (let row = 0; row < DISPLAY_H; row++) {
        for (let col = 0; col < DISPLAY_W; col++) {
            if (disp[row * DISPLAY_W + col]) {
                ctx.fillRect(col * scale, row * scale, scale, scale);
            }
        }
    }
}

function renderState(s) {
    drawDisplay(s.disp);
    document.getElementById("s-step").textContent = s.step_id;
    document.getElementById("s-pc").textContent = "0x" + s.pc.toString(16).toUpperCase().padStart(3, "0");
    document.getElementById("s-op").textContent = "0x" + s.opcode.toString(16).toUpperCase().padStart(4, "0");
    document.getElementById("s-i").textContent = "0x" + s.i.toString(16).toUpperCase().padStart(3, "0");
    document.getElementById("s-sp").textContent = s.sp;
    document.getElementById("s-dt").textContent = s.dt;
    document.getElementById("s-st").textContent = s.st;

    const grid = document.getElementById("reg-grid");
    grid.innerHTML = s.v.map((val, idx) =>
        `<div><span>V${idx.toString(16).toUpperCase()}</span> = 0x${val.toString(16).toUpperCase().padStart(2, "0")}</div>`
    ).join("");
}

function buildKeypad() {
    const el = document.getElementById("keypad");
    el.innerHTML = "";
    for (const key of KEYPAD_LAYOUT) {
        const btn = document.createElement("button");
        btn.textContent = key.toString(16).toUpperCase();
        btn.dataset.key = key;
        btn.onmousedown = () => pressedKeys.add(key);
        btn.onmouseup = () => pressedKeys.delete(key);
        btn.onmouseleave = () => pressedKeys.delete(key);
        el.appendChild(btn);
    }
}

function refreshKeypadHighlight() {
    document.querySelectorAll("#keypad button").forEach(btn => {
        btn.classList.toggle("pressed", pressedKeys.has(Number(btn.dataset.key)));
    });
}

function currentKeysArray() {
    const arr = new Array(16).fill(0);
    for (const k of pressedKeys) arr[k] = 1;
    return arr;
}

window.addEventListener("keydown", e => {
    if (e.key.toLowerCase() in KEY_MAP) { pressedKeys.add(KEY_MAP[e.key.toLowerCase()]); refreshKeypadHighlight(); }
});
window.addEventListener("keyup", e => {
    if (e.key.toLowerCase() in KEY_MAP) { pressedKeys.delete(KEY_MAP[e.key.toLowerCase()]); refreshKeypadHighlight(); }
});

async function loadRoms() {
    const roms = await fetch("/api/roms").then(r => r.json());
    const sel = document.getElementById("rom-select");
    sel.innerHTML = roms.map(r => `<option value="${r}">${r}</option>`).join("");
}

async function newRun() {
    stopPlaying();
    const rom = document.getElementById("rom-select").value;
    const res = await fetch("/api/runs", {
        method: "POST", headers: {"Content-Type": "application/json"},
        body: JSON.stringify({rom}),
    }).then(r => r.json());
    runId = res.run_id;
    document.getElementById("run-badge").textContent = `run ${runId.slice(0, 8)} (${rom})`;
    document.getElementById("run-badge").classList.add("ok");
    document.getElementById("play-pause").disabled = false;
    document.getElementById("step-once").disabled = false;
    const state = await fetch(`/api/runs/${runId}/state`).then(r => r.json());
    renderState(state);
    refreshTrace();
}

async function step(cycles) {
    if (!runId) return;
    const res = await fetch(`/api/runs/${runId}/step`, {
        method: "POST", headers: {"Content-Type": "application/json"},
        body: JSON.stringify({cycles, keys: currentKeysArray()}),
    });
    if (!res.ok) { stopPlaying(); return; }
    renderState(await res.json());
}

function stopPlaying() {
    playing = false;
    if (playTimer) clearInterval(playTimer);
    document.getElementById("play-pause").textContent = "▶ Play";
}

function startPlaying() {
    playing = true;
    document.getElementById("play-pause").textContent = "⏸ Pause";
    const tick = () => step(Number(document.getElementById("speed").value));
    playTimer = setInterval(tick, 33);
}

document.getElementById("new-run").onclick = newRun;
document.getElementById("step-once").onclick = () => step(1);
document.getElementById("play-pause").onclick = () => playing ? stopPlaying() : startPlaying();
document.getElementById("speed").oninput = e => {
    document.getElementById("speed-label").textContent = `${e.target.value} cycles/tick`;
};
document.getElementById("refresh-trace").onclick = refreshTrace;

async function refreshTrace() {
    if (!runId) return;
    const rows = await fetch(`/api/runs/${runId}/history?limit=300`).then(r => r.json());
    const tbody = document.querySelector("#trace-table tbody");
    tbody.innerHTML = rows.slice(-100).map(r =>
        `<tr><td>${r.step_id}</td><td>0x${r.pc.toString(16).toUpperCase()}</td><td>0x${r.opcode.toString(16).toUpperCase().padStart(4, "0")}</td><td>${r.pixels_on}</td><td>${r.dt}</td><td>${r.st}</td></tr>`
    ).join("");
}

buildKeypad();
loadRoms();
drawDisplay(new Array(DISPLAY_W * DISPLAY_H).fill(0));
