import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { withAuth } from '@/lib/supabase/auth-middleware';

const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
const MAX_SIZE = 5 * 1024 * 1024;

export const POST = withAuth(async (req: NextRequest, ctx) => {
  const { slug } = ctx.params as { slug: string };
  const supabase = await createClient();

  const { data: merchant, error: merchantErr } = await supabase
    .from('merchants')
    .select('id, owner_id, status')
    .eq('slug', slug)
    .eq('is_deleted', false)
    .single();

  if (merchantErr || !merchant) {
    return NextResponse.json({ error: 'Merchant not found' }, { status: 404 });
  }

  const role = ctx.user.app_metadata?.role ?? 'user';
  const isOwner = merchant.owner_id === ctx.user.id && merchant.status === 'claimed';
  const isStaff = role === 'moderator' || role === 'super_admin';
  if (!isOwner && !isStaff) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403 });
  }

  const formData = await req.formData();
  const file = formData.get('file') as File | null;
  if (!file) {
    return NextResponse.json({ error: 'No file provided' }, { status: 400 });
  }
  if (!ALLOWED_TYPES.includes(file.type)) {
    return NextResponse.json({ error: 'Invalid file type' }, { status: 400 });
  }
  if (file.size > MAX_SIZE) {
    return NextResponse.json({ error: 'File too large' }, { status: 400 });
  }

  const ext = file.type.split('/')[1];
  const storagePath = `${merchant.id}/${crypto.randomUUID()}.${ext}`;

  const { error: uploadErr } = await supabase.storage
    .from('merchant-images')
    .upload(storagePath, file, { contentType: file.type, upsert: false });

  if (uploadErr) {
    return NextResponse.json({ error: uploadErr.message }, { status: 500 });
  }

  const { data: publicUrlData } = supabase.storage
    .from('merchant-images')
    .getPublicUrl(storagePath);

  const { data: imageRow, error: insertErr } = await supabase
    .from('merchant_images')
    .insert({
      merchant_id: merchant.id,
      url: publicUrlData.publicUrl,
      storage_path: storagePath,
      uploaded_by: ctx.user.id,
      status: 'pending',
    })
    .select()
    .single();

  if (insertErr) {
    await supabase.storage.from('merchant-images').remove([storagePath]);
    return NextResponse.json({ error: insertErr.message }, { status: 500 });
  }

  return NextResponse.json(imageRow, { status: 201 });
});