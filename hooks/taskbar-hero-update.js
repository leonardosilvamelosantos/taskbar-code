// Atualiza o estado do Task Bar Hero a cada evento de hook do Claude Code.
// Segue o padrão dos outros hooks: falha silenciosa, custo mínimo, sem dependências externas.
const fs = require('fs');
const path = require('path');
const os = require('os');

const STATUS_DIR = path.join(os.homedir(), '.claude', 'taskbar-hero');
// Um arquivo por sessao (em vez de um status.json compartilhado) elimina a
// race condition entre terminais diferentes: cada processo de hook so
// le/escreve o proprio arquivo, nunca disputa com o de outra sessao.
const SESSIONS_STATUS_DIR = path.join(STATUS_DIR, 'sessions');
const AGENT_TTL_MS = 12000; // agentes concluidos somem do ticker apos esse tempo
// Comandos com run_in_background (ex: Bash em 2o plano) nao tem um evento de
// "terminou" confiavel (PostToolUse do proprio comando so confirma que ele
// COMECOU a rodar em 2o plano, nao que finalizou) — por isso usamos um TTL
// bem mais longo que o dos agentes, so como rede de seguranca contra um
// comando abandonado/travado nunca sumir do ticker.
const BG_STALE_MS = 30 * 60 * 1000;
const LOCK_RETRIES = 40;
const LOCK_DELAY_MS = 10;

function readJsonSafe(file, fallback) {
  try {
    const raw = fs.readFileSync(file, 'utf8').replace(/^﻿/, '');
    return JSON.parse(raw);
  } catch {
    return fallback;
  }
}

function writeJsonAtomic(file, data) {
  const tmp = file + '.tmp-' + process.pid;
  fs.writeFileSync(tmp, JSON.stringify(data));
  fs.renameSync(tmp, file);
}

// Duas invocacoes concorrentes do hook para a MESMA sessao (ex: 2+ subagentes
// em paralelo, cada um disparando seu proprio PreToolUse/PostToolUse) ainda
// disputariam leitura-modificacao-escrita do mesmo arquivo por-sessao. Um
// lock via mkdir (atomico no filesystem) com espera curta resolve isso sem
// dependencias externas; se esgotar as tentativas, segue sem lock (best
// effort — nunca trava o hook indefinidamente).
function withLock(lockPath, fn) {
  for (let i = 0; i < LOCK_RETRIES; i++) {
    try {
      fs.mkdirSync(lockPath);
      try {
        return fn();
      } finally {
        try { fs.rmdirSync(lockPath); } catch {}
      }
    } catch (e) {
      if (e.code !== 'EEXIST') return fn();
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, LOCK_DELAY_MS);
    }
  }
  return fn();
}

function fmtDuration(ms) {
  const s = Math.round((ms || 0) / 1000);
  const m = Math.floor(s / 60);
  const sec = s % 60;
  return m > 0 ? `${m}m${sec}s` : `${sec}s`;
}

function fmtTokens(n) {
  if (!n) return '0';
  return n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(n);
}

function pruneAgents(agents) {
  const now = Date.now();
  const out = {};
  for (const [id, a] of Object.entries(agents || {})) {
    if (a.phase === 'running' || (now - (a.updatedAt || 0)) < AGENT_TTL_MS) out[id] = a;
  }
  return out;
}

function pruneBackground(background) {
  const now = Date.now();
  const out = {};
  for (const [id, b] of Object.entries(background || {})) {
    if ((now - (b.updatedAt || 0)) < BG_STALE_MS) out[id] = b;
  }
  return out;
}

