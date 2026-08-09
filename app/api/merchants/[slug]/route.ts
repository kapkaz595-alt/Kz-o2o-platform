import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

export async function GET(
  request: NextRequest,
  { params }: { params: { slug: string } }
) {
  const { slug } = params;

  if (!slug) {
    return NextResponse.json({ error: 'slug is required' }, { status: 400 });
  }

  const supabase = createClient();

  const { data: merchant, error } = await supabase
    .from('merchants')
    .select(`
      id, slug, canonical_slug, name, description, category,
      target_audiences, address, location, whatsapp_number,
      twogis_url, business_hours, status, vip_tier, featured,
      rating_avg, review_count, view_count, favorite_count,
      created_at, updated_at
    `)
    .eq('slug', slug)
    .eq('is_deleted', false)
    .maybeSingle();

  if (error) {
    console.error('[merchants/detail] query error:', error);
    return NextResponse.json({ error: 'internal server error' }, { status: 500 });
  }

  if (!merchant) {
    return NextResponse.json({ error: 'merchant not found' }, { status: 404 });
  }

  const { data: isOpen } = await supabase.rpc('is_merchant_open', {
    p_business_hours: merchant.business_hours,
  });

  supabase
    .rpc('increment_merchant_view_count', { p_merchant_id: merchant.id })
    .then(
      () => {},
      (err: unknown) =>
        console.error('[merchants/detail] view count increment failed:', err)
    );

  return NextResponse.json({
    data: { ...merchant, is_open: isOpen ?? null },
  });
}

export const PATCH = withAuth(async (req: NextRequest, { user }, { params }: { params: { slug: string } }) => {
  const supabase = createClient();
  const body = await req.json();

  const { data: merchant, error: findError } = await supabase
    .from('merchants')
    .select('*')
    .eq('slug', params.slug)
    .eq('is_deleted', false)
    .maybeSingle();

  if (findError || !merchant) {
    return NextResponse.json({ error: 'merchant not found' }, { status: 404 });
  }

  const isAdmin = user.role === 'moderator' || user.role === 'super_admin';
  const isOwner = merchant.owner_id === user.id;

  if (!isAdmin && !isOwner) {
    return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  }

  // 管理员：直接更新merchants表
  if (isAdmin) {
    const { data, error } = await supabase
      .from('merchants')
      .update(body)
      .eq('id', merchant.id)
      .select()
      .single();

    if (error) {
      console.error('[merchants/update] admin update error:', error);
      return NextResponse.json({ error: 'update failed' }, { status: 500 });
    }
    return NextResponse.json({ data });
  }

  // 已认领商家owner：提交到merchant_edits审核表
  if (merchant.claim_status === 'claimed') {
    const beforeSnapshot: Record<string, unknown> = {};
    for (const key of Object.keys(body)) {
      beforeSnapshot[key] = merchant[key];
    }

    const { data: editRequest, error: editError } = await supabase
      .from('merchant_edits')
      .insert({
        merchant_id: merchant.id,
        submitted_by: user.id,
        before_snapshot: beforeSnapshot,
        after_snapshot: body,
        status: 'pending',
      })
      .select()
      .single();

    if (editError) {
      console.error('[merchants/update] edit submit error:', editError);
      return NextResponse.json({ error: 'submit failed' }, { status: 500 });
    }

    return NextResponse.json(
      { message: '修改已提交审核', data: editRequest },
      { status: 202 }
    );
  }

  // 未认领商家的owner不应存在，兜底拒绝
  return NextResponse.json({ error: 'forbidden' }, { status: 403 });
});

export const DELETE = withAuth(async (req: NextRequest, { user }, { params }: { params: { slug: string } }) => {
  if (user.role !== 'moderator' && user.role !== 'super_admin') {
    return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  }

  const supabase = createClient();

  const { data: merchant, error: findError } = await supabase
    .from('merchants')
    .select('id')
    .eq('slug', params.slug)
    .eq('is_deleted', false)
    .maybeSingle();

  if (findError || !merchant) {
    return NextResponse.json({ error: 'merchant not found' }, { status: 404 });
  }

  const { error } = await supabase
    .from('merchants')
    .update({ is_deleted: true, deleted_at: new Date().toISOString() })
    .eq('id', merchant.id);

  if (error) {
    console.error('[merchants/delete] error:', error);
    return NextResponse.json({ error: 'delete failed' }, { status: 500 });
  }

  return NextResponse.json({ message: '商家已删除' }, { status: 200 });
});