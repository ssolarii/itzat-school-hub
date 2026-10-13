/** Community APIs use the existing signed-in Supabase client. Cookies never authorize reads. */
export function createCommunityApi(client) {
  if (!client?.rpc || !client?.storage) throw new Error('A Supabase client is required.');
  const unwrap = (result) => {
    if (result.error) {
      const error = new Error(result.error.message || 'The community request could not be completed.');
      error.code = result.error.code;
      throw error;
    }
    return result.data;
  };
  const rpc = async (name, args = {}) => unwrap(await client.rpc(name, args));
  const api = {
    getProfile: () => rpc('community_get_profile'),
    saveProfile: (profile) => rpc('community_save_profile', { p_profile: profile }),
    listProfiles: () => rpc('community_profiles_directory'),
    listRooms: () => rpc('community_list_rooms', { p_pending: false }),
    listPendingRooms: () => rpc('community_list_rooms', { p_pending: true }),
    requestRoom: ({ kind, title, participants = [] }) => rpc('community_request_room', {
      p_kind: kind, p_title: title, p_participants: participants,
    }),
    reviewRoom: (id, approve) => rpc('community_review_room', { p_id: id, p_approve: approve }),
    respondRoom: (id, accept) => rpc('community_respond_room', {p_id:id,p_accept:accept}),
    leaveRoom: id => rpc('community_leave_room', {p_id:id}),
    messages: (roomId, before = null) => rpc('community_messages', { p_room: roomId, p_before: before }),
    mentionDirectory: roomId => rpc('community_mention_directory',{p_room:roomId}),
    editMessage: (id,body) => rpc('community_edit_message',{p_id:id,p_body:body}),
    deleteMessage: id => rpc('community_delete_message',{p_id:id}),
    reactMessage: (id,emoji,active) => rpc('community_react_message',{p_id:id,p_emoji:emoji,p_active:active}),
    sendMessage: ({ roomId, body = '', mediaPath = null, emojiId = null, gifUrl = null, replyTo = null }) => rpc('community_send_message', {
      p_room: roomId, p_body: body, p_media_path: mediaPath, p_emoji: emojiId, p_gif_url: gifUrl, p_reply_to:replyTo,
    }),
    reportMessage: (messageId, reason) => rpc('community_report_message', { p_message: messageId, p_reason: reason }),
    listPosts: ({ scope = 'site', classGroup = null, pending = false } = {}) => rpc('community_list_posts', {
      p_scope: scope, p_class_group: classGroup, p_pending: pending,
    }),
    listPendingPosts: () => rpc('community_list_posts', { p_scope: 'site', p_class_group: null, p_pending: true }),
    createPost: ({ scope, title, body = '', target = 'student' }) => rpc('community_create_post', {
      p_scope: scope, p_title: title, p_body: body, p_target: target,
    }),
    votePost: (id, vote) => rpc('community_vote', { p_post: id, p_vote: vote }),
    likePost: (id, liked) => rpc('community_like', { p_post: id, p_liked: liked }),
    reviewPost: (id, approve) => rpc('community_review_post', { p_id: id, p_approve: approve }),
    setDecision: (id, decision, note = '') => rpc('community_set_decision', { p_id: id, p_decision: decision, p_note: note }),
    postDeveloperAnnouncement: ({ title, body = '', target = 'all' }) => rpc('community_announce', {
      p_title: title, p_body: body, p_target: target,
    }),
    listEmojis: () => rpc('community_list_emojis', { p_pending: false }),
    listPendingEmojis: () => rpc('community_list_emojis', { p_pending: true }),
    submitEmoji: async ({ name, mediaPath }) => ({id:await rpc('community_submit_emoji', { p_name: name, p_media_path: mediaPath }),status:'pending_review',pending_review:true}),
    reviewEmoji: (id, approve) => rpc('community_review_emoji', { p_id: id, p_approve: approve }),
    listReports: () => rpc('community_reports'),
    moderateReport: (id, remove) => rpc('community_moderate_report', { p_id: id, p_remove: remove }),
    pauseUser: (userId, until = null) => rpc('community_pause_user', { p_user: userId, p_until: until }),
    async uploadMedia(file, kind = 'chat') {
      const types = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/gif': 'gif' };
      if (!types[file?.type] || !Number.isFinite(file.size) || file.size < 1 || file.size > 5 * 1024 * 1024) {
        throw new Error('Choose a JPG, PNG, WebP or GIF under 5 MB.');
      }
      if (!['avatar', 'banner', 'emoji', 'chat', 'server'].includes(kind)) throw new Error('Choose a valid image use.');
      const session = unwrap(await client.auth.getSession());
      if (!session?.session?.user?.id) throw new Error('Sign in before uploading an image.');
      const path = `${session.session.user.id}/${kind}/${crypto.randomUUID()}.${types[file.type]}`;
      unwrap(await client.storage.from('community-media').upload(path, file, { upsert: false, contentType: file.type, cacheControl: '0' }));
      return path;
    },
    async signMedia(paths = []) {
      const unique = [...new Set(paths.filter(Boolean))];
      if (!unique.length) return {};
      // Short-lived URLs are never persisted to local storage or the offline shell.
      const data = unwrap(await client.storage.from('community-media').createSignedUrls(unique, 300));
      return Object.fromEntries(data.filter((item) => item.signedUrl).map((item) => [item.path, item.signedUrl]));
    },
  };
  api.listAnnouncements = async () => (await api.listPosts({ scope: 'site' })).filter((post) => post.kind === 'announcement');
  return api;
}
