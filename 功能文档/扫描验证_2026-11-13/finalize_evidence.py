import pathlib, subprocess, json, re, hashlib, shutil, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]
OUT=pathlib.Path(__file__).resolve().parent
def git(*args): return subprocess.check_output(['git',*args],cwd=ROOT).decode('utf-8')
head=git('rev-parse','HEAD').strip()
commits=git('log','--reverse','--since-as-filter=2026-11-11T21:49:35Z','--until=2026-11-12T21:49:35Z','--format=%H %cI %s')
(OUT/'commits.txt').write_text(commits,encoding='utf-8')
(OUT/'business-changes.patch').write_text(git('diff','a26e482',head,'--','Scripts','Tools'),encoding='utf-8')
unique={}
for side in ['head','baseline']:
    log=(OUT/f'strict-{side}.log').read_text(encoding='utf-8-sig')
    errors=sorted(set(re.findall(r'\[game/([^\r\n]+(?:TypeError|SyntaxError|LocalShadow):[^\r\n]*)',log)))
    unique[side]=errors
    (OUT/f'strict-{side}-unique.txt').write_text('\n'.join(errors)+'\n',encoding='utf-8')
(OUT/'strict-new-unique.txt').write_text('\n'.join(sorted(set(unique['head'])-set(unique['baseline'])))+'\n',encoding='utf-8')
paths=['Scripts/ServerStorage/Scripts/ServerPersonalFarmManager.luau','Scripts/ReplicatedStorage/Scripts/Client/UIManager/TextFitting.luau','Scripts/ReplicatedStorage/Scripts/Shared/FarmCombatRules.luau','Scripts/ReplicatedStorage/Scripts/Shared/FarmEconomyConfig.luau','Tools/Tests/SpeciesSwitchRegression.luau']
hashes={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}
(OUT/'source-sha256.json').write_text(json.dumps(hashes,indent=2),encoding='utf-8')
metadata=dict(window_start_utc='2026-11-11T21:49:35Z',window_end_utc='2026-11-12T21:49:35Z',timezone='Asia/Shanghai',head=head,baseline=git('rev-parse','a26e482').strip(),branch=git('branch','--show-current').strip(),commit_count=len(commits.splitlines()),all_refs_count=len(git('log','--all','--since-as-filter=2026-11-11T21:49:35Z','--until=2026-11-12T21:49:35Z','--format=%H').splitlines()),strict_unique_counts={k:len(v) for k,v in unique.items()},diff_stat=git('diff','--shortstat','a26e482',head).strip(),initial_status='clean',fetch_performed=False)
(OUT/'metadata.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
# Only remove the temporary baseline created by this scan, after containment checks.
baseline=json.loads((OUT/'baseline-metadata.json').read_text())
target=pathlib.Path(baseline['snapshot']).resolve()
assert target.parent == pathlib.Path(tempfile.gettempdir()).resolve() and target.name.startswith('chicken-scan-baseline-')
assert not any(p.is_symlink() or p.is_junction() for p in [target,*target.rglob('*')])
shutil.rmtree(target)
print(json.dumps(metadata,ensure_ascii=False,indent=2))
