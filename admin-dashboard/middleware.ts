import { NextResponse, type NextRequest } from "next/server";

const COOKIE = "denkma_admin_session";
const TOKEN_HEADER = "authorization";
const PROTECTED = ["/dashboard"];

export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;
  const needsAuth = PROTECTED.some((p) => pathname.startsWith(p));
  if (!needsAuth) return NextResponse.next();

  // Accept either cookie or Authorization header
  const token =
    req.cookies.get(COOKIE)?.value ||
    req.headers.get(TOKEN_HEADER)?.replace("Bearer ", "");

  // If no token, let the client-side handle the redirect
  // (middleware can't read localStorage)
  return NextResponse.next();
}

export const config = {
  matcher: ["/dashboard/:path*"],
};
