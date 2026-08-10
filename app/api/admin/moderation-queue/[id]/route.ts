import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { withAuth, requireRole } from '@/lib/supabase/auth-middleware';

export const PATCH = withAuth(async (req: NextRequest, ctx) => {
  const check = await requireRole(ctx.user, ['moderator', 'super_admin']);
  if (!check.ok) return check.response;

  const { id } = ctx.params as { id: string };
  const body = await req.json();
  const { status, resolution_note } = body as {
    status: 'approved' | 'rejected';
    resolution_note?: string;
  };

  if (!['approved', 'rejected'].includes(status)) {
    return NextResponse.json({ error: 'Invalid status' }, { status: 400 });
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from('moderation_queue')
    .update({
      status,
      resolution_note: resolution_note ?? null,
      assigned_to: ctx.user.id,
      resolved_at: new Date().toISOString(),
    })
    .eq('id', id)
    .eq('status', 'pending')
    .select()
    .single();

  if (error || !data) {
    return NextResponse.json(
      { error: error?.message ?? 'Not found or already resolved' },
      { status: 404 }
    );
  }

  return NextResponse.json(data);
});