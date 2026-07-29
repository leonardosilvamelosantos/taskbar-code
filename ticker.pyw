"""Task Bar Hero — chip flutuante ancorado na barra de tarefas do Windows,
mostrando o que as sessoes do Claude Code estao fazendo. Design "Vital
Signs": indicador de pulso animado (estado), texto em 2 linhas (nome +
o que esta fazendo), anel duplo de metricas (contexto / rate limit 5h)
e barra de "stories" indicando posicao no carrossel entre terminais."""
import ctypes
import glob
import json
import math
import os
import sqlite3
import sys
import time
import traceback
import tkinter as tk
import tkinter.font as tkfont
from pathlib import Path

if sys.platform != "win32":
    raise SystemExit(
        "Task Bar Hero so roda no Windows (usa ctypes.windll para janela/z-order "
        "e o sqlite do Warp em %LOCALAPPDATA%)."
    )

HOME = os.path.expanduser("~")
STATUS_DIR = os.path.join(HOME, ".claude", "taskbar-hero")
STATUS_FILE = os.path.join(STATUS_DIR, "status.json")
USAGE_FILE = os.path.join(STATUS_DIR, "usage.json")
CONFIG_FILE = os.path.join(STATUS_DIR, "window_config.json")
SESSIONS_DIR = os.path.join(HOME, ".claude", "sessions")
LOG_FILE = os.path.join(STATUS_DIR, "ticker.log")

os.makedirs(STATUS_DIR, exist_ok=True)


def log_exception(where):
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(f"--- {where} ---\n")
            f.write(traceback.format_exc())
            f.write("\n")
    except Exception:
        pass


user32 = ctypes.windll.user32
kernel32 = ctypes.windll.kernel32

HWND_TOP = 0
HWND_TOPMOST = -1
SWP_NOMOVE, SWP_NOSIZE, SWP_NOACTIVATE = 0x0002, 0x0001, 0x0010
GWL_EXSTYLE = -20
WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW = 0x08000000, 0x00000080
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
STILL_ACTIVE = 259

# ZBID_SYSTEM_TOOLS=14 — banda de z-order interna do shell (API nao
# documentada SetWindowBand/GetWindowBand, desde o Windows 8), mais alta que
# a banda padrao de janelas comuns. Tentamos essa banda para brigar melhor
# com flyouts do shell (volume, rede) — nao vence o menu Iniciar, que fica
# numa banda exclusiva do shell por design de seguranca do Windows.
ZBID_SYSTEM_TOOLS = 14

# -- paleta ------------------------------------------------------------------
WIN_BG = "#1C1C1C"
CARD = "#16191D"
CARD_EDGE = "#2E343B"
TXT_1 = "#E6EDF3"
TXT_1_DIM = "#A8B1BA"
TXT_2 = "#8B949E"
TXT_3 = "#5A6570"
TRACK = "#262C33"
TRACK_DONE = "#3A4149"
TRACK_ACTIVE = "#7D8896"
OK = "#3FB950"
WARN = "#E3B341"
CRIT = "#F0736A"
MUTE = "#545D68"

STATE_WORKING, STATE_NEEDS_YOU, STATE_IDLE = "working", "needs_you", "idle"
STATE_COLOR = {STATE_WORKING: OK, STATE_NEEDS_YOU: WARN, STATE_IDLE: MUTE}
STATE_DARK = {STATE_WORKING: "#1E3A24", STATE_NEEDS_YOU: "#4A3A1C", STATE_IDLE: CARD_EDGE}


class RECT(ctypes.Structure):
    _fields_ = [("left", ctypes.c_long), ("top", ctypes.c_long),
                ("right", ctypes.c_long), ("bottom", ctypes.c_long)]


def get_taskbar_rect():
    hwnd = user32.FindWindowW("Shell_TrayWnd", None)
    rect = RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(rect))
    return rect.left, rect.top, rect.right, rect.bottom


def is_pid_alive(pid):
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return False
    exit_code = ctypes.c_ulong(0)
    ok = kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code))
    kernel32.CloseHandle(handle)
    return bool(ok) and exit_code.value == STILL_ACTIVE


def read_json_safe(path, fallback):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return fallback


