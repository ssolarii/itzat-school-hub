import { createClient } from '@supabase/supabase-js';

function publicKeyOnly(key) {
  if (typeof key !== 'string' || !key.trim()) throw new Error('Supabase publishable key is missing.');
  if (key.startsWith('sb_secret_')) throw new Error('A secret Supabase key cannot be used in a browser.');
  if (key.split('.').length === 3) {
    let payload;
    try {
      const segment = key.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
      payload = JSON.parse(atob(segment.padEnd(Math.ceil(segment.length / 4) * 4, '=')));
    } catch {
      throw new Error('Supabase browser key is not a valid publishable or anon key.');
    }
    if (payload.role !== 'anon') throw new Error('Only the Supabase anon key may be used in a browser.');
  } else if (!key.startsWith('sb_publishable_')) {
    throw new Error('Supabase browser configuration requires a publishable or anon key.');
  }
}

function checked(result, fallback) {
  if (result.error) {
    const error = new Error(result.error.code === '40001'
      ? 'Someone published a newer version. Reload the latest schedule and review your changes before publishing again.'
      : (result.error.message || fallback));
    error.code = result.error.code;
    error.details = result.error.details;
    throw error;
  }
  return result.data;
}

function publication(result) {
  const data = checked(result, 'The school document could not be published.');
  const row = Array.isArray(data) ? data[0] : data;
  if (!row?.document || !Number.isSafeInteger(Number(row.revision))) {
    throw new Error('The server did not return a valid school publication.');
  }
  return { ...row, revision: Number(row.revision), publishedAt: row.published_at };
}

/** A browser-only public-key adapter. Authorization is enforced in PostgreSQL. */
export function createBackend({ url, key }) {
  const address = new URL(url);
  if (address.protocol !== 'https:' && !(['localhost', '127.0.0.1'].includes(address.hostname) && address.protocol === 'http:')) {
    throw new Error('Supabase project URL must use HTTPS.');
  }
  publicKeyOnly(key);
  const client = createClient(address.href.replace(/\/$/, ''), key, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
  });

  return {
    client,
    async loadPublished() {
      const row = checked(await client.from('school_versions')
        .select('revision,document,published_at').order('revision', { ascending: false }).limit(1).maybeSingle(),
      'The latest school schedule could not be loaded.');
      return row ? { ...row, revision: Number(row.revision), publishedAt: row.published_at } : null;
    },
    async publish(document, { expectedRevision } = {}) {
      if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 0) throw new Error('Publishing requires the revision you last loaded.');
      return publication(await client.rpc('publish_school_document', {
        p_document: document, p_expected_revision: expectedRevision,
      }));
    },
    async getMembership() {
      return checked(await client.rpc('get_my_school_membership'), 'Membership could not be loaded.');
    },
    async submitNotice(notice) {
      return checked(await client.rpc('submit_school_notice', { p_notice: notice }), 'Notice could not be submitted for review.');
    },
    async approveNotice(id, expectedRevision) {
      if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 0) throw new Error('Approving a notice requires the revision you last loaded.');
      return publication(await client.rpc('approve_school_notice', { p_id: id, p_expected_revision: expectedRevision }));
    },
    async setMember({ userId, role, capabilities = [], groups = [], active = true }) {
      return checked(await client.rpc('set_school_member', {
        p_user_id: userId, p_role: role, p_capabilities: capabilities, p_groups: groups, p_active: active,
      }), 'Membership could not be changed.');
    },
    async listDrafts() {
      return checked(await client.from('school_notice_drafts').select('id,submitted_by,notice,status,created_at,reviewed_at')
        .order('created_at', { ascending: false }), 'Notice drafts could not be loaded.') || [];
    },
    async listMembers() {
      return checked(await client.from('school_members').select('user_id,role,capabilities,groups,active,updated_at')
        .order('updated_at', { ascending: false }), 'Memberships could not be loaded.') || [];
    },
    async requestTeacherAccess({ name, groups, note = '' }) {
      return checked(await client.rpc('request_teacher_access', {
        p_name: name, p_groups: groups, p_note: note,
      }), 'Teacher access could not be requested.');
    },
    async reviewTeacherAccess({ id, approve, groups = [] }) {
      return checked(await client.rpc('review_teacher_access', {
        p_id: id, p_approve: approve, p_groups: groups,
      }), 'Teacher request could not be reviewed.');
    },
    async listTeacherRequests({ leadership = false } = {}) {
      if(leadership) return checked(await client.rpc('list_teacher_requests_for_review'), 'Verified applicant identities could not be loaded.') || [];
      return checked(await client.from('school_teacher_requests')
        .select('id,user_id,name,requested_groups,note,status,approved_groups,created_at,updated_at,reviewed_at')
        .order('created_at', { ascending: false }), 'Teacher requests could not be loaded.') || [];
    },
  };
}
