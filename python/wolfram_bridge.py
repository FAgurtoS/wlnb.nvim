#!/usr/bin/env python3
"""
Wolfram kernel bridge for ipynb.nvim (wln fork)

Speaks the same JSON-over-stdin/stdout protocol as kernel_bridge.py, but drives a
persistent WolframKernel process directly (standard library only, no jupyter_client).

Each cell is sent as one line: $WLNBRun["<base64 code>", "<tag>"]. The kernel answers
with marker lines (@@WLNB@@START/RES/DONE@@tag) mixed with ordinary stdout (Print etc).
"""

import base64
import json
import os
import shutil
import signal
import subprocess
import sys
import threading
import uuid
from typing import Any, Dict, Optional

MARK = "@@WLNB@@"

# Defined once per kernel. Single line: the kernel reads stdin as a terminal would.
# One-dimensional, copyable text for Print output and messages (default is 2D OutputForm).
FORMAT_CODE = (
    'SetOptions[$Output, FormatType -> OutputForm, PageWidth -> Infinity]; '
    'SetOptions[$Messages, FormatType -> OutputForm, PageWidth -> Infinity]; '
    '$MessagePrePrint = (StringReplace[ToString[#, InputForm], '
    'StartOfString ~~ "HoldCompleteForm[" ~~ s__ ~~ "]" ~~ EndOfString :> s] &);'
)

RENDER_MATH = os.environ.get("WLN_RENDER_MATH", "1") != "0"

INIT_CODE = (
    '$WLNBRenderMath = ' + ('True' if RENDER_MATH else 'False') + '; '
    '$WLNBRun[b64_String, tag_String] := Module[{code, res, text, png = ""}, '
    'WriteString["stdout", "' + MARK + 'START@@" <> tag <> "\\n"]; '
    'code = ByteArrayToString[BaseDecode[b64]]; '
    'res = CheckAbort[ToExpression[code], $Aborted]; '
    'If[res =!= Null, '
    'If[MatchQ[res, _Graphics | _Graphics3D | _Image | _Legended], '
    'text = If[ImageQ[res], "-Image-", "-Graphics-"]; '
    'png = Quiet[Check[BaseEncode[ExportByteArray[res, "PNG"]], ""]], '
    'text = ToString[res, InputForm, PageWidth -> Infinity]; '
    'If[$WLNBRenderMath && LeafCount[res] < 3000, '
    'png = Quiet[Check[TimeConstrained[BaseEncode[ExportByteArray[Rasterize[res, ImageResolution -> 144], "PNG"]], 10, ""], ""]]]]; '
    'WriteString["stdout", "' + MARK + 'RES@@" <> tag <> "@@" <> '
    'ExportString[<|"text" -> text, "png" -> png|>, "RawJSON", "Compact" -> True] <> "\\n"]]; '
    'WriteString["stdout", "' + MARK + 'DONE@@" <> tag <> "\\n"]; Null];'
)


COMMON_KERNEL_PATHS = [
    "/Applications/Wolfram Engine.app/Contents/Resources/Wolfram Player.app/Contents/MacOS/WolframKernel",
    "/Applications/Wolfram.app/Contents/MacOS/WolframKernel",
    "/Applications/Mathematica.app/Contents/MacOS/WolframKernel",
    "/usr/local/bin/WolframKernel",
]
COMMON_SCRIPT_PATHS = ["/usr/local/bin/wolframscript", "/opt/homebrew/bin/wolframscript"]


def find_kernel() -> Optional[str]:
    env = os.environ.get("WLN_KERNEL")
    if env and os.path.exists(env):
        return env
    found = shutil.which("WolframKernel")
    if found:
        return found
    for path in COMMON_KERNEL_PATHS:
        if os.path.exists(path):
            return path
    script = shutil.which("wolframscript") or next((p for p in COMMON_SCRIPT_PATHS if os.path.exists(p)), None)
    if script:
        try:
            out = subprocess.run(
                [script, "-code", "$InstallationDirectory"],
                capture_output=True, text=True, timeout=60,
            ).stdout.strip()
            for rel in ("MacOS/WolframKernel", "Executables/WolframKernel"):
                path = os.path.join(out, rel)
                if os.path.exists(path):
                    return path
        except Exception:
            pass
    return None


