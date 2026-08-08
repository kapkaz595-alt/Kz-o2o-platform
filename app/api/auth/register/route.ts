import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const { email, password, target_audience, preferred_language } = body

    if (!email || !password) {
      return NextResponse.json(
        { success: false, data: null, message: '邮箱和密码不能为空', error: 'MISSING_FIELDS' },
        { status: 400 }
      )
    }

    if (password.length < 8) {
      return NextResponse.json(
        { success: false, data: null, message: '密码至少需要8位', error: 'PASSWORD_TOO_SHORT' },
        { status: 400 }
      )
    }

    const supabase = await createClient()

    const { data, error } = await supabase.auth.signUp({
      email,
      password,
    })

    if (error) {
      return NextResponse.json(
        { success: false, data: null, message: error.message, error: 'SIGNUP_FAILED' },
        { status: 400 }
      )
    }

    if (data.user && (target_audience || preferred_language)) {
      await supabase
        .from('users')
        .update({
          ...(target_audience && { target_audience }),
          ...(preferred_language && { preferred_language }),
        })
        .eq('id', data.user.id)
    }

    return NextResponse.json({
      success: true,
      data: { user_id: data.user?.id, email: data.user?.email },
      message: '注册成功',
      error: null,
    })
  } catch (err) {
    return NextResponse.json(
      { success: false, data: null, message: '服务器错误', error: 'INTERNAL_ERROR' },
      { status: 500 }
    )
  }
}
