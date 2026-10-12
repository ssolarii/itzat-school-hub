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
    getState: () => rpc('school_space_get_state'),
    savePreferences: (preferences) => rpc('school_space_preferences', { p_preferences: preferences }),
    saveProfile: (profile, preferences = {}) => rpc('school_space_save_profile', { p_profile: profile, p_preferences: preferences }),
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
