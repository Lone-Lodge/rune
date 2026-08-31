#!/usr/bin/env python3
# Runes radvisa sammanslagning mot git merge-file, pa slumpade fall.
#
# Fem handskrivna fall visar att koden gor nagot rimligt. Det har visar att
# den gor SAMMA sak som en implementation som funnits i tjugo ar - bade i
# verdiktet (krock eller inte) och byte for byte i det som kommer ut.
#
# Ligger utanfor gaten med flit: den behover git, och en korning ar hundratals
# processer. Kor den nar sammanslagningen andras.
#
#     python tools/merge_vs_git.py [antal] [fro]
import random, subprocess, os, shutil, sys

ROT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
R = os.path.join(ROT, "build", "rune_cli.exe")
if not os.path.exists(R):
    R = os.path.join(ROT, "build", "rune_cli")
T = os.path.join(ROT, "build", "mvg")
ANTAL = int(sys.argv[1]) if len(sys.argv) > 1 else 250
FRO = int(sys.argv[2]) if len(sys.argv) > 2 else 0

def andra(rader, fro):
    r = random.Random(fro)
    ut = list(rader)
    for _ in range(r.randint(1, 3)):
        if not ut:
            break
        k = r.random()
        i = r.randrange(len(ut))
        if k < 0.4:
            ut[i] = "andrad-%d-%d" % (fro, i)
        elif k < 0.7:
            ut.insert(i, "ny-%d-%d" % (fro, i))
        else:
            del ut[i]
    return ut

lika = bada_krock = fel = 0
for n in range(FRO, FRO + ANTAL):
    r = random.Random(n)
    bas = ["rad-%d" % i for i in range(r.randint(40, 200))]
    var, deras = andra(bas, n * 2 + 1), andra(bas, n * 2 + 2)
    shutil.rmtree(T, ignore_errors=True)
    os.makedirs(T)
    skriv = lambda p, ls: open(os.path.join(T, p), "w", newline="\n").write("\n".join(ls) + "\n")
    kor = lambda *a: subprocess.run([R] + list(a), cwd=T, capture_output=True, text=True)
    kor("init")
    skriv("a.txt", bas); kor("add", "."); kor("commit", "bas")
    kor("branch", "sido"); kor("switch", "sido")
    skriv("a.txt", deras); kor("add", "."); kor("commit", "s")
    kor("switch", "main")
    skriv("a.txt", var); kor("add", "."); kor("commit", "m")
    rune_krock = "krockar" in kor("merge", "sido").stdout
    rune_ut = None if rune_krock else open(os.path.join(T, "a.txt"), newline="\n").read()

    for namn, rader in (("b", bas), ("o", var), ("t", deras)):
        skriv(namn, rader)
    g = subprocess.run(["git", "merge-file", "-p", "o", "b", "t"], cwd=T, capture_output=True, text=True)
    git_krock = g.returncode != 0

    if rune_krock != git_krock:
        fel += 1
        print("OLIKA VERDIKT #%d: rune krock=%s, git krock=%s" % (n, rune_krock, git_krock))
    elif rune_krock:
        bada_krock += 1
    elif rune_ut == g.stdout:
        lika += 1
    else:
        fel += 1
        print("OLIKT RESULTAT #%d" % n)
        print("  rune %r" % rune_ut)
        print("  git  %r" % g.stdout)

shutil.rmtree(T, ignore_errors=True)
print("lika resultat: %d, bada krockade: %d, avvikelser: %d" % (lika, bada_krock, fel))
sys.exit(1 if fel else 0)
