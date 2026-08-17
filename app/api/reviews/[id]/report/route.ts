import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { withAuth } from '@/lib/supabase/auth-middleware';

export const POST = withAuth(async (req: NextRequest, { params }: { params: Promise<{ id: string }> }) => {
  const { id: reviewId } = await params;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  const body = await req.json();
  const { reason, detail } = body;

  if (!reason) {
    return NextResponse.json({ error: '举报原因(reason)为必填' }, { status: 400 });
  }

  const { data: review, error: reviewErr } = await supabase
    .from('reviews')
    .select('id')
    .eq('id', reviewId)
    .eq('is_deleted', false)
    .single();

  if (reviewErr || !review) {
    return NextResponse.json({ error: '评论不存在' }, { status: 404 });
  }

  const { data, error } = await supabase
    .from('review_reports')
    .insert({
      review_id: reviewId,
      reported_by: user!.id,
      reason,
      detail: detail ?? null,
    })
    .select()
    .single();

  if (error) {
    if (error.code === '23505') {
      return NextResponse.json({ error: '你已举报过该评论' }, { status: 409 });
    }
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json(data, { status: 201 });
});