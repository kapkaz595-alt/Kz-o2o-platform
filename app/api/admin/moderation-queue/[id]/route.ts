import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { withAuth, requireRole } from '@/lib/supabase/auth-middleware';
import { moderationHandlers, VALID_ACTIONS } from '@/lib/moderation/handlers';

export const PATCH = withAuth(async (req: NextRequest, { params }: { params: Promise<{ id: string }> }) => {
  requireRole(req, ['moderator', 'super_admin']);
  const { id } = await params;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  const body = await req.json();
  const { action, review_note } = body;

  const { data: item, error: itemErr } = await supabase
    .from('moderation_queue')
    .select('*')
    .eq('id', id)
    .single();

  if (itemErr || !item) {
    return NextResponse.json({ error: '审核项不存在' }, { status: 404 });
  }

  const validActions = VALID_ACTIONS[item.target_type];
  if (!validActions) {
    return NextResponse.json({ error: `未支持的target_type: ${item.target_type}` }, { status: 400 });
  }
  if (!validActions.includes(action)) {
    return NextResponse.json({ error: `该类型action须为${validActions.join('或')}` }, { status: 400 });
  }

  try {
    await moderationHandlers[item.target_type](action, {
      supabase,
      targetId: item.target_id,
      reviewerId: user!.id,
      reviewNote: review_note,
    });
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 });
  }

  const { error: queueErr } = await supabase
    .from('moderation_queue')
    .update({ status: 'processed', processed_at: new Date().toISOString() })
    .eq('id', id);

  if (queueErr) return NextResponse.json({ error: queueErr.message }, { status: 500 });

  return NextResponse.json({ success: true });
});