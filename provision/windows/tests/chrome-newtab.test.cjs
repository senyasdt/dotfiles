// UI integration tests in an isolated browser profile, never the owner's profile.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const root = path.resolve(process.argv[2]);
const output = path.resolve(process.argv[3]);
fs.mkdirSync(output, {recursive:true});
const manifest = JSON.parse(fs.readFileSync(path.join(root,'manifest.json')));
assert.deepEqual(manifest.permissions, ['storage']);
assert.equal(manifest.chrome_url_overrides.newtab,'newtab.html');
assert(!manifest.background && !manifest.host_permissions && !manifest.content_scripts);
const server = http.createServer((req,res)=>{
  const relative=decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/^\//,'');
  const file=path.resolve(root,relative || 'newtab.html');
  if(!file.startsWith(root+path.sep) || !fs.existsSync(file)){res.writeHead(404);res.end();return;}
  const types={'.html':'text/html; charset=utf-8','.js':'application/javascript','.css':'text/css','.json':'application/json','.png':'image/png'};
  res.setHeader('Content-Type',types[path.extname(file)]||'application/octet-stream');
  res.setHeader('Content-Security-Policy',manifest.content_security_policy.extension_pages);
  res.end(fs.readFileSync(file));
});
(async()=>{
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const url=`http://127.0.0.1:${server.address().port}/newtab.html`;
  let browser;
  try {
    browser=await chromium.launch({headless:true, ...(process.env.TEST_CHROME ? {executablePath:process.env.TEST_CHROME}: {})});
    const context=await browser.newContext();
    // API test adapter: persistence + onChanged semantics. Actual extension load
    // is checked separately; this adapter does not claim Chrome API verification.
    await context.addInitScript(()=>{
      const listeners=[];
      window.chrome={storage:{local:{
        async get(key){const value=JSON.parse(localStorage.getItem(key)||'null');return value===null?{}:{[key]:value};},
        async set(values){
          if(window.failStorage)throw new Error('Test storage failure');
          for(const [key,newValue]of Object.entries(values)){
            const oldValue=JSON.parse(localStorage.getItem(key)||'null');
            localStorage.setItem(key,JSON.stringify(newValue));
            listeners.forEach(fn=>fn({[key]:{oldValue,newValue}},'local'));
          }
        }
      },onChanged:{addListener(fn){listeners.push(fn);}}}};
    });
    const page=await context.newPage();const errors=[],external=[];
    page.on('pageerror',error=>errors.push(error.message));
    page.on('request',request=>{if(!request.url().startsWith('http://127.0.0.1:'))external.push(request.url());});
    await page.goto(url);await page.waitForFunction(()=>document.querySelectorAll('.shortcut').length===6);
    for(const [width,height] of [[1920,1080],[1024,600],[700,700],[390,844],[320,480]]){
      await page.setViewportSize({width,height});
      assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Horizontal overflow');
      assert(await page.locator('#art').evaluate(img=>img.complete&&img.naturalWidth===2480&&img.naturalHeight===1929&&getComputedStyle(img).objectFit==='contain'));
      await page.screenshot({path:path.join(output,`view-${width}x${height}.png`),fullPage:true});
    }
    await page.setViewportSize({width:1024,height:600});
    await page.getByRole('button',{name:'Настроить',exact:true}).click();
    await page.getByRole('button',{name:'Добавить ярлык',exact:true}).click();
    await page.locator('#shortcut-name').fill('<b>My site</b>');
    await page.locator('#shortcut-url').fill('https://example.com/a?q=1&b=2');
    await page.getByRole('button',{name:'Сохранить',exact:true}).click();
    assert.equal(await page.locator('.shortcut').count(),7);
    assert.equal(await page.locator('.shortcut-label b').count(),0);
    await page.getByRole('button',{name:'Изменить <b>My site</b>',exact:true}).click();
    await page.locator('#shortcut-name').fill('Edited');
    await page.locator('#shortcut-url').fill('javascript:alert(1)');
    await page.getByRole('button',{name:'Сохранить',exact:true}).click();
    assert(await page.locator('#editor').evaluate(d=>d.open));
    assert((await page.locator('#editor-status').textContent()).includes('http'));
    await page.locator('#shortcut-url').fill('https://example.org/');
    await page.evaluate(()=>window.failStorage=true);
    await page.getByRole('button',{name:'Сохранить',exact:true}).click();
    assert((await page.locator('#editor-status').textContent()).includes('storage failure'));
    assert(await page.locator('#editor').evaluate(d=>d.open));
    await page.evaluate(()=>window.failStorage=false);
    await page.getByRole('button',{name:'Сохранить',exact:true}).click();
    await page.getByRole('button',{name:'Выше: Edited',exact:true}).click();
    assert.equal(await page.locator('.shortcut-label').nth(5).textContent(),'Edited');
    const downloadPromise=page.waitForEvent('download');await page.locator('#export').click();
    const download=await downloadPromise;const exportedPath=path.join(output,'export.json');await download.saveAs(exportedPath);
    const exported=JSON.parse(fs.readFileSync(exportedPath));assert.equal(exported.shortcuts.length,7);
    await page.getByRole('button',{name:'Удалить Edited',exact:true}).click();
    assert.equal(await page.locator('.shortcut').count(),6);
    await page.locator('#import-file').setInputFiles({name:'bad.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify({version:1,shortcuts:[{id:'bad',name:'Bad',url:'javascript:alert(1)'}]}))});
    await page.waitForFunction(()=>document.getElementById('settings-status').textContent.includes('http'));
    assert.equal(await page.locator('.shortcut').count(),6);
    await page.locator('#import-file').setInputFiles(exportedPath);
    await page.locator('#cancel-import').click();assert.equal(await page.locator('.shortcut').count(),6);
    await page.locator('#import-file').setInputFiles(exportedPath);
    await page.locator('#confirm-import').click();assert.equal(await page.locator('.shortcut').count(),7);
    await page.keyboard.press('Escape');assert(!(await page.locator('#settings').evaluate(d=>d.open)));
    await page.reload();await page.waitForFunction(()=>document.querySelectorAll('.shortcut').length===7);
    assert.equal(await page.locator('.shortcut-label').nth(5).textContent(),'Edited');
    await page.getByRole('button',{name:'Настроить',exact:true}).click();
    await page.mouse.click(2,2);assert(!(await page.locator('#settings').evaluate(d=>d.open)));
    assert.deepEqual(external,[],'Unexpected idle network request');
    const requestPromise=page.waitForRequest(r=>r.url().startsWith('https://www.google.com/search'));
    await page.route('https://www.google.com/**',route=>route.fulfill({status:200,body:'Search intercepted locally'}));
    await page.locator('#query').fill('  холодный серый & окна  ');await page.locator('#query').press('Enter');
    const request=await requestPromise;assert.equal(new URL(request.url()).searchParams.get('q'),'холодный серый & окна');
    assert.deepEqual(errors,[]);
    const report={passed:true,viewports:5,checks:['contain/no cropping','no horizontal overflow','add/edit/reorder/delete','literal titles/no HTML injection','unsafe URL rejected','storage failure visible','export/import/cancel','persistence after reload','Escape and outside click','no idle network','encoded Google query'],limits:'Page tests use a chrome.storage adapter; real extension tested separately.',imageSha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'images/maomao-cold-grey-dark.png'))).digest('hex')};
    fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
  } finally {if(browser)await browser.close();server.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
