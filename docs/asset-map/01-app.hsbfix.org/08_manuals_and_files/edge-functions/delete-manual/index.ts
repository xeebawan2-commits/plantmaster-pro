/**
 * delete-manual — removes a manual, its AI index and its stored file.
 *
 * Runs server-side because removing the storage object, releasing the storage
 * quota and deleting the row must happen together. A client that crashed
 * halfway used to leave orphaned files that still consumed the tenant's quota.
 */
import { handle, HttpError } from '../_shared/guard.ts';

Deno.serve(handle({ name: 'delete-manual' }, async (ctx) => {
  const manualId = String((ctx.body as Record<string, unknown>).manual_id || '');
  if (!manualId) throw new HttpError(400, 'manual_id is required');

  const admin = ctx.adminClient;

  const { data: manual } = await admin
    .from('manuals')
    .select('id, organization_id, plant_id, storage_path, title, size_bytes')
    .eq('id', manualId)
    .maybeSingle();

  if (!manual) throw new HttpError(404, 'Manual not found');
  if (manual.organization_id !== ctx.orgId) {
    // Do not reveal that the id exists in another tenant.
    throw new HttpError(404, 'Manual not found');
  }

  // Only manager and above may delete a manual.
  const { data: member } = await admin
    .from('organization_members')
    .select('role')
    .eq('organization_id', ctx.orgId)
    .eq('user_id', ctx.userId)
    .eq('active', true)
    .maybeSingle();

  if (!['owner', 'manager'].includes(String(member?.role))) {
    throw new HttpError(403, 'Only a manager or owner can delete a manual');
  }

  // 1. Drop the AI index first — a stale index is worse than a missing one.
  const { error: chunkErr } = await admin
    .from('document_chunks')
    .delete()
    .eq('organization_id', ctx.orgId)
    .eq('manual_id', manualId);
  if (chunkErr) console.error('chunk delete failed', chunkErr.message);

  // 2. Remove the stored object and release the quota.
  if (manual.storage_path) {
    const { error: rmErr } = await admin.storage.from('plant-files').remove([manual.storage_path]);
    if (rmErr) console.error('storage remove failed', rmErr.message);

    const { error: metaErr } = await admin
      .from('file_metadata')
      .update({ removed_at: new Date().toISOString(), removed_by: ctx.userId })
      .eq('organization_id', ctx.orgId)
      .eq('object_path', manual.storage_path)
      .is('removed_at', null);
    if (metaErr) console.error('file_metadata update failed', metaErr.message);
  }

  // 3. Soft-delete the manual so it can be restored from the recycle bin.
  const { error: delErr } = await admin
    .from('manuals')
    .update({
      removed_at: new Date().toISOString(),
      removed_by: ctx.userId,
      status: 'deleted',
    })
    .eq('id', manualId)
    .eq('organization_id', ctx.orgId);

  if (delErr) throw new HttpError(500, delErr.message);

  await admin.from('audit_logs').insert({
    organization_id: ctx.orgId,
    plant_id: manual.plant_id,
    user_id: ctx.userId,
    action: 'manual_deleted',
    entity_type: 'manual',
    entity_id: manualId,
    details: { title: manual.title, bytes_released: manual.size_bytes ?? 0 },
  });

  return { ok: true, deleted: manualId, title: manual.title };
}));
