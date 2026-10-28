import json, os, subprocess, re, shutil
from pathlib import Path
source=Path(__file__).resolve().parents[2]
binary=shutil.which('chezmoi')
if not binary: raise RuntimeError('chezmoi is required')
template=source/'.chezmoiignore.tmpl'
checks=[]
for system in ['linux','darwin','windows']:
    for profile in ['lite','full','full,desktop']:
        env=dict(os.environ,CHEZMOI_PROFILES=profile,CI='true',WINDOWS_DESKTOP_BAR='none')
        result=subprocess.run([binary,'--source',str(source),'--override-data',json.dumps({'chezmoi':{'os':system}}),'execute-template'],input=template.read_text(),text=True,capture_output=True,env=env)
        if result.returncode: raise RuntimeError(result.stderr)
        lines=result.stdout.splitlines()
        excluded='.config/desktop-customization/**' in lines
        assert excluded == (system!='windows' or profile!='full,desktop'),(system,profile,lines)
        assert 'provision/**' in lines and 'WORKFLOW.md' in lines
        assert '.config/desktop-customization/finder-widgets/**' in lines
        if system=='windows' and profile!='full,desktop': assert 'AppData/Roaming/Microsoft/Start Menu/Programs/Startup/**' in lines
        checks.append(system+'/'+profile)
for bar in ['none','yasb']:
    env=dict(os.environ,CHEZMOI_PROFILES='full,desktop',WINDOWS_DESKTOP_BAR=bar)
    for name in ['dot_config/desktop-customization/desktop.json.tmpl','dot_config/yasb/config.yaml.tmpl']:
        result=subprocess.run([binary,'--source',str(source),'execute-template'],input=(source/name).read_text(),text=True,capture_output=True,env=env)
        if result.returncode: raise RuntimeError(result.stderr)
        if name.endswith('.json.tmpl'): assert json.loads(result.stdout)['bar']==bar
        else: assert bool(re.search(r'^    enabled: true\s*$',result.stdout,re.M))==(bar=='yasb')
print(json.dumps({'profile_render_checks':checks,'bar_templates':['none','yasb'],'ok':True},indent=2))
