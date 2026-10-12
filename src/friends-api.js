/** Recipient-approved friendship API; all relationships live on the server. */
export function createFriendsApi(client) {
  if (!client?.rpc) throw new Error('A Supabase client is required.');
  const rpc = async (name, args = {}) => {
    const { data, error } = await client.rpc(name, args);
    if (error) {
      const failure = new Error(error.message || 'The friend request could not be completed.');
      failure.code = error.code;
      throw failure;
    }
    return data;
  };
  return {
    listFriends: () => rpc('community_list_friends'),
    requestFriend: (userId) => rpc('community_request_friend', { p_user: userId }),
    respondFriend: (id, accept) => rpc('community_respond_friend', { p_id: id, p_accept: accept }),
    removeFriend: (id) => rpc('community_remove_friend', { p_id: id }),
    blockUser: (userId) => rpc('community_block_user', { p_user: userId }),
    unblockUser: (userId) => rpc('community_unblock_user', { p_user: userId }),
    listBlocks: () => rpc('community_list_blocks'),
    listActivity: (afterId = null) => rpc('community_activity', { p_after: afterId }),
  };
}
