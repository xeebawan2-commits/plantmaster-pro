/**
 * Behavioural test suite — runs against the migrated database as real tenant
 * users, so every assertion exercises the actual RLS policies and RPC
 * authorization rather than just checking that the SQL parsed.
 */
const GREEN = '\x1b[32m', RED = '\x1b[31m', DIM = '\x1b[2m', RESET = '\x1b[0m';

let pass = 0, fail = 0;
const failures = [];

function ok(name) { pass++; console.log(`${GREEN}  ✓${RESET} ${name}`); }
function bad(name, detail) {
  fail++; failures.push(name);
  console.log(`${RED}  ✗ ${name}${RESET}\n      ${String(detail).split('\n')[0]}`);
}

async function check(name, fn) {
  try { await fn(); ok(name); } catch (e) { bad(name, e.message || e); }
}

/** Assert the callback is rejected by the database. */
async function denied(name, fn, expect = /permission|denied|authorized|policy|violates|row-level|42501/i) {
  try {
    await fn();
    bad(name, 'expected the database to reject this, but it succeeded');
  } catch (e) {
    if (expect.test(e.message)) ok(name);
    else bad(name, `rejected for the wrong reason: ${e.message}`);
  }
}

export async function runTests(db) {
  console.log(`\n${DIM}── behaviour (RLS enforced as real users) ──${RESET}`);

  // ---- fixtures ------------------------------------------------------------
  // Created as the table owner (RLS bypassed) so the tests start from a known
  // state; every assertion below then runs as a specific signed-in user.
  const ids = {};
  const mk = async (email) => {
    const r = await db.query(
      `insert into auth.users(email) values ($1) returning id`, [email]);
    return r.rows[0].id;
  };

  ids.ownerA  = await mk('owner-a@test.io');
  ids.mgrA    = await mk('manager-a@test.io');
  ids.techA   = await mk('tech-a@test.io');
  ids.viewerA = await mk('viewer-a@test.io');
  ids.ownerB  = await mk('owner-b@test.io');
  ids.staff   = await mk('staff@hsbfix.org');

  await db.query(`insert into public.platform_admins(user_id,email) values ($1,$2)`,
    [ids.staff, 'staff@hsbfix.org']);

  // Two tenants, created through the real onboarding RPC.
  // Impersonate a signed-in PostgREST user: set the JWT claim, switch to the
  // `authenticated` role, run the statement, then drop back to the owner.
  const asUser = async (uid, sql, params = []) => {
    await db.query(`select auth.login($1)`, [uid]);
    try { return await db.query(sql, params); }
    finally {
      await db.query(`reset role`);
      await db.query(`select auth.logout()`);
      await db.query(`reset role`);
    }
  };

  const orgA = (await asUser(ids.ownerA,
    `select * from public.create_organization('Alpha Cement','Line 1')`)).rows[0];
  const orgB = (await asUser(ids.ownerB,
    `select * from public.create_organization('Beta Steel','Furnace')`)).rows[0];

  ids.orgA = orgA.id; ids.orgB = orgB.id;
  ids.plantA = (await db.query(
    `select id from public.plants where organization_id=$1`, [ids.orgA])).rows[0].id;
  ids.plantB = (await db.query(
    `select id from public.plants where organization_id=$1`, [ids.orgB])).rows[0].id;

  for (const [uid, role] of [[ids.mgrA,'manager'],[ids.techA,'technician'],[ids.viewerA,'viewer']]) {
    await db.query(
      `insert into public.organization_members(organization_id,user_id,plant_id,role,active)
       values ($1,$2,$3,$4,true)`, [ids.orgA, uid, ids.plantA, role]);
  }

  // ---- onboarding ----------------------------------------------------------
  await check('create_organization makes owner + plant + settings', async () => {
    const m = await db.query(
      `select role from public.organization_members where organization_id=$1 and user_id=$2`,
      [ids.orgA, ids.ownerA]);
    if (m.rows[0]?.role !== 'owner') throw new Error('creator is not owner');
    const s = await db.query(
      `select 1 from public.organization_settings where organization_id=$1`, [ids.orgA]);
    if (!s.rows.length) throw new Error('settings row missing');
    const r = await db.query(
      `select 1 from public.data_retention_policies where organization_id=$1`, [ids.orgA]);
    if (!r.rows.length) throw new Error('retention policy missing');
  });

  await denied('create_organization refuses a second workspace', () =>
    asUser(ids.ownerA, `select public.create_organization('Another Co','P')`),
    /already belong/i);

  // ---- tenant isolation ----------------------------------------------------
  await db.query(
    `insert into public.assets(organization_id,plant_id,name,asset_code)
     values ($1,$2,'Kiln Drive','A-001'),($3,$4,'Furnace Fan','B-001')`,
    [ids.orgA, ids.plantA, ids.orgB, ids.plantB]);

  await check('member sees only their own tenant assets', async () => {
    const a = await asUser(ids.techA, `select name from public.assets`);
    if (a.rows.length !== 1 || a.rows[0].name !== 'Kiln Drive') {
      throw new Error(`tech A saw ${JSON.stringify(a.rows.map(r => r.name))}`);
    }
    const b = await asUser(ids.ownerB, `select name from public.assets`);
    if (b.rows.length !== 1 || b.rows[0].name !== 'Furnace Fan') {
      throw new Error(`owner B saw ${JSON.stringify(b.rows.map(r => r.name))}`);
    }
  });

  await denied('cross-tenant insert is blocked', () =>
    asUser(ids.ownerB,
      `insert into public.assets(organization_id,plant_id,name)
       values ($1,$2,'Injected')`, [ids.orgA, ids.plantA]));

  // RLS filters rows out of the UPDATE's scan rather than raising an error, so
  // the correct assertion is "nothing was touched", not "it threw".
  await check('cross-tenant update touches nothing', async () => {
    const n = await asUser(ids.ownerB,
      `update public.assets set name='Hacked' where asset_code='A-001' returning id`);
    if (n.rows.length) throw new Error('an update leaked across tenants');
    const after = await db.query(`select name from public.assets where asset_code='A-001'`);
    if (after.rows[0].name !== 'Kiln Drive') throw new Error('asset name was modified');
  });

  await check('cross-tenant delete touches nothing', async () => {
    const n = await asUser(ids.ownerB,
      `delete from public.assets where asset_code='A-001' returning id`);
    if (n.rows.length) throw new Error('a delete leaked across tenants');
    const still = await db.query(`select count(*)::int n from public.assets where asset_code='A-001'`);
    if (still.rows[0].n !== 1) throw new Error('row was deleted across tenants');
  });

  await denied('plant/org mismatch is rejected by the guard', () =>
    asUser(ids.ownerA,
      `insert into public.assets(organization_id,plant_id,name)
       values ($1,$2,'Mismatch')`, [ids.orgA, ids.plantB]),
    /belongs to organization|does not exist/i);

  // ---- role gradient -------------------------------------------------------
  await check('technician can create a work order', async () => {
    await asUser(ids.techA,
      `insert into public.work_orders(organization_id,plant_id,title)
       values ($1,$2,'Bearing noise')`, [ids.orgA, ids.plantA]);
  });

  await denied('viewer (demo) cannot write', () =>
    asUser(ids.viewerA,
      `insert into public.work_orders(organization_id,plant_id,title)
       values ($1,$2,'Demo write')`, [ids.orgA, ids.plantA]));

  await check('viewer can still read', async () => {
    const r = await asUser(ids.viewerA, `select count(*)::int n from public.work_orders`);
    if (r.rows[0].n < 1) throw new Error('viewer cannot read');
  });

  await check('technician cannot escalate their own role', async () => {
    const n = await asUser(ids.techA,
      `update public.organization_members set role='owner' where user_id=$1 returning id`,
      [ids.techA]);
    if (n.rows.length) throw new Error('privilege escalation succeeded');
    const r = await db.query(
      `select role from public.organization_members where organization_id=$1 and user_id=$2`,
      [ids.orgA, ids.techA]);
    if (r.rows[0].role !== 'technician') throw new Error(`role became ${r.rows[0].role}`);
  });

  await denied('technician cannot add a member', () =>
    asUser(ids.techA,
      `insert into public.organization_members(organization_id,user_id,role)
       values ($1,$2,'owner')`, [ids.orgA, ids.viewerA]));

  await check('owner can change a member role', async () => {
    await asUser(ids.ownerA,
      `update public.organization_members set role='supervisor' where user_id=$1`, [ids.techA]);
    await asUser(ids.ownerA,
      `update public.organization_members set role='technician' where user_id=$1`, [ids.techA]);
  });

  await denied('technician cannot create a checklist template', () =>
    asUser(ids.techA,
      `insert into public.checklist_templates(organization_id,plant_id,name)
       values ($1,$2,'Daily round')`, [ids.orgA, ids.plantA]));

  await check('manager can create a checklist template', async () => {
    await asUser(ids.mgrA,
      `insert into public.checklist_templates(organization_id,plant_id,name)
       values ($1,$2,'Daily round')`, [ids.orgA, ids.plantA]);
  });

  // ---- audit trail is immutable -------------------------------------------
  await check('member can append to the audit log', async () => {
    await asUser(ids.techA,
      `insert into public.audit_logs(organization_id,plant_id,user_id,action)
       values ($1,$2,$3,'test_action')`, [ids.orgA, ids.plantA, ids.techA]);
  });

  // Immutability is defended twice: no UPDATE/DELETE policy, and the grant is
  // revoked in 0008. Either rejecting outright or affecting zero rows is a pass.
  const immutable = async (label, table) => {
    await check(label, async () => {
      for (const stmt of [`update public.${table} set created_at=now() returning 1`,
                          `delete from public.${table} returning 1`]) {
        try {
          const r = await asUser(ids.ownerA, stmt);
          if (r.rows.length) throw new Error(`${stmt.split(' ')[0]} succeeded on ${table}`);
        } catch (e) {
          if (!/permission denied|policy|denied for table/i.test(e.message)) throw e;
        }
      }
      // And the rows are still there.
      const n = await db.query(`select count(*)::int n from public.${table}`);
      if (n.rows[0].n === 0) throw new Error(`${table} was emptied`);
    });
  };

  await immutable('audit trail is immutable (policy + grant)', 'audit_logs');

  await denied('technician cannot read the audit trail', async () => {
    const r = await asUser(ids.techA, `select count(*)::int n from public.audit_logs`);
    if (Number(r.rows[0].n) === 0) throw new Error('permission denied by policy');
    throw new Error('unexpected');
  }, /permission denied by policy/);

  // ---- stock ledger --------------------------------------------------------
  const spare = (await db.query(
    `insert into public.spares(organization_id,plant_id,description,part_number,stock,unit)
     values ($1,$2,'SKF 6205 bearing','BRG-6205',10,'pcs') returning id`,
    [ids.orgA, ids.plantA])).rows[0].id;

  await check('transact_spare issues stock and writes the ledger', async () => {
    await asUser(ids.techA, `select public.transact_spare($1,'issue',3,'WO-1')`, [spare]);
    const s = await db.query(`select stock from public.spares where id=$1`, [spare]);
    if (Number(s.rows[0].stock) !== 7) throw new Error(`stock is ${s.rows[0].stock}, expected 7`);
    const t = await db.query(
      `select balance_after from public.inventory_transactions where spare_id=$1`, [spare]);
    if (Number(t.rows[0].balance_after) !== 7) throw new Error('ledger balance wrong');
  });

  await denied('stock cannot go negative', () =>
    asUser(ids.techA, `select public.transact_spare($1,'issue',999)`, [spare]),
    /in stock/i);

  await denied('viewer cannot move stock', () =>
    asUser(ids.viewerA, `select public.transact_spare($1,'issue',1)`, [spare]));

  await denied('other tenant cannot move our stock', () =>
    asUser(ids.ownerB, `select public.transact_spare($1,'issue',1)`, [spare]));

  await immutable('stock ledger is immutable (policy + grant)', 'inventory_transactions');

  // ---- procurement ---------------------------------------------------------
  await check('next_po_number increments per tenant per year', async () => {
    const a = (await asUser(ids.mgrA, `select public.next_po_number($1) n`, [ids.orgA])).rows[0].n;
    if (!/^PO-\d{4}-0001$/.test(a)) throw new Error(`got ${a}`);
    await db.query(
      `insert into public.purchase_orders(organization_id,plant_id,po_number)
       values ($1,$2,$3)`, [ids.orgA, ids.plantA, a]);
    const b = (await asUser(ids.mgrA, `select public.next_po_number($1) n`, [ids.orgA])).rows[0].n;
    if (!/^PO-\d{4}-0002$/.test(b)) throw new Error(`second number was ${b}`);
  });

  await check('PO totals recalculate from the lines', async () => {
    const po = (await db.query(
      `select id from public.purchase_orders where organization_id=$1 limit 1`, [ids.orgA])).rows[0].id;
    await db.query(`update public.purchase_orders set tax_percent=17 where id=$1`, [po]);
    await db.query(
      `insert into public.purchase_order_lines(purchase_order_id,description,quantity,unit_price)
       values ($1,'Bearing',4,2500)`, [po]);
    const r = await db.query(
      `select subtotal,tax_amount,total from public.purchase_orders where id=$1`, [po]);
    const { subtotal, tax_amount, total } = r.rows[0];
    if (Number(subtotal) !== 10000) throw new Error(`subtotal ${subtotal}`);
    if (Number(tax_amount) !== 1700) throw new Error(`tax ${tax_amount}`);
    if (Number(total) !== 11700) throw new Error(`total ${total}`);
  });

  await check('receive_po_line moves goods into stock', async () => {
    const po = (await db.query(
      `select id from public.purchase_orders where organization_id=$1 limit 1`, [ids.orgA])).rows[0].id;
    const line = (await db.query(
      `insert into public.purchase_order_lines
         (purchase_order_id,spare_id,description,quantity,unit_price)
       values ($1,$2,'SKF 6205',5,2000) returning id`, [po, spare])).rows[0].id;
    const before = Number((await db.query(
      `select stock from public.spares where id=$1`, [spare])).rows[0].stock);
    await asUser(ids.mgrA, `select public.receive_po_line($1,5)`, [line]);
    const after = Number((await db.query(
      `select stock from public.spares where id=$1`, [spare])).rows[0].stock);
    if (after !== before + 5) throw new Error(`stock ${before} -> ${after}`);
  });

  await denied('cannot over-receive a PO line', async () => {
    const line = (await db.query(
      `select id from public.purchase_order_lines where spare_id=$1 limit 1`, [spare])).rows[0].id;
    return asUser(ids.mgrA, `select public.receive_po_line($1,10)`, [line]);
  }, /remaining/i);

  // ---- storage quota -------------------------------------------------------
  await check('reserve -> finalize records usage', async () => {
    const rid = (await asUser(ids.techA,
      `select public.reserve_storage_upload($1,1048576,'manual.pdf','application/pdf') id`,
      [ids.orgA])).rows[0].id;
    await asUser(ids.techA,
      `select public.finalize_storage_upload($1,$2,null)`, [rid, `${ids.orgA}/x/manual.pdf`]);
    const ev = await db.query(
      `select count(*)::int n from public.storage_usage_events
        where organization_id=$1 and event_type='upload'`, [ids.orgA]);
    if (ev.rows[0].n < 1) throw new Error('no usage event written');
  });

  await check('cancelling a reservation frees the quota', async () => {
    const before = Number((await db.query(
      `select public.organization_storage_bytes($1) b`, [ids.orgA])).rows[0].b);
    const rid = (await asUser(ids.techA,
      `select public.reserve_storage_upload($1,5000,'t.bin','application/octet-stream') id`,
      [ids.orgA])).rows[0].id;
    const during = Number((await db.query(
      `select public.organization_storage_bytes($1) b`, [ids.orgA])).rows[0].b);
    if (during !== before + 5000) throw new Error('pending reservation not counted');
    await asUser(ids.techA, `select public.cancel_storage_reservation($1)`, [rid]);
    const after = Number((await db.query(
      `select public.organization_storage_bytes($1) b`, [ids.orgA])).rows[0].b);
    if (after !== before) throw new Error('quota not released');
  });

  await denied('upload beyond the plan quota is refused', () =>
    asUser(ids.techA,
      `select public.reserve_storage_upload($1,99999999999,'huge.bin','x')`, [ids.orgA]),
    /storage limit/i);

  await denied('viewer cannot reserve an upload', () =>
    asUser(ids.viewerA,
      `select public.reserve_storage_upload($1,1000,'a.txt','text/plain')`, [ids.orgA]),
    /read-only|not authorized/i);

  await denied('suspended workspace cannot upload', async () => {
    await db.query(
      `update public.organizations set commercial_status='suspended' where id=$1`, [ids.orgA]);
    try {
      return await asUser(ids.techA,
        `select public.reserve_storage_upload($1,1000,'a.txt','text/plain')`, [ids.orgA]);
    } finally {
      await db.query(
        `update public.organizations set commercial_status='trial' where id=$1`, [ids.orgA]);
    }
  }, /suspended/i);

  // ---- platform admin ------------------------------------------------------
  await check('is_platform_admin distinguishes staff from tenants', async () => {
    const s = await asUser(ids.staff, `select public.is_platform_admin() a`);
    const o = await asUser(ids.ownerA, `select public.is_platform_admin() a`);
    if (s.rows[0].a !== true) throw new Error('staff not recognised');
    if (o.rows[0].a !== false) throw new Error('tenant owner marked as platform admin');
  });

  await check('platform_tenant_overview lists every tenant for staff', async () => {
    const r = await asUser(ids.staff, `select * from public.platform_tenant_overview()`);
    if (r.rows.length < 2) throw new Error(`saw ${r.rows.length} tenants`);
    const a = r.rows.find(x => x.organization_name === 'Alpha Cement');
    if (!a) throw new Error('Alpha missing');
    if (Number(a.workers) !== 4) throw new Error(`worker count ${a.workers}`);
  });

  await check('platform overview is empty for a tenant owner', async () => {
    const r = await asUser(ids.ownerA, `select * from public.platform_tenant_overview()`);
    if (r.rows.length !== 0) throw new Error('tenant could read the platform overview');
  });

  await denied('tenant owner cannot change commercial status', () =>
    asUser(ids.ownerA,
      `select public.platform_set_company($1,'active','professional','hack')`, [ids.orgA]),
    /platform administrator/i);

  await check('staff can change plan and status', async () => {
    await asUser(ids.staff,
      `select public.platform_set_company($1,'active','professional','paid')`, [ids.orgA]);
    const o = await db.query(
      `select commercial_status, plan_code from public.organizations where id=$1`, [ids.orgA]);
    if (o.rows[0].commercial_status !== 'active' || o.rows[0].plan_code !== 'professional') {
      throw new Error(JSON.stringify(o.rows[0]));
    }
  });

  await check('plan summary reflects the new plan', async () => {
    const r = await asUser(ids.ownerA,
      `select public.organization_plan_summary($1) s`, [ids.orgA]);
    const s = r.rows[0].s;
    if (s.plan_code !== 'professional') throw new Error('plan not applied');
    if (Number(s.storage_gb) !== 25) throw new Error(`storage_gb ${s.storage_gb}`);
    if (s.features.branding !== true) throw new Error('branding feature missing');
  });

  await denied('other tenant cannot read our plan summary', () =>
    asUser(ids.ownerB, `select public.organization_plan_summary($1)`, [ids.orgA]),
    /not authorized/i);

  // ---- invitations ---------------------------------------------------------
  await check('invitation flow joins the invited user only', async () => {
    const newbie = await mk('newbie@test.io');
    const tok = (await asUser(ids.mgrA,
      `insert into public.invitations(organization_id,plant_id,email,role,created_by)
       values ($1,$2,'newbie@test.io','operator',$3) returning token`,
      [ids.orgA, ids.plantA, ids.mgrA])).rows[0].token;

    // Wrong person cannot redeem it.
    let blocked = false;
    try { await asUser(ids.ownerB, `select public.accept_invitation($1)`, [tok]); }
    catch (e) { blocked = /was sent to|already belong/i.test(e.message); }
    if (!blocked) throw new Error('someone else redeemed the invite');

    await asUser(newbie, `select public.accept_invitation($1)`, [tok]);
    const m = await db.query(
      `select role, active from public.organization_members
        where organization_id=$1 and user_id=$2`, [ids.orgA, newbie]);
    if (m.rows[0]?.role !== 'operator') throw new Error('role not applied');
    const inv = await db.query(`select accepted_at from public.invitations where token=$1`, [tok]);
    if (!inv.rows[0].accepted_at) throw new Error('invite not marked accepted');
  });

  await denied('an invitation cannot be reused', async () => {
    const other = await mk('other@test.io');
    const tok = (await db.query(
      `select token from public.invitations where accepted_at is not null limit 1`)).rows[0].token;
    return asUser(other, `select public.accept_invitation($1)`, [tok]);
  }, /already been used/i);

  await denied('an expired invitation is refused', async () => {
    const late = await mk('late@test.io');
    const tok = (await db.query(
      `insert into public.invitations(organization_id,plant_id,email,role,expires_at)
       values ($1,$2,'late@test.io','operator', now() - interval '1 day')
       returning token`, [ids.orgA, ids.plantA])).rows[0].token;
    return asUser(late, `select public.accept_invitation($1)`, [tok]);
  }, /expired/i);

  // ---- safety interlocks ---------------------------------------------------
  await check('permit cannot be self-approved', async () => {
    const wo = (await db.query(
      `select id from public.work_orders where organization_id=$1 limit 1`, [ids.orgA])).rows[0].id;
    const permit = (await db.query(
      `insert into public.permits(organization_id,plant_id,work_order_id,permit_type,requested_by)
       values ($1,$2,$3,'hot_work',$4) returning id`,
      [ids.orgA, ids.plantA, wo, ids.mgrA])).rows[0].id;

    let blocked = false;
    try {
      await asUser(ids.mgrA,
        `update public.permits set status='approved', approved_by=$1 where id=$2`,
        [ids.mgrA, permit]);
    } catch (e) { blocked = /cannot be approved by the person who requested/i.test(e.message); }
    if (!blocked) throw new Error('self-approval was allowed');

    await asUser(ids.ownerA,
      `update public.permits set status='approved', approved_by=$1 where id=$2`,
      [ids.ownerA, permit]);
    const p = await db.query(`select status, approved_at from public.permits where id=$1`, [permit]);
    if (p.rows[0].status !== 'approved' || !p.rows[0].approved_at) {
      throw new Error('approval by a second person failed');
    }
  });

  await check('checklist failure raises an alarm notification', async () => {
    const tpl = (await db.query(
      `select id from public.checklist_templates where organization_id=$1 limit 1`,
      [ids.orgA])).rows[0].id;
    await asUser(ids.techA,
      `insert into public.checklist_runs
         (organization_id,plant_id,template_id,performed_by,worker_name,failures)
       values ($1,$2,$3,$4,'Tech A',2)`, [ids.orgA, ids.plantA, tpl, ids.techA]);
    const n = await db.query(
      `select title, alarm, severity from public.notifications
        where organization_id=$1 and category='checklist'`, [ids.orgA]);
    if (!n.rows.length) throw new Error('no notification was raised');
    if (n.rows[0].alarm !== true) throw new Error('not flagged as an alarm');
  });

  await check('work order completion stamps who and when', async () => {
    const wo = (await db.query(
      `select id from public.work_orders where organization_id=$1 limit 1`, [ids.orgA])).rows[0].id;
    await asUser(ids.techA, `update public.work_orders set status='completed' where id=$1`, [wo]);
    const r = await db.query(
      `select completed_at, completed_by from public.work_orders where id=$1`, [wo]);
    if (!r.rows[0].completed_at) throw new Error('completed_at not stamped');
    if (r.rows[0].completed_by !== ids.techA) throw new Error('completed_by not stamped');
  });

  // ---- manuals permission --------------------------------------------------
  await check('manuals can be hidden from a specific member', async () => {
    await db.query(
      `insert into public.manuals(organization_id,plant_id,title) values ($1,$2,'Pump manual')`,
      [ids.orgA, ids.plantA]);
    const before = await asUser(ids.techA, `select count(*)::int n from public.manuals`);
    if (before.rows[0].n !== 1) throw new Error('technician cannot see manuals by default');

    await db.query(
      `update public.organization_members set permissions='{"manuals.view":false}'::jsonb
        where organization_id=$1 and user_id=$2`, [ids.orgA, ids.techA]);
    const after = await asUser(ids.techA, `select count(*)::int n from public.manuals`);
    if (after.rows[0].n !== 0) throw new Error('permission flag had no effect');

    // Managers always retain access.
    const mgr = await asUser(ids.mgrA, `select count(*)::int n from public.manuals`);
    if (mgr.rows[0].n !== 1) throw new Error('manager lost manual access');

    await db.query(
      `update public.organization_members set permissions='{}'::jsonb
        where organization_id=$1 and user_id=$2`, [ids.orgA, ids.techA]);
  });

  // ---- soft delete / recovery ---------------------------------------------
  await check('recovery bin lists soft-deleted rows and restores them', async () => {
    const a = (await db.query(
      `insert into public.assets(organization_id,plant_id,name,asset_code,removed_at)
       values ($1,$2,'Retired Pump','A-OLD',now()) returning id`,
      [ids.orgA, ids.plantA])).rows[0].id;

    const bin = await asUser(ids.mgrA, `select * from public.recovery_bin($1)`, [ids.orgA]);
    const found = bin.rows.find(r => r.record_id === a);
    if (!found) throw new Error('deleted asset not in the recovery bin');
    if (found.source_table !== 'assets') throw new Error('wrong source table');

    await asUser(ids.mgrA, `select public.restore_record('assets',$1)`, [a]);
    const r = await db.query(`select removed_at from public.assets where id=$1`, [a]);
    if (r.rows[0].removed_at !== null) throw new Error('restore did not clear removed_at');
  });

  await denied('a technician cannot restore records', async () => {
    const a = (await db.query(
      `insert into public.assets(organization_id,plant_id,name,removed_at)
       values ($1,$2,'Gone',now()) returning id`, [ids.orgA, ids.plantA])).rows[0].id;
    return asUser(ids.techA, `select public.restore_record('assets',$1)`, [a]);
  }, /only a manager/i);

  await denied('restore_record rejects an arbitrary table name', () =>
    asUser(ids.mgrA, `select public.restore_record('pg_shadow','00000000-0000-0000-0000-000000000000')`),
    /cannot be restored/i);

  // ---- legal consent -------------------------------------------------------
  await check('legal consent is tracked per user', async () => {
    const pend = await asUser(ids.ownerA,
      `select * from public.pending_legal_documents($1)`, [ids.orgA]);
    if (pend.rows.length < 2) throw new Error('terms/privacy not pending');
    const doc = pend.rows[0].id;
    await asUser(ids.ownerA,
      `select public.accept_legal_document($1,$2,'en','hash')`, [doc, ids.orgA]);
    const after = await asUser(ids.ownerA,
      `select * from public.pending_legal_documents($1)`, [ids.orgA]);
    if (after.rows.some(r => r.id === doc)) throw new Error('accepted document still pending');
  });

  // ---- complaints ----------------------------------------------------------
  await check('only the owner raises platform complaints', async () => {
    await asUser(ids.ownerA,
      `select public.submit_app_complaint($1,'billing','high','Invoice','Wrong amount','4.48.1','{}'::jsonb)`,
      [ids.orgA]);
    const r = await asUser(ids.ownerA, `select * from public.owner_app_complaints($1)`, [ids.orgA]);
    if (r.rows.length !== 1) throw new Error('complaint not visible to owner');
    if (!r.rows[0].ticket_number) throw new Error('no ticket number assigned');
  });

  await denied('a manager cannot raise a platform complaint', () =>
    asUser(ids.mgrA,
      `select public.submit_app_complaint($1,'billing','high','X','Y',null,'{}'::jsonb)`,
      [ids.orgA]),
    /owner/i);

  await check('platform staff can see and answer a complaint', async () => {
    const t = (await db.query(`select id from public.app_complaints limit 1`)).rows[0].id;
    await asUser(ids.staff, `select public.reply_app_complaint($1,'We are on it')`, [t]);
    const m = await db.query(
      `select is_staff from public.app_complaint_messages where ticket_id=$1`, [t]);
    if (m.rows[0].is_staff !== true) throw new Error('staff reply not flagged');
    const c = await db.query(`select status from public.app_complaints where id=$1`, [t]);
    if (c.rows[0].status !== 'in_progress') throw new Error('status did not advance');
  });

  await denied('another tenant cannot read our complaints', async () => {
    const r = await asUser(ids.ownerB, `select * from public.owner_app_complaints($1)`, [ids.orgA]);
    if (r.rows.length === 0) throw new Error('returned nothing as expected');
    throw new Error('leak');
  }, /returned nothing as expected/);

  // ---- notifications -------------------------------------------------------
  await check('personal notifications stay private', async () => {
    await db.query(
      `insert into public.notifications(organization_id,plant_id,user_id,title)
       values ($1,$2,$3,'For the manager only')`, [ids.orgA, ids.plantA, ids.mgrA]);
    const tech = await asUser(ids.techA,
      `select count(*)::int n from public.notifications where title='For the manager only'`);
    if (tech.rows[0].n !== 0) throw new Error('technician read a private notification');
    const mgr = await asUser(ids.mgrA,
      `select count(*)::int n from public.notifications where title='For the manager only'`);
    if (mgr.rows[0].n !== 1) throw new Error('addressee cannot see their notification');
  });

  // ---- storage path authorization -----------------------------------------
  await check('storage path guards match the tenant folder', async () => {
    const a = await asUser(ids.techA,
      `select public.storage_path_allowed($1) ok`, [`${ids.orgA}/plant/file.pdf`]);
    if (a.rows[0].ok !== true) throw new Error('own folder not readable');
    const b = await asUser(ids.techA,
      `select public.storage_path_allowed($1) ok`, [`${ids.orgB}/plant/file.pdf`]);
    if (b.rows[0].ok !== false) throw new Error('other tenant folder readable');
    const c = await asUser(ids.techA, `select public.storage_path_allowed('not-a-uuid/x') ok`);
    if (c.rows[0].ok !== false) throw new Error('malformed path accepted');
    const d = await asUser(ids.viewerA,
      `select public.storage_path_writable($1) ok`, [`${ids.orgA}/p/f.pdf`]);
    if (d.rows[0].ok !== false) throw new Error('viewer could write to storage');
  });

  // ---- profile visibility --------------------------------------------------
  await check('profiles are visible to colleagues but not other tenants', async () => {
    const mine = await asUser(ids.techA,
      `select count(*)::int n from public.profiles where id=$1`, [ids.ownerA]);
    if (mine.rows[0].n !== 1) throw new Error('colleague profile hidden');
    const theirs = await asUser(ids.ownerB,
      `select count(*)::int n from public.profiles where id=$1`, [ids.ownerA]);
    if (theirs.rows[0].n !== 0) throw new Error('profile leaked across tenants');
  });

  console.log(`\n${DIM}── ${pass} passed, ${fail} failed ──${RESET}`);
  if (fail) console.log(`${RED}failing: ${failures.join(', ')}${RESET}`);
  return fail;
}
