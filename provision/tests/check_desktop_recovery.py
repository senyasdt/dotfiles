"""Restore portable appearance to an empty destination, never the real profile."""
import argparse, hashlib, json, os, shutil, subprocess, tempfile
from pathlib import Path
import yaml

source=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--destination',type=Path)
args=parser.parse_args()
binary=shutil.which('chezmoi');assert binary,'chezmoi required'
temp=None
if args.destination:
    destination=args.destination.resolve();assert not destination.exists(),'Use a new empty destination';destination.mkdir(parents=True)
else:
    temp=tempfile.TemporaryDirectory(prefix='desktop-recovery-');destination=Path(temp.name)/'home';destination.mkdir()
config=destination.parent/(destination.name+'-chezmoi.toml');assert not config.exists();config.write_text('')
(destination/'.config/desktop-customization').mkdir(parents=True)
env={**os.environ,'CHEZMOI_PROFILES':'full,desktop','WINDOWS_DESKTOP_BAR':'yasb','WINDOWS_DESKTOP_THEME':'catppuccin'}
command=[binary,'--config',str(config),'--source',str(source),'--destination',str(destination),'--override-data',json.dumps({'chezmoi':{'os':'windows'}})]
targets=[destination/'.wezterm.lua',destination/'.config/wezterm',destination/'.config/desktop-customization/appearance',destination/'.config/desktop-customization/yasb-catppuccin']
def apply():
    r=subprocess.run(command+['apply','--include','files,dirs','--exclude','scripts,externals','--force','--',*map(str,targets)],env=env,capture_output=True,text=True)
    if r.returncode:raise RuntimeError(r.stderr)
try:
    apply()
    wez=destination/'.config/wezterm';profile=destination/'.config/desktop-customization/yasb-catppuccin'
    defaults=json.loads((destination/'.config/desktop-customization/appearance/wezterm-state.json').read_text())
    assert defaults=={'theme':'nord-cold-grey','opacity':0.6,'backgroundMode':'solid','fontSize':10}
    assert (wez/'themes/nord-cold-grey.toml').read_bytes()==(source/'dot_config/wezterm/themes/nord-cold-grey.toml').read_bytes()
    assert 'local default_color_scheme = "nord-cold-grey"' in (wez/'theme.lua').read_text()
    assert 'local default_window_background_opacity = 0.6' in (wez/'opacity.lua').read_text()
    main=(destination/'.wezterm.lua').read_text();assert 'config.font_size = 10' in main and 'return "solid"' in main and '{{' not in main
    entry=(wez/'wezterm.lua').read_text();assert 'return dofile(wezterm.home_dir .. "/.wezterm.lua")' in entry and 'config.' not in entry
    for state in ['theme','opacity','background_mode','active_scheme.toml']:assert not (wez/state).exists(),'Mutable state must be seeded/preserved by the appearance manager'
    config_data=yaml.safe_load((profile/'config.yaml').read_text())
    libraries=[w for w in config_data['widgets'].values() if w['type']=='yasb.launchpad.LaunchpadWidget'];assert len(libraries)==2 and all(w['options']['group_apps'] for w in libraries)
    assert (profile/'styles.css').read_bytes()==(source/'dot_config/desktop-customization/yasb-catppuccin/styles.css').read_bytes()
    assert (profile/'launchpad-layout.json').read_bytes()==(source/'dot_config/desktop-customization/yasb-catppuccin/launchpad-layout.json').read_bytes()
    layout=json.loads((profile/'launchpad-layout.json').read_text());assert layout['entries'] and all(set(row)=={'title','group','order'} for row in layout['entries'])
    assert not (destination/'archive').exists() and not (profile/'runtime').exists() and not (profile/'private').exists()
    # Routine apply must keep the user's later selection, opacity and background.
    state={'theme':'forest\n','active_scheme.toml':'theme = "forest"\n','opacity':'0.75\n','background_mode':'image\n'}
    for name,text in state.items():(wez/name).write_text(text)
    apply()
    assert all((wez/name).read_text()==text for name,text in state.items())
    (destination/'.desktop-recovery-fixture.json').write_text(json.dumps({'synthetic':True,'source':str(source)}))
    print(json.dumps({'ok':True,'destination':str(destination),'chezmoi_restore':True,'saved_wezterm':defaults,'yasb_config_styles_layout_restored':True,'existing_state_preserved':True,'no_hooks_or_live_processes':True}))
finally:
    if temp:temp.cleanup();config.unlink(missing_ok=True)