def load_window_config():
    cfg = read_json_safe(CONFIG_FILE, None)
    if cfg and all(k in cfg for k in ("x", "y", "w", "h")):
        return cfg
    left, top, right, bottom = get_taskbar_rect()
    h = max(28, bottom - top)
    w = 380
    x = max(left, right - w - 160)
    y = top
    return {"x": x, "y": y, "w": w, "h": h}


def save_window_config(cfg):
    try:
        tmp = CONFIG_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(cfg, f)
        os.replace(tmp, CONFIG_FILE)
    except Exception:
        pass


def project_name(cwd):
    if not cwd:
        return "?"
    return os.path.basename(cwd.rstrip("\\/")) or cwd


def pct_color(pct):
    """Mesmos thresholds do /statusline do usuario (colorFor em statusline-command.js)."""
    if pct is None:
        return TRACK
    if pct < 50:
        return OK
    if pct < 70:
        return WARN
    return CRIT


WARP_DB_PATH = os.path.join(
    os.environ.get("LOCALAPPDATA", os.path.join(HOME, "AppData", "Local")),
    "warp", "Warp", "data", "warp.sqlite",
)

_warp_name_cache = {}


def refresh_warp_names():
    """Le o nome que o usuario deu a cada aba/pane no Warp, direto do sqlite do
    app (mode=ro, nunca immutable=1 — retorna dado velho). Qualquer falha
    (Warp fechado, lock, coluna renomeada) mantem o cache anterior."""
    global _warp_name_cache
    if not os.path.isfile(WARP_DB_PATH):
        return
    try:
        uri = Path(WARP_DB_PATH).as_uri() + "?mode=ro"
        conn = sqlite3.connect(uri, uri=True, timeout=0.2)
        try:
            cur = conn.execute(
                "SELECT lower(hex(tp.uuid)) AS uuid, "
                "       COALESCE(pl.custom_vertical_tabs_title, t.custom_title) AS name "
                "FROM terminal_panes tp "
                "JOIN pane_leaves pl ON pl.pane_node_id = tp.id "
                "JOIN pane_nodes  pn ON pn.id = tp.id "
                "JOIN tabs t ON t.id = pn.tab_id"
            )
            new_cache = {uuid: name for uuid, name in cur.fetchall() if name}
            if new_cache:
                _warp_name_cache = new_cache
        finally:
            conn.close()
    except Exception:
        pass


def lerp_color(c1, c2, t):
    t = max(0.0, min(1.0, t))
    r1, g1, b1 = int(c1[1:3], 16), int(c1[3:5], 16), int(c1[5:7], 16)
    r2, g2, b2 = int(c2[1:3], 16), int(c2[3:5], 16), int(c2[5:7], 16)
    r = round(r1 + (r2 - r1) * t)
    g = round(g1 + (g2 - g1) * t)
    b = round(b1 + (b2 - b1) * t)
    return f"#{r:02x}{g:02x}{b:02x}"


