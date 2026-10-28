"""Offline profile contracts. Optional --schema points at YASB v2.0.7 schema.json."""
import argparse,json,os,re,shutil,subprocess
from pathlib import Path
import yaml
parser=argparse.ArgumentParser()
parser.add_argument('--schema',type=Path)
args=parser.parse_args()
source=Path(__file__).resolve().parents[2]
profile=source/'dot_config/desktop-customization/yasb-catppuccin'
config=yaml.safe_load((profile/'config.yaml').read_text())
old=yaml.safe_load((profile/'config-predock.yaml').read_text())
for document in [config,old]:
    for bar in document['bars'].values():
        for group in bar['widgets'].values():
            assert all(name in document['widgets'] for name in group)
    assert not re.search(r'(?im)^\s*(api_key|token|password):\s*[^\s\n]+',yaml.safe_dump(document))
assert config['bars']['catppuccin-top']['window_flags']['windows_app_bar']
assert not config['bars']['catppuccin-dock']['window_flags']['windows_app_bar']
assert not config['bars']['catppuccin-dock']['window_flags']['auto_hide']
built_in_layouts={'bsp','columns','rows','grid','scrolling','vertical-stack','horizontal-stack','ultrawide-vertical-stack','right-main-vertical-stack'}
def assert_layout_contract(document):
    for widget in document['widgets'].values():
        if widget['type']=='komorebi.active_layout.ActiveLayoutWidget':
            assert built_in_layouts <= {x.replace('_','-') for x in widget['options']['layouts']}, 'ActiveLayout connect rotation can otherwise loop forever'
for document in [config,old]:assert_layout_contract(document)
assert config['widgets']['library']['options']['keybindings']==[{'keys':'alt+f12','action':'toggle_launchpad'}]
assert config['widgets']['ahk']['options']['exec_options']['run_interval']>=1000
if args.schema:
    import jsonschema
    schema=json.loads(args.schema.read_text())
    for document in [config,old]:jsonschema.Draft202012Validator(schema).validate(document)
binary=shutil.which('chezmoi')
assert binary,'chezmoi required'
for theme in ['classic','catppuccin']:
    env=dict(os.environ,CHEZMOI_PROFILES='full,desktop',WINDOWS_DESKTOP_THEME=theme,WINDOWS_DESKTOP_BAR='yasb')
    def render(name):
        result=subprocess.run([binary,'--source',str(source),'execute-template'],input=(source/name).read_text(),text=True,capture_output=True,env=env,check=True)
        return result.stdout
    assert json.loads(render('dot_config/desktop-customization/desktop.json.tmpl'))['theme']==theme
    if theme=='classic':
        classic=yaml.safe_load(render('dot_config/yasb/config.yaml.tmpl'))
        assert_layout_contract(classic)
        if args.schema:jsonschema.Draft202012Validator(schema).validate(classic)
    ignored=render('.chezmoiignore.tmpl').splitlines()
    for name in ['.config/yasb/config.yaml','.config/yasb/styles.css','.config/autohotkey/mydockfinder-hotkeys.ahk']:
        assert (name in ignored)==(theme=='catppuccin')
print(json.dumps({'ok':True,'profile_contracts':True,'theme_templates':['classic','catppuccin'],'yaml_schema_validated':bool(args.schema)}))
