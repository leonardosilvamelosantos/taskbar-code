// Atualiza o status.json do Task Bar Hero a cada evento de hook do Claude Code.
// Segue o padrão dos outros hooks: falha silenciosa, custo mínimo, sem dependências externas.
const fs = require('fs');
const path = require('path');
const os = require('os');

const STATUS_DIR = path.join(os.homedir(), '.claude', 'taskbar-hero');
const STATUS_FILE = path.join(STATUS_DIR, 'status.json');
const AGENT_TTL_MS = 12000; // agentes concluidos somem do ticker apos esse tempo

function readJsonSafe(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}

function writeJsonAtomic(file, data) {
  const tmp = file + '.tmp-' + process.pid;
  fs.writeFileSync(tmp, JSON.stringify(data));
  fs.renameSync(tmp, file);
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

function summarize(d, prevAgents) {
  const event = d.hook_event_name || '';
  const tool = d.tool_name || null;

  // SessionStart zera os agentes de qualquer execucao anterior (novo processo,
  // sem estado herdado) — sai antes de podar o mapa anterior, que seria
  // descartado de qualquer forma.
  if (event === 'SessionStart') {
    return { summary: 'Sessão iniciada', tool: null, agents: {} };
  }

  const agents = pruneAgents(prevAgents);

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

    return { summary, tool, agents };
  }

  switch (event) {
    case 'UserPromptSubmit':
      return { summary: 'Processando prompt do usuário', tool: null, agents };
    case 'PreToolUse':
      return { summary: `Executando ${tool || 'ferramenta'}`, tool, agents };
    case 'PostToolUse':
      return { summary: `Concluiu ${tool || 'ferramenta'}`, tool, agents };
    case 'Notification':
      return { summary: d.message ? String(d.message).slice(0, 140) : 'Aguardando ação do usuário', tool: null, agents };
    case 'Stop':
    case 'SubagentStop':
      return { summary: 'Aguardando novo prompt', tool: null, agents };
    default:
      return { summary: event, tool, agents };
  }
}

const chunks = [];
process.stdin.on('data', (c) => chunks.push(c));
process.stdin.on('end', () => {
  let d = {};
  try { d = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { process.exit(0); }
  const sessionId = d.session_id;
  if (!sessionId) process.exit(0);

  try { fs.mkdirSync(STATUS_DIR, { recursive: true }); } catch {}

  const data = readJsonSafe(STATUS_FILE, { sessions: {} });
  if (!data.sessions) data.sessions = {};
  const prev = data.sessions[sessionId] || {};

  if (d.hook_event_name === 'SessionEnd') {
    delete data.sessions[sessionId];
  } else {
    const { summary, tool, agents } = summarize(d, prev.agents);
    data.sessions[sessionId] = {
      cwd: d.cwd || prev.cwd || null,
      warpUuid: process.env.WARP_TERMINAL_SESSION_UUID || prev.warpUuid || null,
      event: d.hook_event_name,
      tool,
      summary,
      agents,
      updatedAt: Date.now(),
    };
  }

  try { writeJsonAtomic(STATUS_FILE, data); } catch {}
  process.exit(0);
});
