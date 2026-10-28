"""Branch defaults, admission rules and shared switch contract; no WM is started."""
import json,os,subprocess,tomllib
from pathlib import Path
r=Path(__file__).resolve().parents[2]
defaults=json.loads((r/'.chezmoidata/windows-desktop.json').read_text())['windowsDesktop']
assert defaults['windowManager'] in {'Leopard','Komorebi'}
assert (defaults['bar'],defaults['theme'])==('yasb','catppuccin')
config=tomllib.loads((r/'dot_config/desktop-customization/leopardwm-test/config.toml').read_text())
layout=config['layout']
assert layout['width_presets'][layout['default_width_preset']-1]==0.618
rules=config['window_rules']
def rule(exe):
    matches=[x for x in rules if x.get('match_executable')==exe and not x.get('match_title') and not x.get('match_class')]
    assert len(matches)==1,(exe,matches)
    return matches[0]
assert rule('Telegram.exe')['column_width']==0.5
for exe in ['Unity.exe','Unity Hub.exe']: assert rule(exe)['open_on_workspace']==8
for exe in ['Fusion360.exe','orca-slicer.exe','prusa-slicer.exe']: assert rule(exe)['open_on_workspace']==9
for exe in ['Unity.exe','Fusion360.exe','blender.exe','ZBrush.exe','CLIPStudioPaint.exe']: assert rule(exe)['column_width']==1.0
template=(r/'dot_config/desktop-customization/desktop.json.tmpl').read_text()
for wm in ['Leopard','Komorebi']:
    result=subprocess.run(['chezmoi','--source',str(r),'execute-template'],input=template,text=True,capture_output=True,check=True,
        env=dict(os.environ,CHEZMOI_PROFILES='full,desktop',WINDOWS_DESKTOP_WM=wm))
    assert json.loads(result.stdout)['windowManager']==wm
assert '--toggle-global' in (r/'dot_config/desktop-customization/yasb-catppuccin/config.yaml').read_text()
print(json.dumps({'ok':True,'default':defaults['windowManager'],'width_rules':True,'workspace_admission':True,'wm_template_variants':2}))
