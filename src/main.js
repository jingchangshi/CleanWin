import { invoke } from "@tauri-apps/api/core";
import "./styles.css";

const diagnoseBtn = document.querySelector("#diagnoseBtn");
const cleanBtn = document.querySelector("#cleanBtn");
const clearBtn = document.querySelector("#clearBtn");
const statusEl = document.querySelector("#status");
const outputEl = document.querySelector("#output");
const usedMemoryEl = document.querySelector("#usedMemory");
const pagedPoolEl = document.querySelector("#pagedPool");
const nonpagedPoolEl = document.querySelector("#nonpagedPool");
const wslStatusEl = document.querySelector("#wslStatus");

function setBusy(isBusy, label = "就绪") {
  diagnoseBtn.disabled = isBusy;
  cleanBtn.disabled = isBusy;
  clearBtn.disabled = isBusy;
  statusEl.textContent = label;
  statusEl.dataset.state = isBusy ? "busy" : "idle";
}

function appendOutput(title, result) {
  const text = [
    `\n===== ${title} =====`,
    result.stdout || "",
    result.stderr ? `\n[stderr]\n${result.stderr}` : "",
    `\n退出码：${result.code}`,
  ]
    .filter(Boolean)
    .join("\n");

  outputEl.textContent = outputEl.textContent === "点击“运行诊断”开始。" ? text.trim() : `${outputEl.textContent}\n${text}`;
  updateMetrics(result.stdout || "");
}

function readMetric(text, label) {
  const escaped = label.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = text.match(new RegExp(`${escaped}[:：]\\s*([0-9.]+\\s*GB|[0-9.]+%)`));
  return match ? match[1] : "-";
}

function updateMetrics(text) {
  const used = readMetric(text, "已用内存");
  const paged = readMetric(text, "Paged Pool");
  const nonpaged = readMetric(text, "Nonpaged Pool");

  if (used !== "-") usedMemoryEl.textContent = used;
  if (paged !== "-") pagedPoolEl.textContent = paged;
  if (nonpaged !== "-") nonpagedPoolEl.textContent = nonpaged;

  if (text.includes("正在运行的 WSL 发行版")) {
    wslStatusEl.textContent = "运行中";
  } else if (text.includes("未发现正在运行的 WSL 发行版")) {
    wslStatusEl.textContent = "未运行";
  }
}

async function runAction(title, action) {
  setBusy(true, "运行中");
  try {
    const result = await action();
    appendOutput(title, result);
    statusEl.textContent = result.code === 0 ? "完成" : "完成，有警告";
  } catch (error) {
    outputEl.textContent += `\n\n===== ${title} 失败 =====\n${error}`;
    statusEl.textContent = "失败";
  } finally {
    setBusy(false, statusEl.textContent);
  }
}

diagnoseBtn.addEventListener("click", () => {
  runAction("诊断", () => invoke("run_diagnose"));
});

cleanBtn.addEventListener("click", () => {
  runAction("安全清理", () => invoke("run_clean"));
});

clearBtn.addEventListener("click", () => {
  outputEl.textContent = "点击“运行诊断”开始。";
  usedMemoryEl.textContent = "-";
  pagedPoolEl.textContent = "-";
  nonpagedPoolEl.textContent = "-";
  wslStatusEl.textContent = "-";
  statusEl.textContent = "就绪";
});