class WolframBridge:
    def __init__(self):
        self.proc: Optional[subprocess.Popen] = None
        self.kernel_path: Optional[str] = None
        self.execution_count = 0
        self.pending: Dict[str, Dict[str, Any]] = {}  # tag -> {cell_id}
        self.lock = threading.Lock()
        self.generation = 0  # bumped on restart so old reader threads go quiet

    def send_message(self, msg: Dict[str, Any]):
        with self.lock:
            print(json.dumps(msg), flush=True)

    def _spawn(self) -> bool:
        self.kernel_path = self.kernel_path or find_kernel()
        if not self.kernel_path:
            self.send_message({"type": "error", "error": "WolframKernel not found. Set WLN_KERNEL or install wolframscript."})
            return False
        self.generation += 1
        self.proc = subprocess.Popen(
            [self.kernel_path, "-noprompt"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        threading.Thread(target=self._reader, args=(self.proc, self.generation), daemon=True).start()
        self._write(FORMAT_CODE)
        self._write(INIT_CODE)
        self._write('WriteString["stdout", "' + MARK + 'LICENSE@@" <> ToString[$MaxLicenseProcesses] <> "\\n"];')
        self._write('WriteString["stdout", "' + MARK + 'READY\\n"];')
        return True

    def _write(self, text: str):
        if self.proc and self.proc.stdin:
            self.proc.stdin.write((text + "\n").encode("utf-8"))
            self.proc.stdin.flush()

    def start_kernel(self, kernel_name: str = "wolframscript"):
        self.kernel_name = kernel_name
        self._spawn()

    def _stream(self, tag: Optional[str], text: str):
        if not text:
            return
        cell_id = self.pending.get(tag or "", {}).get("cell_id") if tag else self._current_cell()
        self.send_message({
            "type": "output", "cell_id": cell_id,
            "output": {"output_type": "stream", "name": "stdout", "text": text},
        })

    def _current_cell(self) -> Optional[str]:
        for info in self.pending.values():
            if info.get("started") and not info.get("done"):
                return info["cell_id"]
        return None

    def _reader(self, proc: subprocess.Popen, generation: int):
        assert proc.stdout is not None
        for raw in iter(proc.stdout.readline, b""):
            if generation != self.generation:
                return
            line = raw.decode("utf-8", errors="replace")
            idx = line.find(MARK)
            if idx < 0:
                self._stream(None, line)
                continue
            self._stream(None, line[:idx])
            self._marker(line[idx + len(MARK):].rstrip("\n"))
        if generation == self.generation:
            self.send_message({"type": "shutdown"})

    def _marker(self, body: str):
        parts = body.split("@@", 2)
        kind = parts[0]
        if kind == "READY":
            self.send_message({
                "type": "kernel_started", "kernel_name": getattr(self, "kernel_name", "wolframscript"),
                "kernel_id": str(self.proc.pid) if self.proc else "unknown", "language": "wolfram",
            })
            return
        if kind == "LICENSE":
            try:
                self.send_message({"type": "license", "max": int(parts[1])})
            except (IndexError, ValueError):
                pass
            return
        tag = parts[1] if len(parts) > 1 else ""
        info = self.pending.get(tag)
        if info is None:
            return
        cell_id = info["cell_id"]
        if kind == "START":
            info["started"] = True
            self.execution_count += 1
            info["count"] = self.execution_count
            self.send_message({"type": "status", "state": "busy", "cell_id": cell_id})
            self.send_message({"type": "execute_input", "cell_id": cell_id, "execution_count": info["count"]})
        elif kind == "RES":
            data = json.loads(parts[2])
            mime = {"text/plain": data.get("text", "")}
            if data.get("png"):
                mime["image/png"] = data["png"]
            self.send_message({
                "type": "output", "cell_id": cell_id,
                "output": {"output_type": "execute_result", "execution_count": info.get("count"),
                           "data": mime, "metadata": {}},
            })
        elif kind == "DONE":
            info["done"] = True
            self.pending.pop(tag, None)
            self.send_message({"type": "status", "state": "idle", "cell_id": cell_id})

    def execute(self, code: str, cell_id: str):
        if not self.proc or self.proc.poll() is not None:
            self.send_message({"type": "error", "error": "No kernel connected", "cell_id": cell_id})
            return
        tag = uuid.uuid4().hex
        self.pending[tag] = {"cell_id": cell_id}
        self.send_message({"type": "execute_request", "cell_id": cell_id, "msg_id": tag})
        b64 = base64.b64encode(code.encode("utf-8")).decode("ascii")
        self._write(f'$WLNBRun["{b64}", "{tag}"];')

    def interrupt(self):
        # A piped WolframKernel dies on SIGINT (no interrupt menu without a tty), so
        # interrupting means killing it and starting a fresh one: kernel state is lost.
        busy = [i for i in self.pending.values() if i.get("started") and not i.get("done")]
        if not busy or not self.proc or self.proc.poll() is not None:
            return
        self._kill()
        for info in list(self.pending.values()):
            self.send_message({
                "type": "output", "cell_id": info["cell_id"],
                "output": {"output_type": "error", "ename": "Interrupted",
                           "evalue": "Evaluation interrupted; kernel restarted (state lost)", "traceback": []},
            })
            self.send_message({"type": "status", "state": "idle", "cell_id": info["cell_id"]})
        self.pending.clear()
        self._spawn()
        self.send_message({"type": "interrupted"})

    def restart(self):
        self._kill()
        self.pending.clear()
        self.execution_count = 0
        self._spawn()
        self.send_message({"type": "restarted"})

    def _kill(self):
        self.generation += 1
        if self.proc and self.proc.poll() is None:
            try:
                os.killpg(self.proc.pid, signal.SIGKILL)
            except Exception:
                self.proc.kill()
            self.proc.wait()

    def shutdown(self):
        self._kill()
        self.send_message({"type": "shutdown"})

    def is_alive(self) -> bool:
        return bool(self.proc and self.proc.poll() is None)


def main():
    bridge = WolframBridge()

    def stop(_signum, _frame):
        # Neovim ends the bridge with SIGTERM/SIGHUP: take the kernel down too, otherwise it
        # lingers (it runs in its own session) and holds a Wolfram license slot.
        bridge._kill()
        sys.exit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGHUP, stop)
    bridge.send_message({"type": "ready"})
    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                cmd = json.loads(line)
            except json.JSONDecodeError as e:
                bridge.send_message({"type": "error", "error": f"Invalid JSON: {e}"})
                continue
            action = cmd.get("action", "")
            if action == "start":
                bridge.start_kernel(cmd.get("kernel_name", "wolframscript"))
            elif action == "execute":
                cell_id = cmd.get("cell_id")
                if not isinstance(cell_id, str) or not cell_id:
                    bridge.send_message({"type": "error", "error": "Missing required cell_id for execute action"})
                    continue
                bridge.execute(cmd.get("code", ""), cell_id)
            elif action == "interrupt":
                bridge.interrupt()
            elif action == "restart":
                bridge.restart()
            elif action == "shutdown":
                bridge.shutdown()
                break
            elif action == "is_alive":
                bridge.send_message({"type": "is_alive", "alive": bridge.is_alive()})
            elif action == "ping":
                bridge.send_message({"type": "pong"})
            elif action in ("complete", "inspect", "info", "connect", "input_reply"):
                bridge.send_message({"type": "error", "error": f"Not supported by the Wolfram bridge: {action}"})
            else:
                bridge.send_message({"type": "error", "error": f"Unknown action: {action}"})
    except KeyboardInterrupt:
        pass
    finally:
        bridge._kill()


if __name__ == "__main__":
    main()