def smoothstep(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def fmt_elapsed(ms):
    if ms is None:
        return ""
    secs = max(0, int((time.time() * 1000 - ms) / 1000))
    if secs < 60:
        return f"{secs}s"
    mins = secs // 60
    if mins < 60:
        return f"{mins}m"
    h = mins // 60
    m = mins % 60
    return f"{h}h{m:02d}"


def derive_state(session):
    if session["status"] == "busy":
        return STATE_WORKING
    if "aguardando sua resposta" in (session.get("summary") or "").lower():
        return STATE_NEEDS_YOU
    return STATE_IDLE


def project_dir_name(cwd):
    if not cwd:
        return None
    return cwd.replace(":", "-").replace("\\", "-").replace("/", "-").replace(" ", "-")


_title_cache = {}


def get_ai_title(sid, cwd):
    """Le o titulo real da sessao (aiTitle), gerado pelo proprio Claude Code e
    persistido no transcript .jsonl. Le so os ultimos ~200KB do arquivo e
    cacheia por mtime para nao reprocessar arquivos grandes a cada poll."""
    if not sid or not cwd:
        return None
    proj_dir = project_dir_name(cwd)
    path = os.path.join(HOME, ".claude", "projects", proj_dir, f"{sid}.jsonl")
    try:
        mtime = os.path.getmtime(path)
    except OSError:
        return _title_cache.get(sid, {}).get("title")

    cached = _title_cache.get(sid)
    if cached and cached.get("mtime") == mtime:
        return cached.get("title")

    title = None
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            chunk_size = min(size, 200_000)
            if size > chunk_size:
                f.seek(-chunk_size, os.SEEK_END)
            data = f.read().decode("utf-8", errors="ignore")
        for line in reversed(data.splitlines()):
            if '"type":"ai-title"' in line:
                try:
                    title = json.loads(line).get("aiTitle")
                    break
                except Exception:
                    continue
    except Exception:
        title = None
    _title_cache[sid] = {"title": title, "mtime": mtime}
    return title


def collect_sessions():
    """Junta ~/.claude/sessions/<pid>.json (status busy/idle) com o status.json
    escrito pelos hooks (evento/tool/summary/updatedAt/agent), casando por
    sessionId, e o titulo real da conversa (aiTitle) do transcript."""
    hook_status = read_json_safe(STATUS_FILE, {"sessions": {}}).get("sessions", {})
    entries = []
    for path in sorted(glob.glob(os.path.join(SESSIONS_DIR, "*.json"))):
        s = read_json_safe(path, None)
        if not s:
            continue
        pid = s.get("pid")
        if pid and not is_pid_alive(pid):
            continue
        sid = s.get("sessionId")
        hook = hook_status.get(sid, {})
        cwd = hook.get("cwd") or s.get("cwd")
        warp_name = _warp_name_cache.get(hook.get("warpUuid"))
        name = warp_name or get_ai_title(sid, cwd) or s.get("name") or project_name(cwd)
        status = s.get("status", "idle")
        summary = hook.get("summary")
        if not summary:
            summary = "Trabalhando..." if status == "busy" else "Aguardando sua resposta"
        entries.append({
            "sid": sid, "name": name, "status": status, "summary": summary,
            "tool": hook.get("tool"), "agents": hook.get("agents") or {},
            "updatedAt": hook.get("updatedAt") or s.get("updatedAt"),
        })
    return entries


class Ticker:
    HOLD_MS = 9000
    SLIDE_MS = 420
    FRAME_MS = 33
    POLL_MS = 1000

    CAP_W = 44
    VIEW_X0 = 32

    def __init__(self):
        cfg = load_window_config()
        self.root = tk.Tk()
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.configure(bg=WIN_BG)
        self.root.geometry(f"{cfg['w']}x{cfg['h']}+{cfg['x']}+{cfg['y']}")

        self.canvas = tk.Canvas(self.root, bg=WIN_BG, highlightthickness=0)
        self.canvas.pack(fill="both", expand=True)

        self.resize_handle = tk.Frame(self.root, bg="#555555", width=10, height=10, cursor="size_nw_se")
        self.resize_handle.place(relx=1.0, rely=1.0, anchor="se")

        self.font_name = tkfont.Font(family="Segoe UI Semibold", size=9)
        self.font_summary = tkfont.Font(family="Segoe UI", size=8)
        self.font_mono = tkfont.Font(family="Consolas", size=7)
        self.font_ring = tkfont.Font(family="Segoe UI", size=7, weight="bold")

        self.paused = False
        self.blocks = []
        self.current_sid = None
        self.sliding = False
        self.slide_t0 = None
        self.slide_from_state = STATE_IDLE
        self.slide_to_state = STATE_IDLE
        self.hold_started = time.time()
        self.last_frame_state = None
        self._pending_save = None
        self._drag_origin = None
        self._resize_origin = None
        self._usage_map = {}
        self._session_pct_cached = None

        self.root.update_idletasks()
        self.root.after(0, self._apply_exstyle)
        self._build_menu()
        self._bind_events()
        self._reassert_top()
        self._poll_warp_names()
        self._poll_data()
        self._schedule_hold()
        self._tick()

    # -- janela / z-order --------------------------------------------------
    def _apply_exstyle(self):
        try:
            hwnd = self.root.winfo_id()
            style = user32.GetWindowLongW(hwnd, GWL_EXSTYLE)
            user32.SetWindowLongW(hwnd, GWL_EXSTYLE, style | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW)
        except Exception:
            log_exception("_apply_exstyle")

    def _reassert_top(self):
        try:
            hwnd = self.root.winfo_id()
            flags = SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE
            # sem o toggle NOTOPMOST->TOPMOST: ele fazia a janela cair por um
            # instante antes de voltar, o que causava o "atraso" ao reaparecer.
            # So reafirmar TOPMOST + TOP e mais rapido e sem piscar.
            user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, flags)
            user32.SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0, flags)
            self.root.attributes("-topmost", True)
            try:
                user32.SetWindowBand(hwnd, HWND_TOP, ZBID_SYSTEM_TOOLS)
            except Exception:
                pass
        except Exception:
            log_exception("_reassert_top")
        finally:
            self.root.after(60, self._reassert_top)

    def _poll_warp_names(self):
        try:
            refresh_warp_names()
        except Exception:
            log_exception("_poll_warp_names")
        finally:
            self.root.after(4000, self._poll_warp_names)

    # -- drag manual / resize -------------------------------------------------
    def _bind_events(self):
        self.canvas.bind("<ButtonPress-1>", self._start_drag)
        self.canvas.bind("<B1-Motion>", self._do_drag)
        self.canvas.bind("<Button-3>", self._show_menu)
        self.root.bind("<Configure>", self._on_configure)
        self.resize_handle.bind("<ButtonPress-1>", self._start_resize)
        self.resize_handle.bind("<B1-Motion>", self._do_resize)

    def _start_drag(self, event):
        self._drag_origin = (event.x_root, event.y_root, self.root.winfo_x(), self.root.winfo_y())

    def _do_drag(self, event):
        if not self._drag_origin:
            return
        sx, sy, wx, wy = self._drag_origin
        nx = wx + (event.x_root - sx)
        ny = wy + (event.y_root - sy)
        self.root.geometry(f"+{nx}+{ny}")

    def _start_resize(self, event):
        self._resize_origin = (event.x_root, event.y_root, self.root.winfo_width(), self.root.winfo_height())

    def _do_resize(self, event):
        ox, oy, ow, oh = self._resize_origin
        w = max(220, ow + (event.x_root - ox))
        h = max(30, oh + (event.y_root - oy))
        self.root.geometry(f"{w}x{h}")

    def _on_configure(self, _event):
        if self._pending_save:
            self.root.after_cancel(self._pending_save)
        self._pending_save = self.root.after(1500, self._save_geometry)

    def _save_geometry(self):
        self._pending_save = None
        save_window_config({
            "x": self.root.winfo_x(), "y": self.root.winfo_y(),
            "w": self.root.winfo_width(), "h": self.root.winfo_height(),
        })
        self._draw_frame(self.last_frame_state or STATE_IDLE, force=True)

    # -- menu ----------------------------------------------------------------
    def _build_menu(self):
        self.menu = tk.Menu(self.root, tearoff=0)
        self.menu.add_command(label="Pausar", command=self._toggle_pause)
        self.menu.add_command(label="Resetar posição", command=self._reset_position)
        self.menu.add_separator()
        self.menu.add_command(label="Sair", command=self._quit)

    def _show_menu(self, event):
        self.menu.entryconfig(0, label="Retomar" if self.paused else "Pausar")
        self.menu.tk_popup(event.x_root, event.y_root)

    def _toggle_pause(self):
        self.paused = not self.paused

    def _reset_position(self):
        try:
            os.remove(CONFIG_FILE)
        except OSError:
            pass
        cfg = load_window_config()
        self.root.geometry(f"{cfg['w']}x{cfg['h']}+{cfg['x']}+{cfg['y']}")

    def _quit(self):
        self._save_geometry()
        self.root.destroy()

    # -- geometria derivada ----------------------------------------------------
    def _geom(self):
        w = self.canvas.winfo_width() or self.root.winfo_width()
        h = self.canvas.winfo_height() or self.root.winfo_height()
        view_x1 = w - self.CAP_W - 4
        ring_cx = w - 24
        r_out = min(15, (h - 14) / 2)
        r_in = max(4, r_out - 5)
        return {
            "w": w, "h": h, "cy": h / 2, "organ_cx": 17,
            "view_x0": self.VIEW_X0, "view_x1": view_x1,
            "ring_cx": ring_cx, "r_out": r_out, "r_in": r_in,
            "bar_y": h - 5,
        }

    # -- dados -----------------------------------------------------------------
    def _current_block_by_sid(self, sid):
        for b in self.blocks:
            if b["sid"] == sid:
                return b
        return None

    def _index_of_sid(self, sid, default=0):
        return next((i for i, b in enumerate(self.blocks) if b["sid"] == sid), default)

    def _poll_data(self):
        try:
            self.blocks = collect_sessions()
            # usage.json e lido 1x por ciclo de poll (1/s) e cacheado; o slide
            # roda a ~30fps e antes reabria/reparseava esse arquivo a cada frame.
            self._usage_map = read_json_safe(USAGE_FILE, {})
            self._session_pct_cached = (
                max(self._usage_map.values(), key=lambda e: e.get("updatedAt", 0)).get("sessionPct")
                if self._usage_map else None
            )
            if not self.sliding:
                blk = self._current_block_by_sid(self.current_sid) if self.current_sid else None
                if blk is None and self.blocks:
                    blk = self.blocks[0]
                    self.current_sid = blk["sid"]
                self._redraw_static(blk)
        except Exception:
            log_exception("_poll_data")
        finally:
            self.root.after(self.POLL_MS, self._poll_data)

    def _redraw_static(self, blk):
        g = self._geom()
        state = derive_state(blk) if blk else STATE_IDLE
        self._draw_frame(state)
        self.canvas.delete("blk_cur", "blk_next")
        if blk:
            idx = self._index_of_sid(blk["sid"])
            self._draw_block(blk, g["view_x0"], "blk_cur", g, idx, len(self.blocks), 1.0)
        else:
            self.canvas.create_text(g["view_x0"], g["cy"], text="nenhuma sessão ativa",
                                     fill=TXT_3, anchor="w", font=self.font_summary, tags="blk_cur")
        self._draw_ring(self._ctx_pct_for(self.current_sid), self._session_pct_cached, g)

    def _ctx_pct_for(self, sid):
        """Contexto e por sessao/janela — cada terminal tem sua propria conversa.
        Le do cache de usage.json (atualizado 1x/s em _poll_data), nao do disco."""
        if not sid:
            return None
        return self._usage_map.get(sid, {}).get("contextPct")

    # -- moldura (camada 0) -----------------------------------------------------
    def _draw_frame(self, state, force=False):
        if state == self.last_frame_state and not force:
            return
        self.last_frame_state = state
        g = self._geom()
        w, h = g["w"], g["h"]
        self.canvas.delete("frame")
        self.canvas.create_rectangle(1, 1, w - 2, h - 2, fill=CARD, outline="", tags="frame")
        r = 8
        self.canvas.create_arc(0, 0, r * 2, r * 2, start=90, extent=90, style="pieslice",
                                fill=WIN_BG, outline=WIN_BG, tags="frame")
        self.canvas.create_arc(w - r * 2, 0, w, r * 2, start=0, extent=90, style="pieslice",
                                fill=WIN_BG, outline=WIN_BG, tags="frame")
        self.canvas.create_arc(0, h - r * 2, r * 2, h, start=180, extent=90, style="pieslice",
                                fill=WIN_BG, outline=WIN_BG, tags="frame")
        self.canvas.create_arc(w - r * 2, h - r * 2, w, h, start=270, extent=90, style="pieslice",
                                fill=WIN_BG, outline=WIN_BG, tags="frame")
        self.canvas.create_rectangle(1, 1, w - 2, h - 2, fill="", outline=CARD_EDGE, tags="frame")
        dark = STATE_DARK[state]
        steps = max(6, w // 12)
        for i in range(steps):
            x0 = 2 + i * (w - 4) / steps
            x1 = 2 + (i + 1) * (w - 4) / steps
            t = min(1.0, (x0 - 2) / (0.6 * w))
            self.canvas.create_line(x0, 2, x1, 2, fill=lerp_color(dark, CARD_EDGE, t), tags="frame")
        self.canvas.tag_lower("frame")

    # -- bloco de texto (camada 1) ------------------------------------------------
    def _truncate(self, text, max_w, font=None):
        font = font or self.font_summary
        if font.measure(text) <= max_w:
            return text
        while text and font.measure(text + "…") > max_w:
            text = text[:-1]
        return text + "…" if text else ""

    def _icon_robot(self, tag, x, y, color):
        """Icone vetorial de robo (sem depender de emoji/fonte) — marca que a
        atividade exibida e de um subagente, nao do terminal principal."""
        w, h = 13, 11
        top = y - h / 2
        self.canvas.create_line(x + w / 2, top - 3, x + w / 2, top, fill=color, tags=tag)
        self.canvas.create_oval(x + w / 2 - 1.5, top - 5, x + w / 2 + 1.5, top - 2,
                                 fill=color, outline="", tags=tag)
        self.canvas.create_rectangle(x, top, x + w, top + h, fill=CARD, outline=color, tags=tag)
        eye_y = top + h * 0.4
        self.canvas.create_oval(x + 3, eye_y - 1.3, x + 6, eye_y + 1.3, fill=color, outline="", tags=tag)
        self.canvas.create_oval(x + w - 6, eye_y - 1.3, x + w - 3, eye_y + 1.3, fill=color, outline="", tags=tag)
        return w

    def _draw_block(self, session, x0, tag, g, idx, total, alpha):
        one = total <= 1
        l1_cy = g["cy"] - (7 if one else 8)
        l2_cy = g["cy"] + (8 if one else 7)
        avail = g["view_x1"] - g["view_x0"] - 10
        counter_txt = f"{idx + 1}/{total}" if total > 1 else ""
        counter_w = (self.font_mono.measure(counter_txt) + 10) if counter_txt else 0

        blend = lambda target: lerp_color(CARD, target, alpha)
        name_col = blend(TXT_1 if session["status"] == "busy" else TXT_1_DIM)
        sum_col = blend(TXT_2)
        dim_col = blend(TXT_3)

        name = self._truncate(session["name"], avail - counter_w, self.font_name)
        self.canvas.create_text(x0, l1_cy, text=name, anchor="w", fill=name_col,
                                 font=self.font_name, tags=tag)

        cursor2 = x0
        agents = list((session.get("agents") or {}).values())
        if agents:
            any_running = any(a.get("phase") == "running" for a in agents)
            icon_color = blend("#58A6FF" if any_running else OK)
            icon_w = self._icon_robot(tag, cursor2, l2_cy, icon_color)
            cursor2 += icon_w + 4
            if len(agents) > 1:
                count_txt = str(len(agents))
                self.canvas.create_text(cursor2, l2_cy - 5, text=count_txt, anchor="w",
                                         fill=blend(TXT_1), font=self.font_mono, tags=tag)
                cursor2 += self.font_mono.measure(count_txt) + 4

        elapsed = fmt_elapsed(session.get("updatedAt"))
        suffix = f" · {elapsed}" if elapsed else ""
        summary_full = (session.get("summary") or "") + suffix
        summary = self._truncate(summary_full, avail - counter_w - (cursor2 - x0), self.font_summary)
        self.canvas.create_text(cursor2, l2_cy, text=summary, anchor="w", fill=sum_col,
                                 font=self.font_summary, tags=tag)

        if counter_txt:
            self.canvas.create_text(g["view_x1"], l2_cy, text=counter_txt, anchor="e",
                                     fill=dim_col, font=self.font_mono, tags=tag)

    # -- anel de metricas (camada 2) ----------------------------------------------
    def _draw_ring(self, ctx_pct, h5_pct, g):
        self.canvas.delete("ring")
        cx, cy = g["ring_cx"], g["cy"]
        r_out, r_in = g["r_out"], g["r_in"]

        self.canvas.create_oval(cx - r_out, cy - r_out, cx + r_out, cy + r_out,
                                 outline=TRACK, width=3, tags="ring")
        self.canvas.create_oval(cx - r_in, cy - r_in, cx + r_in, cy + r_in,
                                 outline=TRACK, width=3, tags="ring")
        if h5_pct is not None:
            self.canvas.create_arc(cx - r_out, cy - r_out, cx + r_out, cy + r_out,
                                    start=90, extent=-3.6 * min(100, h5_pct), style="arc",
                                    width=3, outline=pct_color(h5_pct), tags="ring")
        if ctx_pct is not None:
            self.canvas.create_arc(cx - r_in, cy - r_in, cx + r_in, cy + r_in,
                                    start=90, extent=-3.6 * min(100, ctx_pct), style="arc",
                                    width=3, outline=pct_color(ctx_pct), tags="ring")
        if ctx_pct is None:
            label, label_color = "·", TXT_3
        elif ctx_pct >= 100:
            label, label_color = "!", pct_color(ctx_pct)
        else:
            label, label_color = str(ctx_pct), (TXT_2 if ctx_pct < 70 else pct_color(ctx_pct))
        self.canvas.create_text(cx, cy, text=label, anchor="center", font=self.font_ring,
                                 fill=label_color, tags="ring")

    # -- barra de carrossel (camada 3) ---------------------------------------------
    def _draw_carousel(self, g):
        self.canvas.delete("carousel")
        total = len(self.blocks)
        if total <= 1:
            return
        idx = self._index_of_sid(self.current_sid)
        x0, x1 = g["view_x0"], g["view_x1"]
        bar_y = g["bar_y"]
        hold_progress = 0.0 if self.paused else min(1.0, (time.time() - self.hold_started) * 1000 / self.HOLD_MS)

        if total <= 5:
            gap = 3
            seg_w = (x1 - x0 - gap * (total - 1)) / total
            for k in range(total):
                sx = x0 + k * (seg_w + gap)
                self.canvas.create_rectangle(sx, bar_y, sx + seg_w, bar_y + 2, fill=TRACK,
                                              outline="", tags="carousel")
                if k < idx or self.paused and k == idx:
                    self.canvas.create_rectangle(sx, bar_y, sx + seg_w, bar_y + 2,
                                                  fill=TRACK_DONE, outline="", tags="carousel")
                elif k == idx:
                    self.canvas.create_rectangle(sx, bar_y, sx + seg_w * hold_progress, bar_y + 2,
                                                  fill=TRACK_ACTIVE, outline="", tags="carousel")
        else:
            self.canvas.create_rectangle(x0, bar_y, x1, bar_y + 2, fill=TRACK, outline="", tags="carousel")
            fill_w = (x1 - x0) * (1.0 if self.paused else hold_progress)
            self.canvas.create_rectangle(x0, bar_y, x0 + fill_w, bar_y + 2, fill=TRACK_ACTIVE,
                                          outline="", tags="carousel")

        if self.paused:
            px = x1 - 8
            self.canvas.create_rectangle(px, g["cy"] - 4, px + 2, g["cy"] + 4, fill=TXT_3, outline="", tags="carousel")
            self.canvas.create_rectangle(px + 5, g["cy"] - 4, px + 7, g["cy"] + 4, fill=TXT_3, outline="", tags="carousel")

    # -- indicador de pulso (camada 4) -----------------------------------------------
    def _draw_organ(self, state, g):
        self.canvas.delete("organ")
        cx, cy = g["organ_cx"], g["cy"]
        now = time.time()

        if state == STATE_IDLE:
            self.canvas.create_oval(cx - 3.5, cy - 3.5, cx + 3.5, cy + 3.5, outline=MUTE,
                                     width=1, tags="organ")
            return

        color = STATE_COLOR[state]
        period = 0.9 if state == STATE_WORKING else 1.6
        halo_count = 2 if state == STATE_WORKING else 1
        core_r = 3.0 + 0.4 * math.sin(now * 2 * math.pi / 1.4)
        self.canvas.create_oval(cx - core_r, cy - core_r, cx + core_r, cy + core_r,
                                 fill=color, outline="", tags="organ")
        for k in range(halo_count):
            phase = ((now / period) + k * 0.5) % 1.0
            r = 4.5 + phase * 5.5
            col = lerp_color(color, CARD, phase)
            self.canvas.create_oval(cx - r, cy - r, cx + r, cy + r, outline=col, width=1, tags="organ")

        blk = self._current_block_by_sid(self.current_sid)
        if state == STATE_WORKING and blk and blk.get("tool"):
            ang = -(now * 360 * 1.4) % 360
            self.canvas.create_arc(cx - 10, cy - 10, cx + 10, cy + 10, start=ang, extent=95,
                                    style="arc", outline=lerp_color(color, CARD, 0.45), width=2, tags="organ")

    # -- laço de animação ------------------------------------------------------------
    def _tick(self):
        try:
            g = self._geom()
            state = self.last_frame_state or STATE_IDLE

            if self.sliding:
                self._slide_frame(g)
            self._draw_organ(state, g)
            self._draw_carousel(g)

            self.canvas.tag_raise("carousel")
        except Exception:
            log_exception("_tick")
        finally:
            interval = self.FRAME_MS if (self.last_frame_state != STATE_IDLE or self.sliding) else 500
            self.root.after(interval, self._tick)

    def run(self):
        self.root.mainloop()

    # -- rotação em blocos (carrossel) ---------------------------------------------------
    def _schedule_hold(self):
        self.hold_started = time.time()
        self.root.after(self.HOLD_MS, self._start_slide)

    def _start_slide(self):
        try:
            if self.paused or len(self.blocks) <= 1:
                self._schedule_hold()
                return
            idx = self._index_of_sid(self.current_sid, default=-1)
            next_block = self.blocks[(idx + 1) % len(self.blocks)]
            self._next_idx = (idx + 1) % len(self.blocks)
            self._next_sid = next_block["sid"]
            self._next_session = next_block
            self._cur_session = self._current_block_by_sid(self.current_sid) or next_block
            self._cur_idx = idx if idx >= 0 else 0
            self.slide_from_state = derive_state(self._cur_session)
            self.slide_to_state = derive_state(next_block)
            self.slide_t0 = time.time()
            self.sliding = True
        except Exception:
            log_exception("_start_slide")
            self.canvas.delete("blk_cur", "blk_next", "mask")
            self.sliding = False
            if self.blocks:
                self.current_sid = self.blocks[0]["sid"]
                self._redraw_static(self.blocks[0])
            self._schedule_hold()

    def _slide_frame(self, g):
        try:
            t_raw = (time.time() - self.slide_t0) / (self.SLIDE_MS / 1000)
            if t_raw >= 1.0:
                self.current_sid = self._next_sid
                self.sliding = False
                self._draw_frame(self.slide_to_state, force=True)
                self.canvas.delete("blk_cur", "blk_next")
                self._draw_block(self._next_session, g["view_x0"], "blk_cur", g,
                                  self._next_idx, len(self.blocks), 1.0)
                self._draw_ring(self._ctx_pct_for(self.current_sid), self._session_pct_cached, g)
                self._schedule_hold()
                return

            ease = smoothstep(t_raw)
            viewport = g["view_x1"] - g["view_x0"]
            out_x = g["view_x0"] - ease * viewport
            in_x = g["view_x0"] + viewport - ease * viewport

            self.canvas.delete("blk_cur", "blk_next")
            self._draw_block(self._cur_session, out_x, "blk_cur", g, self._cur_idx,
                              len(self.blocks), 1.0 - ease)
            self._draw_block(self._next_session, in_x, "blk_next", g, self._next_idx,
                              len(self.blocks), ease)

            mix_state = self.slide_to_state if ease > 0.5 else self.slide_from_state
            self._draw_frame(mix_state, force=(mix_state != self.last_frame_state))
            ctx = self._ctx_pct_for(self._next_sid if ease > 0.5 else self.current_sid)
            self._draw_ring(ctx, self._session_pct_cached, g)

            self._mask(g)
        except Exception:
            log_exception("_slide_frame")
            self.canvas.delete("blk_cur", "blk_next", "mask")
            self.sliding = False
            if self.blocks:
                self.current_sid = self.blocks[0]["sid"]
                self._redraw_static(self.blocks[0])
            self._schedule_hold()

    def _mask(self, g):
        self.canvas.delete("mask")
        self.canvas.create_rectangle(0, 0, g["view_x0"], g["h"], fill=CARD, outline="", tags="mask")
        self.canvas.create_rectangle(g["view_x1"], 0, g["w"], g["h"], fill=CARD, outline="", tags="mask")
        self.canvas.tag_raise("ring")


if __name__ == "__main__":
    Ticker().run()
