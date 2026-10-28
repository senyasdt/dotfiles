"""Generate the desktop's colour adapters from one palette; no live deployment."""
from pathlib import Path
import argparse
import json

ROOT = Path(__file__).resolve().parents[2]
APPEARANCE = ROOT / 'dot_config/desktop-customization/appearance'

def generate():
    palette = json.loads((APPEARANCE / 'palette.json').read_text(encoding='utf-8'))
    c = palette['colors']
    name = palette['name']
    outputs = {}
    def put(relative, text):
        outputs[ROOT / relative] = text
    def json_text(value):
        return json.dumps(value, ensure_ascii=False, indent=4) + '\n'

    # Merge appearance only; existing editor/security settings remain source-owned.
    path = ROOT / 'AppData/Roaming/Code/User/settings.json'
    settings = json.loads(path.read_text(encoding='utf-8-sig'))
    settings['workbench.colorTheme'] = 'Default Dark Modern'
    settings['editor.fontFamily'] = "'JetBrainsMono Nerd Font Mono', Consolas, monospace"
    ui = {
        'foreground': c['text'], 'descriptionForeground': c['muted'],
        'focusBorder': c['accent'], 'selection.background': c['selection'],
        'editor.background': c['background'], 'editor.foreground': c['text'],
        'editor.selectionBackground': c['selection'], 'editor.lineHighlightBackground': c['mantle'],
        'editorCursor.foreground': c['accentSoft'], 'editorLineNumber.foreground': c['muted'],
        'editorLineNumber.activeForeground': c['text'], 'editorGroup.border': c['border'],
        'editorGroupHeader.tabsBackground': c['mantle'],
        'tab.activeBackground': c['background'], 'tab.inactiveBackground': c['mantle'],
        'tab.activeForeground': c['text'], 'tab.inactiveForeground': c['muted'],
        'tab.activeBorderTop': c['accent'], 'tab.border': c['mantle'],
        'sideBar.background': c['mantle'], 'sideBar.foreground': c['subtext'],
        'sideBarTitle.foreground': c['text'], 'sideBarSectionHeader.background': c['surface'],
        'activityBar.background': c['crust'], 'activityBar.foreground': c['accentSoft'],
        'activityBar.inactiveForeground': c['muted'], 'activityBarBadge.background': c['accent'],
        'activityBarBadge.foreground': c['crust'], 'statusBar.background': c['mantle'],
        'statusBar.foreground': c['subtext'], 'statusBar.noFolderBackground': c['mantle'],
        'titleBar.activeBackground': c['mantle'], 'titleBar.activeForeground': c['text'],
        'titleBar.inactiveBackground': c['crust'], 'titleBar.inactiveForeground': c['muted'],
        'panel.background': c['mantle'], 'panel.border': c['border'],
        'dropdown.background': c['surface'], 'dropdown.foreground': c['text'],
        'dropdown.border': c['border'], 'input.background': c['surface'],
        'input.foreground': c['text'], 'input.border': c['border'],
        'input.placeholderForeground': c['muted'], 'button.background': c['accent'],
        'button.foreground': c['crust'], 'button.hoverBackground': c['accentSoft'],
        'button.secondaryBackground': c['surface'], 'button.secondaryForeground': c['text'],
        'list.activeSelectionBackground': c['selection'], 'list.activeSelectionForeground': c['text'],
        'list.inactiveSelectionBackground': c['surface'], 'list.hoverBackground': c['surface'],
        'notifications.background': c['background'], 'notifications.foreground': c['text'],
        'notificationCenterHeader.background': c['mantle'], 'badge.background': c['accent'],
        'badge.foreground': c['crust'], 'terminal.background': c['background'],
        'terminal.foreground': c['text'], 'terminalCursor.foreground': c['accentSoft'],
    }
    settings.setdefault('workbench.colorCustomizations', {})['[Default Dark Modern]'] = ui
    settings.setdefault('editor.tokenColorCustomizations', {})['[Default Dark Modern]'] = {
        'comments': c['muted'], 'strings': c['green'], 'keywords': c['accent'],
        'numbers': c['yellow'], 'types': c['accentSoft'], 'functions': c['purple'],
    }
    put('AppData/Roaming/Code/User/settings.json', json_text(settings))
    put('dot_config/desktop-customization/appearance/vscode.json', json_text({k: settings[k] for k in
        ['workbench.colorTheme', 'editor.fontFamily', 'workbench.colorCustomizations', 'editor.tokenColorCustomizations']}))

    ansi = [c[k] for k in ['surface', 'red', 'green', 'yellow', 'accent', 'purple', 'cyan', 'subtext']]
    bright = ['#626b79'] + ansi[1:7] + [c['text']]
    wt = {
        'name': name, 'background': c['background'], 'foreground': c['text'],
        'cursorColor': c['accentSoft'], 'selectionBackground': c['selection'],
    }
    for key, value in zip(['black','red','green','yellow','blue','purple','cyan','white'], ansi):
        wt[key] = value
    for key, value in zip(['brightBlack','brightRed','brightGreen','brightYellow','brightBlue','brightPurple','brightCyan','brightWhite'], bright):
        wt[key] = value
    put('dot_config/desktop-customization/appearance/windows-terminal.json', json_text(wt))
    path = ROOT / 'AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'
    terminal = json.loads(path.read_text(encoding='utf-8-sig'))
    terminal['theme'] = 'dark'
    defaults = terminal.setdefault('profiles', {}).setdefault('defaults', {})
    defaults.update(colorScheme=name, opacity=88, useAcrylic=True)
    defaults.setdefault('font', {}).update(face=palette['fonts']['code'], size=10)
    for profile in terminal['profiles']['list']:
        if profile.get('colorScheme') == 'Catppuccin Macchiato':
            profile['colorScheme'] = name
    terminal['schemes'] = [s for s in terminal.get('schemes', []) if s.get('name') != name] + [wt]
    put(path.relative_to(ROOT), json_text(terminal))

    toml = '[metadata]\nname = '+json.dumps(name)+'\n\n[colors]\n'
    for key, value in {'foreground':c['text'],'background':c['background'],'cursor_bg':c['accentSoft'],
                       'cursor_fg':c['crust'],'cursor_border':c['accentSoft'],
                       'selection_fg':c['text'],'selection_bg':c['selection']}.items():
        toml += f'{key} = "{value}"\n'
    toml += 'ansi = '+json.dumps(ansi)+'\nbrights = '+json.dumps(bright)+'\n'
    put('dot_config/wezterm/themes/cold-grey.toml',toml)
    put('dot_config/desktop-customization/appearance/wezterm.toml',toml)
    put('dot_config/wezterm/theme',name+'\n')
    cp = {'rosewater':c['text'],'flamingo':c['subtext'],'pink':c['purple'],'mauve':c['purple'],
          'red':c['red'],'maroon':'#bb7f8b','peach':'#d3af91','yellow':c['yellow'],
          'green':c['green'],'teal':c['cyan'],'sky':'#a6bacb','sapphire':'#99b5cc',
          'blue':c['accent'],'lavender':c['accentSoft'],'text':c['text'],
          'subtext1':c['subtext'],'subtext0':c['muted'],'overlay2':'#858d99',
          'overlay1':'#707987','overlay0':'#626b79','surface2':c['border'],
          'surface1':c['surface1'],'surface0':c['surface'],'base':c['background'],
          'mantle':c['mantle'],'crust':c['crust'],'none':'NONE'}
    lua='-- Generated by provision/windows/generate_appearance.py from appearance/palette.json.\nreturn {\n'
    lua+=''.join(f'  {k} = "{v}",\n' for k,v in cp.items())+'}\n'
    put('nvim-full/lua/config/cold_grey_palette.lua',lua)
    css='/* Optional Obsidian snippet; only enabled after choosing a vault. */\n.theme-dark {\n'
    variables={'background-primary':c['background'],'background-primary-alt':c['mantle'],
               'background-secondary':c['mantle'],'background-secondary-alt':c['crust'],
               'background-modifier-border':c['border'],'text-normal':c['text'],
               'text-muted':c['muted'],'text-accent':c['accent'],'interactive-accent':c['accent'],
               'text-on-accent':c['crust'],'text-selection':c['selection'],
               'code-background':c['mantle'],'titlebar-background':c['mantle'],
               'titlebar-background-focused':c['mantle']}
    css+=''.join(f'  --{k}: {v};\n' for k,v in variables.items())+'}\n'
    put('dot_config/desktop-customization/appearance/obsidian/cold-grey.css',css)
    return outputs

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true',help='Check adapters without writing files')
    args=parser.parse_args()
    outputs=generate()
    different=[]
    for path,text in outputs.items():
        if not path.exists() or path.read_text(encoding='utf-8')!=text:
            different.append(str(path.relative_to(ROOT)))
            if not args.check:
                path.parent.mkdir(parents=True,exist_ok=True)
                path.write_text(text,encoding='utf-8')
    if args.check and different:
        raise SystemExit('Appearance adapters differ: '+', '.join(different))
    print(f'{len(outputs)} appearance adapters '+('verified.' if args.check else 'generated.'))

if __name__=='__main__':main()
