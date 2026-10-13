/** School-space authority is returned by PostgreSQL; cosmetic labels never grant rights. */
export function createSchoolSpaceApi(client) {
  if (!client?.rpc) throw new Error('A Supabase client is required.');
  const rpc = async (name, args = {}) => {
    const { data, error } = await client.rpc(name, args);
    if (error) {
      const failure = new Error(error.message || 'The school-space request could not be completed.');
      failure.code = error.code;
      throw failure;
    }
    return data;
  };
  return {
    admissionState: () => rpc('community_admission_state'),
    requestAdmission: (name,note='') => rpc('community_request_admission',{p_name:name,p_note:note}),
    listAdmissionRequests: () => rpc('community_admission_requests'),
    reviewAdmission: (id,approve) => rpc('community_review_admission',{p_id:id,p_approve:approve}),
    createInvite: () => rpc('community_create_invite'),
    redeemInvite: token => rpc('community_redeem_invite',{p_token:token}),
    listInvites: () => rpc('community_list_invites'),
    revokeInvite: id => rpc('community_revoke_invite',{p_id:id}),
    discover: () => rpc('community_discover'),
    getState: () => rpc('school_space_get_state'),
    savePreferences: (preferences) => rpc('school_space_preferences', { p_preferences: preferences }),
    saveProfile: (profile, preferences = {}) => rpc('school_space_save_profile', { p_profile: profile, p_preferences: preferences }),
    updateServer: ({ name, description, iconKey='school', iconPath=null, joinPolicy=null }) => rpc('school_space_update_server', { p_name: name, p_description: description, p_icon_key:iconPath?null:iconKey, p_icon_path:iconPath, p_join_policy:joinPolicy }),
    saveChannel: ({ id = null, name, description = '', category = 'Conversation', postingPolicy='members', speakingRoles=null, slowmodeSeconds=0 }) => rpc('school_space_save_channel_controls', { p_id: id, p_name: name, p_description: description, p_category: category, p_posting_policy:postingPolicy, p_speaking_roles:speakingRoles, p_slowmode_seconds:slowmodeSeconds }),
    setRateLimit: (enabled,limit,windowSeconds) => rpc('school_space_set_rate_limit',{p_enabled:enabled,p_limit:limit,p_window_seconds:windowSeconds}),
    reportUser: (user,category,reason) => rpc('community_report_user',{p_user:user,p_category:category,p_reason:reason}),
    listUserReports: () => rpc('community_list_user_reports'),
    reviewUserReport: (id,action) => rpc('community_review_user_report',{p_id:id,p_action:action}),
    setChannelArchived: (id, archived = true) => rpc('school_space_set_channel_archived', { p_id: id, p_archived: archived }),
    createBadge: ({ name, description = '', iconKey = 'award', color = '#512393' }) => rpc('school_space_create_badge', { p_name: name, p_description: description, p_icon_key: iconKey, p_color: color }),
    awardBadge: (userId, badgeId, active = true) => rpc('school_space_award_badge', { p_user: userId, p_badge: badgeId, p_active: active }),
    heartbeat: () => rpc('school_space_heartbeat'),
    listMembers: () => rpc('school_space_members'),
    assignModerator: (userId, permissions = [], active = true) => rpc('school_space_assign_moderator', {
      p_user: userId, p_permissions: permissions, p_active: active,
    }),
    kickMember: (userId) => rpc('school_space_kick', { p_user: userId, p_kicked: true }),
    restoreMember: (userId) => rpc('school_space_kick', { p_user: userId, p_kicked: false }),
    removeMessage: (id) => rpc('school_space_remove_message', { p_id: id }),
    submitEmoji: ({ name, mediaPath }) => rpc('school_space_submit_emoji', { p_name: name, p_media_path: mediaPath }),
  };
}
