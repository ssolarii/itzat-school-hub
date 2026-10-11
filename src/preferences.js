export const AUDIENCE_COOKIE = 'isa_audience';
const audiences = new Set(['student', 'teacher', 'parent']);

/** This cookie remembers presentation only; it never grants staff permissions. */
export function parseAudienceCookie(cookieString = '') {
  if (typeof cookieString !== 'string') return null;
  const matches = cookieString.split(';').map(part => part.trim()).filter(part => part.slice(0, part.indexOf('=')) === AUDIENCE_COOKIE);
  // Conflicting paths/duplicate values should ask the person to choose again.
  if (matches.length !== 1) return null;
  try {
    const value = decodeURIComponent(matches[0].slice(matches[0].indexOf('=') + 1));
    return audiences.has(value) ? value : null;
  } catch { return null; }
}

function cookieOptions({ secure = false, basePath = '/' } = {}) {
  if (typeof secure !== 'boolean') throw new TypeError('Secure cookie setting must be boolean');
  if (typeof basePath !== 'string' || !basePath.startsWith('/') || /[;\s?#=\\\u0000-\u001f\u007f]/.test(basePath)) throw new TypeError('Cookie path must be an absolute URL directory path');
  const path = basePath.endsWith('/') ? basePath : `${basePath}/`;
  return `Path=${path}; SameSite=Lax${secure ? '; Secure' : ''}`;
}

export function audienceCookie(audience, options = {}) {
  if (!audiences.has(audience)) throw new TypeError('Choose Student, Teacher, or Parent');
  return `${AUDIENCE_COOKIE}=${encodeURIComponent(audience)}; Max-Age=31536000; ${cookieOptions(options)}`;
}

export function clearAudienceCookie(options = {}) {
  return `${AUDIENCE_COOKIE}=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; ${cookieOptions(options)}`;
}
