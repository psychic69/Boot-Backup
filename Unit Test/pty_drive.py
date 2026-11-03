"""Run a command under a pseudo-terminal, answering prompts, and report its output and exit code.

Usage: pty_drive.py "answer1|answer2" command [args...]
Each answer is sent when the output ends with a prompt (": "). Prints the output, then "rc=N".
"""
import os, pty, select, sys, time

answers = sys.argv[1].split("|") if sys.argv[1] else []
cmd = sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)

out = b""
status = None
deadline = time.time() + 60
while time.time() < deadline:
    ready, _, _ = select.select([fd], [], [], 0.5)
    if ready:
        try:
            data = os.read(fd, 4096)
        except OSError:
            break
        if not data:
            break
        out += data
        if answers and out.endswith(b": "):
            os.write(fd, (answers.pop(0) + "\n").encode())
            out += b"\n"
    else:
        done, st = os.waitpid(pid, os.WNOHANG)
        if done:
            status = st
            break
if status is None:
    _, status = os.waitpid(pid, 0)
print(out.decode(errors="replace").replace("\r", ""), end="")
print("rc=%d" % os.waitstatus_to_exitcode(status))
