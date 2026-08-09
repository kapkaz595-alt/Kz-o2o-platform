import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { withAuth } from '@/lib/supabase/auth-middleware';

export const PATCH = withAuth(async (req: NextRequest, { user }, { params }: { params: { id: string } }) => {
  if (user.role !== 'moderator' && user.role !== 'super_admin') {
    return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  }

  const body = await req.json();
  const { action, note } = body as { action: 'approve' | 'reject'; note?: string };

  if (action !== 'approve' && action !== 'reject') {
    return NextResponse.json({ error: 'action must be approve or reject' }, { status: 400 });
  }

  const supabase = createClient();
  const newStatus = action === 'approve' ? 'approved' : 'rejected';

  const { data: image, error: updateError } = await supabase
    .from('merchant_images')
    .update({ status: newStatus, updated_at: new Date().toISOString() })
    .eq('id', params.id)
    .select()
    .single();

  if (updateError || !image) {
    console.error('[moderation/images] update error:', updateError);
    return NextResponse.json({ error: 'image not found or update failed' }, { status: 404 });
  }

  await supabase
    .from('moderation_queue')
    .update({
      status: newStatus,
      assigned_to: user.id,
      resolution_note: note ?? null,
      resolved_at: new Date().toISOString(),
    })
    .eq('target_type', 'merchant_image')
    .eq('target_id', params.id);

  return NextResponse.json({ message: `图片已${action === 'approve' ? '通过' : '拒绝'}审核`, data: image });
});