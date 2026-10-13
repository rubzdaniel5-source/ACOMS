import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

/**
 * Refreshes the Supabase auth session on every request.
 * Required for @supabase/ssr — without this, sessions expire silently
 * in Server Components. This does NOT perform authorization; that
 * happens via RLS and server-side capability checks.
 */
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          );
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  // Refresh session if expired
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Users given a temporary password must set their own before doing anything
  // else. The flag lives in app_metadata, which only the service role can write.
  const path = request.nextUrl.pathname;
  if (user?.app_metadata?.must_change_password === true && path !== "/change-password" && path !== "/login") {
    const url = request.nextUrl.clone();
    url.pathname = "/change-password";
    url.search = "";
    const redirectResponse = NextResponse.redirect(url);
    response.cookies.getAll().forEach((c) => redirectResponse.cookies.set(c));
    return redirectResponse;
  }

  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
