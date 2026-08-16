import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { withAuth } from '@/lib/supabase/auth-middleware';

export const POST = withAuth(async (req: NextRequest, { user, params }) => {
  const { slug } = await (params as Promise<{ slug: string }>);
  const supabase = await createClient();

  const { data: merchant, error: merchantErr } = await supabase
    .from('merchants')
    .select('id')
    .eq('slug', slug)
    .eq('is_deleted', false)
    .single();

  if (merchantErr || !merchant) {
    return NextResponse.json({ error: 'Merchant not found' }, { status: 404 });
  }

  const body = await req.json();
  const { rating, content } = body;

  if (typeof rating !== 'number' || rating < 1 || rating > 5) {
    return NextResponse.json(
      { error: 'rating must be an integer between 1 and 5' },
      { status: 400 }
    );
  }

  if (typeof content !== 'string' || content.trim().length < 5 || content.length > 2000) {
    return NextResponse.json(
      { error: 'content must be between 5 and 2000 characters' },
      { status: 400 }
    );
  }

  const { data, error } = await supabase
    .from('reviews')
    .insert({
      merchant_id: merchant.id,
      user_id: user.id,
      rating,
      content: content.trim(),
    })
    .select()
    .single();

  if (error) {
    if (error.code === '23505') {
      return NextResponse.json(
        { error: 'You have already reviewed this merchant' },
        { status: 409 }
      );
    }
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ data }, { status: 201 });
});

export const GET = async (req: NextRequest, { params }: { params: Promise<{ slug: string }> }) => {
  const { slug } = await params;
  const supabase = await createClient();

  const { data: merchant, error: merchantErr } = await supabase
    .from('merchants')
    .select('id')
    .eq('slug', slug)
    .eq('is_deleted', false)
    .single();

  if (merchantErr || !merchant) {
    return NextResponse.json({ error: 'Merchant not found' }, { status: 404 });
  }

  const { searchParams } = new URL(req.url);
  const page = Math.max(parseInt(searchParams.get('page') || '1', 10), 1);
  const pageSize = Math.min(Math.max(parseInt(searchParams.get('page_size') || '10', 10), 1), 50);
  const sort = searchParams.get('sort') === 'helpful' ? 'helpful_count' : 'created_at';
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  const { data, error, count } = await supabase
    .from('reviews')
    .select('id, user_id, rating, content, is_edited, helpful_count, unhelpful_count, created_at, updated_at', { count: 'exact' })
    .eq('merchant_id', merchant.id)
    .eq('status', 'approved')
    .eq('is_deleted', false)
    .order(sort, { ascending: false })
    .range(from, to);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({
    data,
    pagination: { page, page_size: pageSize, total: count ?? 0 },
  });
};