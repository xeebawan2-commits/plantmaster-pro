import fs from 'fs'; import path from 'path';
const roots={ app:'public', site:'dist/site', admin:'dist/admin' };
let problems=0;
for(const [label,root] of Object.entries(roots)){
  const files=[];
  (function walk(d){ for(const e of fs.readdirSync(d,{withFileTypes:true})){
    const p=path.join(d,e.name); e.isDirectory()?walk(p):files.push(p); }})(root);
  for(const f of files.filter(f=>/\.html$/.test(f))){
    const html=fs.readFileSync(f,'utf8');
    for(const m of html.matchAll(/(?:src|href)="([^"]+)"/g)){
      let u=m[1];
      if(/^(https?:|data:|mailto:|tel:|#|\/\/)/.test(u))continue;
      u=u.split('?')[0].split('#')[0];
      if(!u)continue;
      const target=u.startsWith('/')?path.join(root,u):path.join(path.dirname(f),u);
      if(!fs.existsSync(target)){ console.log(`  MISSING [${label}] ${path.basename(f)} -> ${m[1]}`); problems++; }
    }
  }
  // JS bare imports from local paths
  for(const f of files.filter(f=>/\.(js|mjs)$/.test(f))){
    const js=fs.readFileSync(f,'utf8');
    for(const m of js.matchAll(/from\s*['"](\/[^'"]+|\.\/[^'"]+)['"]/g)){
      const u=m[1].split('?')[0];
      const target=u.startsWith('/')?path.join(root,u):path.join(path.dirname(f),u);
      if(!fs.existsSync(target)){ console.log(`  MISSING-IMPORT [${label}] ${path.basename(f)} -> ${m[1]}`); problems++; }
    }
  }
  console.log(`[${label}] ${files.length} files checked`);
}
console.log(problems? `\n${problems} BROKEN REFERENCES`:'\nAll internal references resolve.');
process.exit(problems?1:0);
