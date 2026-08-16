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

  const { error } = await supabase
    .from('favorites')
    .insert({ merchant_id: merchant.id, user_id: user.id });

  if (error) {
    if (error.code === '23505') {
      return NextResponse.json({ error: 'Already favorited' }, { status: 409 });
    }
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ favorited: true }, { status: 201 });
});

export const DELETE = withAuth(async (req: NextRequest, { user, params }) => {
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

  const { error, count } = await supabase
    .from('favorites')
    .delete({ count: 'exact' })
    .eq('merchant_id', merchant.id)
    .eq('user_id', user.id);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  if (count === 0) {
    return NextResponse.json({ error: 'Favorite not found' }, { status: 404 });
  }

  return NextResponse.json({ favorited: false }, { status: 200 });
});