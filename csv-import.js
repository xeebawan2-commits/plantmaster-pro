// PlantMaster Pro — CSV Import v1.0.0
// Bulk import for assets and spares. No external dependency.
//
// Wire up in app.js:
//   import{createCsvImport}from'./csv-import.js?v=1.0.0';
//   const csvImport=createCsvImport({sb,$,esc,toast,state:()=>({org,plant,userId,role})});
//   window.PMCsv=csvImport;   // exposes openImport()
//
// Add a button wherever you render Assets / Spares:
//   <button class="secondary" onclick="window.PMCsv.openImport('assets')">Import CSV</button>
//   <button class="secondary" onclick="window.PMCsv.openImport('spares')">Import CSV</button>

export function createCsvImport(ctx){
  const {sb,$,esc,toast}=ctx;

  // Shares the procurement stylesheet; inject a minimal fallback if that
  // module has not been opened yet this session.
  if(!document.getElementById('pmProcCss')&&!document.getElementById('pmCsvCss')){
    const st=document.createElement('style');
    st.id='pmCsvCss';
    st.textContent=`
      .data-table{width:100%;border-collapse:collapse;margin:12px 0;font-size:13.5px}
      .data-table th,.data-table td{padding:9px 10px;text-align:left;
        border-bottom:1px solid var(--pm-line,#2b4a68)}
      .data-table th{font-size:11.5px;letter-spacing:.04em;text-transform:uppercase;color:var(--pm-muted,#8aa2ba)}
      #fields .form-field.wide{grid-column:1/-1}
      @media(max-width:700px){.data-table{display:block;overflow-x:auto;white-space:nowrap}}
    `;
    document.head.appendChild(st);
  }

  const S=()=>ctx.state();
  const now=()=>new Date().toISOString();

  // Column maps: csvHeader -> dbColumn
  const SCHEMAS={
    assets:{
      table:'assets',
      label:'Assets',
      required:['name'],
      map:{
        'name':'name','asset name':'name','equipment':'name','equipment name':'name',
        'code':'asset_code','asset code':'asset_code','tag':'asset_code','tag number':'asset_code','tag no':'asset_code',
        'type':'asset_type','asset type':'asset_type','category':'asset_type',
        'location':'location','area':'location','plant area':'location','department':'location',
        'status':'status','condition':'status',
        'running state':'running_state','state':'running_state','running':'running_state',
        'meter unit':'meter_unit','uom':'meter_unit','meter uom':'meter_unit',
        'current meter':'current_meter_value','meter reading':'current_meter_value','reading':'current_meter_value',
        'pm trigger':'pm_trigger_meter_value','trigger':'pm_trigger_meter_value','pm threshold':'pm_trigger_meter_value'
      },
      defaults:{status:'operational',running_state:'running'}
    },
    spares:{
      table:'spares',
      label:'Spares',
      required:['description'],
      map:{
        'description':'description','name':'description','part name':'description','item':'description','item name':'description',
        'code':'part_number','part code':'part_number','part number':'part_number','part no':'part_number','sku':'part_number',
        'stock':'stock','quantity':'stock','qty':'stock','opening stock':'stock','on hand':'stock',
        'minimum':'min_stock','min':'min_stock','min stock':'min_stock','reorder level':'min_stock','reorder':'min_stock',
        'unit':'unit','uom':'unit',
        'location':'bin_location','bin':'bin_location','rack':'bin_location','store':'bin_location','bin location':'bin_location',
        'supplier':'supplier','vendor':'supplier'
      },
      defaults:{stock:0,min_stock:0,unit:'pcs'}
    }
  };

  // ---------- RFC4180-ish parser: handles quotes, commas, CRLF ----------
  function parseCSV(text){
    text=text.replace(/^\uFEFF/,'');                 // strip BOM
    const rows=[];let row=[],cell='',q=false;
    for(let i=0;i<text.length;i++){
      const c=text[i],n=text[i+1];
      if(q){
        if(c==='"'&&n==='"'){cell+='"';i++;}
        else if(c==='"'){q=false;}
        else cell+=c;
      }else{
        if(c==='"')q=true;
        else if(c===','){row.push(cell);cell='';}
        else if(c==='\n'){row.push(cell);rows.push(row);row=[];cell='';}
        else if(c==='\r'){/* skip */}
        else cell+=c;
      }
    }
    if(cell.length||row.length){row.push(cell);rows.push(row);}
    return rows.filter(r=>r.some(x=>String(x).trim()!==''));
  }

  function normalise(h){return String(h||'').trim().toLowerCase().replace(/[_-]+/g,' ').replace(/\s+/g,' ');}

  function mapRows(rows,schema){
    const header=rows[0].map(normalise);
    const out=[],errors=[];
    for(let i=1;i<rows.length;i++){
      const raw=rows[i],rec={};
      header.forEach((h,j)=>{
        const col=schema.map[h];
        if(!col)return;
        let v=String(raw[j]??'').trim();
        if(v==='')return;
        if(['stock','min_stock','current_meter_value','pm_trigger_meter_value'].includes(col)){
          const n=Number(v.replace(/,/g,''));
          if(!Number.isNaN(n))rec[col]=n;
        }else rec[col]=v;
      });
      const missing=schema.required.filter(r=>!rec[r]);
      if(missing.length){errors.push(`Row ${i+1}: missing ${missing.join(', ')}`);continue;}
      out.push({...schema.defaults,...rec});
    }
    return {records:out,errors,unmapped:header.filter(h=>h&&!schema.map[h])};
  }

  function template(kind){
    const s=SCHEMAS[kind];
    const cols=[...new Set(Object.values(s.map))];
    const header=cols.join(',');
    const example=kind==='assets'
      ? 'Boiler Feed Pump 1,BFP-01,Pump,Boiler House,operational,running,hours,12500,20000'
      : 'SKF 6205 Bearing,BRG-6205,40,10,pcs,Rack A-3,Al-Noor Bearings';
    const blob=new Blob(['\ufeff'+header+'\n'+example+'\n'],{type:'text/csv'});
    const a=document.createElement('a');
    a.href=URL.createObjectURL(blob);
    a.download=`plantmaster-${kind}-template.csv`;
    a.click();URL.revokeObjectURL(a.href);
    toast('Template downloaded');
  }

  async function commit(kind,records){
    const s=SCHEMAS[kind];
    const stamped=records.map(r=>({
      id:crypto.randomUUID(),
      organization_id:S().org.id,
      plant_id:S().plant.id,
      ...r,
      created_at:now(),updated_at:now()
    }));
    // chunk to stay well inside payload limits
    let done=0;
    for(let i=0;i<stamped.length;i+=100){
      const batch=stamped.slice(i,i+100);
      const q=await sb.from(s.table).insert(batch);
      if(q.error)throw new Error(`Row ${i+1}+: ${q.error.message}`);
      done+=batch.length;
    }
    return done;
  }

  function openImport(kind='assets'){
    const s=SCHEMAS[kind];
    if(!s)return toast('Unknown import type');
    if(!['owner','manager'].includes(S().role))return toast('Only owners and managers can import');

    const m=$('#modal'),f=$('#recordForm');
    $('#modalTitle').textContent=`Import ${s.label} from CSV`;
    $('#fields').innerHTML=`
      <div class="form-field wide">
        <p class="muted-text">
          Upload a CSV file. The first row must be column headers —
          common names are recognised automatically
          (for example <code>part number</code>, <code>qty</code>, <code>bin</code>).
        </p>
        <button type="button" class="secondary" id="csvTemplate">Download template</button>
      </div>
      <label class="form-field wide">
        <span>CSV file *</span>
        <input type="file" id="csvFile" accept=".csv,text/csv" required>
      </label>
      <div id="csvPreview"></div>`;

    let parsed=null;

    $('#csvTemplate').onclick=()=>template(kind);

    $('#csvFile').onchange=async e=>{
      const file=e.target.files[0];
      if(!file)return;
      if(file.size>5*1024*1024)return toast('File too large — split into files under 5 MB');
      const text=await file.text();
      const rows=parseCSV(text);
      if(rows.length<2){$('#csvPreview').innerHTML='<p class="muted-text">File appears empty.</p>';return;}
      parsed=mapRows(rows,s);
      const {records,errors,unmapped}=parsed;
      $('#csvPreview').innerHTML=`
        <div class="form-field wide">
          <p><b>${records.length}</b> row${records.length===1?'':'s'} ready to import.</p>
          ${errors.length?`<p style="color:#f87171">${errors.length} row${errors.length===1?'':'s'} skipped:<br>${errors.slice(0,5).map(esc).join('<br>')}${errors.length>5?'<br>…':''}</p>`:''}
          ${unmapped.length?`<p class="muted-text">Ignored columns: ${unmapped.map(esc).join(', ')}</p>`:''}
          ${records.length?`<table class="data-table"><thead><tr>${
            Object.keys(records[0]).map(k=>`<th>${esc(k)}</th>`).join('')
          }</tr></thead><tbody>${
            records.slice(0,3).map(r=>`<tr>${Object.values(r).map(v=>`<td>${esc(v)}</td>`).join('')}</tr>`).join('')
          }</tbody></table><p class="muted-text">Showing first 3 rows.</p>`:''}
        </div>`;
    };

    f.onsubmit=async ev=>{
      ev.preventDefault();
      if(!parsed||!parsed.records.length)return toast('Nothing to import');
      const btn=$('#saveRecord');btn.disabled=true;btn.textContent='Importing…';
      try{
        const n=await commit(kind,parsed.records);
        toast(`Imported ${n} ${s.label.toLowerCase()}`);
        m.close();
        if(window.go)window.go(kind==='assets'?'assets':'inventory');
      }catch(err){
        toast(err.message||'Import failed');
      }finally{
        btn.disabled=false;btn.textContent='Save';
      }
    };

    m.style.removeProperty('display');
    m.showModal();
  }

  return {openImport,parseCSV,template};
}
