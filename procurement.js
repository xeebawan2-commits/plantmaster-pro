// PlantMaster Pro — Procurement module v1.0.0
// Suppliers + Purchase Orders + Goods Receipt
// Mirrors the createOperations(ctx) contract used by operations.js
//
// Wire up in app.js:
//   import{createProcurement}from'./procurement.js?v=1.0.0';
//   const procurement=createProcurement({sb,$,esc,toast,state:()=>({session,userId,org,plant,role,profile,email:session?.user?.email||''}),audit:operations.audit,enhanceVoice:operations.enhanceVoice});
//   // then in your router, before the default branch:
//   if(procurement.handles(v)) return procurement.render(v);
//
// Add to the drawer in index.html:
//   <button data-view="procurement" onclick="window.go('procurement')">Purchase Orders</button>
//   <button data-view="suppliers"   onclick="window.go('suppliers')">Suppliers</button>

export function createProcurement(ctx){
  const {sb,$,esc,toast}=ctx;
  const S=()=>ctx.state();
  const audit=ctx.audit||(async()=>{});
  const enhanceVoice=ctx.enhanceVoice||(()=>{});

  const STATUSES=['draft','pending_approval','approved','sent','partially_received','received','cancelled'];
  const URGENCY=['low','normal','high','critical'];

  let module='procurement',cache=[],suppliers=[],search='',currentPO=null;

  const id=()=>crypto.randomUUID();
  const now=()=>new Date().toISOString();
  const value=(fd,k)=>String(fd.get(k)||'').trim();
  const num=(fd,k)=>Number(String(fd.get(k)||'0').replace(/,/g,''))||0;
  const leader=()=>['owner','manager'].includes(S().role);
  const owner=()=>S().role==='owner';

  const money=(v,cur='PKR')=>{
    const n=Number(v||0);
    return `${cur} ${n.toLocaleString('en-PK',{minimumFractionDigits:2,maximumFractionDigits:2})}`;
  };
  const stateBadge=v=>`<span class="state ${esc(String(v||'').toLowerCase())}">${esc(String(v||'—').replaceAll('_',' '))}</span>`;
  const empty=t=>`<div class="empty-state"><b>Nothing here yet</b><p>${esc(t)}</p></div>`;
  const options=(items,selected='')=>items.map(x=>
    `<option value="${esc(x)}" ${x===selected?'selected':''}>${esc(String(x).replaceAll('_',' '))}</option>`).join('');

  const field=(name,label,type='text',val='',required=true,extra='')=>
    `<label class="form-field"><span>${esc(label)}${required?' *':''}</span><input name="${name}" type="${type}" value="${esc(val)}" ${required?'required':''} ${extra}></label>`;
  const area=(name,label,val='',required=false)=>
    `<label class="form-field wide"><span>${esc(label)}${required?' *':''}</span><textarea name="${name}" rows="3" ${required?'required':''}>${esc(val)}</textarea></label>`;
  const select=(name,label,items,selected='',required=true)=>
    `<label class="form-field"><span>${esc(label)}${required?' *':''}</span><select name="${name}" ${required?'required':''}>${options(items,selected)}</select></label>`;

  // dialog() mirrors the helper in operations.js — uses the existing #modal element
  function dialog(title,html,onSave){
    const m=$('#modal'),f=$('#recordForm');
    $('#modalTitle').textContent=title;
    $('#fields').innerHTML=html;
    enhanceVoice($('#fields'));
    f.onsubmit=async e=>{
      e.preventDefault();
      const btn=$('#saveRecord');btn.disabled=true;
      try{ await onSave(new FormData(f)); m.close(); }
      catch(err){ toast(err.message||'Save failed'); }
      finally{ btn.disabled=false; }
    };
    m.showModal();
  }

  // ---------------------------------------------------------------- data
  async function loadSuppliers(){
    const q=await sb.from('suppliers').select('*')
      .eq('organization_id',S().org.id).is('removed_at',null)
      .order('name');
    if(q.error){toast(q.error.message);return[];}
    suppliers=q.data||[];
    return suppliers;
  }

  async function loadPOs(){
    const q=await sb.from('purchase_orders')
      .select('*, suppliers(name), purchase_order_lines(id,description,quantity,received_qty,unit_price,line_total,spare_id,unit)')
      .eq('plant_id',S().plant.id).is('removed_at',null)
      .order('created_at',{ascending:false});
    if(q.error){toast(q.error.message);return[];}
    cache=q.data||[];
    return cache;
  }

  // ---------------------------------------------------------------- render
  async function render(v){
    module=v;
    $('#toolbar').hidden=false;
    const add=$('#add');
    if(v==='suppliers'){
      add.hidden=!leader();
      add.onclick=()=>supplierForm();
      await loadSuppliers();
      return renderSuppliers();
    }
    add.hidden=!leader();
    add.onclick=()=>poForm();
    await Promise.all([loadPOs(),loadSuppliers()]);
    return renderPOs();
  }

  function renderSuppliers(){
    const term=search.toLowerCase();
    const rows=suppliers.filter(s=>!term||
      [s.name,s.contact_person,s.phone,s.email,s.ntn].join(' ').toLowerCase().includes(term));
    if(!rows.length) return $('#content').innerHTML=empty('Add your first supplier to start raising purchase orders.');
    $('#content').innerHTML=`<div class="list">${rows.map(s=>`
      <article class="card">
        <div class="card-head">
          <div>
            <b>${esc(s.name)}</b>
            <p class="muted-text">${esc(s.contact_person||'—')} • ${esc(s.phone||'no phone')}</p>
          </div>
          ${s.rating?`<span class="badge">★ ${esc(s.rating)}</span>`:''}
        </div>
        <p class="muted-text">
          ${s.email?`✉ ${esc(s.email)}<br>`:''}
          ${s.ntn?`NTN ${esc(s.ntn)} `:''}${s.strn?`• STRN ${esc(s.strn)}<br>`:'<br>'}
          Terms: ${esc(s.payment_terms||'—')} • ${esc(s.currency||'PKR')}
        </p>
        <div class="actions">
          ${s.phone?`<button class="whatsapp-btn" onclick="window.PMProc.waSupplier('${s.id}')">WhatsApp</button>`:''}
          ${leader()?`<button class="secondary" onclick="window.PMProc.editSupplier('${s.id}')">Edit</button>`:''}
          ${owner()?`<button class="danger" onclick="window.PMProc.removeSupplier('${s.id}')">Delete</button>`:''}
        </div>
      </article>`).join('')}</div>`;
  }

  function renderPOs(){
    const term=search.toLowerCase();
    const rows=cache.filter(p=>!term||
      [p.po_number,p.suppliers?.name,p.status,p.notes].join(' ').toLowerCase().includes(term));

    const totalOpen=cache.filter(p=>!['received','cancelled'].includes(p.status))
                         .reduce((a,b)=>a+Number(b.total||0),0);

    const head=`<div class="summary-row">
      <article class="stat"><b>${cache.length}</b><span>Purchase orders</span></article>
      <article class="stat"><b>${cache.filter(p=>p.status==='pending_approval').length}</b><span>Awaiting approval</span></article>
      <article class="stat"><b>${money(totalOpen)}</b><span>Open commitment</span></article>
    </div>`;

    if(!rows.length) return $('#content').innerHTML=head+empty('No purchase orders yet. Tap Add to raise one.');

    $('#content').innerHTML=head+`<div class="list">${rows.map(p=>{
      const lines=p.purchase_order_lines||[];
      const outstanding=lines.filter(l=>Number(l.received_qty)<Number(l.quantity)).length;
      return `<article class="card">
        <div class="card-head">
          <div>
            <b>${esc(p.po_number)}</b>
            <p class="muted-text">${esc(p.suppliers?.name||'No supplier')} • ${lines.length} line${lines.length===1?'':'s'}</p>
          </div>
          ${stateBadge(p.status)}
        </div>
        <p class="muted-text">
          <b>${money(p.total,p.currency)}</b>
          ${p.expected_date?` • expected ${esc(p.expected_date)}`:''}
          ${outstanding?` • ${outstanding} line${outstanding===1?'':'s'} outstanding`:''}
        </p>
        <div class="actions">
          <button class="secondary" onclick="window.PMProc.viewPO('${p.id}')">Open</button>
          ${leader()&&p.status==='draft'?`<button class="secondary" onclick="window.PMProc.addLine('${p.id}')">Add line</button>`:''}
          ${leader()&&p.status==='draft'?`<button class="primary" onclick="window.PMProc.submitPO('${p.id}')">Submit</button>`:''}
          ${owner()&&p.status==='pending_approval'?`<button class="primary" onclick="window.PMProc.approvePO('${p.id}')">Approve</button>`:''}
          ${leader()&&['approved','sent','partially_received'].includes(p.status)?`<button class="primary" onclick="window.PMProc.receivePO('${p.id}')">Receive</button>`:''}
          <button class="secondary" onclick="window.PMProc.printPO('${p.id}')">Print</button>
        </div>
      </article>`;}).join('')}</div>`;
  }

  // ---------------------------------------------------------------- forms
  function supplierForm(existing=null){
    const s=existing||{};
    dialog(existing?'Edit supplier':'New supplier',
      field('name','Supplier name','text',s.name||'')+
      field('contact_person','Contact person','text',s.contact_person||'',false)+
      field('phone','Phone / WhatsApp','tel',s.phone||'',false)+
      field('email','Email','email',s.email||'',false)+
      field('ntn','NTN','text',s.ntn||'',false)+
      field('strn','STRN','text',s.strn||'',false)+
      field('payment_terms','Payment terms','text',s.payment_terms||'Net 30',false)+
      select('currency','Currency',['PKR','USD','EUR','AED','GBP'],s.currency||'PKR')+
      field('rating','Rating 0–5','number',s.rating||'',false,'step="0.5" min="0" max="5"')+
      area('address','Address',s.address||'')+
      area('notes','Notes',s.notes||''),
      async fd=>{
        const rec={
          name:value(fd,'name'),contact_person:value(fd,'contact_person'),
          phone:value(fd,'phone'),email:value(fd,'email'),
          ntn:value(fd,'ntn'),strn:value(fd,'strn'),
          payment_terms:value(fd,'payment_terms'),currency:value(fd,'currency'),
          rating:fd.get('rating')?num(fd,'rating'):null,
          address:value(fd,'address'),notes:value(fd,'notes'),
          updated_at:now()
        };
        if(existing){
          const q=await sb.from('suppliers').update(rec).eq('id',existing.id);
          if(q.error)throw q.error;
          await audit('supplier_updated','supplier',existing.id,{name:rec.name});
          toast('Supplier updated');
        }else{
          rec.id=id();rec.organization_id=S().org.id;rec.plant_id=S().plant.id;
          rec.created_by=S().userId;rec.created_at=now();
          const q=await sb.from('suppliers').insert(rec);
          if(q.error)throw q.error;
          await audit('supplier_created','supplier',rec.id,{name:rec.name});
          toast('Supplier added');
        }
        await loadSuppliers();renderSuppliers();
      });
  }

  async function poForm(){
    if(!suppliers.length){
      toast('Add a supplier first');
      return supplierForm();
    }
    const {data:poNum}=await sb.rpc('next_po_number',{p_org:S().org.id});
    dialog('New purchase order',
      field('po_number','PO number','text',poNum||'',true,'readonly')+
      select('supplier_id','Supplier',suppliers.map(s=>s.name))+
      field('expected_date','Expected delivery','date','',false)+
      field('tax_percent','Tax / GST %','number','18',false,'step="0.01" min="0"')+
      area('notes','Notes'),
      async fd=>{
        const supName=value(fd,'supplier_id');
        const sup=suppliers.find(s=>s.name===supName);
        const rec={
          id:id(),organization_id:S().org.id,plant_id:S().plant.id,
          po_number:value(fd,'po_number'),
          supplier_id:sup?.id||null,
          currency:sup?.currency||'PKR',
          tax_percent:num(fd,'tax_percent'),
          expected_date:value(fd,'expected_date')||null,
          notes:value(fd,'notes'),
          status:'draft',requested_by:S().userId,
          created_at:now(),updated_at:now()
        };
        const q=await sb.from('purchase_orders').insert(rec);
        if(q.error)throw q.error;
        await audit('po_created','purchase_order',rec.id,{po:rec.po_number});
        toast('Purchase order created — now add lines');
        await loadPOs();renderPOs();
      });
  }

  // ---------------------------------------------------------------- actions
  window.PMProc={};

  window.PMProc.editSupplier=sid=>{
    const s=suppliers.find(x=>x.id===sid);
    if(s)supplierForm(s);
  };

  window.PMProc.removeSupplier=async sid=>{
    const s=suppliers.find(x=>x.id===sid);
    if(!s||!confirm(`Delete supplier "${s.name}"? This can be restored from the Recovery Bin.`))return;
    const q=await sb.from('suppliers').update({removed_at:now()}).eq('id',sid);
    if(q.error)return toast(q.error.message);
    await audit('supplier_deleted','supplier',sid,{name:s.name});
    toast('Supplier deleted');
    await loadSuppliers();renderSuppliers();
  };

  window.PMProc.waSupplier=sid=>{
    const s=suppliers.find(x=>x.id===sid);
    if(!s?.phone)return toast('No phone number on file');
    const phone=String(s.phone).replace(/[^0-9]/g,'');
    const msg=encodeURIComponent(`Assalam o Alaikum ${s.contact_person||s.name}, this is ${S().org?.name||'our plant'} regarding a purchase enquiry.`);
    window.open(`https://wa.me/${phone}?text=${msg}`,'_blank');
  };

  window.PMProc.addLine=async pid=>{
    const {data:spares}=await sb.from('spares').select('id,part_number,description,unit,stock')
      .eq('plant_id',S().plant.id).order('description');
    const list=spares||[];
    const names=['— free text —',...list.map(s=>`${s.part_number?s.part_number+' · ':''}${s.description||''}`)];
    dialog('Add PO line',
      select('spare','Spare part',names,'— free text —',false)+
      field('description','Description','text','',true)+
      field('quantity','Quantity','number','1',true,'step="any" min="0.001"')+
      field('unit','Unit','text','pcs',false)+
      field('unit_price','Unit price','number','0',true,'step="0.01" min="0"'),
      async fd=>{
        const label=value(fd,'spare');
        const idx=names.indexOf(label)-1;
        const sp=idx>=0?list[idx]:null;
        const rec={
          id:id(),purchase_order_id:pid,
          spare_id:sp?.id||null,
          description:value(fd,'description')||label,
          quantity:num(fd,'quantity'),
          unit:value(fd,'unit')||'pcs',
          unit_price:num(fd,'unit_price'),
          created_at:now()
        };
        const q=await sb.from('purchase_order_lines').insert(rec);
        if(q.error)throw q.error;
        toast('Line added');
        await loadPOs();renderPOs();
      });
  };

  window.PMProc.viewPO=async pid=>{
    const p=cache.find(x=>x.id===pid);
    if(!p)return;
    const lines=p.purchase_order_lines||[];
    $('#toolbar').hidden=true;
    $('#content').innerHTML=`
      <article class="card">
        <div class="card-head">
          <div><b>${esc(p.po_number)}</b><p class="muted-text">${esc(p.suppliers?.name||'No supplier')}</p></div>
          ${stateBadge(p.status)}
        </div>
        <table class="data-table">
          <thead><tr><th>Item</th><th>Qty</th><th>Recvd</th><th>Rate</th><th>Total</th></tr></thead>
          <tbody>${lines.map(l=>`<tr>
            <td>${esc(l.description)}</td>
            <td>${esc(l.quantity)} ${esc(l.unit||'')}</td>
            <td>${esc(l.received_qty||0)}</td>
            <td>${money(l.unit_price,p.currency)}</td>
            <td>${money(l.line_total,p.currency)}</td>
          </tr>`).join('')||'<tr><td colspan="5">No lines yet</td></tr>'}</tbody>
        </table>
        <dl class="totals">
          <div><dt>Subtotal</dt><dd>${money(p.subtotal,p.currency)}</dd></div>
          <div><dt>Tax (${esc(p.tax_percent||0)}%)</dt><dd>${money(p.tax_amount,p.currency)}</dd></div>
          <div><dt><b>Total</b></dt><dd><b>${money(p.total,p.currency)}</b></dd></div>
        </dl>
        ${p.notes?`<p class="muted-text">${esc(p.notes)}</p>`:''}
        <div class="actions">
          <button class="secondary" onclick="window.go('procurement')">← Back</button>
          <button class="secondary" onclick="window.PMProc.printPO('${p.id}')">Print / PDF</button>
        </div>
      </article>`;
  };

  window.PMProc.submitPO=async pid=>{
    const p=cache.find(x=>x.id===pid);
    if(!p)return;
    if(!(p.purchase_order_lines||[]).length)return toast('Add at least one line first');
    const q=await sb.from('purchase_orders')
      .update({status:'pending_approval',updated_at:now()}).eq('id',pid);
    if(q.error)return toast(q.error.message);
    await audit('po_submitted','purchase_order',pid,{po:p.po_number,total:p.total});
    toast('Submitted for approval');
    await loadPOs();renderPOs();
  };

  window.PMProc.approvePO=async pid=>{
    const p=cache.find(x=>x.id===pid);
    if(!p)return;
    if(!confirm(`Approve ${p.po_number} for ${money(p.total,p.currency)}?`))return;
    const q=await sb.from('purchase_orders')
      .update({status:'approved',approved_by:S().userId,approved_at:now(),updated_at:now()})
      .eq('id',pid);
    if(q.error)return toast(q.error.message);
    await audit('po_approved','purchase_order',pid,{po:p.po_number,total:p.total});
    toast('Purchase order approved');
    await loadPOs();renderPOs();
  };

  window.PMProc.receivePO=async pid=>{
    const p=cache.find(x=>x.id===pid);
    if(!p)return;
    const open=(p.purchase_order_lines||[]).filter(l=>Number(l.received_qty)<Number(l.quantity));
    if(!open.length)return toast('All lines already received');
    const labels=open.map(l=>`${l.description} (${Number(l.quantity)-Number(l.received_qty)} outstanding)`);
    dialog(`Receive against ${p.po_number}`,
      select('line','Line',labels)+
      field('qty','Quantity received','number','',true,'step="any" min="0.001"'),
      async fd=>{
        const i=labels.indexOf(value(fd,'line'));
        const line=open[i];
        if(!line)throw new Error('Line not found');
        const {error}=await sb.rpc('receive_po_line',{
          p_line:line.id,p_qty:num(fd,'qty'),p_user:S().userId
        });
        if(error)throw error;
        await audit('po_received','purchase_order',pid,{po:p.po_number,line:line.description,qty:num(fd,'qty')});
        toast('Received — stock updated');
        await loadPOs();renderPOs();
      });
  };

  window.PMProc.printPO=pid=>{
    const p=cache.find(x=>x.id===pid);
    if(!p)return;
    const lines=p.purchase_order_lines||[];
    const sup=suppliers.find(s=>s.id===p.supplier_id);
    const w=window.open('','_blank');
    w.document.write(`<!doctype html><html><head><meta charset="utf-8"><title>${esc(p.po_number)}</title>
    <style>
      body{font:13px/1.5 Arial,sans-serif;padding:32px;color:#111}
      h1{font-size:21px;margin:0 0 2px}
      .muted{color:#666;font-size:12px}
      table{width:100%;border-collapse:collapse;margin:18px 0}
      th,td{border:1px solid #ccc;padding:7px 9px;text-align:left}
      th{background:#f2f2f2}
      .right{text-align:right}
      .tot{margin-left:auto;width:260px}
      .tot td{border:none;padding:3px 0}
      .sign{margin-top:54px;display:flex;gap:60px}
      .sign div{border-top:1px solid #333;padding-top:5px;flex:1;font-size:12px}
    </style></head><body>
      <h1>${esc(S().org?.name||'Purchase Order')}</h1>
      <p class="muted">${esc(S().plant?.name||'')}</p>
      <h2 style="font-size:16px">Purchase Order ${esc(p.po_number)}</h2>
      <p class="muted">
        Date: ${esc((p.created_at||'').slice(0,10))}<br>
        ${p.expected_date?`Expected: ${esc(p.expected_date)}<br>`:''}
        Status: ${esc(String(p.status).replaceAll('_',' '))}
      </p>
      <p><b>Supplier</b><br>
        ${esc(sup?.name||'—')}<br>
        ${sup?.contact_person?esc(sup.contact_person)+'<br>':''}
        ${sup?.phone?esc(sup.phone)+'<br>':''}
        ${sup?.ntn?'NTN: '+esc(sup.ntn)+'<br>':''}
        ${sup?.address?esc(sup.address):''}
      </p>
      <table>
        <thead><tr><th>#</th><th>Description</th><th class="right">Qty</th><th>Unit</th><th class="right">Rate</th><th class="right">Amount</th></tr></thead>
        <tbody>${lines.map((l,i)=>`<tr>
          <td>${i+1}</td><td>${esc(l.description)}</td>
          <td class="right">${esc(l.quantity)}</td><td>${esc(l.unit||'')}</td>
          <td class="right">${esc(Number(l.unit_price).toFixed(2))}</td>
          <td class="right">${esc(Number(l.line_total).toFixed(2))}</td></tr>`).join('')}</tbody>
      </table>
      <table class="tot">
        <tr><td>Subtotal</td><td class="right">${esc(p.currency)} ${esc(Number(p.subtotal).toFixed(2))}</td></tr>
        <tr><td>Tax (${esc(p.tax_percent||0)}%)</td><td class="right">${esc(p.currency)} ${esc(Number(p.tax_amount).toFixed(2))}</td></tr>
        <tr><td><b>Total</b></td><td class="right"><b>${esc(p.currency)} ${esc(Number(p.total).toFixed(2))}</b></td></tr>
      </table>
      ${p.notes?`<p><b>Notes:</b> ${esc(p.notes)}</p>`:''}
      <div class="sign"><div>Prepared by</div><div>Approved by</div><div>Received by</div></div>
    </body></html>`);
    w.document.close();w.print();
  };

  function setSearch(t){search=t||'';module==='suppliers'?renderSuppliers():renderPOs();}

  return {
    handles:v=>['procurement','suppliers'].includes(v),
    render,
    setSearch
  };
}
