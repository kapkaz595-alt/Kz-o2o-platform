import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const { email, password } = body

    if (!email || !password) {
      return NextResponse.json(
        { success: false, data: null, message: '邮箱和密码不能为空', error: 'MISSING_FIELDS' },
        { status: 400 }
      )
    }

    const supabase = await createClient()

    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    })

    if (error) {
      return NextResponse.json(
        { success: false, data: null, message: '邮箱或密码错误', error: 'LOGIN_FAILED' },
        { status: 401 }
      )
    }

    const { data: userProfile } = await supabase
      .from('users')
      .select('id, role, display_name, target_audience, preferred_language')
      .eq('id', data.user.id)
      .single()

    return NextResponse.json({
      success: true,
      data: {
        user_id: data.user.id,
        email: data.user.email,
        profile: userProfile,
      },
      message: '登录成功',
      error: null,
    })
  } catch (err) {
    return NextResponse.json(
      { success: false, data: null, message: '服务器错误', error: 'INTERNAL_ERROR' },
      { status: 500 }
    )
  }
}
