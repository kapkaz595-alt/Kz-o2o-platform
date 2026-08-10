import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { withAuth, requireRole } from '@/lib/supabase/auth-middleware';

export const GET = withAuth(async (req: NextRequest, ctx) => {
  const check = await requireRole(ctx.user, ['moderator', 'super_admin']);
  if (!check.ok) return check.response;

  const supabase = await createClient();
  const { searchParams } = new URL(req.url);
  const status = (searchParams.get('status') ?? 'pending') as 'pending' | 'approved' | 'rejected';
  const targetType = searchParams.get('target_type');
  const page = Number(searchParams.get('page') ?? '1');
  const pageSize = Number(searchParams.get('page_size') ?? '20');

  let query = supabase
    .from('moderation_queue')
    .select('*', { count: 'exact' })
    .eq('status', status)
    .order('created_at', { ascending: true })
    .range((page - 1) * pageSize, page * pageSize - 1);

  if (targetType) {
    query = query.eq('target_type', targetType);
  }

  const { data, error, count } = await query;
  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ data, total: count, page, page_size: pageSize });
});