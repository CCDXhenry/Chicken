import subprocess, pathlib, json, concurrent.futures, datetime
ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = pathlib.Path(__file__).resolve().parent
def run(name, args, timeout=45):
    try:
        p = subprocess.run(args, cwd=ROOT, capture_output=True, timeout=timeout)
        log = p.stdout.decode('utf-8', 'replace') + p.stderr.decode('utf-8', 'replace')
        code = p.returncode
    except subprocess.TimeoutExpired as e:
        log = (e.stdout or b'').decode('utf-8', 'replace') + '\nTIMEOUT'
        code = 'timeout'
    (OUT / (name + '.log')).write_text(log, encoding='utf-8')
    return dict(name=name, command=args, exit_code=code, log=name+'.log')
if __name__ == '__main__':
    tests = sorted((ROOT/'Tools/Tests').glob('*.luau'))
    jobs = [(p.stem, ['lune','run',str(p)]) for p in tests]
    jobs += [('audio-python',['python','-m','unittest','discover','-s','Tools/Tests','-p','test_*.py']), ('obs-python',['python','-m','unittest','discover','-s','Tools/Studio','-p','test_*.py']), ('layout-python',['python','-m','unittest','discover','-s','Tools/UI','-p','test_*.py']), ('diff-check',['git','diff','--check','a26e482','7238c748'])]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda j: run(*j), jobs))
    (OUT/'test-results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps([{k:v for k,v in r.items() if k!='command'} for r in results],ensure_ascii=False))