function summarize(d, prevAgents, prevBackground) {
  const event = d.hook_event_name || '';
  const tool = d.tool_name || null;

  // SessionStart zera o estado de qualquer execucao anterior (novo processo,
  // sem estado herdado) — sai antes de podar os mapas anteriores, que seriam
  // descartados de qualquer forma.
  if (event === 'SessionStart') {
    return { summary: 'Sessão iniciada', tool: null, agents: {}, background: {} };
  }

  const agents = pruneAgents(prevAgents);
  const background = pruneBackground(prevBackground);

  // Comando disparado com run_in_background:true (tipicamente Bash) — o
  // PostToolUse desse MESMO comando so confirma que ele comecou a rodar em
  // 2o plano, entao so tratamos o PreToolUse aqui; o job fica "running" ate
  // o TTL (pruneBackground) ou o fim da sessao, na falta de um evento
  // confiavel de "terminou". Fora isso, quando o Claude "para" (Stop) com um
  // job desses ainda rodando, a sessao NAO esta parada esperando voce
  // digitar — esta esperando o job terminar; o switch abaixo reflete isso
  // em vez do "Aguardando novo prompt" generico.
  if (tool && tool !== 'Agent' && event === 'PreToolUse' && d.tool_input && d.tool_input.run_in_background === true) {
    const toolUseId = d.tool_use_id || `${tool}:${Date.now()}`;
    const raw = d.tool_input.command || d.tool_input.description || tool;
    background[toolUseId] = { tool, description: String(raw).slice(0, 80), phase: 'running', updatedAt: Date.now() };
  }

  if (tool === 'Agent' && (event === 'PreToolUse' || event === 'PostToolUse')) {
    const ti = d.tool_input || {};
    const subagentType = ti.subagent_type || 'agent';
    const description = ti.description || '';
    const toolUseId = d.tool_use_id || `${subagentType}:${description}`;
    const base = { type: subagentType, description, updatedAt: Date.now() };

    if (event === 'PreToolUse') {
      agents[toolUseId] = { ...base, phase: 'running' };
    } else {
      const tr = d.tool_response || {};
      const stats = `${tr.totalToolUseCount || 0} tool uses · ${fmtTokens(tr.totalTokens)} tokens · ${fmtDuration(tr.totalDurationMs)}`;
      agents[toolUseId] = { ...base, phase: 'done', stats };
    }

    const list = Object.values(agents);
    const latest = list.reduce((a, b) => ((b.updatedAt || 0) > (a.updatedAt || 0) ? b : a));
    const detail = latest.phase === 'done' ? latest.stats : latest.description;
    const summary = list.length > 1
      ? `${list.length} agentes · ${latest.type}: ${detail}`
      : (latest.phase === 'done' ? `Concluído · ${detail}` : `${latest.type}: ${detail}`);

    return { summary, tool, agents, background };
  }

  const runningBg = Object.values(background).filter((b) => b.phase === 'running');

  switch (event) {
    case 'UserPromptSubmit':
      return { summary: 'Processando prompt do usuário', tool: null, agents, background };
    case 'PreToolUse':
      return { summary: `Executando ${tool || 'ferramenta'}`, tool, agents, background };
    case 'PostToolUse':
      return { summary: `Concluiu ${tool || 'ferramenta'}`, tool, agents, background };
    case 'Notification':
      return { summary: d.message ? String(d.message).slice(0, 140) : 'Aguardando ação do usuário', tool: null, agents, background };
    case 'Stop':
    case 'SubagentStop': {
      if (runningBg.length > 0) {
        const latest = runningBg.reduce((a, b) => ((b.updatedAt || 0) > (a.updatedAt || 0) ? b : a));
        const summary = runningBg.length > 1
          ? `Aguardando ${runningBg.length} tarefas em 2º plano · ${latest.description}`
          : `Aguardando em 2º plano: ${latest.description}`;
        return { summary, tool: null, agents, background };
      }
      return { summary: 'Aguardando novo prompt', tool: null, agents, background };
    }
    default:
      return { summary: event, tool, agents, background };
  }
}

const chunks = [];
process.stdin.on('data', (c) => chunks.push(c));
process.stdin.on('end', () => {
  let d = {};
  try {
    const raw = Buffer.concat(chunks).toString('utf8').replace(/^﻿/, '');
    d = JSON.parse(raw);
  } catch {
    process.exit(0);
  }
  const sessionId = d.session_id;
  if (!sessionId) process.exit(0);

  try { fs.mkdirSync(SESSIONS_STATUS_DIR, { recursive: true }); } catch {}

  const file = path.join(SESSIONS_STATUS_DIR, `${sessionId}.json`);
  const lockPath = file + '.lock';

  withLock(lockPath, () => {
    if (d.hook_event_name === 'SessionEnd') {
      try { fs.unlinkSync(file); } catch {}
      return;
    }
    const prev = readJsonSafe(file, {});
    const { summary, tool, agents, background } = summarize(d, prev.agents, prev.background);
    const next = {
      cwd: d.cwd || prev.cwd || null,
      warpUuid: process.env.WARP_TERMINAL_SESSION_UUID || prev.warpUuid || null,
      event: d.hook_event_name,
      tool,
      summary,
      agents,
      background,
      updatedAt: Date.now(),
    };
    try { writeJsonAtomic(file, next); } catch {}
  });

  process.exit(0);
});
